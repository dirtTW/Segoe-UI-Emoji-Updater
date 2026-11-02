@echo off
setlocal EnableExtensions
set "SELF=%~f0"
set "ARGS=%*"
set "ELEVATE=1"
echo %ARGS% | findstr /i "dryrun" >nul && set "ELEVATE=0"

if "%ELEVATE%"=="1" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Requesting administrator rights...
        if defined ARGS (
            powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -ArgumentList $env:ARGS -Verb RunAs"
        ) else (
            powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
        )
        exit /b
    )
)

set "PS1=%TEMP%\update-emoji-font.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:SELF);$i=$t.LastIndexOf('<#PS#>');$j=$t.LastIndexOf('<#/PS#>');if($i -lt 0 -or $j -lt 0){exit 9};[IO.File]::WriteAllText($env:PS1,$t.Substring($i+6,$j-$i-6),(New-Object Text.UTF8Encoding $false))"
if errorlevel 1 (
    echo Failed to unpack the helper script.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (echo Done.) else (echo Finished with code %RC%.)
echo.
pause
exit /b %RC%

<#PS#>
param(
    [switch]$DryRun,
    [string]$Source,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$FontsDir  = Join-Path $env:SystemRoot 'Fonts'
$Target    = Join-Path $FontsDir 'seguiemj.ttf'
$Stage     = Join-Path $FontsDir 'seguiemj.upd'
$BackupDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'EmojiFontBackup'
$TID       = '*S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
$SYSID     = '*S-1-5-18'
$ADMID     = '*S-1-5-32-544'
$USRID     = '*S-1-5-32-545'
$ACID      = '*S-1-15-2-1'
$RACID     = '*S-1-15-2-2'
$Sources   = @(
    'https://raw.githubusercontent.com/skeyuui/windows-seguiemj-emoji-tracker/main/seguiemj.ttf',
    'https://raw.githubusercontent.com/Gitbreast/win11_emoji_for_win10/main/newest/seguiemj.ttf'
)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not ('EmojiFontProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text;
public class EmojiFontProbe {
    public string Family = ""; public string Version = ""; public int Glyphs = 0;
    public static EmojiFontProbe Read(string path) {
        var r = new EmojiFontProbe();
        byte[] b = File.ReadAllBytes(path);
        if (b.Length < 12) return r;
        Func<int,int> U = o => (b[o]<<8)|b[o+1];
        Func<int,long> L = o => ((long)b[o]<<24)|((long)b[o+1]<<16)|((long)b[o+2]<<8)|b[o+3];
        bool sfnt = (b[0] == 0 && b[1] == 1 && b[2] == 0 && b[3] == 0);
        string sig = Encoding.ASCII.GetString(b, 0, 4);
        if (!sfnt && sig != "OTTO" && sig != "true") return r;
        int n = U(4), nm = -1, mp = -1;
        for (int i = 0; i < n; i++) {
            int x = 12 + i * 16;
            if (x + 16 > b.Length) break;
            string t = Encoding.ASCII.GetString(b, x, 4);
            long off = L(x + 8);
            if (t == "name") nm = (int)off; else if (t == "maxp") mp = (int)off;
        }
        if (nm > 0) {
            int c = U(nm + 2), sb = nm + U(nm + 4);
            for (int i = 0; i < c; i++) {
                int x = nm + 6 + i * 12;
                if (x + 12 > b.Length) break;
                int pid = U(x), nid = U(x + 6), len = U(x + 8), of = U(x + 10);
                if (pid == 3 && (nid == 1 || nid == 5))
                    if (nid == 1) r.Family = Encoding.BigEndianUnicode.GetString(b, sb + of, len);
                    else r.Version = Encoding.BigEndianUnicode.GetString(b, sb + of, len);
            }
        }
        if (mp > 0) r.Glyphs = U(mp + 4);
        return r;
    }
}
'@
}

function Get-FontInfo([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $i = [EmojiFontProbe]::Read($Path)
    if (-not $i.Family) { throw "Not a valid TrueType font: $Path" }
    $v = $null
    if ($i.Version -match '([0-9]+(?:\.[0-9]+)+)') { $v = [version]$matches[1] }
    [pscustomobject]@{ Path = $Path; Family = $i.Family; Version = $v; VersionText = $i.Version; Glyphs = $i.Glyphs }
}

Write-Host ''
Say '  Segoe UI Emoji updater for Windows 10' 'Cyan'
Say '  ====================================' 'DarkCyan'
Write-Host ''

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) { throw 'This script needs administrator rights. Right-click it and choose "Run as administrator".' }

$current = Get-FontInfo $Target
if (-not $current) { throw "Current emoji font not found: $Target" }
Say ("  Installed : {0}  ({1} glyphs)" -f $current.Version, $current.Glyphs) 'White'

$work = Join-Path $env:TEMP 'emoji-font-update'
New-Item -ItemType Directory -Force -Path $work | Out-Null

if ($Source) {
    $candidate = (Resolve-Path -LiteralPath $Source).Path
    Say ("  Source    : {0}" -f $candidate) 'White'
} else {
    $candidate = Join-Path $work 'seguiemj.ttf'
    if (Test-Path $candidate) { Remove-Item $candidate -Force }
    $got = $false
    foreach ($u in $Sources) {
        try {
            Say ("  Download  : {0}" -f $u) 'DarkGray'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $u -OutFile $candidate -UseBasicParsing -TimeoutSec 300
            $got = $true; break
        } catch { Say ("    failed: " + $_.Exception.Message) 'Yellow' }
    }
    if (-not $got) { throw 'Could not download the font from any source. Use -Source <path-to-seguiemj.ttf> to install a local file.' }
}

$new = Get-FontInfo $candidate
if ($new.Family -ne 'Segoe UI Emoji') { throw "That file is '$($new.Family)', not 'Segoe UI Emoji'." }
Say ("  Available : {0}  ({1} glyphs)" -f $new.Version, $new.Glyphs) 'White'

$mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
if (Test-Path $mp) {
    Say '  Scanning  : Windows Defender...' 'DarkGray'
    $scan = (& $mp -Scan -ScanType 3 -File $candidate 2>&1 | Out-String)
    if ($scan -match 'found (\d+) threats' -and [int]$matches[1] -gt 0) { throw 'Windows Defender reported a threat in the downloaded font. Aborting.' }
    Say '  Scan      : clean' 'Green'
}

if ($new.Version -le $current.Version -and -not $Force) {
    Write-Host ''
    if ($new.Version -lt $current.Version) {
        Say ("  The available font ({0}) is older than the installed one ({1}) - skipping." -f $new.Version, $current.Version) 'Yellow'
    } else {
        Say ("  Already up to date ({0}) - nothing to do." -f $current.Version) 'Green'
    }
    Say '  Use -Force to reinstall anyway.' 'DarkGray'
    Write-Host ''
    exit 0
}

if ($DryRun) {
    Write-Host ''
    Say '  DRY RUN - nothing was changed. It would:' 'Cyan'
    Say ("    1. back up   {0}" -f $Target)
    Say ("                    -> {0}\seguiemj-{1}-<timestamp>.ttf" -f $BackupDir, $current.Version)
    Say ("    2. stage     {0}" -f $Stage)
    Say  '    3. replace now, or queue boot-time renames if the file is locked:'
    Say ("         {0}  ->  {1}\seguiemj-old-{2}-<timestamp>.ttf" -f $Target, $BackupDir, $current.Version)
    Say ("         {0}  ->  {1}" -f $Stage, $Target)
    Say  '    4. restart Font Cache and offer to reboot'
    Write-Host ''
    exit 0
}

if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$retireName = "seguiemj-old-$($current.Version)-$stamp.ttf"
$retired    = Join-Path $BackupDir $retireName

Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir "seguiemj-$($current.Version)-$stamp.ttf") -Force
Say ("  Backup    : {0}" -f $BackupDir) 'Green'

# Drop a standalone revert helper next to the backups so Undo always works.
$self = [IO.File]::ReadAllText($env:SELF)
$ra = $self.LastIndexOf('<#REVERT#>'); $rb = $self.LastIndexOf('<#/REVERT#>')
if ($ra -ge 0 -and $rb -gt $ra) {
    $revert = $self.Substring($ra + 10, $rb - $ra - 10)
    [IO.File]::WriteAllText((Join-Path $BackupDir 'revert-emoji.ps1'), $revert, (New-Object Text.UTF8Encoding $false))
}

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue }
Copy-Item -LiteralPath $candidate -Destination $Stage -Force

