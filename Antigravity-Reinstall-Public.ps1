<#
===============================================================================
  ANTIGRAVITY + FreeLLMAPI: ALL-IN-ONE AUTOMATED SETUP & REINSTALL SCRIPT
===============================================================================

  SYNOPSIS:
    This PowerShell script automates the complete lifecycle for Google Antigravity
    on Windows: clean uninstallation (optional), fresh installation, downloading
    and building the custom model patch (vahapogut/antigravity-add-model),
    patching Antigravity's language server, injecting FreeLLMAPI custom models,
    configuring system tray minimization, and creating a launch shortcut with
    the required security bypass flags for local proxies.

  WHY THIS SCRIPT EXISTS:
    Google Antigravity is a premier AI coding agent, but by default it is locked
    to Google's cloud models. FreeLLMAPI is a powerful local/remote multi-model
    router that aggregates free-tier tokens (Gemini, Groq, Cerebras, GitHub Models,
    Mistral, etc.) behind a single OpenAI-compatible endpoint.

    The "antigravity-add-model" patch bridges the two, allowing Antigravity to
    use any custom LLM provider or local router. This script completely automates
    the setup, updates, and maintenance so you don't have to fiddle with manual
    Node builds, JSON BOM bugs, or CLI flags every time Antigravity updates.

===============================================================================
  PREREQUISITES & SYSTEM REQUIREMENTS (READ BEFORE RUNNING!)
===============================================================================

  1. Operating System:
     - Windows 10 or Windows 11 (64-bit).
     - Must be run in PowerShell as Administrator (Right-click PowerShell ->
       "Run as administrator").

  2. PowerShell Execution Policy:
     - PowerShell restricts running downloaded scripts by default.
     - Open PowerShell as Administrator and run:
         Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
       (or run this script with: powershell -ExecutionPolicy Bypass -File .\setup.ps1)

  3. Node.js & npm (REQUIRED for compiling the patch):
     - Node.js version 22.12.0 or higher is required.
     - Download and install the LTS version from: https://nodejs.org/
     - Verify it is installed by opening a terminal and typing:
         node -v
         npm -v

  4. Antigravity Installer:
     - Download the Windows installer (`Antigravity-x64.exe`) from Google.
     - Place it in the same directory as this script, or put it in your
       `Downloads` folder, or specify its path in the USER CONFIGURATION section below.

  5. FreeLLMAPI (or any OpenAI-compatible API Server):
     - FreeLLMAPI desktop app or docker instance: https://github.com/tashfeenahmed/freellmapi
     - Make sure FreeLLMAPI is running and note your API URL and Key.
     - Default local desktop app address is usually: http://localhost:31415/v1/chat/completions
       (or http://127.0.0.1:31415/v1/chat/completions, or your LAN IP if hosted remotely).

===============================================================================
  USER CONFIGURATION (TWEAK THESE VALUES FOR YOUR COMPUTER!)
===============================================================================
#>

#Requires -RunAsAdministrator

param(
    # Command-line switches (leave default or pass flags when running)
    [switch]$SkipUninstall,       # Set to $true if you just want to patch existing Antigravity without reinstalling
    [switch]$SkipInstall,         # Set to $true if Antigravity is already installed
    [switch]$SkipPatchUpdate,     # Set to $true to skip checking GitHub for patch updates
    [switch]$ForcePatchUpdate,    # Set to $true to force re-downloading the patch even if on latest commit
    [switch]$SkipPatch,           # Set to $true to skip applying the patch
    [switch]$SkipConfigure,       # Set to $true to skip UI / tray configurations
    [switch]$SkipRestore,         # Set to $true to skip backup restoration (recommended for fresh setups)
    [switch]$SkipShortcut,        # Set to $true to skip creating the desktop/folder shortcut
    [switch]$SkipModelInjection,  # Set to $true to skip injecting your FreeLLMAPI model into custom_models.json
    [string]$InstallerPath = "",  # Optional custom path to Antigravity-x64.exe
    [string]$PatchDir = ""        # Optional custom folder for the patch files
)

# -----------------------------------------------------------------------------
# [USER CONFIG 1] FreeLLMAPI / Custom Model Settings
# Replace these placeholders with your actual FreeLLMAPI server details.
# -----------------------------------------------------------------------------
$Global:Config_ModelName        = "models/freellmapi"                          # Internal model ID
$Global:Config_DisplayName      = "FreeLLMAPI (Auto)"                          # Name shown in Antigravity model dropdown
$Global:Config_ModelDescription = "Multi-model token pool via FreeLLMAPI"      # Description shown in UI
$Global:Config_Provider         = "openai"                                     # API format ("openai" compatible)

# TODO: Put your FreeLLMAPI or proxy endpoint here:
# If running locally on the same PC: "http://127.0.0.1:31415/v1/chat/completions"
# If running on another machine on your LAN: "http://192.168.1.XXX:31415/v1/chat/completions"
$Global:Config_ApiUrl           = "http://127.0.0.1:31415/v1/chat/completions"

# TODO: Put your FreeLLMAPI API key or token here:
$Global:Config_ApiKey           = "YOUR_FREELLMAPI_API_KEY_HERE"

# The upstream model you want FreeLLMAPI to route to ("auto" lets FreeLLMAPI decide):
$Global:Config_ExternalModel    = "auto"

# -----------------------------------------------------------------------------
# [USER CONFIG 2] Backup & Restore Settings (Optional)
# If you are reinstalling and want to restore previous memory, conversations & settings
# from a backup folder, configure the path below. If this is a brand new install,
# you can leave this blank or run with -SkipRestore.
# -----------------------------------------------------------------------------
# Example: "D:\Backups\Antigravity\.gemini"
$Global:Config_BackupGeminiDir  = ""

# Example: "D:\Backups\Antigravity\app_storage.json"
$Global:Config_BackupAppStorage = ""

# =============================================================================
# SCRIPT INITIALIZATION & ENVIRONMENT SETUP
# (No need to edit below unless you know what you are doing)
# =============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Directory where this script is executed
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = Get-Location }

