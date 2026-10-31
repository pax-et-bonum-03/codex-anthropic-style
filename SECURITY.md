# Security notes

## Supported version

Use version 1.0.3 or later. Version 1.0.3 preserves the fixes from 1.0.2. Version 1.0.0 has configuration and restore-validation defects; version 1.0.1 can misdecode non-ASCII backup text in Windows PowerShell. Both are superseded.

## Version 1.0.2 fix

Backups are read explicitly as UTF-8, with invalid byte sequences rejected. A non-ASCII font-family regression test verifies preservation in both PowerShell environments.

## Version 1.0.1 fixes

- Some valid TOML constructs could be misidentified by the previous editor and written back as invalid configuration. The editor now refuses unsupported syntax before writing. Native appearance import remains available for configurations outside the supported subset.
- A backup previously controlled both the destination path and raw restore text. Restore now selects its destination independently, checks that the backup matches it, refuses links and non-TOML targets, and accepts only supported appearance tables and typed values. These checks cannot be disabled with `-Force`.
- CI uses a verified full commit reference for checkout, retains read-only token permissions, and does not persist checkout credentials.

The checks are intentionally conservative. Do not bypass a refusal by editing a backup or disabling validation. Use native import instead. Backups contain local paths and appearance preferences; keep them private.

## Fonts and execution

No proprietary font binaries are shipped. Optional downloads use the listed HTTPS sources with pinned sizes and SHA-256 hashes. The package does not upload app configuration or chats, install a service, register a startup task, or restart the app.

Run the scripts only from a package whose checksum and source you have reviewed. The command launchers set execution policy for their PowerShell process only; they do not change persistent Windows policy. Administrator access is unnecessary.

## Contact

Do not put credentials, private backups, personal paths, or private screenshots in public issues. Public issues are suitable for non-sensitive reproduction steps. This repository does not offer a private vulnerability intake channel.