$replacedNow = $false
$movedAside  = $false
try {
    [IO.File]::Move($Target, $retired)
    $movedAside = $true
    [IO.File]::Move($Stage, $Target)
    $replacedNow = $true
} catch {
    if ($movedAside) { try { [IO.File]::Move($retired, $Target) } catch { } }
    Say ("  Locked    : {0}" -f $_.Exception.Message) 'Yellow'
}

if ($replacedNow) {
    icacls $Target /setowner "NT SERVICE\TrustedInstaller" | Out-Null
    icacls $Target /grant:r "$($SYSID):(RX)" "$($ADMID):(RX)" "$($USRID):(RX)" "$($TID):(F)" "$($ACID):(RX)" "$($RACID):(RX)" | Out-Null
    Say '  Result    : replaced immediately, no reboot needed.' 'Green'
    Say '  Note      : restart WhatsApp / Edge to pick it up.' 'DarkGray'
} else {
    Say '  Swapping at next boot (the file is in use right now).' 'Cyan'

    takeown /f $Target /a | Out-Null
    icacls $Target /grant "$($SYSID):(F)" | Out-Null
    takeown /f $Stage /a | Out-Null
    icacls $Stage /grant:r "$($SYSID):(F)" "$($ADMID):(RX)" "$($USRID):(RX)" "$($TID):(F)" "$($ACID):(RX)" "$($RACID):(RX)" | Out-Null
    icacls $Stage /setowner "NT SERVICE\TrustedInstaller" | Out-Null

    $ops = @(
        "\??\$Target", "\??\$retired",
        "\??\$Stage",  "\??\$Target"
    )
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $true)
    $existing = $key.GetValue('PendingFileRenameOperations', $null)
    $all = if ($existing) { @($existing) + $ops } else { $ops }
    $key.SetValue('PendingFileRenameOperations', [string[]]$all, [Microsoft.Win32.RegistryValueKind]::MultiString)
    $key.Close()
    Say '  Queued    : boot-time rename written to Session Manager.' 'Green'
}

