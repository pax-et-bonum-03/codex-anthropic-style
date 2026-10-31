# Shared appearance-only configuration helpers. No app process is started or stopped.
Set-StrictMode -Version 2.0
$script:AppearanceKeys = 'appearanceTheme|sansFontSize|codeFontSize|pagesFontSize'
$script:TomlBasicString = '"(?:[^"\\\x00-\x1F]|\\(?:["\\btnfr]|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}))*"'
$script:TomlLiteralString = "'[^'\x00-\x1F]*'"

function Get-TomlCodeLine([string]$Line) {
    # Comments and quoted strings cannot introduce a table or a new assignment.
    $quote = [char]0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($quote -ne [char]0) {
            if ($quote -eq '"' -and $c -eq '\') { $i++; continue }
            if ($c -eq $quote) { $quote = [char]0 }
        } elseif ($c -eq '"' -or $c -eq "'") { $quote = $c }
        elseif ($c -eq '#') { return $Line.Substring(0, $i).Trim() }
    }
    if ($quote -ne [char]0) { throw 'Multiline or unterminated strings are not supported. Use native theme import.' }
    return $Line.Trim()
}

function Assert-SingleLineValue([string]$Value) {
    $stack = New-Object 'System.Collections.Generic.Stack[char]'
    $quote = [char]0
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $c = $Value[$i]
        if ($quote -ne [char]0) {
            if ($quote -eq '"' -and $c -eq '\') { $i++; continue }
            if ($c -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($c -eq '"' -or $c -eq "'") { $quote = $c; continue }
        if ($c -eq '[' -or $c -eq '{') { $stack.Push($c); continue }
        if ($c -eq ']' -or $c -eq '}') {
            if (-not $stack.Count) { throw 'Unbalanced TOML value. No settings were written.' }
            $open = $stack.Pop()
            if (($open -eq '[' -and $c -ne ']') -or ($open -eq '{' -and $c -ne '}')) { throw 'Unbalanced TOML value. No settings were written.' }
        }
    }
    if ($quote -ne [char]0 -or $stack.Count) { throw 'Multiline values are not supported. Use native theme import. No settings were written.' }
}

function Assert-SupportedToml([string]$Text) {
    # This is a conservative editing subset, not a general TOML parser.
    # Reject unsupported syntax before looking for table boundaries or writing files.
    if ($Text.Contains('"""') -or $Text.Contains("'''")) { throw 'Multiline TOML strings are not supported. Use native theme import.' }
    $keyPart = '(?:[A-Za-z0-9_-]+|' + $script:TomlBasicString + '|' + $script:TomlLiteralString + ')'
    $keyPath = '\A' + $keyPart + '(?:[ \t]*\.[ \t]*' + $keyPart + ')*\z'
    $currentTable = ''
    foreach ($line in ($Text -split '\r?\n')) {
        $code = Get-TomlCodeLine $line
        if (-not $code) { continue }
        if ($code.StartsWith('[')) {
            $arrayTable = $code.StartsWith('[[')
            $width = if ($arrayTable) { 2 } else { 1 }
            $ending = if ($arrayTable) { ']]' } else { ']' }
            if (-not $code.EndsWith($ending) -or $code.Length -le 2 * $width) { throw 'Unsupported TOML table syntax. Use native theme import.' }
            $name = $code.Substring($width, $code.Length - 2 * $width).Trim()
            if (-not [regex]::IsMatch($name, $keyPath) -or -not [regex]::IsMatch($name, '\A[A-Za-z0-9_-]+(?:\s*\.|\z)')) {
                throw 'Unsupported or quoted first table component. Use native theme import.'
            }
            $first = [regex]::Match($name, '\A[A-Za-z0-9_-]+').Value
            if ($first -ceq 'desktop' -and ($arrayTable -or -not [regex]::IsMatch($name, '\Adesktop(?:\.[A-Za-z0-9_-]+)*\z'))) {
                throw 'Quoted, spaced, or array desktop tables are not supported. Use native theme import.'
            }
            $currentTable = $name
            continue
        }
        $quote = [char]0
        $equals = -1
        for ($i = 0; $i -lt $code.Length; $i++) {
            $c = $code[$i]
            if ($quote -ne [char]0) {
                if ($quote -eq '"' -and $c -eq '\') { $i++; continue }
                if ($c -eq $quote) { $quote = [char]0 }
            } elseif ($c -eq '"' -or $c -eq "'") { $quote = $c }
            elseif ($c -eq '=') { $equals = $i; break }
        }
        if ($equals -lt 1 -or $equals -eq $code.Length - 1) { throw 'Unsupported TOML assignment. Use native theme import.' }
        $key = $code.Substring(0, $equals).Trim()
        if (-not [regex]::IsMatch($key, $keyPath)) { throw 'Unsupported TOML key syntax. Use native theme import.' }
        if ($currentTable -ceq 'desktop' -and -not [regex]::IsMatch($key, '\A[A-Za-z0-9_-]+\z')) { throw 'Quoted keys and dotted assignments in the desktop table are not supported. Use native theme import.' }
        if (-not $currentTable) {
            $firstRaw = [regex]::Match($key, '\A' + $keyPart).Value
            if ($firstRaw.StartsWith('"') -and $firstRaw.Contains('\')) { throw 'Escaped root keys are not supported. Use native theme import.' }
            $first = $firstRaw.Trim('"', "'")
            if ($first -ceq 'desktop') { throw 'Inline or dotted desktop settings are not supported. Use native theme import.' }
        }
        Assert-SingleLineValue $code.Substring($equals + 1).Trim()
    }
}

function Assert-ConfigTarget([string]$Path) {
    if ([IO.Path]::GetExtension($Path) -ine '.toml') { throw 'The configuration target must be an explicitly selected TOML file.' }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) { throw 'The configuration target must be a regular file.' }
    # Do not follow a reparse point on the file or any parent directory.
    while ($item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Configuration paths through links or junctions are not supported.' }
        if ($item -is [IO.FileInfo]) { $item = $item.Directory } else { $item = $item.Parent }
    }
}

function Assert-AppearanceState($State) {
    if ($null -eq $State -or $State.DesktopExisted -isnot [bool]) { throw 'Invalid appearance state.' }
    $names = @($State.PSObject.Properties | ForEach-Object { $_.Name })
    if (@($names | Where-Object { $_ -cnotin @('DesktopExisted','DesktopEntries','ThemeSections') }).Count -or $names.Count -ne 3) { throw 'Unexpected appearance-state fields.' }
    if ($State.DesktopEntries -isnot [array] -or $State.ThemeSections -isnot [array]) { throw 'Appearance state must contain arrays.' }
    if ($State.DesktopEntries.Count -gt 4 -or $State.ThemeSections.Count -gt 8) { throw 'Appearance state exceeds its allowed size.' }
    if (-not $State.DesktopExisted -and $State.DesktopEntries.Count) { throw 'Invalid desktop-state combination.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($entry in $State.DesktopEntries) {
        if ($entry -isnot [string] -or $entry.Length -gt 4096 -or $entry.TrimEnd("`r", "`n") -match '[\r\n]') { throw 'Invalid desktop appearance entry.' }
        $code = Get-TomlCodeLine $entry.TrimEnd("`r", "`n")
        $match = [regex]::Match($code, '\A(?<key>appearanceTheme|sansFontSize|codeFontSize|pagesFontSize)\s*=\s*(?<value>.+)\z')
        if (-not $match.Success -or -not $seen.Add($match.Groups['key'].Value)) { throw 'Unexpected or duplicate desktop appearance key.' }
        $value = $match.Groups['value'].Value.Trim()
        if ($match.Groups['key'].Value -ceq 'appearanceTheme') {
            if (-not [regex]::IsMatch($value, '\A(?:"(?:light|dark|system|auto)"|''(?:light|dark|system|auto)'')\z')) { throw 'Invalid appearance mode.' }
        } elseif (-not [regex]::IsMatch($value, '\A[0-9]{1,3}\z') -or [int]$value -lt 1 -or [int]$value -gt 256) { throw 'Invalid font size.' }
    }
    $combined = ''
    foreach ($text in $State.ThemeSections) {
        if ($text -isnot [string] -or $text.Length -gt 32768) { throw 'Invalid theme-section data.' }
        $combined += $text + "`n"
    }
    if (-not $combined.Trim()) { return }
    $themeTables = @(Get-ConfigSections $combined)
    $seenTables = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($table in $themeTables) {
        if (-not $table.Name) {
            if (@(($table.Text -split '\r?\n') | Where-Object { (Get-TomlCodeLine $_) }).Count) { throw 'Theme data cannot contain root assignments.' }
            continue
        }
        if (-not $seenTables.Add($table.Name)) { throw 'Duplicate theme table in backup.' }
        $root = 'desktop.appearanceLightChromeTheme'
        $allowed = switch -CaseSensitive ($table.Name) {
            $root { @('accent','accentSource','contrast','ink','opaqueWindows','surface') }
            ($root + '.fonts') { @('code','content','ui') }
            ($root + '.fonts.contentFace') { @('family','fullName','postscriptName') }
            ($root + '.fonts.codeFace') { @('family','fullName','postscriptName') }
            ($root + '.fonts.uiFace') { @('family','fullName','postscriptName') }
            ($root + '.semanticColors') { @('diffAdded','diffRemoved','skill') }
            default { throw 'A backup may contain only supported light-appearance tables.' }
        }
        $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($line in ($table.Text -split '\r?\n' | Select-Object -Skip 1)) {
            $code = Get-TomlCodeLine $line
            if (-not $code) { continue }
            $m = [regex]::Match($code, '\A(?<key>[A-Za-z0-9_-]+)\s*=\s*(?<value>.+)\z')
            $key = $m.Groups['key'].Value
            $value = $m.Groups['value'].Value.Trim()
            if (-not $m.Success -or $key -cnotin $allowed -or -not $keys.Add($key)) { throw 'Unexpected or duplicate theme key in backup.' }
            if ($key -ceq 'contrast') {
                if (-not [regex]::IsMatch($value, '\A[0-9]{1,3}\z') -or [int]$value -gt 100) { throw 'Invalid theme contrast.' }
            } elseif ($key -ceq 'opaqueWindows') {
                if ($value -cnotin @('true','false')) { throw 'Invalid window appearance value.' }
            } elseif ($value.Length -gt 4096 -or -not [regex]::IsMatch($value, '\A(?:' + $script:TomlBasicString + '|' + $script:TomlLiteralString + ')\z')) { throw 'Theme text values must be single TOML strings.' }
        }
    }
}

function Get-DefaultConfigPath {
    if ($env:CODEX_HOME) { return Join-Path $env:CODEX_HOME 'config.toml' }
    return Join-Path $env:USERPROFILE '.codex\config.toml'
}

function Assert-AppClosed([string]$ConfigPath) {
    $defaultPath = [IO.Path]::GetFullPath((Get-DefaultConfigPath))
    if ([IO.Path]::GetFullPath($ConfigPath) -ieq $defaultPath) {
        if (Get-Process -Name 'Codex', 'ChatGPT' -ErrorAction SilentlyContinue) {
            throw 'Save your work and close Codex Desktop yourself before applying or restoring settings. This script will not close or restart it.'
        }
    }
}

function Get-ConfigSections([string]$Text) {
    Assert-SupportedToml $Text
    if ($Text.Contains('"""') -or $Text.Contains("'''")) {
        throw 'Multiline TOML strings are not supported. Use the native theme import instead.'
    }
    if ($Text -match '(?m)^[ \t]*desktop[ \t]*(?:\.|=)') {
        throw 'Inline or dotted desktop settings are not supported. Use the native theme import instead.'
    }
    $headers = [regex]::Matches($Text, '(?m)^[ \t]*\[(?<name>[^\r\n]+?)\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)')
    $sections = @()
    $end = if ($headers.Count) { $headers[0].Index } else { $Text.Length }
    $sections += [pscustomobject]@{ Name = ''; Text = $Text.Substring(0, $end) }
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $header = $headers[$i]
        $name = $header.Groups['name'].Value.Trim()
        if ($name -cmatch '^desktop(?:\.|$)' -and ($name -match '["\x27]' -or $name -match '\s')) {
            throw 'Quoted or spaced desktop table names are not supported. Use the native theme import instead.'
        }
        $end = if ($i + 1 -lt $headers.Count) { $headers[$i + 1].Index } else { $Text.Length }
        $sections += [pscustomobject]@{ Name = $name; Text = $Text.Substring($header.Index, $end - $header.Index) }
    }
    if (@($sections | Where-Object { $_.Name -ceq 'desktop' }).Count -gt 1) { throw 'Duplicate desktop tables were found.' }
    return $sections
}

function Test-LightSection([string]$Name) {
    return $Name -ceq 'desktop.appearanceLightChromeTheme' -or $Name.StartsWith('desktop.appearanceLightChromeTheme.', [StringComparison]::Ordinal)
}

function Get-AppearanceState([string]$Text) {
    $sections = @(Get-ConfigSections $Text)
    $desktop = @($sections | Where-Object { $_.Name -ceq 'desktop' })
    $entries = @()
    if ($desktop.Count) {
        $pattern = '(?m)^[ \t]*(?:' + $script:AppearanceKeys + ')[ \t]*=[^\r\n]*(?:\r?\n|\z)'
        $entries = @([regex]::Matches($desktop[0].Text, $pattern) | ForEach-Object { $_.Value })
    }
    $state = [pscustomobject]@{
        DesktopExisted = [bool]$desktop.Count
        DesktopEntries = $entries
        ThemeSections = @($sections | Where-Object { Test-LightSection $_.Name } | ForEach-Object { $_.Text })
    }
    Assert-AppearanceState $state
    return $state
}

function Set-AppearanceState([string]$Text, $State) {
    Assert-AppearanceState $State
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $found = $false
    foreach ($section in @(Get-ConfigSections $Text)) {
        if (Test-LightSection $section.Name) { continue }
        if ($section.Name -ceq 'desktop') {
            $found = $true
            $pattern = '(?m)^[ \t]*(?:' + $script:AppearanceKeys + ')[ \t]*=[^\r\n]*(?:\r?\n|\z)'
            $block = [regex]::Replace($section.Text, $pattern, '')
            $body = [regex]::Replace($block, '\A[^\r\n]*(?:\r?\n|\z)', '')
            if (-not $State.DesktopExisted -and -not $body.Trim()) { continue }
            if (@($State.DesktopEntries).Count) {
                if (-not $block.EndsWith("`n")) { $block += $newline }
                foreach ($entry in @($State.DesktopEntries)) { $block += $entry.TrimEnd("`r", "`n") + $newline }
            }
            $parts.Add($block)
        } else { $parts.Add($section.Text) }
    }
    $result = [string]::Join('', $parts)
    if (-not $found -and $State.DesktopExisted) {
        if ($result -and -not $result.EndsWith("`n")) { $result += $newline }
        $result += $newline + '[desktop]' + $newline
        foreach ($entry in @($State.DesktopEntries)) { $result += $entry.TrimEnd("`r", "`n") + $newline }
    }
    foreach ($section in @($State.ThemeSections)) {
        if ($result -and -not $result.EndsWith("`n")) { $result += $newline }
        $result += $section
    }
    Assert-SupportedToml $result
    return $result
}

function Get-AppearanceHash([string]$Text) {
    $state = Get-AppearanceState $Text
    $value = ([string]::Join('', @($state.DesktopEntries)) + "`n--theme--`n" + [string]::Join('', @($state.ThemeSections))) -replace '\r\n', "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-PresetState {
    $theme = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'themes\anthropic-clear-light.json') -Raw | ConvertFrom-Json
    $t = $theme.theme
    # JSON basic strings are compatible with the single-line TOML strings used here.
    $q = { param($Value) ConvertTo-Json -InputObject $Value -Compress }
    $table = @(
        '[desktop.appearanceLightChromeTheme]',
        ('accent = ' + (& $q $t.accent)), ('contrast = ' + $t.contrast),
        ('ink = ' + (& $q $t.ink)), 'opaqueWindows = true', ('surface = ' + (& $q $t.surface)), '',
        '[desktop.appearanceLightChromeTheme.fonts]',
        ('code = ' + (& $q $t.fonts.code)), ('content = ' + (& $q $t.fonts.content)), ('ui = ' + (& $q $t.fonts.ui)), '',
        '[desktop.appearanceLightChromeTheme.fonts.contentFace]',
        ('family = ' + (& $q $t.fonts.contentFace.family)),
        ('fullName = ' + (& $q $t.fonts.contentFace.fullName)),
        ('postscriptName = ' + (& $q $t.fonts.contentFace.postscriptName)), '',
        '[desktop.appearanceLightChromeTheme.semanticColors]',
        ('diffAdded = ' + (& $q $t.semanticColors.diffAdded)),
        ('diffRemoved = ' + (& $q $t.semanticColors.diffRemoved)), ('skill = ' + (& $q $t.semanticColors.skill)), ''
    ) -join "`n"
    return [pscustomobject]@{
        DesktopExisted = $true
        DesktopEntries = @('appearanceTheme = "light"', 'sansFontSize = 16', 'codeFontSize = 14', 'pagesFontSize = 16')
        ThemeSections = @($table)
    }
}

function Write-ConfigSafely([string]$Path, [string]$Expected, [string]$Updated) {
    Assert-ConfigTarget $Path
    Assert-SupportedToml $Updated
    if ([IO.File]::ReadAllText($Path) -cne $Expected) { throw 'The configuration changed during preparation. Nothing was replaced.' }
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Updated, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::ReadAllText($Path) -cne $Expected) { throw 'The configuration changed during preparation. Nothing was replaced.' }
        [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    if ([IO.File]::ReadAllText($Path) -cne $Updated) { throw 'Configuration readback did not match.' }
}
