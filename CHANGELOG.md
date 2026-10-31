# Changelog

## 1.0.3 - 2026-10-31

- Publish as Codex Anthropic Style with updated project and download links.
- Preserve the configuration, backup validation, and UTF-8 fixes from 1.0.2.
- Keep installer behavior and the 73-check fixture suite unchanged.

## 1.0.2 - 2026-10-31

- Read backups explicitly as UTF-8, including in Windows PowerShell 5.1.
- Add a regression test that restores a non-ASCII font family without corruption.

## 1.0.1 - 2026-10-31

- Refuse unsupported TOML before writing, including quoted desktop keys and multiline arrays.
- Preserve unrelated quoted project paths, quoted keys, and dotted assignments.
- Bind restore to an independently selected TOML path; reject links and junctions.
- Validate backup structure, table names, appearance keys, value types, and size limits, including with `-Force`.
- Recheck the configuration before atomic replacement.
- Add adversarial regression tests and pin the read-only CI checkout dependency.
- Exclude personal configuration and local recovery bundles from future Git tracking.

## 1.0.0 - 2026-10-30

- Add Anthropic Clear Light as a native appearance preset.
- Select Anthropic Serif Text Medium explicitly and set 16 px content.
- Add an optional, checksum-verified Serif/Sans font downloader and per-user Windows font installation.
- Add appearance-only backups and restoration that preserves unrelated settings.
- Include English installation instructions, source attribution, and Windows fixture tests.
- Keep proprietary fonts, personal configuration, and desktop screenshots out of the distribution.
