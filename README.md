# Segoe UI Emoji updater (Windows 10 / 11)

**One file. Double-click it.** The Windows emoji font
(`C:\Windows\Fonts\seguiemj.ttf`) is updated to the newest build, and your current font
is backed up first. No setup, no copying files around, no arguments.

## Use

1. Double-click **`EmojiFontUpdater.cmd`**.
2. Click **Yes** on the UAC prompt.
3. Done.

If the font is not in use it is replaced immediately — just restart WhatsApp/Edge.
If it is in use (the normal case), the swap is queued and applied before any app starts
on the next boot, and the script asks whether to restart now.

## Undo

Run the same file with `-Undo` to restore the newest backup:

```
EmojiFontUpdater.cmd -Undo
```

## Options (optional)

Run from a command prompt if you need them:

| Option | Meaning |
|---|---|
| `-DryRun` | Show what would happen. No changes, no admin needed. |
| `-Force` | Reinstall even if the installed font is the same version. |
| `-Source <file.ttf>` | Install a local font file instead of downloading. |
| `-Undo` | Restore the newest backup instead of updating. |

Example: `EmojiFontUpdater.cmd -Undo -DryRun`

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

## Notes

- Works on Windows 10 and 11. Needs internet unless `-Source` is used.
- A cumulative update or `sfc /scannow` can put an older font back; just run the script again.
- Native Windows 10 apps (WPF/.NET Framework) draw these glyphs as monochrome outlines;
  Chromium/WebView2 apps (WhatsApp, Edge, Chrome) show full colour.
- The font binaries are **not** bundled: `seguiemj.ttf` is Microsoft's property and
  redistribution isn't permitted. Restore from your own backup, or point `-Source` at a
  font file you obtained yourself.

## Credits

The font mirrors this tool downloads from are maintained by:

- **skeyuui** — [windows-seguiemj-emoji-tracker](https://github.com/skeyuui/windows-seguiemj-emoji-tracker)
- **Gitbreast** — [win11_emoji_for_win10](https://github.com/Gitbreast/win11_emoji_for_win10)

Thanks to both for keeping a current `seguiemj.ttf` available.

## License

MIT — see [LICENSE](LICENSE).
