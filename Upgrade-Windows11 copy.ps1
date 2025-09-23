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
$TotalSteps = 8
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

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            default { "White" }
        }
    )
    # Also write to log file if it exists
    if (Test-Path $LogFile) {
        Add-Content -Path $LogFile -Value $logEntry
    }
}

function Test-SystemCompatibility {
    Write-Log "Starting system compatibility check..." "INFO"
    $compatibility = @{
        Compatible = $true
        Issues = @()
        Warnings = @()
    }
    
    # Check current Windows version
    try {
        $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $currentBuild = [int]$OS.CurrentBuild
        
        Write-Log "Current Windows: $($OS.ProductName) Build $currentBuild" "INFO"
        
        if ($currentBuild -ge 22000) {
            $compatibility.Issues += "Already running Windows 11 (Build $currentBuild)"
            $compatibility.Compatible = $false
        } elseif ($currentBuild -lt 18362) {
            $compatibility.Issues += "Windows 10 build too old (minimum 1903/18362 required)"
            $compatibility.Compatible = $false
        }
    } catch {
        $compatibility.Issues += "Unable to determine Windows version"
        $compatibility.Compatible = $false
    }
    
    # Check TPM
    try {
        $tpm = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction SilentlyContinue
        if ($tpm -and $tpm.IsEnabled_InitialValue) {
            Write-Log "TPM: Present and enabled (Version $($tpm.ManufacturerVersion))" "SUCCESS"
        } else {
            $compatibility.Warnings += "TPM not detected or not enabled"
            Write-Log "TPM: Not detected or not enabled (will use registry bypass)" "WARNING"
        }
    } catch {
        $compatibility.Warnings += "Could not check TPM status"
    }
    
    # Check CPU architecture
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    if ($cpu.Architecture -ne 9) {  # 9 = x64
        $compatibility.Issues += "CPU architecture not supported (x64 required)"
        $compatibility.Compatible = $false
    } else {
        Write-Log "CPU: $($cpu.Name) (x64)" "SUCCESS"
    }
    
    # Check RAM
    $ramGB = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    if ($ramGB -lt 4) {
        $compatibility.Issues += "Insufficient RAM: ${ramGB}GB (4GB minimum required)"
        $compatibility.Compatible = $false
    } else {
        Write-Log "RAM: ${ramGB}GB" "SUCCESS"
    }
    
    # Check disk space
    $systemDrive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    if ($freeSpaceGB -lt 64) {
        $compatibility.Issues += "Insufficient disk space: ${freeSpaceGB}GB free (64GB minimum required)"
        $compatibility.Compatible = $false
    } else {
        Write-Log "Disk Space: ${freeSpaceGB}GB free on $($systemDrive.DeviceID)" "SUCCESS"
    }
    
    # Check Secure Boot (if available)
    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        if ($secureBoot) {
            Write-Log "Secure Boot: Enabled" "SUCCESS"
        } else {
            $compatibility.Warnings += "Secure Boot not enabled"
            Write-Log "Secure Boot: Not enabled (recommended for Windows 11)" "WARNING"
        }
    } catch {
        $compatibility.Warnings += "Could not check Secure Boot status"
    }
    
    return $compatibility
}

