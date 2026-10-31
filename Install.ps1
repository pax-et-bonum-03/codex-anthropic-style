#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath,
    [string]$FontDirectory,
    [switch]$DownloadFonts,
    [string]$StateDirectory = (Join-Path $PSScriptRoot '.state')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ThemeTools.ps1')
if (-not $ConfigPath) { $ConfigPath = Get-DefaultConfigPath }
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw 'Configuration file not found. Start the app once or specify -ConfigPath.' }
Assert-ConfigTarget $ConfigPath
$before = [IO.File]::ReadAllText($ConfigPath)
$oldState = Get-AppearanceState $before
$updated = Set-AppearanceState $before (Get-PresetState)
if (-not $PSCmdlet.ShouldProcess($ConfigPath, 'Apply Anthropic Clear Light and save an appearance-only backup')) { return }
Assert-AppClosed $ConfigPath
if ($DownloadFonts -or $FontDirectory) {
    & (Join-Path $PSScriptRoot 'Install-Fonts.ps1') -FontDirectory $FontDirectory -DownloadFonts:$DownloadFonts
}
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
[IO.Directory]::CreateDirectory($StateDirectory) | Out-Null
$backupPath = Join-Path $StateDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.backup.json')
$backup = [pscustomobject]@{
    Format = 'codex-anthropic-appearance-backup-v1'
    ConfigPath = $ConfigPath
    Created = [DateTime]::UtcNow.ToString('o')
    AppliedHash = Get-AppearanceHash $updated
    State = $oldState
}
[IO.File]::WriteAllText($backupPath, ($backup | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Write-ConfigSafely $ConfigPath $before $updated
Write-Host 'Anthropic Clear Light applied: 16 px interface/content, 14 px code, Serif Medium.'
Write-Host ('Appearance backup: ' + $backupPath)
Write-Host 'No app was closed, started, or restarted. Open the app yourself when ready.'
