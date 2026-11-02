@echo off
setlocal EnableExtensions
set "SELF=%~f0"
set "ARGS=%*"

rem Dry runs never need admin; everything else self-elevates.
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

rem Unpack the helper script embedded below and run it.
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
    [switch]$Force,
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---- configuration ---------------------------------------------------------
$FontsDir  = Join-Path $env:SystemRoot 'Fonts'
$Target    = Join-Path $FontsDir 'seguiemj.ttf'
$Stage     = Join-Path $FontsDir 'seguiemj.upd'
$BackupDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'EmojiFontBackup'

$SYSID = '*S-1-5-18'                                                        # SYSTEM
$ADMID = '*S-1-5-32-544'                                                    # Administrators
$USRID = '*S-1-5-32-545'                                                    # Users
$TID   = '*S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'  # TrustedInstaller
$ACID  = '*S-1-15-2-1'                                                      # ALL APPLICATION PACKAGES
$RACID = '*S-1-15-2-2'                                                      # ALL RESTRICTED APPLICATION PACKAGES

$Sources = @(
    'https://raw.githubusercontent.com/skeyuui/windows-seguiemj-emoji-tracker/main/seguiemj.ttf',
    'https://raw.githubusercontent.com/Gitbreast/win11_emoji_for_win10/main/newest/seguiemj.ttf'
)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# ---- font reader -----------------------------------------------------------
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

function Assert-EmojiFont($info) {
    if ($info.Family -ne 'Segoe UI Emoji') { throw "That file is '$($info.Family)', not 'Segoe UI Emoji'." }
}

# ---- privileged font swap --------------------------------------------------
function New-FontBackup([string]$Version) {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $Target -Destination (Join-Path $BackupDir "seguiemj-$Version-$stamp.ttf") -Force
    return $stamp
}

function Set-FontAcl([string]$Path) {
    icacls $Path /setowner "NT SERVICE\TrustedInstaller" | Out-Null
    icacls $Path /grant:r "$($SYSID):(RX)" "$($ADMID):(RX)" "$($USRID):(RX)" "$($TID):(F)" "$($ACID):(RX)" "$($RACID):(RX)" | Out-Null
}

function Grant-SystemFull([string]$Path) {
    takeown /f $Path /a | Out-Null
    icacls $Path /grant "$($SYSID):(F)" | Out-Null
}

function Queue-BootSwap([string]$Retired) {
    $ops = @("\??\$Target", "\??\$Retired", "\??\$Stage", "\??\$Target")
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $true)
    $existing = $key.GetValue('PendingFileRenameOperations', $null)
    $all = if ($existing) { @($existing) + $ops } else { $ops }
    $key.SetValue('PendingFileRenameOperations', [string[]]$all, [Microsoft.Win32.RegistryValueKind]::MultiString)
    $key.Close()
}

# Replace the installed font with $Candidate, backing up the current one first.
function Install-Font([string]$Candidate, [string]$Verb) {
    $current = Get-FontInfo $Target
    if (-not $current) { throw "Current emoji font not found: $Target" }

    $stamp   = New-FontBackup $current.Version
    $retired = Join-Path $BackupDir "seguiemj-old-$($current.Version)-$stamp.ttf"
    Say ("  Backup    : {0}" -f $BackupDir) 'Green'

    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Force -ErrorAction SilentlyContinue }
    Copy-Item -LiteralPath $Candidate -Destination $Stage -Force

    $now = $false; $aside = $false
    try {
        [IO.File]::Move($Target, $retired); $aside = $true
        [IO.File]::Move($Stage,  $Target);  $now   = $true
    } catch {
        if ($aside) { try { [IO.File]::Move($retired, $Target) } catch { } }
        Say ("  Locked    : {0}" -f $_.Exception.Message) 'Yellow'
    }

    if ($now) {
        Set-FontAcl $Target
        Say '  Result    : replaced immediately, no reboot needed.' 'Green'
        Say '  Note      : restart WhatsApp / Edge to pick it up.' 'DarkGray'
    } else {
        Say '  Swapping at next boot (the file is in use right now).' 'Cyan'
        Grant-SystemFull $Target
        Grant-SystemFull $Stage
        Set-FontAcl $Stage
        Queue-BootSwap $retired
        Say '  Queued    : boot-time rename written to Session Manager.' 'Green'
    }

    try { Stop-Service FontCache -Force -ErrorAction SilentlyContinue } catch { }

    $new = Get-FontInfo $Candidate
    Write-Host ''
    if ($now) { Say ("  {0} to {1}." -f $Verb, $new.Version) 'Green'; Write-Host ''; return }
    Say ("  {0} to {1} is ready. A restart is required to finish." -f $Verb, $new.Version) 'Green'
    Write-Host ''
    $answer = Read-Host '  Restart this PC now? [y/N]'
    if ($answer -match '^(y|yes)$') {
        Say '  Restarting in 20 seconds (close any unsaved work)...' 'Yellow'
        shutdown.exe /r /t 20 /c "Applying the Segoe UI Emoji font"
    } else {
        Say '  Restart later to apply the change.' 'Yellow'
    }
}

