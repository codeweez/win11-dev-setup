# Requires: Windows 11, Admin PowerShell
# Usage   : irm "<url>" | iex

$ErrorActionPreference = "Stop"

function Require-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "[!] Please run PowerShell as Administrator." -ForegroundColor Red
        exit 1
    }
}

function Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Message"
}

Require-Admin
Log "Starting setup script..." "INFO"

# ---------- WinGet bootstrap ----------

function Ensure-WinGet {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log "WinGet already available." "INFO"
        return
    }
    Log "WinGet not found. Installing WinGet (this can take several minutes)..." "INFO"
    try {
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null  # [web:119]
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope AllUsers | Out-Null  # [web:119]
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers  # [web:119]
        Log "WinGet installation attempted. A reboot may be required before winget is usable." "INFO"
    }
    catch {
        Log "Failed to install WinGet automatically: $($_.Exception.Message)" "ERROR"
        Log "You can install WinGet manually from Microsoft Store (App Installer) and rerun this script." "INFO"
    }
}

Ensure-WinGet

function Install-App {
    param(
        [string]$Id,
        [string]$Name
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log "Skipping $Name because WinGet is not available." "ERROR"
        return
    }

    Log "Installing $Name ..." "INFO"
    try {
        winget install --id $Id --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity  # [web:51][web:117]
        Log "Finished installing $Name." "INFO"
    }
    catch {
        # IMPORTANT FIX: use ${Name} so the ':' is not treated as part of the variable
        Log "Error installing ${Name}: $($_.Exception.Message)" "ERROR
