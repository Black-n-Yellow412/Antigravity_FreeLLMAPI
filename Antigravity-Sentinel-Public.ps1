<#
===============================================================================
  ANTIGRAVITY UPDATE SENTINEL - AUTOMATED VERSION CHECK & PRE-DOWNLOAD
===============================================================================

  SYNOPSIS:
    A lightweight, non-intrusive "sentinel" script that runs in the background
    (typically via Windows Task Scheduler at 2 AM) to check whether a newer
    version of Google Antigravity is available online. If a newer version is
    found, it silently downloads the installer and drops a flag file
    (.pending_update.txt) so that a companion script (Antigravity-PendingUpdate-Public.ps1)
    can trigger a clean reinstall at a later time (e.g. 3 AM).

    IMPORTANT: This script does NOT close Antigravity, does NOT run backups,
    and does NOT perform the reinstall. It only prepares everything so the
    actual reinstall can happen later with zero user interruption.

  WHY THIS EXISTS:
    Google Antigravity auto-updates can sometimes break custom patches or
    settings. By controlling the update cycle ourselves, we ensure that:
      1. The latest installer is downloaded while the app is still running.
      2. A clean uninstall + reinstall + patch + restore happens at a quiet
         time (e.g. 3 AM) when you're not using the machine.
      3. Your memory, conversations, settings, and custom models are surgically
         restored from backup.

===============================================================================
  PREREQUISITES
===============================================================================

  1. Windows 10 or 11 (64-bit)
  2. PowerShell 5.1+ (built into Windows)
  3. The Antigravity-Reinstall-Public.ps1 script (the "main course") placed
     in the same folder as this sentinel script.
  4. Internet access (to check antigravity.google/download for version info)
  5. (Optional) A backup folder where you keep nightly copies of your
     .gemini directory and app_storage.json - used by the reinstall script.

  TO RUN AUTOMATICALLY (RECOMMENDED):
    Use Windows Task Scheduler to run this script daily at 2:00 AM.
    At the bottom of this script, there is a helper function
    Register-SentinelTask that will create the scheduled task for you.
    Simply run this script manually once with -RegisterTask to set it up.

===============================================================================
  HOW THE FULL AUTOMATION PIPELINE WORKS
===============================================================================

    10:00 PM  ->  Your nightly backup job (e.g. FreeFileSync, robocopy, etc.)
                  copies .gemini + app_storage.json to a backup folder.

    02:00 AM  ->  THIS SCRIPT (Sentinel) runs:
                    - Checks antigravity.google/download for the latest version
                    - Compares to your installed version
                    - If newer: downloads the installer to the Workshop folder
                    - Creates .pending_update.txt flag file
                    - Antigravity keeps running the entire time (no interruption)

    03:00 AM  ->  Antigravity-PendingUpdate-Public.ps1 runs:
                    - Checks for .pending_update.txt flag
                    - If found: runs Antigravity-Reinstall-Public.ps1
                    - Clean uninstall -> install -> patch -> restore -> launch
                    - Clears the flag file when done

===============================================================================
  USER CONFIGURATION (TWEAK THESE FOR YOUR COMPUTER)
===============================================================================
#>

