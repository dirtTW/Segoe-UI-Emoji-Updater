# Segoe UI Emoji updater (Windows 10)

One double-click updates the Windows emoji font (`C:\Windows\Fonts\seguiemj.ttf`) to the
newest build Microsoft ships, without breaking the font's security settings.

## Use

Double-click **`EmojiFontUpdater.cmd`** and approve the UAC prompt. That's it.

- If the font file is not in use, it is replaced immediately — just restart WhatsApp/Edge.
- If it is in use (normal case), the swap is queued and runs before any app starts on the
  next boot. The script asks whether to restart now.

## Options

Run from a command prompt if you need them:

| Option | Meaning |
|---|---|
| `-DryRun` | Show what would happen. No changes, no admin needed. |
| `-Force` | Reinstall even if the installed font is the same version. |
| `-Source <file.ttf>` | Install a local font file instead of downloading. |

Example: `EmojiFontUpdater.cmd -DryRun -Force`

## What it does

1. Reads the installed font's family name, version and glyph count.
2. Downloads the newest `seguiemj.ttf` (mirror of the stock Windows Server image font),
   verifies it really is *Segoe UI Emoji* and scans it with Windows Defender.
3. Refuses to downgrade unless `-Force` is given.
4. Copies the current font to `Documents\EmojiFontBackup\seguiemj-<version>-<timestamp>.ttf`.
5. Replaces it now, or queues two renames in
   `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`:
   - old `seguiemj.ttf` -> `Documents\EmojiFontBackup\seguiemj-old-<version>-<timestamp>.ttf`
   - staged `seguiemj.upd` -> `seguiemj.ttf`
6. Restarts the Font Cache service and offers a reboot.

The queued rename needs `SYSTEM` to have delete rights on the source file — Windows only
gives it read access by default, which is exactly why a plain copy fails. The script grants
that temporarily and restores a normal ACL afterwards.

## Undo

Every update drops `revert-emoji.ps1` into `Documents\EmojiFontBackup`. Right-click it ->
*Run with PowerShell* as administrator to stage the newest backup and reboot. The same
script ships in this repo and can restore a specific file:

    powershell -NoProfile -ExecutionPolicy Bypass -File revert-emoji.ps1 -Backup <backup.ttf>

Add `-DryRun` to see what it would do without changing anything.

`fonts-registry-backup.reg` and `fonts-registry-backup-wow64.reg` are exports of the
stock `...\CurrentVersion\Fonts` registry keys, kept for reference.

> The font binaries themselves are **not** bundled: `seguiemj.ttf` is Microsoft's property
> and redistribution isn't permitted. Restore from your own backup, or point `-Source` at a
> font file you obtained yourself.

## Notes

- Works on Windows 10 and 11. Needs internet unless `-Source` is used.
- A cumulative update or `sfc /scannow` can put an older font back; just run the script again.
- Native Windows 10 apps (WPF/.NET Framework) draw these glyphs as monochrome outlines;
  Chromium/WebView2 apps (WhatsApp, Edge, Chrome) show full colour.

## License

MIT — see [LICENSE](LICENSE).
