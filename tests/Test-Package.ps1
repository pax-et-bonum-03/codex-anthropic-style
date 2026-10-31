#Requires -Version 5.1
param([string]$TestDirectory = ([IO.Path]::GetTempPath()))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'ThemeTools.ps1')
$testRoot = Join-Path $TestDirectory ('codex-anthropic-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$script:checks = 0
function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAILED: ' + $Message) }
    $script:checks++
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-True $thrown $Message
}
function Write-Fixture([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
try {
    foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse) {
        $tokens = $null; $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-True (@($parseErrors).Count -eq 0) ('PowerShell parses: ' + $file.Name)
    }
    $json = Get-Content -LiteralPath (Join-Path $root 'themes\anthropic-clear-light.json') -Raw | ConvertFrom-Json
    $shared = (Get-Content -LiteralPath (Join-Path $root 'themes\anthropic-clear-light.txt') -Raw).Trim()
    Assert-True ($shared.StartsWith('codex-theme-v1:')) 'Native share prefix'
    $decoded = $shared.Substring('codex-theme-v1:'.Length) | ConvertFrom-Json
    Assert-True (($decoded | ConvertTo-Json -Depth 10 -Compress) -ceq ($json | ConvertTo-Json -Depth 10 -Compress)) 'JSON and native import agree'
    Assert-True ($json.theme.fonts.contentFace.postscriptName -ceq 'AnthropicSerifText-Medium') 'Explicit Medium face'
    Assert-True ($json.theme.ink -ceq '#141413' -and $json.theme.contrast -eq 67) 'Final clarity settings'

    $fixture = @'
# Unrelated settings must survive.
model = "fixture-model"
model_provider = "fixture-provider"

[desktop]
appearanceTheme = "dark" # original mode
sansFontSize = 13
codeFontSize = 12
pagesFontSize = 14
pagesFontSizeOther = 99
unrelated = "keep this"

[desktop.appearanceDarkChromeTheme]
ink = "#eeeeee"

[desktop.appearanceLightChromeTheme]
ink = "#111111"
surface = "#ffffff"

[desktop.appearanceLightChromeTheme.fonts]
content = "Georgia"

[model_providers.fixture]
base_url = "https://example.invalid/v1"
secret_marker = "DO-NOT-INCLUDE-IN-APPEARANCE-BACKUP"
'@
    foreach ($newline in @("`n", "`r`n")) {
        $suffix = if ($newline.Length -eq 1) { 'lf' } else { 'crlf' }
        $path = Join-Path $testRoot ($suffix + '.toml')
        $stateDirectory = Join-Path $testRoot ($suffix + '-state')
        $before = ($fixture -replace '\r?\n', $newline) + $newline
        Write-Fixture $path $before
        & (Join-Path $root 'Install.ps1') -ConfigPath $path -StateDirectory $stateDirectory -WhatIf
        Assert-True ([IO.File]::ReadAllText($path) -ceq $before) 'Dry run preserves config'
        Assert-True (-not (Test-Path -LiteralPath $stateDirectory)) 'Dry run creates no backup'
        & (Join-Path $root 'Install.ps1') -ConfigPath $path -StateDirectory $stateDirectory
        $installed = [IO.File]::ReadAllText($path)
        Assert-True ($installed -match '(?m)^pagesFontSize = 16\r?$') 'Content size applied'
        Assert-True ($installed -match 'postscriptName = "AnthropicSerifText-Medium"') 'Medium descriptor written'
        Assert-True ($installed.Contains('pagesFontSizeOther = 99')) 'Similar unrelated keys preserved'
        Assert-True ($installed.Contains('[desktop.appearanceDarkChromeTheme]')) 'Dark appearance preserved'
        Assert-True ($installed.Contains('secret_marker = "DO-NOT-INCLUDE-IN-APPEARANCE-BACKUP"')) 'Unrelated provider settings preserved'
        Assert-True (@([regex]::Matches($installed, '(?m)^\[desktop\.appearanceLightChromeTheme\]\r?$')).Count -eq 1) 'Single light theme table'
        $backup = Get-ChildItem -LiteralPath $stateDirectory -Filter '*.backup.json' | Select-Object -First 1
        Assert-True (-not ([IO.File]::ReadAllText($backup.FullName).Contains('DO-NOT-INCLUDE'))) 'Backup excludes unrelated values'
        Write-Fixture $path ($installed.Replace('keep this', 'new unrelated value'))
        & (Join-Path $root 'Restore.ps1') -BackupPath $backup.FullName -ConfigPath $path
        $restored = [IO.File]::ReadAllText($path)
        Assert-True ((Get-AppearanceHash $restored) -ceq (Get-AppearanceHash $before)) 'Original appearance restored'
        Assert-True ($restored.Contains('new unrelated value')) 'Restore preserves later unrelated edits'

        & (Join-Path $root 'Install.ps1') -ConfigPath $path -StateDirectory $stateDirectory
        $backup = Get-ChildItem -LiteralPath $stateDirectory -Filter '*.backup.json' | Sort-Object Name -Descending | Select-Object -First 1
        $changed = [IO.File]::ReadAllText($path).Replace('ink = "#141413"', 'ink = "#222222"')
        Write-Fixture $path $changed
        Assert-Throws { & (Join-Path $root 'Restore.ps1') -BackupPath $backup.FullName -ConfigPath $path } 'Later appearance change blocks restore'
        Assert-True ([IO.File]::ReadAllText($path) -ceq $changed) 'Rejected restore writes nothing'
        & (Join-Path $root 'Restore.ps1') -BackupPath $backup.FullName -ConfigPath $path -Force
        Assert-True ((Get-AppearanceHash ([IO.File]::ReadAllText($path))) -ceq (Get-AppearanceHash $before)) 'Explicit force restores appearance'
    }
    $absent = "model = `"fixture`"`n[projects.fixture]`ntrusted = true`n"
    $applied = Set-AppearanceState $absent (Get-PresetState)
    $restored = Set-AppearanceState $applied (Get-AppearanceState $absent)
    Assert-True (-not $restored.Contains('[desktop]')) 'Newly introduced empty desktop table removed on restore'
    Assert-True ($restored.Contains('[projects.fixture]')) 'Other tables preserved without original desktop'
    Assert-Throws { Get-AppearanceState ('note = ' + '"""' + "`n[desktop]`n" + '"""') } 'Multiline strings rejected'
    Assert-Throws { Get-AppearanceState ('["desktop"]' + "`n") } 'Quoted desktop table rejected'
    Assert-Throws { Get-AppearanceState "[desktop]`n[desktop]`n" } 'Duplicate desktop tables rejected'
    Assert-Throws { Get-AppearanceState 'desktop = { appearanceTheme = "light" }' } 'Inline desktop rejected'
    $unsupported = @(
        "[desktop]`n`"appearanceTheme`" = `"dark`"`n",
        "[desktop]`nmatrix = [`n  [1, 2]`n]`n",
        "[desktop]`nui.options = true`n",
        "[[desktop]]`nmode = `"test`"`n",
        "[`"\u0064esktop`"]`nappearanceTheme = `"dark`"`n"
    )
    $caseNumber = 0
    foreach ($text in $unsupported) {
        $caseNumber++
        $target = Join-Path $testRoot ('unsupported-' + $caseNumber + '.toml')
        $state = Join-Path $testRoot ('unsupported-state-' + $caseNumber)
        Write-Fixture $target $text
        Assert-Throws { & (Join-Path $root 'Install.ps1') -ConfigPath $target -StateDirectory $state } 'Unsupported TOML refused before writing'
        Assert-True ([IO.File]::ReadAllText($target) -ceq $text) 'Unsupported TOML remains byte-for-byte unchanged'
        Assert-True (-not (Test-Path -LiteralPath $state)) 'Rejected TOML creates no backup directory'
    }
    $quotedProject = "model = `"fixture`"`n[projects.'C:\example\desktop-project']`ntrusted = true`n"
    Assert-True ((Set-AppearanceState $quotedProject (Get-PresetState)).Contains("[projects.'C:\example\desktop-project']")) 'Unrelated quoted project paths are preserved'
    $otherKeys = "`"`$schema`" = `"https://example.invalid/schema`"`n[other]`n`"quoted-key`" = true`nsection.value = 3`n"
    Assert-True ((Set-AppearanceState $otherKeys (Get-PresetState)).Contains($otherKeys)) 'Unrelated quoted and dotted keys are preserved'

    $safePath = Join-Path $testRoot 'safe-config.toml'
    $safeText = "model = `"fixture`"`n"
    Write-Fixture $safePath $safeText
    $victim = Join-Path $testRoot 'unrelated-target.txt'
    Write-Fixture $victim 'UNCHANGED'
    $forgedPath = Join-Path $testRoot 'forged.backup.json'
    $forged = [pscustomobject]@{
        Format = 'codex-anthropic-appearance-backup-v1'; ConfigPath = $victim
        AppliedHash = ('0' * 64); State = (Get-PresetState)
    }
    Write-Fixture $forgedPath ($forged | ConvertTo-Json -Depth 10)
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $safePath -BackupPath $forgedPath -Force } 'Backup cannot select a different destination even with Force'
    Assert-True ([IO.File]::ReadAllText($victim) -ceq 'UNCHANGED') 'Unrelated target untouched'
    Assert-True ([IO.File]::ReadAllText($safePath) -ceq $safeText) 'Selected target untouched after rejected backup'
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $victim -BackupPath $forgedPath -Force } 'Non-TOML destination rejected'
    $forged.ConfigPath = $safePath
    $forged.State = [pscustomobject]@{DesktopExisted=$false; DesktopEntries=@(); ThemeSections=@("[model_providers.injected]`nbase_url = `"https://example.invalid`"`n")}
    Write-Fixture $forgedPath ($forged | ConvertTo-Json -Depth 10)
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $safePath -BackupPath $forgedPath -Force } 'Non-appearance table injection rejected'
    $forged.State = [pscustomobject]@{DesktopExisted=$true; DesktopEntries=@("appearanceTheme = `"light`"`nmodel = `"injected`""); ThemeSections=@()}
    Write-Fixture $forgedPath ($forged | ConvertTo-Json -Depth 10)
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $safePath -BackupPath $forgedPath -Force } 'Multiline desktop entry injection rejected'
    $forged.State = [pscustomobject]@{DesktopExisted=$true; DesktopEntries=@('model = "injected"'); ThemeSections=@()}
    Write-Fixture $forgedPath ($forged | ConvertTo-Json -Depth 10)
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $safePath -BackupPath $forgedPath -Force } 'Unexpected desktop key rejected'
    $forged.State = [pscustomobject]@{DesktopExisted=$false; DesktopEntries=@(); ThemeSections=@("[desktop.appearanceLightChromeTheme]`nink = true`n")}
    Write-Fixture $forgedPath ($forged | ConvertTo-Json -Depth 10)
    Assert-Throws { & (Join-Path $root 'Restore.ps1') -ConfigPath $safePath -BackupPath $forgedPath -Force } 'Invalid theme value type rejected'
    Assert-True ([IO.File]::ReadAllText($safePath) -ceq $safeText) 'Every rejected state preserves the selected config'
    $unicodeFont = ([string][char]0x5b8b) + ([string][char]0x4f53)
    $unicodePath = Join-Path $testRoot 'unicode-config.toml'
    $unicodeState = Join-Path $testRoot 'unicode-state'
    $unicodeText = "[desktop]`nappearanceTheme = `"light`"`n[desktop.appearanceLightChromeTheme.fonts]`ncontent = `"$unicodeFont`"`n"
    Write-Fixture $unicodePath $unicodeText
    & (Join-Path $root 'Install.ps1') -ConfigPath $unicodePath -StateDirectory $unicodeState
    $unicodeBackup = Get-ChildItem -LiteralPath $unicodeState -Filter '*.backup.json' | Select-Object -First 1
    & (Join-Path $root 'Restore.ps1') -ConfigPath $unicodePath -BackupPath $unicodeBackup.FullName
    Assert-True ([IO.File]::ReadAllText($unicodePath).Contains($unicodeFont)) 'UTF-8 font names survive backup and restore'
    $badFonts = Join-Path $testRoot 'invalid-fonts'
    [IO.Directory]::CreateDirectory($badFonts) | Out-Null
    Write-Fixture (Join-Path $badFonts 'AnthropicSerif-Text-Medium-Static.otf') 'invalid font bytes'
    Assert-Throws { & (Join-Path $root 'Install-Fonts.ps1') -FontDirectory $badFonts } 'Invalid font fails preflight'
    Write-Fixture (Join-Path $badFonts 'Unknown.ttf') 'invalid font bytes'
    Assert-Throws { & (Join-Path $root 'Install-Fonts.ps1') -FontDirectory $badFonts } 'Unknown font rejected'
    $fontFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -match '^\.(otf|ttf|woff2?)$' })
    Assert-True ($fontFiles.Count -eq 0) 'No proprietary font binaries distributed'
    Write-Host ('PASS: ' + $script:checks + ' checks. No real settings were modified and no fonts were installed.')
} finally {
    $tempRoot = [IO.Path]::GetFullPath($TestDirectory).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('codex-anthropic-tests-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
