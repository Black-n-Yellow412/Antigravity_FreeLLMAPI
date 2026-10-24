<#
===============================================================================
  ANTIGRAVITY PENDING UPDATE - THE "3 AM REINSTALL TRIGGER"
===============================================================================

  SYNOPSIS:
    A tiny wrapper script designed to run daily via Windows Task Scheduler
    (typically at 3:00 AM). It checks for the .pending_update.txt flag file
    created by Antigravity-Sentinel-Public.ps1. If the flag exists, it runs
    the full Antigravity-Reinstall-Public.ps1 pipeline (clean uninstall,
    install, patch, restore, launch). If no flag exists, it does nothing
    and exits quietly.

  HOW THE PAIR WORKS:
    Antigravity-Sentinel-Public.ps1  (2 AM)  ->  Downloads installer + sets flag
    Antigravity-PendingUpdate-Public.ps1 (3 AM) ->  Sees flag -> runs full reinstall

  PREREQUISITES:
    1. Windows 10 or 11 (64-bit)
    2. PowerShell 5.1+ (built into Windows)
    3. Antigravity-Reinstall-Public.ps1 in the same folder as this script
    4. (Recommended) Run via Task Scheduler with these settings:
         - Run whether user is logged on or not
         - Run with highest privileges
         - Hidden window (no blue console popup)

  TO SET UP THE SCHEDULED TASK:
    Run this script once with -RegisterTask. It will create a daily 3 AM
    Task Scheduler entry that runs this wrapper in the background.

===============================================================================
  USER CONFIGURATION
===============================================================================
#>

param(
    # Register the 3 AM daily Task Scheduler entry for this script.
    [switch]$RegisterTask,

    # Remove the Task Scheduler entry.
    [switch]$UnregisterTask,

    # Override the Workshop directory. Default: folder containing this script.
    [string]$WorkshopDir = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# -----------------------------------------------------------------------------
# RESOLVE PATHS
# -----------------------------------------------------------------------------
if (-not $WorkshopDir) {
    $WorkshopDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$FlagFile        = Join-Path $WorkshopDir ".pending_update.txt"
$ReinstallScript = Join-Path $WorkshopDir "Antigravity-Reinstall-Public.ps1"
$TaskName        = "Antigravity Pending Reinstall"

# -----------------------------------------------------------------------------
# TASK SCHEDULER REGISTRATION (OPTIONAL)
# -----------------------------------------------------------------------------
if ($RegisterTask -or $UnregisterTask) {
    Write-Host "=== Antigravity Pending Update - Task Scheduler Setup ===" -ForegroundColor Cyan

    if ($RegisterTask) {
        $thisScript = $MyInvocation.MyCommand.Definition
        $taskArgs = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $thisScript + '"'
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
        $trigger = New-ScheduledTaskTrigger -Daily -At "03:00AM"
        $settings = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 60) `
                    -MultipleInstances IgnoreNew

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
            -Settings $settings -Force | Out-Null
        Write-Host "  Task '$TaskName' registered: daily at 3:00 AM (hidden window)" -ForegroundColor Green
    }

    if ($UnregisterTask) {
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "  Task '$TaskName' removed." -ForegroundColor Green
        } else {
            Write-Host "  Task '$TaskName' not found. Nothing to remove." -ForegroundColor Yellow
        }
    }
    exit 0
}

# -----------------------------------------------------------------------------
# MAIN: CHECK FLAG AND RUN REINSTALL IF NEEDED
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Antigravity Pending Update Check ===" -ForegroundColor Cyan
Write-Host "Workshop directory: $WorkshopDir" -ForegroundColor Gray
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# --- No flag? Nothing to do. ---
if (-not (Test-Path $FlagFile)) {
    Write-Host "No pending update flag found. Nothing to do. Exiting quietly." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# --- Verify the reinstall script exists before we start tearing things down ---
if (-not (Test-Path $ReinstallScript)) {
    Write-Host "ERROR: Reinstall script not found at:" -ForegroundColor Red
    Write-Host "  $ReinstallScript" -ForegroundColor Red
    Write-Host "Please place Antigravity-Reinstall-Public.ps1 in the same folder as this script." -ForegroundColor Yellow
    exit 1
}

$pendingVersion = (Get-Content $FlagFile -Raw).Trim()
Write-Host "Pending update flag found (target version: $pendingVersion)." -ForegroundColor Yellow
Write-Host "Starting full Antigravity reinstall pipeline..." -ForegroundColor Yellow
Write-Host ""

try {
    # Run the reinstall script directly in this session (no nested process).
    # This keeps a single log stream and avoids window handle issues.
    & $ReinstallScript
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0 -or $null -eq $exitCode) {
        Write-Host ""
        Write-Host "=== Reinstall completed successfully! ===" -ForegroundColor Green
        if (Test-Path $FlagFile) {
            Remove-Item -Path $FlagFile -Force
            Write-Host "Pending update flag cleared." -ForegroundColor Green
        }
        exit 0
    } else {
        Write-Host ""
        Write-Host "ERROR: Reinstall failed with exit code $exitCode." -ForegroundColor Red
        Write-Host "The flag file was left in place so the next run can retry." -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Failed to run reinstall script: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "The flag file was left in place so the next run can retry." -ForegroundColor Yellow
    exit 1
}
