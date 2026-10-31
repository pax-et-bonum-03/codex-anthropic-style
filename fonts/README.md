# Local fonts

No font files are included. Place your own supported Anthropic font files here, then run:

```powershell
.\Install.ps1 -FontDirectory .\fonts
```

Supported filenames and checksums are listed in `font-sources.json`. Files are checked before installation. Unknown or modified files are rejected.

The optional `-DownloadFonts` switch downloads the seven listed Serif and Sans OTF files directly from `assets.claude.ai`. It does not download Mono. Anthropic Mono is optional and falls back to Consolas.

Anthropic fonts are proprietary. This project's MIT license does not apply to them. A public download URL does not grant a font license. Supply or download fonts only if you are entitled to use them.
