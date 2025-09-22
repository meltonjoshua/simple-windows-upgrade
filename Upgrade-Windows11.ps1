<#
.SYNOPSIS
  Silently sets registry keys, downloads, and runs the Windows 11 Installation Assistant.
 
.DESCRIPTION
  Designed for deployment through an RMM.
  Must be executed with administrative rights.
#>

param(
    [switch]$KeepOpen,  # Add this parameter to keep window open
    [switch]$ShowProgress = $true  # Show progress by default
)
 
# ----- CONFIG -----
$TempDir     = "C:\Temp"
$Installer   = Join-Path $TempDir "Windows11InstallationAssistant.exe"
$LogFile     = Join-Path $TempDir "upgrade.log"
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2171764"

# Progress tracking
$TotalSteps = 5
$CurrentStep = 0

function Update-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$Step
    )
    if ($ShowProgress) {
        $PercentComplete = ($Step / $TotalSteps) * 100
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
        Write-Host "[$Step/$TotalSteps] $Status" -ForegroundColor Cyan
    }
}

# Detect if running from one-liner (no console attached) or RMM
$IsInteractive = [Environment]::UserInteractive -and ![Console]::IsOutputRedirected
$RunningFromOneLiner = $MyInvocation.Line -match "iex.*iwr|Invoke-Expression.*Invoke-WebRequest"

if ($IsInteractive -and -not $RunningFromOneLiner) {
    $KeepOpen = $true  # Auto-enable for interactive sessions
}

# Step 1: Initialize
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Initializing upgrade process..." $CurrentStep

# Check if running as Administrator
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Warning "⚠️  This script requires Administrator privileges to modify registry keys."
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Right-click PowerShell → 'Run as Administrator'" -ForegroundColor Cyan
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 1
}

Write-Host "✅ Running with Administrator privileges" -ForegroundColor Green

# Create temp directory if needed
if (-not (Test-Path $TempDir)) {
    Write-Host "Creating temporary directory: $TempDir" -ForegroundColor Yellow
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
} else {
    Write-Host "Using existing temporary directory: $TempDir" -ForegroundColor Green
}
 
# ----- SET REGISTRY KEYS -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Configuring registry keys for upgrade compatibility..." $CurrentStep

$regItems = @(
    @{Path="HKCU:\SOFTWARE\Microsoft\PCHC"; Name="UpgradeEligibility"; Description="User upgrade eligibility"},
    @{Path="HKLM:\SOFTWARE\Microsoft\PCHC"; Name="UpgradeEligibility"; Description="System upgrade eligibility"},
    @{Path="HKLM:\SYSTEM\Setup\MoSetup"; Name="AllowUpgradesWithUnsupportedTPMOrCPU"; Description="TPM/CPU bypass"}
)
 
foreach ($item in $regItems) {
    Write-Host "Setting registry key: $($item.Description)" -ForegroundColor Yellow
    try {
        if (-not (Test-Path $item.Path)) {
            New-Item -Path $item.Path -Force | Out-Null
            Write-Host "  Created registry path: $($item.Path)" -ForegroundColor Green
        }
        New-ItemProperty -Path $item.Path -Name $item.Name -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Host "  Set $($item.Path)\$($item.Name) = 1" -ForegroundColor Green
    } catch {
        Write-Warning "  Failed to set $($item.Path)\$($item.Name): $($_.Exception.Message)"
        Write-Host "  This may affect upgrade compatibility on unsupported hardware." -ForegroundColor Yellow
    }
}
 
# ----- DOWNLOAD INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep

Write-Host "Download URL: $DownloadUrl" -ForegroundColor Yellow
Write-Host "Destination: $Installer" -ForegroundColor Yellow

try {
    $ProgressPreference = 'SilentlyContinue'  # Hide Invoke-WebRequest progress bar
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer -UseBasicParsing -ErrorAction Stop
    $ProgressPreference = 'Continue'  # Re-enable progress bar
    
    $FileSize = (Get-Item $Installer).Length / 1MB
    Write-Host "Downloaded successfully! File size: $([math]::Round($FileSize, 2)) MB" -ForegroundColor Green
} catch {
    $ProgressPreference = 'Continue'
    Write-Error "Failed to download Windows 11 Installation Assistant. $_"
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    exit 1
}
 
# ----- VERIFY INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Verifying downloaded installer..." $CurrentStep

if (Test-Path $Installer) {
    $FileInfo = Get-Item $Installer
    Write-Host "Installer verified successfully!" -ForegroundColor Green
    Write-Host "  File: $($FileInfo.Name)" -ForegroundColor Gray
    Write-Host "  Size: $([math]::Round($FileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray
    Write-Host "  Modified: $($FileInfo.LastWriteTime)" -ForegroundColor Gray
} else {
    Write-Error "Installer file not found after download!"
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    exit 1
}

# ----- RUN INSTALLER SILENTLY -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Starting Windows 11 upgrade process..." $CurrentStep

$arguments = "/quietinstall /skipeula /auto upgrade /CopyLogs `"$LogFile`""
Write-Host "Running installer with arguments: $arguments" -ForegroundColor Yellow
Write-Host "Log file will be created at: $LogFile" -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host "⚠️  IMPORTANT: The upgrade process will now begin and may take 30-60 minutes." -ForegroundColor Yellow
Write-Host "   Your computer will restart automatically when complete." -ForegroundColor Yellow
Write-Host "   Do not power off or interrupt the process." -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow

$process = Start-Process -FilePath $Installer -ArgumentList $arguments -PassThru -Wait

# Complete progress bar
if ($ShowProgress) {
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
}

# Show final status
if ($process.ExitCode -eq 0) {
    Write-Host "✅ Windows 11 upgrade completed successfully!" -ForegroundColor Green
    Write-Host "   Exit Code: $($process.ExitCode)" -ForegroundColor Green
    Write-Host "   Check $LogFile for detailed logs." -ForegroundColor Green
} else {
    Write-Host "❌ Windows 11 upgrade completed with errors." -ForegroundColor Red
    Write-Host "   Exit Code: $($process.ExitCode)" -ForegroundColor Red
    Write-Host "   Check $LogFile for error details." -ForegroundColor Red
}

# Keep window open if requested or running interactively
if ($KeepOpen) {
    Write-Host ""
    Write-Host "Press any key to close this window..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Return installer exit code to RMM
exit $process.ExitCode