try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($replacedNow) {
    Say ("  Updated {0} -> {1}." -f $current.Version, $new.Version) 'Green'
    Write-Host ''
    exit 0
}

Say ("  {0} -> {1} is ready. A restart is required to finish." -f $current.Version, $new.Version) 'Green'
Write-Host ''
$answer = Read-Host '  Restart this PC now? [y/N]'
if ($answer -match '^(y|yes)$') {
    Say '  Restarting in 20 seconds (close any unsaved work)...' 'Yellow'
    shutdown.exe /r /t 20 /c "Applying the new Segoe UI Emoji font"
} else {
    Say '  Restart later to apply the new emoji font.' 'Yellow'
}
Write-Host ''
exit 0
<#/PS#>
<#REVERT#>
<#
    revert-emoji.ps1

    Restores a previously backed-up Segoe UI Emoji font (seguiemj.ttf) on
    Windows 10/11. EmojiFontUpdater.cmd drops a copy of this script into
    Documents\EmojiFontBackup every time it runs, but it also works standalone
    if you copy it anywhere.

    Usage (as administrator):
        powershell -NoProfile -ExecutionPolicy Bypass -File revert-emoji.ps1

    Options:
        -Backup <file.ttf>  Restore this specific backup instead of the newest.
        -DryRun             Show what would happen. No changes, no admin needed.
