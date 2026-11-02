# Security audit — EmojiFontUpdater

Audited before the initial public release. Scope: every file in this repository
(`EmojiFontUpdater.cmd`, `README.md`).

Date: 2026-11-02
Files (SHA-256):

| File | SHA-256 |
|---|---|
| `EmojiFontUpdater.cmd` | `288633C933856FB965F52DBC04244EF316C324296E912AF8FAFEFCEA1C381465` |
| `README.md` | `F988D1875FDCB8574B6C20263943D1CDB6BFC2B0FA22EDC29C21F7C9CB118ED3` |

## Summary

No credentials, secrets, telemetry, obfuscation or data exfiltration were found.
The script is a single self-contained batch file that embeds a PowerShell helper
between `<#PS#>` / `<#/PS#>` markers and runs it. All behaviour matches the
documented purpose: replace `C:\Windows\Fonts\seguiemj.ttf` with a newer copy.

Overall risk for a public release: **low / acceptable**, with the supply-chain
notes below understood.

## Findings

### 1. Third-party font download (informational, by design)

The only network access is downloading the font over HTTPS from two GitHub raw
URLs (`raw.githubusercontent.com/...`). Risks and mitigations:

- Transport is HTTPS (`Tls12` forced).
- The downloaded file is parsed and must report family name `Segoe UI Emoji`,
  otherwise the script aborts.
- The file is scanned with Windows Defender (`MpCmdRun.exe -Scan`) when present.
- **Residual risk:** the font bytes are *not* pinned to a known SHA-256, so a
  compromised upstream repo could serve a different but still-valid emoji font.
  This is inherent to an "always latest" updater. Users who need reproducibility
  should pass `-Source <file.ttf>` with a file they trust.

### 2. Elevation and `ExecutionPolicy Bypass` (informational)

The script self-elevates via `Start-Process -Verb RunAs` and runs PowerShell with
`-ExecutionPolicy Bypass`. This is normal for a double-click installer and does
not itself grant code execution beyond what the user invoked. No remote or
obfuscated code is fetched or executed.

### 3. Privileged system changes (by design, documented)

The script writes to `HKLM\...\Session Manager\PendingFileRenameOperations`,
adjusts ACLs on `seguiemj.ttf`/`seguiemj.upd` (`takeown`/`icacls`), and restarts
the `FontCache` service. All are required to swap a font that is locked by
Windows. The original file is copied to `Documents\EmojiFontBackup` first, and a
`revert-emoji.ps1` is produced for undo.

### 4. No secret / exfiltration patterns

Searched for passwords, tokens, API keys, private keys, `Invoke-Expression`,
`DownloadString`, `certutil`, `bitsadmin`, `schtasks`, `net user`, `vssadmin`,
`wevtutil`, base64 decode, and plain-HTTP URLs. Only the expected
`Start-Process` (elevation) and `Invoke-WebRequest` (font download) matched.

### 5. Argument handling (informational)

`%*` is passed through to the helper script. A caller who can already run the
script can also pass `-Source <path>`, which is an intended feature. No injection
into a higher-privilege context beyond the elevation the user approves.

## Recommendation

Safe to publish publicly as-is, with the un-pinned download understood as the
main trade-off. If you later want stricter guarantees, add an expected SHA-256
check for the downloaded font.