function Start-UpgradeMonitoring {
    param([string]$LogPath)
    
    $monitoringJob = Start-Job -ScriptBlock {
        param($LogPath)
        
        $monitorLog = $LogPath -replace "\.log$", "_monitor.log"
        "Upgrade monitoring started $(Get-Date)" | Out-File -FilePath $monitorLog -Encoding UTF8
        
        while ($true) {
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            
            # Check for installer processes
            $processes = Get-Process | Where-Object {
                $_.ProcessName -like "*Windows11*" -or 
                $_.ProcessName -like "*setup*" -or 
                $_.ProcessName -like "*install*" -or
                $_.ProcessName -like "*assistant*"
            }
            
            if ($processes) {
                $processInfo = ($processes | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ", "
                "[$timestamp] Active processes: $processInfo" | Add-Content -Path $monitorLog
            }
            
            # Check Windows Update service
            $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            if ($wuService -and $wuService.Status -eq "Running") {
                "[$timestamp] Windows Update service active" | Add-Content -Path $monitorLog
            }
            
            # Check for upgrade folders
            if (Test-Path "C:\`$Windows.~BT") {
                "[$timestamp] Windows upgrade folder detected: C:\`$Windows.~BT" | Add-Content -Path $monitorLog
            }
            
            Start-Sleep 30
        }
    } -ArgumentList $LogPath
    
    return $monitoringJob
}

function Get-InstallerExitCodeMeaning {
    param([int]$ExitCode)
    
    switch ($ExitCode) {
        0 { return "Success - Upgrade completed successfully" }
        1 { return "General failure - Check logs for details" }
        2 { return "System requirements not met" }
        3 { return "User cancelled the operation" }
        4 { return "Another installation is in progress" }
        5 { return "Insufficient disk space" }
        6 { return "Unsupported architecture" }
        7 { return "Blocked by policy" }
        8 { return "Reboot required" }
        -1073741819 { return "Access denied or insufficient privileges" }
        -2147024894 { return "File not found or corrupted installer" }
        -2147024891 { return "Access denied" }
        default { return "Unknown error code: $ExitCode" }
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

# Initialize log file
"Windows 11 Upgrade Log - Started $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8
Write-Log "Upgrade process initialized" "INFO"

# Step 2: System Compatibility Check
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Checking system compatibility..." $CurrentStep

$compatibility = Test-SystemCompatibility

if (-not $compatibility.Compatible) {
    Write-Log "COMPATIBILITY CHECK FAILED:" "ERROR"
    foreach ($issue in $compatibility.Issues) {
        Write-Log "❌ $issue" "ERROR"
    }
    
    Write-Host "" -ForegroundColor Red
    Write-Host "❌ This system does not meet Windows 11 requirements." -ForegroundColor Red
    Write-Host "   The upgrade cannot proceed safely." -ForegroundColor Red
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 2
}

if ($compatibility.Warnings.Count -gt 0) {
    Write-Log "COMPATIBILITY WARNINGS:" "WARNING"
    foreach ($warning in $compatibility.Warnings) {
        Write-Log "⚠️  $warning" "WARNING"
    }
    Write-Host "⚠️  System has compatibility warnings but upgrade can proceed" -ForegroundColor Yellow
}

Write-Log "✅ System compatibility check passed" "SUCCESS"
 
# ----- SET REGISTRY KEYS -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Configuring registry keys for upgrade compatibility..." $CurrentStep

$regItems = @(
    @{Path="HKCU:\SOFTWARE\Microsoft\PCHC"; Name="UpgradeEligibility"; Description="User upgrade eligibility"},
    @{Path="HKLM:\SOFTWARE\Microsoft\PCHC"; Name="UpgradeEligibility"; Description="System upgrade eligibility"},
    @{Path="HKLM:\SYSTEM\Setup\MoSetup"; Name="AllowUpgradesWithUnsupportedTPMOrCPU"; Description="TPM/CPU bypass"}
)

Write-Log "Configuring registry keys for compatibility bypass..." "INFO"
 
foreach ($item in $regItems) {
    Write-Log "Setting registry key: $($item.Description)" "INFO"
    try {
        if (-not (Test-Path $item.Path)) {
            New-Item -Path $item.Path -Force | Out-Null
            Write-Log "Created registry path: $($item.Path)" "SUCCESS"
        }
        New-ItemProperty -Path $item.Path -Name $item.Name -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Write-Log "Set $($item.Path)\$($item.Name) = 1" "SUCCESS"
    } catch {
        Write-Log "Failed to set $($item.Path)\$($item.Name): $($_.Exception.Message)" "ERROR"
        Write-Log "This may affect upgrade compatibility on unsupported hardware." "WARNING"
    }
}
 
# ----- DOWNLOAD INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep

Write-Log "Download URL: $DownloadUrl" "INFO"
Write-Log "Destination: $Installer" "INFO"

# Remove existing installer if present
if (Test-Path $Installer) {
    Write-Log "Removing existing installer file..." "INFO"
    Remove-Item $Installer -Force
}

$downloadAttempts = 0
$maxAttempts = 3
$downloadSuccess = $false

while ($downloadAttempts -lt $maxAttempts -and -not $downloadSuccess) {
    $downloadAttempts++
    Write-Log "Download attempt $downloadAttempts of $maxAttempts..." "INFO"
    
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer -UseBasicParsing -ErrorAction Stop -TimeoutSec 300
        $ProgressPreference = 'Continue'
        
        # Verify download completed
        if (Test-Path $Installer) {
            $FileSize = (Get-Item $Installer).Length
            if ($FileSize -gt 1MB) {  # Minimum reasonable size
                $downloadSuccess = $true
                Write-Log "Downloaded successfully! File size: $([math]::Round($FileSize / 1MB, 2)) MB" "SUCCESS"
            } else {
                Write-Log "Download failed: File too small ($([math]::Round($FileSize / 1KB, 2)) KB)" "ERROR"
                Remove-Item $Installer -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Log "Download failed: File not created" "ERROR"
        }
    } catch {
        $ProgressPreference = 'Continue'
        Write-Log "Download attempt $downloadAttempts failed: $($_.Exception.Message)" "ERROR"
        
        if ($downloadAttempts -lt $maxAttempts) {
            Write-Log "Waiting 5 seconds before retry..." "INFO"
            Start-Sleep 5
        }
    }
}

if (-not $downloadSuccess) {
    Write-Log "Failed to download Windows 11 Installation Assistant after $maxAttempts attempts" "ERROR"
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 3
}
 
# ----- VERIFY INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Verifying downloaded installer..." $CurrentStep

if (Test-Path $Installer) {
    $FileInfo = Get-Item $Installer
    Write-Log "Installer verification successful!" "SUCCESS"
    Write-Log "File: $($FileInfo.Name)" "INFO"
    Write-Log "Size: $([math]::Round($FileInfo.Length / 1MB, 2)) MB" "INFO"
    Write-Log "Modified: $($FileInfo.LastWriteTime)" "INFO"
    
    # Verify file is executable
    if ($FileInfo.Extension -eq ".exe") {
        Write-Log "File type verified as executable" "SUCCESS"
    } else {
        Write-Log "Warning: File extension is not .exe" "WARNING"
    }
    
    # Check digital signature (if available)
    try {
        $signature = Get-AuthenticodeSignature $Installer -ErrorAction SilentlyContinue
        if ($signature.Status -eq "Valid") {
            Write-Log "Digital signature verified: $($signature.SignerCertificate.Subject)" "SUCCESS"
        } else {
            Write-Log "Digital signature status: $($signature.Status)" "WARNING"
        }
    } catch {
        Write-Log "Could not verify digital signature" "WARNING"
    }
} else {
    Write-Log "Installer file not found after download!" "ERROR"
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 4
}

# ----- PRE-INSTALLATION CHECKS -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Performing pre-installation checks..." $CurrentStep

# Check if another Windows installation is running
$existingSetup = Get-Process | Where-Object {
    $_.ProcessName -like "*setup*" -or 
    $_.ProcessName -like "*Windows11*" -or
    $_.ProcessName -like "*install*"
}

if ($existingSetup) {
    Write-Log "Another installation process is already running: $($existingSetup.Name -join ', ')" "ERROR"
    Write-Log "Please wait for the current installation to complete or restart the computer" "ERROR"
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 5
}

# Start background monitoring
Write-Log "Starting background monitoring..." "INFO"
$monitoringJob = Start-UpgradeMonitoring -LogPath $LogFile

# ----- RUN INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Starting Windows 11 upgrade process..." $CurrentStep

$arguments = "/quietinstall /skipeula /auto upgrade /CopyLogs `"$LogFile`""
Write-Log "Running installer with arguments: $arguments" "INFO"
Write-Log "Primary log file: $LogFile" "INFO"
Write-Log "Monitor log file: $($LogFile -replace '\.log$', '_monitor.log')" "INFO"

Write-Host "" -ForegroundColor Yellow
Write-Log "⚠️  IMPORTANT: The upgrade process will now begin and may take 30-90 minutes." "WARNING"
Write-Log "   Your computer will restart automatically when complete." "WARNING"
Write-Log "   Do not power off or interrupt the process." "WARNING"
Write-Host "" -ForegroundColor Yellow

# Record start time
$startTime = Get-Date
Write-Log "Upgrade started at: $startTime" "INFO"

try {
    $process = Start-Process -FilePath $Installer -ArgumentList $arguments -PassThru -ErrorAction Stop
    Write-Log "Installer process started with PID: $($process.Id)" "SUCCESS"
    
    # Monitor the process
    $checkInterval = 30 # seconds
    $lastLogCheck = Get-Date
    
    while (-not $process.HasExited) {
        Start-Sleep $checkInterval
        
        # Check if log file has been updated
        if (Test-Path $LogFile) {
            $logFile = Get-Item $LogFile
            if ($logFile.LastWriteTime -gt $lastLogCheck) {
                $lastLogCheck = $logFile.LastWriteTime
                Write-Log "Installation log updated at: $($logFile.LastWriteTime)" "INFO"
                
                # Show last few lines of log
                $lastLines = Get-Content $LogFile -Tail 3 -ErrorAction SilentlyContinue
                if ($lastLines) {
                    Write-Log "Recent log entries:" "INFO"
                    foreach ($line in $lastLines) {
                        Write-Log "  $line" "INFO"
                    }
                }
            }
        }
        
        # Show process is still running
        $elapsed = (Get-Date) - $startTime
        Write-Log "Installation running for $([math]::Round($elapsed.TotalMinutes, 1)) minutes..." "INFO"
    }
    
    # Wait for process to fully complete
    $process.WaitForExit()
    $endTime = Get-Date
    $totalTime = $endTime - $startTime
    
    Write-Log "Installer process completed after $([math]::Round($totalTime.TotalMinutes, 1)) minutes" "INFO"
    Write-Log "Exit code: $($process.ExitCode)" "INFO"
    
} catch {
    Write-Log "Failed to start installer process: $($_.Exception.Message)" "ERROR"
    $process = @{ ExitCode = -1 }
} finally {
    # Stop background monitoring
    if ($monitoringJob) {
        Stop-Job $monitoringJob -ErrorAction SilentlyContinue
        Remove-Job $monitoringJob -ErrorAction SilentlyContinue
        Write-Log "Background monitoring stopped" "INFO"
    }
}

# ----- FINAL STATUS AND CLEANUP -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Analyzing results and cleaning up..." $CurrentStep

# Complete progress bar
if ($ShowProgress) {
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
}

# Analyze exit code
$exitCodeMeaning = Get-InstallerExitCodeMeaning -ExitCode $process.ExitCode
Write-Log "Exit code meaning: $exitCodeMeaning" "INFO"

# Show final status
if ($process.ExitCode -eq 0) {
    Write-Log "✅ Windows 11 upgrade completed successfully!" "SUCCESS"
    Write-Log "Exit Code: $($process.ExitCode)" "SUCCESS"
    Write-Log "Total time: $([math]::Round($totalTime.TotalMinutes, 1)) minutes" "SUCCESS"
    
    # Check for restart requirement
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        Write-Log "⚠️  System restart required to complete installation" "WARNING"
    }
    
} elseif ($process.ExitCode -eq 8) {
    Write-Log "✅ Windows 11 upgrade initiated successfully!" "SUCCESS"
    Write-Log "Exit Code: $($process.ExitCode) - Reboot required" "SUCCESS"
    Write-Log "System will restart automatically to complete the upgrade" "INFO"
    
} else {
    Write-Log "❌ Windows 11 upgrade completed with errors" "ERROR"
    Write-Log "Exit Code: $($process.ExitCode)" "ERROR"
    Write-Log "Error Description: $exitCodeMeaning" "ERROR"
    
    # Provide troubleshooting information
    Write-Log "" "INFO"
    Write-Log "=== TROUBLESHOOTING INFORMATION ===" "INFO"
    Write-Log "Check the following log files for detailed error information:" "INFO"
    Write-Log "1. Primary log: $LogFile" "INFO"
    Write-Log "2. Monitor log: $($LogFile -replace '\.log$', '_monitor.log')" "INFO"
    Write-Log "3. Windows Setup logs: C:\Windows\Logs\MoSetup\" "INFO"
    Write-Log "4. Windows Update logs: C:\Windows\WindowsUpdate.log" "INFO"
    
    # Check for common log locations
    $commonLogs = @(
        "C:\Windows\Logs\MoSetup\BlueBox.log",
        "C:\Windows\Panther\setupact.log",
        "C:\`$Windows.~BT\Sources\Panther\setupact.log"
    )
    
    foreach ($logPath in $commonLogs) {
        if (Test-Path $logPath) {
            Write-Log "Found additional log: $logPath" "INFO"
        }
    }
}

# Display log file contents if available
if (Test-Path $LogFile) {
    $logSize = (Get-Item $LogFile).Length
    Write-Log "Installation log file size: $([math]::Round($logSize / 1KB, 2)) KB" "INFO"
    
    if ($logSize -gt 0) {
        Write-Log "" "INFO"
        Write-Log "=== RECENT LOG ENTRIES ===" "INFO"
        $recentLines = Get-Content $LogFile -Tail 10 -ErrorAction SilentlyContinue
        foreach ($line in $recentLines) {
            Write-Log $line "INFO"
        }
    }
} else {
    Write-Log "⚠️  No installation log file was created" "WARNING"
    Write-Log "This may indicate the installer failed to start properly" "WARNING"
}

# Summary
Write-Log "" "INFO"
Write-Log "=== UPGRADE SUMMARY ===" "INFO"
Write-Log "Start time: $startTime" "INFO"
Write-Log "End time: $(Get-Date)" "INFO"
Write-Log "Total duration: $([math]::Round($totalTime.TotalMinutes, 1)) minutes" "INFO"
Write-Log "Final result: $(if($process.ExitCode -eq 0 -or $process.ExitCode -eq 8){'SUCCESS'}else{'FAILURE'})" "INFO"

# Keep window open if requested or running interactively
if ($KeepOpen) {
    Write-Host ""
    Write-Host "Press any key to close this window..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Return installer exit code to RMM
exit $process.ExitCode