# Auto-locate Installer Path if not explicitly provided
if (-not $InstallerPath) {
    $candidates = @(
        (Join-Path $ScriptDir "Antigravity-x64.exe"),
        "$env:USERPROFILE\Downloads\Antigravity-x64.exe",
        "$env:USERPROFILE\Downloads\Antigravity-x64 (1).exe"
    )
    foreach ($cand in $candidates) {
        if (Test-Path $cand) {
            $InstallerPath = $cand
            break
        }
    }
    if (-not $InstallerPath) {
        $InstallerPath = "$env:USERPROFILE\Downloads\Antigravity-x64.exe"
    }
}

# Auto-locate Patch Directory if not explicitly provided
if (-not $PatchDir) {
    $coLocatedPatch = Join-Path $ScriptDir "antigravity_patch"
    $downloadsPatch = "$env:USERPROFILE\Downloads\antigravity_patch"
    if (Test-Path $coLocatedPatch) {
        $PatchDir = $coLocatedPatch
    } elseif (Test-Path $downloadsPatch) {
        $PatchDir = $downloadsPatch
    } else {
        $PatchDir = $coLocatedPatch
    }
}

# Setup log file
$LogFilePath = Join-Path $ScriptDir "Antigravity-Setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Cleanup older log files from previous runs in the same folder
Get-ChildItem -Path $ScriptDir -Filter "Antigravity-Setup-*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $LogFilePath } |
    ForEach-Object { try { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue } catch {} }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = switch ($Level) {
        "ERROR"   { "[ERROR]" }
        "WARN"    { "[WARN] " }
        "SUCCESS" { "[OK]   " }
        default   { "[INFO] " }
    }
    $logEntry = "$timestamp $prefix $Message"
    
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARN"    { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry -ForegroundColor Cyan }
    }
    Add-Content -Path $LogFilePath -Value $logEntry
}

# Initialize log file
New-Item -Path $LogFilePath -ItemType File -Force | Out-Null
Write-Log "================================================================="
Write-Log "Starting Antigravity + FreeLLMAPI Automated Setup"
Write-Log "Script Directory: $ScriptDir"
Write-Log "Log file: $LogFilePath"
Write-Log "================================================================="

