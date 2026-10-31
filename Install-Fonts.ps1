#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$FontDirectory, [switch]$DownloadFonts)
$ErrorActionPreference = 'Stop'
if (-not $FontDirectory -and -not $DownloadFonts) { throw 'Specify -FontDirectory or -DownloadFonts.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'font-sources.json') -Raw | ConvertFrom-Json
$entries = @($manifest.fonts)
$sources = @{}
$staging = $null
try {
    if ($FontDirectory) {
        $folder = (Resolve-Path -LiteralPath $FontDirectory).ProviderPath
        $files = @(Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Extension -match '^\.(otf|ttf|woff2?)$' })
        foreach ($file in $files) {
            if (-not @($entries | Where-Object { $_.file -ceq $file.Name }).Count) { throw ('Unsupported font file: ' + $file.Name) }
            $sources[$file.Name] = $file.FullName
        }
    }
    if ($DownloadFonts) {
        Write-Host 'Anthropic fonts are proprietary. Download only if you are entitled to use them. No font license is granted by this package.'
        if (-not $PSCmdlet.ShouldProcess('assets.claude.ai', 'Download the seven pinned Serif and Sans OTF files')) { return }
        $staging = Join-Path ([IO.Path]::GetTempPath()) ('codex-anthropic-fonts-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        foreach ($entry in $entries) {
            if (-not $entry.url) { continue }
            $destination = Join-Path $staging $entry.file
            Invoke-WebRequest -Uri $entry.url -OutFile $destination -UseBasicParsing
            $sources[$entry.file] = $destination
        }
    }
    if (-not $sources.Count) { throw 'No supported font files were found.' }
    $targetDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Microsoft\Windows\Fonts'
    $registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $install = @()
    # Preflight the entire selection before copying or registering any font.
    foreach ($entry in $entries) {
        if (-not $sources.ContainsKey($entry.file)) { continue }
        $source = $sources[$entry.file]
        $info = Get-Item -LiteralPath $source
        if ($info.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $entry.sha256) {
            throw ('Font checksum or size mismatch: ' + $entry.file)
        }
        $destination = Join-Path $targetDirectory $entry.file
        if ((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $entry.sha256) {
            throw ('A different font already exists; nothing was overwritten: ' + $entry.file)
        }
        $registration = Get-ItemProperty -LiteralPath $registryPath -Name $entry.label -ErrorAction SilentlyContinue
        if ($registration -and $registration.($entry.label) -ine $destination) { throw ('An existing font registration differs: ' + $entry.label) }
        $install += [pscustomobject]@{ Entry = $entry; Source = $source; Destination = $destination }
    }
    if (-not $PSCmdlet.ShouldProcess($targetDirectory, ('Install or register ' + $install.Count + ' verified fonts for the current user'))) { return }
    if (-not ('CodexAnthropic.FontRegistration' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CodexAnthropic {
    public static class FontRegistration {
        [DllImport("gdi32.dll", CharSet=CharSet.Unicode)]
        public static extern int AddFontResourceExW(string path, uint flags, IntPtr reserved);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)]
        public static extern bool SendNotifyMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    }
}
'@
    }
    [IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
    New-Item -Path $registryPath -Force | Out-Null
    foreach ($item in $install) {
        if (-not (Test-Path -LiteralPath $item.Destination)) { [IO.File]::Copy($item.Source, $item.Destination, $false) }
        if ([CodexAnthropic.FontRegistration]::AddFontResourceExW($item.Destination, 0, [IntPtr]::Zero) -lt 1) { throw ('Windows could not load font: ' + $item.Entry.file) }
        New-ItemProperty -LiteralPath $registryPath -Name $item.Entry.label -Value $item.Destination -PropertyType String -Force | Out-Null
        Write-Host ('Available: ' + $item.Entry.label)
    }
    [CodexAnthropic.FontRegistration]::SendNotifyMessageW([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Write-Host 'Fonts installed for the current user. The app was not restarted.'
} finally {
    if ($staging -and [IO.Directory]::Exists($staging)) {
        # Delete only the unique temporary directory created by this invocation.
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $resolved = [IO.Path]::GetFullPath($staging)
        if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('codex-anthropic-fonts-')) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