param(
    # Register a Windows Task Scheduler entry (2 AM daily) for this sentinel.
    # Run once manually with this flag to set up the scheduled task.
    [switch]$RegisterTask,

    # Remove the Windows Task Scheduler entry for this sentinel.
    [switch]$UnregisterTask,

    # Override the Workshop directory (where this script and the installer live).
    # Default: the folder containing this script.
    [string]$WorkshopDir = "",

    # Optional: A second folder to mirror the downloaded installer to
    # (e.g. a backup SSD or network share). Leave blank to skip mirroring.
    # Example: "D:\Backups\Antigravity" or "\\NAS\Shares\Antigravity"
    [string]$MirrorDir = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# RESOLVE PATHS
# -----------------------------------------------------------------------------

# Default to the folder where this script lives
if (-not $WorkshopDir) {
    $WorkshopDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$InstallerName   = "Antigravity-x64.exe"
$LocalInstaller  = Join-Path $WorkshopDir $InstallerName
$FlagFile        = Join-Path $WorkshopDir ".pending_update.txt"
$DownloadPage    = "https://antigravity.google/download"
$MirrorInstaller = if ($MirrorDir) { Join-Path $MirrorDir $InstallerName } else { $null }

# -----------------------------------------------------------------------------
# TASK SCHEDULER REGISTRATION (OPTIONAL)
# -----------------------------------------------------------------------------

function Register-SentinelTask {
    param([string]$ScriptPath, [string]$TaskName = "Antigravity Update Sentinel")

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Task '$TaskName' already exists. Updating..." -ForegroundColor Yellow
    }

    $taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptPath + '"'
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Daily -At "02:00AM"
    $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
                -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Force | Out-Null
    Write-Host "  Task '$TaskName' registered: daily at 2:00 AM" -ForegroundColor Green
}

function Remove-SentinelTask {
    param([string]$TaskName = "Antigravity Update Sentinel")

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Task '$TaskName' removed." -ForegroundColor Green
    } else {
        Write-Host "  Task '$TaskName' not found. Nothing to remove." -ForegroundColor Yellow
    }
}

# Handle registration flags and exit early
if ($RegisterTask -or $UnregisterTask) {
    Write-Host "=== Antigravity Update Sentinel - Task Scheduler Setup ===" -ForegroundColor Cyan
    if ($RegisterTask) {
        Register-SentinelTask -ScriptPath $MyInvocation.MyCommand.Definition
    }
    if ($UnregisterTask) {
        Remove-SentinelTask
    }
    exit 0
}

# -----------------------------------------------------------------------------
# MAIN SENTINEL LOGIC
# -----------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Antigravity Update Sentinel (Pre-Check) ===" -ForegroundColor Cyan
Write-Host "Workshop directory: $WorkshopDir" -ForegroundColor Gray
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# STEP 1: CHECK LATEST VERSION FROM OFFICIAL DOWNLOAD PAGE
# =============================================================================
Write-Host "[1/4] Checking antigravity.google/download for latest version..." -ForegroundColor Yellow

try {
    $pageContent = Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing -TimeoutSec 30
} catch {
    Write-Host "  ERROR: Could not reach $DownloadPage ($($_.Exception.Message))" -ForegroundColor Red
    Write-Host "  This is usually a temporary network issue. The sentinel will retry on the next run." -ForegroundColor Gray
    exit 1
}

# The download page contains a link like:
#   https://storage.googleapis.com/antigravity-public/antigravity-hub/2.26.0-.../windows-x64/Antigravity-x64.exe
# We extract the version from the URL path.
$latestUrl = $pageContent.Links.href | Where-Object {
    $_ -match "storage\.googleapis\.com/antigravity-public/antigravity-hub/.*windows-x64.*Antigravity-x64\.exe"
} | Select-Object -First 1

if (-not $latestUrl) {
    Write-Host "  ERROR: Could not find the Windows x64 download link on the page." -ForegroundColor Red
    Write-Host "  Google may have changed their download page structure. Check manually." -ForegroundColor Gray
    exit 1
}

# Extract version from URL (e.g. "2.26.0" from the URL path)
$urlVersion   = ($latestUrl -split "/")[-3]
$onlineSemVer = ($urlVersion -split "-")[0]
Write-Host "  Latest online version: $urlVersion (SemVer: $onlineSemVer)" -ForegroundColor Green

# =============================================================================
# STEP 2: COMPARE WITH INSTALLED VERSION
# =============================================================================
Write-Host "[2/4] Comparing with installed version..." -ForegroundColor Yellow

$installedExe     = "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
$installedVersion = if (Test-Path $installedExe) {
    (Get-Item $installedExe).VersionInfo.FileVersion
} else { $null }

$installerVersion = if (Test-Path $LocalInstaller) {
    (Get-Item $LocalInstaller).VersionInfo.FileVersion
} else { $null }