#>
[CmdletBinding()]
param(
    [string]$Backup,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$FontsDir  = Join-Path $env:SystemRoot 'Fonts'
$Target    = Join-Path $FontsDir 'seguiemj.ttf'
$Stage     = Join-Path $FontsDir 'seguiemj.upd'
$BackupDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'EmojiFontBackup'
$TID       = '*S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
$SYSID     = '*S-1-5-18'
$ADMID     = '*S-1-5-32-544'
$USRID     = '*S-1-5-32-545'
$ACID      = '*S-1-15-2-1'
$RACID     = '*S-1-15-2-2'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not ('EmojiFontProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text;
public class EmojiFontProbe {
    public string Family = ""; public string Version = ""; public int Glyphs = 0;
    public static EmojiFontProbe Read(string path) {
        var r = new EmojiFontProbe();
        byte[] b = File.ReadAllBytes(path);
        if (b.Length < 12) return r;
        Func<int,int> U = o => (b[o]<<8)|b[o+1];
        Func<int,long> L = o => ((long)b[o]<<24)|((long)b[o+1]<<16)|((long)b[o+2]<<8)|b[o+3];
        bool sfnt = (b[0] == 0 && b[1] == 1 && b[2] == 0 && b[3] == 0);
        string sig = Encoding.ASCII.GetString(b, 0, 4);
        if (!sfnt && sig != "OTTO" && sig != "true") return r;
        int n = U(4), nm = -1, mp = -1;
        for (int i = 0; i < n; i++) {
            int x = 12 + i * 16;
            if (x + 16 > b.Length) break;
            string t = Encoding.ASCII.GetString(b, x, 4);
            long off = L(x + 8);
            if (t == "name") nm = (int)off; else if (t == "maxp") mp = (int)off;
        }
        if (nm > 0) {
            int c = U(nm + 2), sb = nm + U(nm + 4);
            for (int i = 0; i < c; i++) {
                int x = nm + 6 + i * 12;
                if (x + 12 > b.Length) break;
                int pid = U(x), nid = U(x + 6), len = U(x + 8), of = U(x + 10);
                if (pid == 3 && (nid == 1 || nid == 5))
                    if (nid == 1) r.Family = Encoding.BigEndianUnicode.GetString(b, sb + of, len);
                    else r.Version = Encoding.BigEndianUnicode.GetString(b, sb + of, len);
            }
        }
        if (mp > 0) r.Glyphs = U(mp + 4);
        return r;
    }
}
'@
}

function Get-FontInfo([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $i = [EmojiFontProbe]::Read($Path)
    if (-not $i.Family) { throw "Not a valid TrueType font: $Path" }
    $v = $null
    if ($i.Version -match '([0-9]+(?:\.[0-9]+)+)') { $v = [version]$matches[1] }
    [pscustomobject]@{ Path = $Path; Family = $i.Family; Version = $v; VersionText = $i.Version; Glyphs = $i.Glyphs }
}

Write-Host ''
Say '  Segoe UI Emoji - restore a backup' 'Cyan'
Say '  =================================' 'DarkCyan'
Write-Host ''

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) { throw 'This script needs administrator rights. Right-click it and choose "Run as administrator".' }

if ($Backup) {
    if (-not (Test-Path -LiteralPath $Backup)) { throw "Backup file not found: $Backup" }
    $candidate = (Resolve-Path -LiteralPath $Backup).Path
} else {
    if (-not (Test-Path -LiteralPath $BackupDir)) { throw "No backup folder found: $BackupDir" }
    $candidate = Get-ChildItem -LiteralPath $BackupDir -Filter 'seguiemj*.ttf' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $candidate) { throw "No emoji font backups found in $BackupDir" }
}

