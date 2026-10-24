# Antigravity + FreeLLMAPI Automated Suite

> **An automated, beginner-friendly suite of PowerShell scripts to install, update, and patch Google Antigravity with FreeLLMAPI multi-model routing on Windows — with hands-free nightly background update automation.**

---

## 🌟 Overview

[Google Antigravity](https://antigravity.google) is an incredible AI coding assistant, but out-of-the-box it is restricted to Google's cloud models. 

[FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) is an open-source multi-model router that lets you pool dozens of free-tier AI keys (Gemini, Groq, Cerebras, GitHub Models, Mistral, Ollama, etc.) into a single OpenAI-compatible `/v1` endpoint with automatic rate-limit failovers.

The patch created by **vahapogut** ([antigravity-add-model](https://github.com/vahapogut/antigravity-add-model)) unlocks Antigravity to support custom endpoints.

### 🍽️ The Three Scripts in This Suite

| Script | Nickname | Role |
|---|---|---|
| [`Antigravity-Reinstall-Public.ps1`](Antigravity-Reinstall-Public.ps1) | **The Main Course** | Complete setup: clean uninstall, install, GitHub patch sync, TypeScript build, model injection, tray minimization, and launch shortcut. |
| [`Antigravity-Sentinel-Public.ps1`](Antigravity-Sentinel-Public.ps1) | **The Appetizer** | Runs at 2:00 AM (or on demand) to check `antigravity.google/download` for new versions, silently pre-downloads the installer, and leaves Antigravity running uninterrupted. |
| [`Antigravity-PendingUpdate-Public.ps1`](Antigravity-PendingUpdate-Public.ps1) | **The Nightcap** | Runs at 3:00 AM via Windows Task Scheduler to see if a new installer was downloaded. If so, triggers the clean reinstall while you sleep. |

---

## 📋 Prerequisites

Before running the suite, make sure your Windows PC has:

1. **Windows 10 / 11 (64-bit)**
2. **Administrator Rights** — Required to install software and update services.
3. **Node.js (version 22.12.0 or higher)**:
   - Download the LTS installer from [nodejs.org](https://nodejs.org/) and install it.
   - To verify, open PowerShell and run: `node -v` and `npm -v`.
4. **Antigravity Windows Installer (`Antigravity-x64.exe`)**:
   - Download the installer from Google (or let the Sentinel script fetch it for you!).
   - Place it either in your `Downloads` folder or in the same directory as these scripts.
5. **FreeLLMAPI**:
   - Download and run the desktop app or Docker container from [FreeLLMAPI GitHub](https://github.com/tashfeenahmed/freellmapi).
   - Grab your API key and URL (default: `http://127.0.0.1:31415/v1/chat/completions`).
6. **PowerShell Execution Policy**:
   - Windows restricts running scripts by default. Open PowerShell as Administrator and run:
     ```powershell
     Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
     ```

---

## 🚀 Quick Start (Manual Setup in 3 Steps)

### Step 1: Clone or Download
Download the scripts and place them together in a folder of your choice (e.g. `C:\Antigravity-Setup`).

### Step 2: Configure Your Settings
Open `Antigravity-Reinstall-Public.ps1` in Notepad or VS Code. Near the top under **`USER CONFIGURATION`**, update these lines:

```powershell
# Put your FreeLLMAPI address:
$Global:Config_ApiUrl    = "http://127.0.0.1:31415/v1/chat/completions"

# Put your FreeLLMAPI API key:
$Global:Config_ApiKey    = "YOUR_FREELLMAPI_API_KEY_HERE"
```

### Step 3: Run as Administrator
Right-click your PowerShell icon, select **Run as Administrator**, navigate to your folder, and run:

```powershell
.\Antigravity-Reinstall-Public.ps1
```

*(Or right-click the `.ps1` file and choose "Run with PowerShell" elevated)*.

---

## 🤖 Hands-Free Nightly Update Automation (Set It and Forget It!)

Want Antigravity to automatically check for updates and update itself overnight without interrupting your daily work? Both the Sentinel and PendingUpdate scripts have built-in Task Scheduler installers!

Open PowerShell as Administrator in your script folder and run:

```powershell
# 1. Register the 2:00 AM Sentinel check:
.\Antigravity-Sentinel-Public.ps1 -RegisterTask

# 2. Register the 3:00 AM automated update runner:
.\Antigravity-PendingUpdate-Public.ps1 -RegisterTask
```

### How the Overnight Pipeline Works

```
10:00 PM -> Your normal nightly backup job (FreeFileSync, Robocopy, etc.)
            backs up your conversations (.gemini) and settings.

02:00 AM -> Antigravity-Sentinel-Public.ps1 runs in the background:
            - Checks Google for newer Antigravity releases
            - If newer: downloads the installer & creates .pending_update.txt
            - Antigravity remains open; your work is NOT interrupted.

03:00 AM -> Antigravity-PendingUpdate-Public.ps1 triggers:
            - Sees the .pending_update.txt flag
            - Runs the clean reinstall, updates the patch, and restores data
            - Clears the flag and launches fresh Antigravity
```

To remove the scheduled tasks at any time:
```powershell
.\Antigravity-Sentinel-Public.ps1 -UnregisterTask
.\Antigravity-PendingUpdate-Public.ps1 -UnregisterTask
```

---

## ⚙️ What the Reinstall Script Does Automatically

| Step | Action | Description |
|---|---|---|
| **1. Uninstall** | Clean Slate | Closes running instances and cleanly removes old versions & temporary data (including child helper processes). |
| **2. Install** | Fresh Setup | Installs `Antigravity-x64.exe` silently and prepares the binary directories. |
| **3. Patch Update** | GitHub Sync | Checks GitHub (`vahapogut/antigravity-add-model`) for the latest commit, downloads updates, and compiles TypeScript. |
| **4. Patch Deploy** | Language Server | Patches Antigravity's language server to support custom OpenAI-compatible endpoints. |
| **5. Configuration** | Settings & Tray | Configures Antigravity to minimize to system tray (`runInBackground=true`) and fixes UAC drive mapping isolation (`EnableLinkedConnections=1`). |
| **6. Restore** *(Optional)* | Data Migration | Optionally mirrors your previous conversations and configuration from a backup directory. |
| **7. Shortcut** | Browser Flags | Creates an "Antigravity (FreeLLMAPI)" shortcut with `--ignore-certificate-errors --disable-web-security` so local HTTP proxies work without browser blockades. |
| **8. Model Injection** | Zero-Click Setup | Directly injects your FreeLLMAPI model into `custom_models.json` using UTF-8 without BOM so Electron doesn't crash on launch. |

---

## 🛠️ Advanced CLI Options

You can skip specific steps using PowerShell parameters:

```powershell
# Patch an existing installation without reinstalling Antigravity:
.\Antigravity-Reinstall-Public.ps1 -SkipUninstall -SkipInstall

# Force re-download the latest patch files from GitHub:
.\Antigravity-Reinstall-Public.ps1 -ForcePatchUpdate

# Skip creating shortcuts or launching:
.\Antigravity-Reinstall-Public.ps1 -SkipShortcut -SkipModelInjection
```

---

## 💡 Troubleshooting & Known Windows Quirks Solved

- **Child Process Locks (`language_server.exe`):** Antigravity spawns background language server helper processes that hold open file locks even after the main window is closed. The scripts explicitly terminate lingering child processes to ensure uninstalls never get blocked.
- **Electron JSON Parse Crash (BOM Bug):** Standard PowerShell commands write UTF-8 with a Byte Order Mark (`0xEF, 0xBB, 0xBF`), which causes Electron's `JSON.parse` to silently crash and wipe settings. This script uses .NET `UTF8Encoding($false)` to guarantee valid JSON formatting.
- **UAC Network Drive Isolation:** When running tasks with elevated Administrator privileges, Windows separates mapped drive tokens. The script applies `EnableLinkedConnections = 1` in `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` so your drives remain accessible.
- **Local HTTP Proxy Blockade:** Modern Chromium/Electron apps block insecure local HTTP endpoints. The generated shortcut includes `--allow-running-insecure-content` and `--disable-web-security` to allow seamless local router connectivity.
- **Hidden Window Background Execution:** The Task Scheduler entries run with `-WindowStyle Hidden` so no annoying blue PowerShell console windows pop up while you're using the computer.

---

## 📄 License & Credits
- [Google Antigravity](https://antigravity.google) by Google
- [FreeLLMAPI](https://github.com/tashfeenahmed/freellmapi) by Tashfeen Ahmed
- [antigravity-add-model](https://github.com/vahapogut/antigravity-add-model) by Vahap Öğüt
- Suite automation scripts provided for community use under [MIT License](LICENSE).
