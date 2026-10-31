#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$BackupPath,
    [string]$ConfigPath,
    [string]$StateDirectory = (Join-Path $PSScriptRoot '.state'),
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ThemeTools.ps1')
if (-not $ConfigPath) { $ConfigPath = Get-DefaultConfigPath }
$path = [IO.Path]::GetFullPath($ConfigPath)
Assert-ConfigTarget $path
if (-not $BackupPath) {
    $latest = Get-ChildItem -LiteralPath $StateDirectory -Filter '*.backup.json' -File | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No appearance backup was found. Specify -BackupPath.' }
    $BackupPath = $latest.FullName
}
$backupFile = Get-Item -LiteralPath $BackupPath -Force
if ($backupFile.PSIsContainer -or $backupFile.Length -gt 131072 -or ($backupFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Invalid or oversized appearance backup.' }
$backup = [IO.File]::ReadAllText($backupFile.FullName, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
if ($backup -isnot [pscustomobject]) { throw 'The appearance backup must be one JSON object.' }
$backupNames = @($backup.PSObject.Properties | ForEach-Object { $_.Name })
if (@($backupNames | Where-Object { $_ -cnotin @('Format','ConfigPath','Created','AppliedHash','State') }).Count -or @(@('Format','ConfigPath','AppliedHash','State') | Where-Object { $_ -cnotin $backupNames }).Count) { throw 'Unexpected or missing backup fields.' }
if ($backup.Format -cne 'codex-anthropic-appearance-backup-v1') { throw 'Unrecognized appearance backup format.' }
if ($backup.ConfigPath -isnot [string] -or -not [IO.Path]::IsPathRooted($backup.ConfigPath) -or [IO.Path]::GetFullPath($backup.ConfigPath) -ine $path) { throw 'The backup does not match the independently selected configuration path. Use -ConfigPath only for the intended TOML file.' }
if ($backup.AppliedHash -isnot [string] -or $backup.AppliedHash -cnotmatch '\A[0-9a-f]{64}\z') { throw 'Invalid appearance checksum in backup.' }
Assert-AppearanceState $backup.State
$before = [IO.File]::ReadAllText($path)
if (-not $Force -and (Get-AppearanceHash $before) -cne $backup.AppliedHash) {
    throw 'Appearance settings have changed since installation. Review the backup and use -Force only if you want to replace those later appearance changes.'
}
$updated = Set-AppearanceState $before $backup.State
if (-not $PSCmdlet.ShouldProcess($path, 'Restore only the backed-up appearance settings')) { return }
Assert-AppClosed $path
Write-ConfigSafely $path $before $updated
Write-Host 'Previous appearance restored. Unrelated settings and installed fonts were preserved.'
Write-Host 'No app was closed, started, or restarted.'