$restore = Get-FontInfo $candidate
if ($restore.Family -ne 'Segoe UI Emoji') { throw "That file is '$($restore.Family)', not 'Segoe UI Emoji'." }
Say ("  Restore   : {0}  ({1} glyphs)" -f $restore.Version, $restore.Glyphs) 'White'
Say ("  From      : {0}" -f $candidate) 'DarkGray'

$current = Get-FontInfo $Target
if ($current) { Say ("  Installed : {0}  ({1} glyphs)" -f $current.Version, $current.Glyphs) 'White' }

if ($DryRun) {
    Write-Host ''
    Say '  DRY RUN - nothing was changed. It would:' 'Cyan'
    Say ("    1. back up the current font to {0}" -f $BackupDir)
    Say ("    2. stage     {0}" -f $candidate)
    Say  '    3. replace now, or queue boot-time renames if the file is locked'
    Say  '    4. restart Font Cache and offer to reboot'
    Write-Host ''
    exit 0
}

if (-not $current) { throw "Current emoji font not found: $Target" }

if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir "seguiemj-before-revert-$($current.Version)-$stamp.ttf") -Force
Say ("  Backup    : {0}" -f $BackupDir) 'Green'

$retiredName = "seguiemj-old-$($current.Version)-$stamp.ttf"
$retired     = Join-Path $BackupDir $retiredName

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue }
Copy-Item -LiteralPath $candidate -Destination $Stage -Force

$replacedNow = $false
$movedAside  = $false
try {
    [IO.File]::Move($Target, $retired)
    $movedAside = $true
    [IO.File]::Move($Stage, $Target)
    $replacedNow = $true
} catch {
    if ($movedAside) { try { [IO.File]::Move($retired, $Target) } catch { } }
    Say ("  Locked    : {0}" -f $_.Exception.Message) 'Yellow'
}

if ($replacedNow) {
    icacls $Target /setowner "NT SERVICE\TrustedInstaller" | Out-Null
    icacls $Target /grant:r "$($SYSID):(RX)" "$($ADMID):(RX)" "$($USRID):(RX)" "$($TID):(F)" "$($ACID):(RX)" "$($RACID):(RX)" | Out-Null
    Say '  Result    : restored immediately, no reboot needed.' 'Green'
    Say '  Note      : restart WhatsApp / Edge to pick it up.' 'DarkGray'
} else {
    Say '  Swapping at next boot (the file is in use right now).' 'Cyan'

    takeown /f $Target /a | Out-Null
    icacls $Target /grant "$($SYSID):(F)" | Out-Null
    takeown /f $Stage /a | Out-Null
    icacls $Stage /grant:r "$($SYSID):(F)" "$($ADMID):(RX)" "$($USRID):(RX)" "$($TID):(F)" "$($ACID):(RX)" "$($RACID):(RX)" | Out-Null
    icacls $Stage /setowner "NT SERVICE\TrustedInstaller" | Out-Null

    $ops = @(
        "\??\$Target", "\??\$retired",
        "\??\$Stage",  "\??\$Target"
    )
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $true)
    $existing = $key.GetValue('PendingFileRenameOperations', $null)
    $all = if ($existing) { @($existing) + $ops } else { $ops }
    $key.SetValue('PendingFileRenameOperations', [string[]]$all, [Microsoft.Win32.RegistryValueKind]::MultiString)
    $key.Close()
    Say '  Queued    : boot-time rename written to Session Manager.' 'Green'
}

try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ''
if ($replacedNow) {
    Say '  Restored. Restart WhatsApp / Edge to pick it up.' 'Green'
    Write-Host ''
    exit 0
}

Say '  The restore is ready. A restart is required to finish.' 'Green'
Write-Host ''
$answer = Read-Host '  Restart this PC now? [y/N]'
if ($answer -match '^(y|yes)$') {
    Say '  Restarting in 20 seconds (close any unsaved work)...' 'Yellow'
    shutdown.exe /r /t 20 /c "Restoring the backed-up Segoe UI Emoji font"
} else {
    Say '  Restart later to apply the restored font.' 'Yellow'
}
Write-Host ''
exit 0
<#/REVERT#>
