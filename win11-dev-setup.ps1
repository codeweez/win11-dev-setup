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
        # Official guidance: use Microsoft.WinGet.Client to bootstrap winget. [web:13]
        Install-PackageProvider -Name NuGet -Force -Scope AllUsers | Out-Null  # [web:13]
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope AllUsers | Out-Null  # [web:13]
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers  # [web:13]
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
        winget install --id $Id --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
        Log "Finished installing $Name." "INFO"
    }
    catch {
        Log "Error installing $Name: $($_.Exception.Message)" "ERROR"
    }
}

# ---------- Debloat Windows 11 ----------

function Debloat-Windows11 {
    Log "Starting Windows 11 debloat (built-in apps only, safe subset)..." "INFO"

    # Very conservative list. You can extend as you like. [web:11][web:46]
    $patterns = @(
        "*Xbox*",
        "*ZuneMusic*",
        "*ZuneVideo*",
        "*GetHelp*",
        "*Getstarted*",
        "*Spotify*",
        "*Disney*",
        "*Twitter*",
        "*TikTok*",
        "*Facebook*",
        "*Cortana*",
        "*FeedbackHub*",
        "*MicrosoftTeams*",
        "*SkypeApp*",
        "*Microsoft.BingNews*",
        "*Microsoft.BingWeather*",
        "*Microsoft.Todos*",
        "*Microsoft.MicrosoftSolitaireCollection*"
    )

    foreach ($pat in $patterns) {
        Log "Removing AppX packages matching '$pat' for current user..." "INFO"
        Get-AppxPackage -Name $pat -AllUsers -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Log "Removing $($_.Name) for user $($_.InstallLocation)" "INFO"
                    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                }
                catch {
                    Log "Failed to remove $($_.Name): $($_.Exception.Message)" "ERROR"
                }
            }

        Log "Removing provisioned packages matching '$pat'..." "INFO"
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pat } |
            ForEach-Object {
                try {
                    Log "Removing provisioned package $($_.DisplayName)" "INFO"
                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                    Log "Failed to remove provisioned $($_.DisplayName): $($_.Exception.Message)" "ERROR"
                }
            }
    }

    Log "Debloat routine completed. A reboot is recommended." "INFO"
}

# ---------- Runtime menu ----------

Write-Host ""
Write-Host "=== Windows 11 Dev Setup ==="
Write-Host "1) Debloat Windows 11 (safe subset)"
Write-Host "2) Install Dev Stack (Python, Node.js, Java JDK, VS Code, Git, MySQL, MongoDB Compass, WinSCP, Firefox, Chrome)"
Write-Host "3) Do both (1 + 2)"
Write-Host "4) Exit"
Write-Host ""

$choice = Read-Host "Select an option (1-4)"

if ($choice -eq "4" -or [string]::IsNullOrWhiteSpace($choice)) {
    Log "User chose to exit. Nothing done." "INFO"
    exit 0
}

switch ($choice) {
    "1" { Debloat-Windows11 }
    "2" { }
    "3" { Debloat-Windows11 }
    default {
        Log "Invalid choice. Exiting." "ERROR"
        exit 1
    }
}

# ---------- Install dev stack (via WinGet) ----------

Log "Installing development tools and browsers..." "INFO"

# Package IDs tested/commonly used with winget. [web:51]
$apps = @(
    @{ Id = "Python.Python.3.13";               Name = "Python 3" },
    @{ Id = "OpenJS.NodeJS.LTS";               Name = "Node.js LTS" },
    @{ Id = "Oracle.JDK.21";                   Name = "Java JDK 21" },
    @{ Id = "Microsoft.VisualStudioCode";      Name = "Visual Studio Code" },
    @{ Id = "Mozilla.Firefox";                 Name = "Mozilla Firefox" },
    @{ Id = "Google.Chrome";                   Name = "Google Chrome" },
    @{ Id = "Git.Git";                         Name = "Git SCM" },
    @{ Id = "WinSCP.WinSCP";                   Name = "WinSCP" },
    @{ Id = "Oracle.MySQL";                    Name = "MySQL (Server + Tools)" },
    @{ Id = "MongoDB.Compass.Full";            Name = "MongoDB Compass" }
)

foreach ($app in $apps) {
    Install-App -Id $app.Id -Name $app.Name
}

Log "Dev stack installation phase finished. Some apps may require a reboot to finalize." "INFO"

Write-Host ""
Write-Host "All done. Recommended next steps:"
Write-Host "- Reboot Windows."
Write-Host "- Verify 'winget list' to see installed apps."
Write-Host "- Configure MySQL root password and MongoDB local connection as needed."