Write-Host "  Installed version:  $(if ($installedVersion) { $installedVersion } else { 'not found' })" -ForegroundColor Gray
Write-Host "  Local installer:    $(if ($installerVersion) { $installerVersion } else { 'not downloaded' })" -ForegroundColor Gray

# --- Already up to date? ---
if ($installedVersion) {
    try {
        if ([version]$installedVersion -ge [version]$onlineSemVer) {
            Write-Host "  Antigravity is already up to date ($installedVersion >= $onlineSemVer)." -ForegroundColor Green
            if (Test-Path $FlagFile) {
                Remove-Item -Path $FlagFile -Force
                Write-Host "  Cleared stale pending update flag." -ForegroundColor Gray
            }
            Write-Host "=== No update needed. Sentinel complete. ===" -ForegroundColor Cyan
            exit 0
        }
    } catch {
        # Fallback: string comparison if version parsing fails
        if ($installedVersion -eq $onlineSemVer) {
            Write-Host "  Antigravity is up to date ($installedVersion)." -ForegroundColor Green
            if (Test-Path $FlagFile) { Remove-Item -Path $FlagFile -Force }
            Write-Host "=== No update needed. Sentinel complete. ===" -ForegroundColor Cyan
            exit 0
        }
    }
}

# --- Installer already downloaded for this version? ---
if ($installerVersion) {
    try {
        if ([version]$installerVersion -ge [version]$onlineSemVer -and (Test-Path $FlagFile)) {
            Write-Host "  Installer $installerVersion already downloaded and flag is set." -ForegroundColor Green
            Write-Host "  Reinstall will run at the scheduled time. Nothing to do." -ForegroundColor Gray
            Write-Host "=== Sentinel complete (already prepared). ===" -ForegroundColor Cyan
            exit 0
        }
    } catch {}
}

# =============================================================================
# STEP 3: DOWNLOAD NEWER INSTALLER
# =============================================================================
Write-Host "[3/4] Newer version available ($onlineSemVer > $(if ($installedVersion) { $installedVersion } else { 'none' }))." -ForegroundColor Yellow
Write-Host "  Downloading installer (~100-200 MB, may take a few minutes)..." -ForegroundColor Yellow

try {
    Invoke-WebRequest -Uri $latestUrl -OutFile $LocalInstaller -TimeoutSec 600
} catch {
    Write-Host "  ERROR: Download failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  The sentinel will retry on the next scheduled run." -ForegroundColor Gray
    exit 1
}

$downloadedSize = [math]::Round(((Get-Item $LocalInstaller).Length / 1MB), 1)
Write-Host "  Downloaded: $LocalInstaller ($downloadedSize MB)" -ForegroundColor Green

# --- Optional: Mirror to backup/secondary location ---
if ($MirrorDir -and $MirrorInstaller) {
    try {
        if (-not (Test-Path $MirrorDir)) {
            New-Item -ItemType Directory -Path $MirrorDir -Force | Out-Null
        }
        Copy-Item -Path $LocalInstaller -Destination $MirrorInstaller -Force
        Write-Host "  Mirrored to:   $MirrorInstaller" -ForegroundColor Green
    } catch {
        Write-Host "  Mirror target not accessible, skipping mirror: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# =============================================================================
# STEP 4: CREATE PENDING UPDATE FLAG
# =============================================================================
Write-Host "[4/4] Creating pending update flag for 3 AM reinstall..." -ForegroundColor Yellow

# Write the version string to the flag file.
# Use UTF-8 WITHOUT BOM to avoid issues with any downstream JSON/text parsers.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($FlagFile, $urlVersion, $utf8NoBom)

Write-Host "  Flag created: $FlagFile (version: $urlVersion)" -ForegroundColor Green
Write-Host ""
Write-Host "=== Sentinel complete. ===" -ForegroundColor Cyan
Write-Host "  Antigravity continues running normally." -ForegroundColor Gray
Write-Host "  The reinstall will be triggered by Antigravity-PendingUpdate-Public.ps1" -ForegroundColor Gray
Write-Host "  (typically scheduled at 3:00 AM via Task Scheduler)." -ForegroundColor Gray
Write-Host ""