# Target application installation paths
$Paths = @{
    InstallDir         = "$env:LOCALAPPDATA\Programs\antigravity"
    AppDataRoaming     = "$env:APPDATA\Antigravity"
    UserGeminiDir      = "$env:USERPROFILE\.gemini"
    
    PatchDeployScript  = Join-Path $PatchDir "scripts\deploy.mjs"
    PatchDeployWrapper = Join-Path $PatchDir "deploy.ps1"
    PatchDistDir       = Join-Path $PatchDir "dist"
    
    ShortcutPath       = Join-Path $ScriptDir "Antigravity (FreeLLMAPI).lnk"
    ExePath            = "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
    # Essential Chromium/Electron flags: allows connecting to unencrypted/local HTTP API proxies
    LaunchArgs         = "--ignore-certificate-errors --disable-web-security --allow-running-insecure-content"
    CustomModelsPath   = Join-Path $env:USERPROFILE ".gemini\antigravity\custom_models.json"
}

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

function Invoke-Retry {
    param(
        [scriptblock]$Action,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5,
        [string]$Description
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            return & $Action
        } catch {
            $errMsg = $_.Exception.Message
            Write-Log "Attempt $i/$MaxAttempts failed for ${Description}: $errMsg" "WARN"
            if ($i -lt $MaxAttempts) {
                Write-Log "Retrying in $DelaySeconds seconds..." "INFO"
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    throw "All $MaxAttempts attempts failed for ${Description}."
}

function Remove-DirectoryForce {
    param(
        [string]$Path,
        [int]$MaxAttempts = 4,
        [int]$DelaySeconds = 4
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (-not (Test-Path $Path)) {
            Write-Log "Directory already removed or absent: $Path" "SUCCESS"
            return
        }
        
        Write-Log "Removing directory (attempt $attempt/$MaxAttempts): $Path"
        
        # 1. Native PowerShell Remove-Item
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Log "Successfully removed: $Path" "SUCCESS"
            return
        } catch {
            Write-Log "Remove-Item failed: $($_.Exception.Message). Trying cmd rmdir..." "WARN"
        }
        
        # 2. Command Prompt rmdir fallback
        try {
            $null = cmd /c rmdir /s /q "`"$Path`"" 2>&1
            if ($LASTEXITCODE -eq 0 -and -not (Test-Path $Path)) {
                Write-Log "Successfully removed via cmd rmdir: $Path" "SUCCESS"
                return
            }
        } catch {}
        
        # 3. Robocopy mirror empty directory trick (clears deeply nested / locked subtrees)
        try {
            $emptyDir = "$env:TEMP\empty_$([guid]::NewGuid())"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null
            robocopy $emptyDir $Path /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS > $null 2>&1
            Remove-Item -Path $emptyDir -Force -ErrorAction SilentlyContinue
            $null = cmd /c rmdir /s /q "`"$Path`"" 2>&1
            if (-not (Test-Path $Path)) {
                Write-Log "Successfully cleared and removed via robocopy mirror: $Path" "SUCCESS"
                return
            }
        } catch {}
        
        if ($attempt -lt $MaxAttempts) {
            Write-Log "Directory still locked. Checking for lingering processes..." "WARN"
            $lingering = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
            if ($lingering) {
                Write-Log "Found lingering Antigravity processes, terminating..." "WARN"
                $lingering | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            # Also kill child helper processes (language_server.exe) which hold file
            # handles on the installation directory and block rmdir.
            $childLingering = Get-Process -Name "language_server" -ErrorAction SilentlyContinue
            if ($childLingering) {
                Write-Log "Found $($childLingering.Count) lingering child process(es) (language_server), terminating..." "WARN"
                $childLingering | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    throw "Unable to remove $Path after $MaxAttempts attempts. Please close any open applications and retry."
}

# =============================================================================
# PRE-CHECK: VERIFY PREREQUISITES
# =============================================================================
function Assert-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # 1. Check Node.js
    $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        throw "Node.js was not found in your system PATH! Node.js (>= 22.12.0) is required to build the patch. Please install from https://nodejs.org/ and restart your PowerShell terminal."
    }
    $nodeVersion = node -v
    Write-Log "Detected Node.js version: $nodeVersion" "SUCCESS"
    
    # 2. Check npm
    $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        throw "npm was not found in your system PATH! npm is required to install dependencies for the patch."
    }
    $npmVersion = npm -v
    Write-Log "Detected npm version: $npmVersion" "SUCCESS"
}

# =============================================================================
# STEP 1: CLEAN UNINSTALL (OPTIONAL)
# =============================================================================
function Step-Uninstall {
    Write-Log "========== STEP 1: CLEAN UNINSTALL =========="
    
    Write-Log "Checking for running Antigravity processes..."
    $processes = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Log "Closing $($processes.Count) running Antigravity process(es)..."
        $processes | Stop-Process -Force
        Start-Sleep -Seconds 5
        
        # Verify termination
        $stillRunning = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
        if ($stillRunning) {
            Write-Log "Waiting for lingering background processes..." "WARN"
            Start-Sleep -Seconds 5
            $stillRunning | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Write-Log "All Antigravity processes stopped" "SUCCESS"
    } else {
        Write-Log "No Antigravity processes currently running" "SUCCESS"
    }

    # IMPORTANT: Antigravity spawns child helper processes (e.g. language_server.exe)
    # that keep file handles open on the installation directory. Even after the main
    # process is killed, these orphans hold locks and cause "Access to the path is
    # denied" errors when we try to rmdir the folder. We must terminate them too.
    $childProcesses = Get-Process -Name "language_server" -ErrorAction SilentlyContinue
    if ($childProcesses) {
        Write-Log "Found $($childProcesses.Count) lingering Antigravity child process(es) (language_server), terminating..."
        $childProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Write-Log "Child processes terminated" "SUCCESS"
    }

    $uninstaller = Join-Path $Paths.InstallDir "Uninstall Antigravity.exe"
    if (Test-Path $uninstaller) {
        Write-Log "Running official silent uninstaller..."
        Invoke-Retry -Action {
            Start-Process -FilePath $uninstaller -ArgumentList "/S" -Wait -NoNewWindow
        } -Description "Official Uninstaller" -MaxAttempts 2
        Write-Log "Official uninstaller completed" "SUCCESS"
        Start-Sleep -Seconds 4
    } else {
        Write-Log "No previous uninstaller found at $uninstaller (skipping silent uninstaller)" "INFO"
    }
    
    # Clean leftover directories for a pure clean-slate install
    $dirsToRemove = @(
        $Paths.InstallDir,
        $Paths.AppDataRoaming,
        $Paths.UserGeminiDir
    )
    
    foreach ($dir in $dirsToRemove) {
        Remove-DirectoryForce -Path $dir
    }
    
    Write-Log "Clean uninstall completed successfully" "SUCCESS"
}

# =============================================================================
# STEP 2: INSTALL LATEST ANTIGRAVITY
# =============================================================================
function Step-Install {
    Write-Log "========== STEP 2: INSTALL LATEST ANTIGRAVITY =========="
    
    Write-Log "Locating Antigravity installer at: $InstallerPath"
    if (-not (Test-Path $InstallerPath)) {
        throw "Installer not found at '$InstallerPath'! Please download Antigravity-x64.exe and place it in your Downloads folder or specify its location in the script."
    }
    
    $sizeMB = [math]::Round(((Get-Item $InstallerPath).Length / 1MB), 1)
    Write-Log "Found installer ($sizeMB MB): $InstallerPath" "SUCCESS"
    
    Write-Log "Running installer silently (please wait a moment)..."
    Invoke-Retry -Action {
        Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -NoNewWindow -PassThru
    } -Description "Antigravity Installer" -MaxAttempts 2
    
    Write-Log "Installer finished execution" "SUCCESS"
    
    # The installer automatically launches Antigravity in the background upon completion.
    # We must cleanly terminate it so we can safely patch its binary files.
    Write-Log "Waiting for any auto-launched Antigravity instance to appear..."
    Start-Sleep -Seconds 10
    
    $autoLaunched = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if ($autoLaunched) {
        Write-Log "Closing auto-launched instance to allow patching..."
        $autoLaunched | Stop-Process -Force
        Start-Sleep -Seconds 3
        Write-Log "Auto-launched instance closed" "SUCCESS"
    }
    
    if (Test-Path $Paths.ExePath) {
        Write-Log "Installation verified: $($Paths.ExePath)" "SUCCESS"
    } else {
        throw "Installation verification failed! '$($Paths.ExePath)' was not found after running installer."
    }
}

# =============================================================================
# STEP 3: CHECK AND UPDATE PATCH (GitHub commit tracking)
# =============================================================================
function Step-UpdatePatch {
    param(
        [string]$TargetPatchDir,
        [switch]$Force
    )
    
    Write-Log "========== STEP 3: CHECK AND UPDATE PATCH =========="
    
    # Prune any previous single-backup folder to prevent disk bloat
    $backupDir = "${TargetPatchDir}_backup"
    if (Test-Path $backupDir) {
        Remove-Item -Path $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $commitFile = Join-Path $TargetPatchDir ".commit_sha"
    $localCommit = if (Test-Path $commitFile) { (Get-Content $commitFile -Raw).Trim() } else { "none" }
    $localShort = if ($localCommit.Length -ge 7) { $localCommit.Substring(0, 7) } else { $localCommit }
    Write-Log "Current local patch commit: $localShort"
    
    Write-Log "Checking GitHub repository (vahapogut/antigravity-add-model:main) for updates..."
    $apiUrl = "https://api.github.com/repos/vahapogut/antigravity-add-model/commits/main"
    $remoteCommit = $null
    
    try {
        $headers = @{ "Accept" = "application/vnd.github.v3+json"; "User-Agent" = "PowerShell-Antigravity-Reinstaller" }
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15
        $remoteCommit = $response.sha
        Write-Log "Latest commit on GitHub: $($remoteCommit.Substring(0, 7))" "INFO"
    } catch {
        Write-Log "Could not contact GitHub API ($($_.Exception.Message)). Proceeding with local patch files." "WARN"
        return
    }
    
    if (-not $Force -and (Test-Path $TargetPatchDir) -and ($localCommit -eq $remoteCommit)) {
        Write-Log "Patch is already on the latest commit ($($remoteCommit.Substring(0, 7))). No update required." "SUCCESS"
        return
    }
    
    Write-Log "Newer patch version found or fresh install needed. Downloading from GitHub..." "INFO"
    
    $tempDir = Join-Path $env:TEMP "antigravity_patch_$([guid]::NewGuid())"
    $tempZip = "$tempDir.zip"
    
    try {
        Write-Log "Downloading zip archive from GitHub..."
        Invoke-WebRequest -Uri "https://github.com/vahapogut/antigravity-add-model/archive/refs/heads/main.zip" -OutFile $tempZip -TimeoutSec 90
        
        Write-Log "Extracting archive..."
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        $extractedDir = Join-Path $tempDir "antigravity-add-model-main"
        
        # Backup existing patch directory if present
        if (Test-Path $TargetPatchDir) {
            Write-Log "Backing up existing patch directory..."
            Copy-Item $TargetPatchDir $backupDir -Recurse -Force
        } else {
            New-Item -Path $TargetPatchDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Log "Copying fresh patch files into $TargetPatchDir..."
        Copy-Item (Join-Path $extractedDir "*") $TargetPatchDir -Recurse -Force
        Set-Content -Path $commitFile -Value $remoteCommit
        
        Push-Location $TargetPatchDir
        Write-Log "Installing patch dependencies via npm (npm ci --ignore-scripts)..."
        npm ci --ignore-scripts
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
        
        Write-Log "Compiling patch TypeScript code (npm run build)..."
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build failed with exit code $LASTEXITCODE" }
        
        Write-Log "Patch successfully updated and compiled to commit $($remoteCommit.Substring(0, 7))!" "SUCCESS"
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Patch update failed: $errorMessage" "ERROR"
        if (Test-Path $backupDir) {
            Write-Log "Restoring previously working patch backup..." "WARN"
            Remove-Item $TargetPatchDir -Recurse -Force -ErrorAction SilentlyContinue
            Rename-Item $backupDir $TargetPatchDir -ErrorAction SilentlyContinue
        }
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# STEP 4: APPLY PATCH FOR FREELLMAPI
# =============================================================================
function Step-Patch {
    Write-Log "========== STEP 4: APPLY PATCH FOR FREELLMAPI =========="
    
    if (-not (Test-Path $PatchDir)) {
        Write-Log "Patch directory not found. Attempting download..." "WARN"
        Step-UpdatePatch -TargetPatchDir $PatchDir -Force
    }
    
    if (-not (Test-Path $Paths.PatchDeployWrapper)) {
        throw "Patch deploy wrapper '$($Paths.PatchDeployWrapper)' was not found! Cannot deploy patch."
    }
    
    Push-Location $PatchDir
    try {
        # Ensure node_modules and required electron asar tooling are present
        if (-not (Test-Path "node_modules") -or -not (Test-Path "node_modules\@electron\asar")) {
            Write-Log "Patch dependencies missing or incomplete. Running npm ci --ignore-scripts..."
            npm ci --ignore-scripts
            if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE" }
        }
        
        if (-not (Test-Path "dist")) {
            Write-Log "dist folder missing. Running npm run build..."
            npm run build
            if ($LASTEXITCODE -ne 0) { throw "npm run build failed with exit code $LASTEXITCODE" }
        }
        
        Write-Log "Running preflight patch verification (node scripts/deploy.mjs --check)..."
        $checkOutput = node scripts/deploy.mjs --check 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Check indicated build refresh needed. Rebuilding..." "WARN"
            npm ci --ignore-scripts
            npm run build
            if ($LASTEXITCODE -ne 0) { throw "Rebuild failed with exit code $LASTEXITCODE" }
        } else {
            Write-Log "Patch preflight check passed" "SUCCESS"
        }
        
        Write-Log "Deploying language server patch via deploy.ps1..."
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        
        Invoke-Retry -Action {
            $deployOutput = .\deploy.ps1 --patch-language-server 2>&1
            $deployExit = $LASTEXITCODE
            foreach ($line in $deployOutput) {
                Write-Log "  [deploy] $line"
            }
            if ($deployExit -ne 0) {
                throw "deploy.ps1 failed with exit code ${deployExit}: $($deployOutput -join '; ')"
            }
        } -Description "Patch deployment" -MaxAttempts 2
        
        Write-Log "Language server patched successfully!" "SUCCESS"
    } finally {
        Pop-Location
    }
}

# =============================================================================
# STEP 5: CONFIGURE TRAY BEHAVIOR & MAPPED DRIVES (UAC FIX)
# =============================================================================
function Step-Configure {
    Write-Log "========== STEP 5: CONFIGURE ENVIRONMENT & SETTINGS =========="
    
    # -------------------------------------------------------------------------
    # 1. Close-to-system-tray behavior:
    # Setting "runInBackground": "true" in app_storage.json makes Antigravity
    # minimize to the Windows system notification tray when you click the 'X'
    # button, instead of terminating the app and killing running tasks.
    #
    # CRITICAL TECHNICAL NOTE:
    # PowerShell 5.1 Out-File / Set-Content writes UTF-8 WITH a Byte Order Mark
    # (BOM: 0xEF, 0xBB, 0xBF). Electron's native JSON.parse crashes when encountering
    # a BOM and wipes or reverts app_storage.json to defaults. We must write
    # UTF-8 WITHOUT BOM using [System.IO.File]::WriteAllText.
    # -------------------------------------------------------------------------
    try {
        $appStorage = Join-Path $env:APPDATA "Antigravity\app_storage.json"
        $appStorageDir = Split-Path $appStorage -Parent
        if (-not (Test-Path $appStorageDir)) {
            New-Item -Path $appStorageDir -ItemType Directory -Force | Out-Null
        }
        
        if (Test-Path $appStorage) {
            $json = Get-Content $appStorage -Raw | ConvertFrom-Json
            $json | Add-Member -NotePropertyName "runInBackground" -NotePropertyValue "true" -Force
        } else {
            $json = @{ "runInBackground" = "true" }
        }
        
        $jsonString = $json | ConvertTo-Json -Depth 10
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($appStorage, $jsonString, $utf8NoBom)
        Write-Log "Configured runInBackground=true (minimize to tray enabled, UTF-8 no BOM)" "SUCCESS"
    } catch {
        Write-Log "Could not configure app_storage.json: $_" "WARN"
    }
    
    # -------------------------------------------------------------------------
    # 2. EnableLinkedConnections (UAC Elevation Drive Mapping Fix):
    # When running PowerShell or Task Scheduler tasks with administrative privileges,
    # Windows User Account Control (UAC) isolates network drive mappings (like Z:, Y:)
    # to the non-elevated user token. Setting EnableLinkedConnections=1 tells
    # Windows to share mapped network drives between elevated and standard tokens.
    # -------------------------------------------------------------------------
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $currentVal = (Get-ItemProperty -Path $regPath -Name "EnableLinkedConnections" -ErrorAction SilentlyContinue).EnableLinkedConnections
        if ($currentVal -ne 1) {
            Set-ItemProperty -Path $regPath -Name "EnableLinkedConnections" -Value 1 -Type DWord -Force
            Write-Log "Enabled EnableLinkedConnections=1 in Windows registry (shares mapped drives across elevation)" "SUCCESS"
        } else {
            Write-Log "EnableLinkedConnections is already configured (=1)" "INFO"
        }
    } catch {
        Write-Log "Could not configure EnableLinkedConnections registry key: $_" "WARN"
    }
}

# =============================================================================
# STEP 6: SURGICAL RESTORE FROM BACKUP (OPTIONAL)
# =============================================================================
function Step-Restore {
    Write-Log "========== STEP 6: SURGICAL RESTORE FROM BACKUP =========="
    
    if (-not $Global:Config_BackupGeminiDir -and -not $Global:Config_BackupAppStorage) {
        Write-Log "No backup paths configured in USER CONFIGURATION. Skipping restore." "INFO"
        return
    }
    
    # Restore app_storage.json
    if ($Global:Config_BackupAppStorage -and (Test-Path $Global:Config_BackupAppStorage)) {
        if (-not (Test-Path $Paths.AppDataRoaming)) {
            New-Item -Path $Paths.AppDataRoaming -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $Global:Config_BackupAppStorage -Destination (Join-Path $Paths.AppDataRoaming "app_storage.json") -Force
        Write-Log "Restored app_storage.json from backup" "SUCCESS"
    }
    
    # Restore .gemini directory (conversations, history, projects)
    # Uses robocopy to preserve folder structure while intentionally EXCLUDING
    # machine-specific or regenerated files (custom_models.json, installation_id)
    if ($Global:Config_BackupGeminiDir -and (Test-Path $Global:Config_BackupGeminiDir)) {
        if (-not (Test-Path $Paths.UserGeminiDir)) {
            New-Item -Path $Paths.UserGeminiDir -ItemType Directory -Force | Out-Null
        }
        Write-Log "Restoring .gemini data from $($Global:Config_BackupGeminiDir)..."
        robocopy $Global:Config_BackupGeminiDir $Paths.UserGeminiDir /MIR /XF custom_models.json* installation_id /R:1 /W:1 /NFL /NDL /NJH /NJS > $null 2>&1
        Write-Log ".gemini folder restored successfully" "SUCCESS"
    }
}

# =============================================================================
# STEP 7: CREATE LAUNCH SHORTCUT WITH PROXY FLAGS
# =============================================================================
function Step-CreateShortcut {
    Write-Log "========== STEP 7: CREATE LAUNCH SHORTCUT =========="
    
    if (-not (Test-Path $Paths.ExePath)) {
        Write-Log "Antigravity executable not found at $($Paths.ExePath), skipping shortcut." "WARN"
        return
    }
    
    Write-Log "Creating launch shortcut with required local proxy flags..."
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Paths.ShortcutPath)
    $shortcut.TargetPath = $Paths.ExePath
    $shortcut.Arguments = $Paths.LaunchArgs
    $shortcut.WorkingDirectory = Split-Path $Paths.ExePath -Parent
    $shortcut.Description = "Antigravity with FreeLLMAPI Integration"
    $shortcut.Save()
    
    Write-Log "Shortcut created: $($Paths.ShortcutPath)" "SUCCESS"
    Write-Log "TIP: You can right-click this shortcut to copy it to your Desktop or 'Pin to taskbar'." "INFO"
}

# =============================================================================
# STEP 8: INJECT CUSTOM MODEL & LAUNCH ANTIGRAVITY
# =============================================================================
function Step-InjectModelAndLaunch {
    Write-Log "========== STEP 8: INJECT MODEL CONFIG & LAUNCH =========="
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    
    # Ensure directory exists for custom_models.json
    $customModelsDir = Split-Path $Paths.CustomModelsPath -Parent
    if (-not (Test-Path $customModelsDir)) {
        New-Item -Path $customModelsDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $Paths.CustomModelsPath)) {
        $emptyTemplate = @{ models = @() } | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($Paths.CustomModelsPath, $emptyTemplate, $utf8NoBom)
        Write-Log "Created new custom_models.json" "INFO"
    }
    
    # Check if user left the default API key placeholder
    if ($Global:Config_ApiKey -eq "YOUR_FREELLMAPI_API_KEY_HERE") {
        Write-Log "NOTE: Config_ApiKey is still set to placeholder 'YOUR_FREELLMAPI_API_KEY_HERE'." "WARN"
        Write-Log "Remember to set your actual FreeLLMAPI key or update it inside Antigravity Settings > Custom Models." "WARN"
    }
    
    try {
        $json = Get-Content $Paths.CustomModelsPath -Raw | ConvertFrom-Json
        if (-not $json.models) { $json | Add-Member -NotePropertyName "models" -NotePropertyValue @() -Force }
        
        # Check if model with this identifier already exists
        $existing = $json.models | Where-Object { $_.name -eq $Global:Config_ModelName }
        if ($existing) {
            Write-Log "Model '$($Global:Config_ModelName)' already configured in custom_models.json." "INFO"
        } else {
            # Build the custom model object
            $newModel = [PSCustomObject]@{
                "name"              = $Global:Config_ModelName
                "displayName"       = $Global:Config_DisplayName
                "description"       = $Global:Config_ModelDescription
                "provider"          = $Global:Config_Provider
                "apiKey"            = $Global:Config_ApiKey
                "apiUrl"            = $Global:Config_ApiUrl
                "externalModelName" = $Global:Config_ExternalModel
                "encrypted"         = $false
                "supportsVision"    = $true
                "idleTimeout"       = 45000
            }
            # Prepend to the models array
            $json.models = @($newModel) + $json.models
            $jsonString = $json | ConvertTo-Json -Depth 10
            # CRITICAL: Save without UTF-8 BOM to prevent parse failures
            [System.IO.File]::WriteAllText($Paths.CustomModelsPath, $jsonString, $utf8NoBom)
            Write-Log "Successfully injected '$($Global:Config_DisplayName)' into custom_models.json!" "SUCCESS"
        }
    } catch {
        Write-Log "Failed to inject custom model: $_" "ERROR"
    }
    
    # Launch Antigravity
    # Using explorer.exe to launch the shortcut ensures the app runs inside the
    # interactive user desktop token (avoiding background service token isolation).
    Write-Log "Launching Antigravity..."
    $launched = $false
    if (Test-Path $Paths.ShortcutPath) {
        try {
            Start-Process "explorer.exe" -ArgumentList "`"$($Paths.ShortcutPath)`""
            $launched = $true
        } catch {
            Write-Log "Could not launch via Explorer shortcut. Launching directly..." "WARN"
        }
    }
    if (-not $launched) {
        Start-Process -FilePath $Paths.ExePath -ArgumentList $Paths.LaunchArgs -WindowStyle Normal
    }
    
    # Verify Antigravity started
    $running = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        if (Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue) {
            $running = $true
            Write-Log "Antigravity process confirmed running!" "SUCCESS"
            break
        }
    }
    if (-not $running) {
        Write-Log "Process not detected immediately; it may still be initializing." "INFO"
    }
}

# =============================================================================
# MAIN ORCHESTRATOR
# =============================================================================
function Main {
    Write-Log "Starting execution pipeline..."
    
    Assert-Prerequisites
    
    if (-not $SkipUninstall)      { Step-Uninstall }            else { Write-Log "Skipping Step 1 (Uninstall)" "INFO" }
    if (-not $SkipInstall)        { Step-Install }              else { Write-Log "Skipping Step 2 (Install)" "INFO" }
    if (-not $SkipPatchUpdate)    { Step-UpdatePatch -TargetPatchDir $PatchDir -Force:$ForcePatchUpdate } else { Write-Log "Skipping Step 3 (Patch Update)" "INFO" }
    if (-not $SkipPatch)          { Step-Patch }                else { Write-Log "Skipping Step 4 (Apply Patch)" "INFO" }
    if (-not $SkipConfigure)      { Step-Configure }            else { Write-Log "Skipping Step 5 (Configure)" "INFO" }
    if (-not $SkipRestore)        { Step-Restore }              else { Write-Log "Skipping Step 6 (Restore)" "INFO" }
    if (-not $SkipShortcut)       { Step-CreateShortcut }       else { Write-Log "Skipping Step 7 (Shortcut)" "INFO" }
    if (-not $SkipModelInjection) { Step-InjectModelAndLaunch } else { Write-Log "Skipping Step 8 (Model Injection & Launch)" "INFO" }
    
    Write-Log "================================================================="
    Write-Log "ALL STEPS COMPLETED SUCCESSFULLY!" "SUCCESS"
    Write-Log "Your Antigravity instance is patched and ready with FreeLLMAPI."
    Write-Log "================================================================="
}

try {
    Main
} catch {
    Write-Log "FATAL ERROR ENCOUNTERED: $($_.Exception.Message)" "ERROR"
    Write-Log "Check the detailed log file at: $LogFilePath" "ERROR"
    exit 1
}