function Show-DryRun([string]$Candidate) {
    $current = Get-FontInfo $Target
    Write-Host ''
    Say '  DRY RUN - nothing was changed. It would:' 'Cyan'
    Say ("    1. back up   {0}" -f $Target)
    Say ("                    -> {0}\seguiemj-{1}-<timestamp>.ttf" -f $BackupDir, $current.Version)
    Say ("    2. stage     {0}" -f $Candidate)
    Say  '    3. replace now, or queue boot-time renames if the file is locked:'
    Say ("         {0}  ->  {1}\seguiemj-old-{2}-<timestamp>.ttf" -f $Target, $BackupDir, $current.Version)
    Say ("         {0}  ->  {1}" -f $Stage, $Target)
    Say  '    4. restart Font Cache and offer to reboot'
    Write-Host ''
}

# ---- candidate sources -----------------------------------------------------
function Get-NewestBackup {
    if (-not (Test-Path -LiteralPath $BackupDir)) { return $null }
    Get-ChildItem -LiteralPath $BackupDir -Filter 'seguiemj*.ttf' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function Get-DownloadedFont {
    $work = Join-Path $env:TEMP 'emoji-font-update'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $dest = Join-Path $work 'seguiemj.ttf'
    if (Test-Path $dest) { Remove-Item $dest -Force }
    foreach ($u in $Sources) {
        try {
            Say ("  Download  : {0}" -f $u) 'DarkGray'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return $dest
        } catch { Say ("    failed: " + $_.Exception.Message) 'Yellow' }
    }
    throw 'Could not download the font from any source. Use -Source <path-to-seguiemj.ttf> to install a local file.'
}

function Test-Defender([string]$Path) {
    $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (-not (Test-Path $mp)) { return }
    Say '  Scanning  : Windows Defender...' 'DarkGray'
    $scan = (& $mp -Scan -ScanType 3 -File $Path 2>&1 | Out-String)
    if ($scan -match 'found (\d+) threats' -and [int]$matches[1] -gt 0) {
        throw 'Windows Defender reported a threat in the downloaded font. Aborting.'
    }
    Say '  Scan      : clean' 'Green'
}

# ---- main ------------------------------------------------------------------
Write-Host ''
if ($Undo) {
    Say '  Segoe UI Emoji - restore a backup' 'Cyan'
    Say '  =================================' 'DarkCyan'
} else {
    Say '  Segoe UI Emoji updater for Windows 10' 'Cyan'
    Say '  ====================================' 'DarkCyan'
}
Write-Host ''

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $DryRun) { throw 'This script needs administrator rights. Right-click it and choose "Run as administrator".' }

$installed = Get-FontInfo $Target

if ($Undo) {
    $candidate = if ($Source) { (Resolve-Path -LiteralPath $Source).Path } else { Get-NewestBackup }
    if (-not $candidate) { throw "No emoji font backups found in $BackupDir" }
    $backup = Get-FontInfo $candidate
    Assert-EmojiFont $backup
    Say ("  Restore   : {0}  ({1} glyphs)" -f $backup.Version, $backup.Glyphs) 'White'
    Say ("  From      : {0}" -f $candidate) 'DarkGray'
    if ($installed) { Say ("  Installed : {0}  ({1} glyphs)" -f $installed.Version, $installed.Glyphs) 'White' }
    if ($DryRun) { Show-DryRun $candidate; exit 0 }
    Install-Font $candidate 'Restored'
    exit 0
}

if (-not $installed) { throw "Current emoji font not found: $Target" }
Say ("  Installed : {0}  ({1} glyphs)" -f $installed.Version, $installed.Glyphs) 'White'

if ($Source) {
    $candidate = (Resolve-Path -LiteralPath $Source).Path
    Say ("  Source    : {0}" -f $candidate) 'White'
} else {
    $candidate = Get-DownloadedFont
}

$new = Get-FontInfo $candidate
Assert-EmojiFont $new
Say ("  Available : {0}  ({1} glyphs)" -f $new.Version, $new.Glyphs) 'White'
Test-Defender $candidate

if ($new.Version -le $installed.Version -and -not $Force) {
    Write-Host ''
    if ($new.Version -lt $installed.Version) {
        Say ("  The available font ({0}) is older than the installed one ({1}) - skipping." -f $new.Version, $installed.Version) 'Yellow'
    } else {
        Say ("  Already up to date ({0}) - nothing to do." -f $installed.Version) 'Green'
    }
    Say '  Use -Force to reinstall anyway.' 'DarkGray'
    Write-Host ''
    exit 0
}

if ($DryRun) { Show-DryRun $candidate; exit 0 }

Install-Font $candidate 'Updated'
exit 0
<#/PS#>
