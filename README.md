# Codex Anthropic Style

A warm light theme for Codex Desktop, with Anthropic typography and clearer body text. It uses the app's native appearance settings.

**[Download v1.0.3 ZIP](https://github.com/pax-et-bonum-03/codex-anthropic-style/raw/refs/heads/main/dist/codex-anthropic-style-v1.0.3.zip)** | [SHA-256 checksum](https://github.com/pax-et-bonum-03/codex-anthropic-style/blob/main/dist/SHA256SUMS.txt)

Version 1.0.3 includes the configuration and backup-validation security fixes and preserves non-ASCII font names during restore. Upgrade before using earlier scripts. See [security notes](SECURITY.md).

## Appearance

| Setting | Value |
| --- | --- |
| Background | `#f8f6f1` |
| Text | `#141413` |
| Accent | `#ca7554` |
| Contrast | `67` |
| Interface | Anthropic Sans Text, 16 px |
| Content | Anthropic Serif Text Medium, 16 px |
| Code | Anthropic Mono Variable, 14 px |
| Window | Opaque |

The content face explicitly selects **Medium (500)**. Choosing only a font family can leave the app using Regular. Chinese text uses the installed fallback fonts; this package does not install Noto Serif SC. Missing fonts fall back to Windows fonts, so the result will differ.

## Quick start on Windows

1. Download and extract `codex-anthropic-style-v1.0.3.zip`.
2. Save your work and close Codex Desktop yourself.
3. Double-click `Install.cmd` to apply the theme with your currently installed fonts.
4. Open the app yourself when you are ready.

The installer never closes, starts, or restarts the app. It needs no administrator access. It backs up only the appearance values it changes and preserves unrelated configuration. It refuses to edit the default configuration while a Codex or ChatGPT process is running.

For Anthropic typography, use fonts you are entitled to use. No font binaries are included. You can supply supported local files or explicitly request the optional download:

```powershell
# Preview configuration changes without writing anything.
.\Install.ps1 -WhatIf

# Apply the theme and install supported files from a local folder.
.\Install.ps1 -FontDirectory .\fonts

# Download the pinned Serif/Sans files from Anthropic's asset host,
# install them for the current Windows user, and apply the theme.
.\Install.ps1 -DownloadFonts
```

Review `THIRD_PARTY_NOTICES.md` before using the optional download. This project does not grant a license to Anthropic fonts. Mono is optional: supply your own `AnthropicMonoVariable.ttf`, or use the Consolas fallback. See `font-sources.json` for accepted files and checksums. The downloader checks both file size and SHA-256 before installation.

## Native import without scripts

Open **Settings > Appearance**, select **Light**, and use the theme import control to paste the complete contents of [`themes/anthropic-clear-light.txt`](themes/anthropic-clear-light.txt).

Set **interface size to 16**, **content size to 16**, and **code size to 14** separately. Font sizes are not included in the shared theme string. The preset includes the Anthropic Serif Text Medium face; that face must be installed to render correctly. New fonts may not appear in the app's font picker until you reopen the app yourself.

The [official appearance settings documentation](https://learn.chatgpt.com/docs/app/settings) describes the native theme and font controls. Control names and configuration fields may change between app versions.

## Restore

Close the app yourself, then double-click `Restore.cmd`. It restores the most recent appearance backup created by this extracted copy. If appearance settings have changed since installation, it stops instead of replacing them.

Restore selects the default configuration independently of the backup. For a custom configuration location, pass `-ConfigPath` explicitly; it must match the backup and must be a regular `.toml` file. Links and junctions are refused. `-Force` bypasses only the changed-appearance check; all destination and content checks still apply.

```powershell
# Restore a specific appearance backup.
.\Restore.ps1 -BackupPath .\.state\20261030-120000-000.backup.json

# Restore a backup for a custom configuration location.
.\Restore.ps1 -ConfigPath D:\MyApp\config.toml -BackupPath .\.state\YOUR-BACKUP.backup.json

# Deliberately replace later appearance changes with that backup.
.\Restore.ps1 -BackupPath .\.state\YOUR-BACKUP.backup.json -Force
```

Restore affects appearance settings only. Installed fonts remain available to other apps; remove them through **Windows Settings > Personalization > Fonts** if desired. Keep the `.state` folder until you no longer need the backup. It stays on your computer and is excluded from Git.

## Configuration and compatibility

- Windows PowerShell 5.1 or PowerShell 7. No extra modules.
- Uses `$CODEX_HOME/config.toml` when `CODEX_HOME` is set, otherwise `%USERPROFILE%/.codex/config.toml`.
- `-ConfigPath` supports a different config location. Close any app using that file first.
- Changes the light appearance subtree, appearance mode, and three font sizes. It leaves dark themes and unrelated settings intact.
- The editor supports a conservative TOML subset. It refuses multiline values, quoted or dotted keys in `[desktop]`, noncanonical desktop tables, and unsupported appearance fields before writing. Unrelated quoted project paths, ordinary quoted keys, and dotted assignments are preserved. Use native import if preflight refuses your file.
- Missing or changed download sources fail verification. Existing different font files or registry values are not overwritten.
- Native theme import, the Medium face, and the final 16 px content size were checked on the author's Windows desktop setup on October 30, 2026. The package's configuration and restore tests use isolated fixtures. Other app versions and operating systems have not been verified.

## Development

```powershell
.\tests\Test-Package.ps1
```

The tests do not modify your real app settings or install fonts. They check theme consistency, configuration preservation, restoration, changed-setting protection, dry runs, unsupported TOML, malicious backup destinations, and appearance-data injection. CI runs them on Windows with read-only permissions and a pinned checkout action.

## Credits and license

Adapted from [miniLV/Anthropic-codex-theme](https://github.com/miniLV/Anthropic-codex-theme). The scripts and theme are MIT licensed; Anthropic fonts are excluded. See [third-party notices](THIRD_PARTY_NOTICES.md).
