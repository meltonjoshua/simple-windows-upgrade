# Windows 11 Upgrade Script - Enterprise Perfect Edition
# Automatically handles Windows 10 updates and Windows 11 upgrade
# Run with: iex (iwr -Uri "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11-Fixed.ps1" -UseBasicParsing).Content

param(
    [switch]$KeepOpen,
    [switch]$NoProgress
)

# Configuration
$TempDir = "C:\Temp"
$Installer = Join-Path $TempDir "Windows11InstallationAssistant.exe"
$LogFile = Join-Path $TempDir "upgrade.log"
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2171764"

# Progress tracking
$TotalSteps = 9
$CurrentStep = 0
$script:StartTime = Get-Date
$script:StepTimes = @()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
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
    try {
        $logEntry | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Update-Progress {
    param([string]$Activity, [string]$Status, [int]$Step, [string]$SubStatus = "")
    
    if (-not $NoProgress) {
        $PercentComplete = ($Step / $TotalSteps) * 100
        $currentTime = Get-Date
        
        try {
            $elapsed = $currentTime - $script:StartTime
            
            if ($script:StepTimes.Count -gt 0) {
                $avgStepTime = ($script:StepTimes | Measure-Object -Average).Average
                $remainingSteps = $TotalSteps - $Step
                $etaSeconds = $remainingSteps * $avgStepTime
                $eta = [TimeSpan]::FromSeconds($etaSeconds)
                $etaString = if ($eta.TotalMinutes -lt 60) { "{0:mm}m {0:ss}s" -f $eta } else { "{0:hh}h {0:mm}m" -f $eta }
            } else {
                $etaString = "Calculating..."
            }
            
            $progressStatus = "$Status"
            if ($SubStatus) { $progressStatus += " - $SubStatus" }
            $progressStatus += " (ETA: $etaString)"
            
            Write-Progress -Activity $Activity -Status $progressStatus -PercentComplete $PercentComplete
            
            $timeStamp = $currentTime.ToString("HH:mm:ss")
            $elapsedString = "{0:mm}m {0:ss}s" -f $elapsed
            Write-Host "[$Step/$TotalSteps] [$timeStamp] [$elapsedString] $Status" -ForegroundColor Cyan
            
            if ($SubStatus) {
                Write-Host "    └─ $SubStatus" -ForegroundColor Gray
            }
        } catch {
            # Fallback if date calculations fail
            Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
            Write-Host "[$Step/$TotalSteps] $Status" -ForegroundColor Cyan
            if ($SubStatus) {
                Write-Host "    └─ $SubStatus" -ForegroundColor Gray
            }
        }
    }
}

function Test-SystemHealth {
    Write-Log "🏥 Performing comprehensive system health check..." "INFO"
    $issues = @()
    
    # Check disk space
    try {
        $disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        if ($freeSpaceGB -lt 32) {
            $issues += "Insufficient disk space: ${freeSpaceGB}GB (32GB minimum required)"
        } else {
            Write-Log "✅ Disk space: ${freeSpaceGB}GB available" "SUCCESS"
        }
    } catch {
        Write-Log "Could not verify disk space" "WARNING"
    }
    
    # Check for pending reboot
    $rebootRequired = $false
    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    )
    
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) {
            $rebootRequired = $true
            break
        }
    }
    
    if ($rebootRequired) {
        $issues += "System reboot is pending - please restart before upgrading"
    }
    
    return @{ Issues = $issues; Healthy = ($issues.Count -eq 0) }
}

function Update-Windows10ToLatest {
    Write-Log "🔄 Checking Windows 10 update status..." "INFO"
    
    try {
        $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $currentBuild = [int]$OS.CurrentBuild
        
        if ($currentBuild -ge 19045) {
            Write-Log "✅ Windows 10 is already at latest build ($currentBuild)" "SUCCESS"
            return $true
        }
        
        if ($currentBuild -eq 19044) {
            Write-Log "🚀 Attempting to update Windows 10 to latest build..." "INFO"
            
            # Use UsoClient
            try {
                Start-Process "UsoClient.exe" -ArgumentList "StartScan" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 5
                Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 5
                Start-Process "UsoClient.exe" -ArgumentList "StartInstall" -Wait -WindowStyle Hidden
                Write-Log "✅ Windows Update initiated successfully" "SUCCESS"
                Write-Log "⚠️  System restart may be required" "WARNING"
                return $false # Indicate restart may be needed
            } catch {
                Write-Log "Windows Update failed: $($_.Exception.Message)" "WARNING"
                return $true # Continue anyway
            }
        }
        
        return $true
    } catch {
        Write-Log "Failed to check Windows version: $($_.Exception.Message)" "WARNING"
        return $true
    }
}

# Detect if running from one-liner
$IsInteractive = [Environment]::UserInteractive -and ![Console]::IsOutputRedirected
$RunningFromOneLiner = $MyInvocation.Line -match "iex.*iwr|Invoke-Expression.*Invoke-WebRequest"

if ($IsInteractive -and -not $RunningFromOneLiner) {
    $KeepOpen = $true
}

# Main execution
try {
    # Step 1: Initialize
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Initializing upgrade process..." $CurrentStep
    
    # Create temp directory
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    # Initialize log
    "Windows 11 Upgrade Log - Started $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Log "Upgrade process initialized" "INFO"
    
    # Step 2: Check admin privileges
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking administrator privileges..." $CurrentStep
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $IsAdmin) {
        Write-Log "❌ Administrator privileges required" "ERROR"
        Write-Host "❌ This script requires Administrator privileges." -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Log "✅ Running with Administrator privileges" "SUCCESS"
    
    # Step 3: System health check
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Performing system health check..." $CurrentStep
    
    $healthCheck = Test-SystemHealth
    if (-not $healthCheck.Healthy) {
        Write-Log "❌ System health issues detected:" "ERROR"
        foreach ($issue in $healthCheck.Issues) {
            Write-Log "  • $issue" "ERROR"
        }
        Write-Host "❌ Please resolve health issues before upgrading." -ForegroundColor Red
        exit 2
    }
    
    # Step 4: Check Windows version and update if needed
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking Windows version..." $CurrentStep
    
    $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $currentBuild = [int]$OS.CurrentBuild
    Write-Log "Current Windows: $($OS.ProductName) Build $currentBuild" "INFO"
    
    if ($currentBuild -ge 22000) {
        Write-Log "✅ Already running Windows 11 (Build $currentBuild)" "SUCCESS"
        Write-Host "✅ System is already running Windows 11!" -ForegroundColor Green
        exit 0
    }
    
    if ($currentBuild -eq 19044) {
        Write-Log "🔄 Windows 10 Build 19044 detected - updating first..." "INFO"
        $updateResult = Update-Windows10ToLatest
        
        if (-not $updateResult) {
            Write-Log "⚠️  Windows 10 update initiated - restart required" "WARNING"
            Write-Host "⚠️  Windows 10 has been updated but requires a restart." -ForegroundColor Yellow
            Write-Host "Please restart your computer and re-run this script." -ForegroundColor Yellow
            exit 3
        }
    }
    
    # Step 5: Apply registry bypasses
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Applying Windows 11 hardware bypasses..." $CurrentStep
    
    $regItems = @(
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassTPMCheck"; Description = "Bypass TPM requirement" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassSecureBootCheck"; Description = "Bypass Secure Boot requirement" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassRAMCheck"; Description = "Bypass RAM requirement" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassCPUCheck"; Description = "Bypass CPU requirement" },
        @{ Path = "HKLM:\SYSTEM\Setup\MoSetup"; Name = "AllowUpgradesWithUnsupportedTPMOrCPU"; Description = "Installation Assistant bypass" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"; Name = "AllowUpgradesWithUnsupportedTPMOrCPU"; Description = "Windows Update bypass" }
    )
    
    $bypassCount = 0
    foreach ($item in $regItems) {
        try {
            if (-not (Test-Path $item.Path)) {
                New-Item -Path $item.Path -Force | Out-Null
            }
            New-ItemProperty -Path $item.Path -Name $item.Name -Value 1 -PropertyType DWord -Force | Out-Null
            Write-Log "✅ Set $($item.Path)\$($item.Name) = 1" "SUCCESS"
            $bypassCount++
        } catch {
            Write-Log "❌ Failed to set $($item.Path)\$($item.Name): $($_.Exception.Message)" "WARNING"
        }
    }
    
    Write-Log "🎯 Applied $bypassCount essential hardware bypasses" "SUCCESS"
    
    # Step 6: Download installer
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep
    
    if (Test-Path $Installer) {
        Remove-Item $Installer -Force
    }
    
    $downloadSuccess = $false
    $attempts = 0
    $maxAttempts = 3
    
    while ($attempts -lt $maxAttempts -and -not $downloadSuccess) {
        $attempts++
        Write-Log "Download attempt $attempts of $maxAttempts..." "INFO"
        
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer -UseBasicParsing -TimeoutSec 300
            
            if (Test-Path $Installer) {
                $FileSize = (Get-Item $Installer).Length
                if ($FileSize -gt 1MB) {
                    $downloadSuccess = $true
                    Write-Log "✅ Downloaded successfully! File size: $([math]::Round($FileSize / 1MB, 2)) MB" "SUCCESS"
                } else {
                    Write-Log "❌ Download failed: File too small" "ERROR"
                    Remove-Item $Installer -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Log "❌ Download failed: $($_.Exception.Message)" "ERROR"
            Start-Sleep 5
        }
    }
    
    if (-not $downloadSuccess) {
        Write-Log "❌ Failed to download installer after $maxAttempts attempts" "ERROR"
        Write-Host "❌ Could not download Windows 11 Installation Assistant" -ForegroundColor Red
        exit 4
    }
    
    # Step 7: Verify installer
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Verifying installer..." $CurrentStep
    
    if (-not (Test-Path $Installer)) {
        Write-Log "❌ Installer file not found after download!" "ERROR"
        exit 5
    }
    
    Write-Log "✅ Installer verification successful!" "SUCCESS"
    
    # Step 8: Run installer
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Starting Windows 11 upgrade..." $CurrentStep
    
    $arguments = @("/quietinstall", "/skipeula", "/auto upgrade", "/CopyLogs `"$LogFile`"", "/noreboot")
    $argumentString = $arguments -join " "
    
    Write-Log "🚀 Running installer with arguments: $argumentString" "INFO"
    Write-Log "⚠️  The upgrade process will now begin and may take 30-90 minutes." "WARNING"
    Write-Log "   Your computer will restart automatically when complete." "WARNING"
    
    $process = Start-Process -FilePath $Installer -ArgumentList $argumentString -PassThru -WindowStyle Hidden -Wait
    
    # Step 9: Check results
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking upgrade results..." $CurrentStep
    
    $exitCode = $process.ExitCode
    Write-Log "Installer exit code: $exitCode" "INFO"
    
    if ($exitCode -eq 0) {
        Write-Log "🎉 Windows 11 upgrade completed successfully!" "SUCCESS"
        Write-Host "🎉 Windows 11 upgrade completed successfully!" -ForegroundColor Green
    } else {
        Write-Log "❌ Upgrade completed with exit code: $exitCode" "WARNING"
        Write-Host "⚠️  Upgrade completed with warnings. Check log for details." -ForegroundColor Yellow
    }
    
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    
} catch {
    Write-Log "❌ Critical error: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 99
} finally {
    # Cleanup
    Write-Log "=== UPGRADE SUMMARY ===" "INFO"
    
    # Safe duration calculation
    try {
        $duration = (Get-Date) - $script:StartTime
        $durationMinutes = [math]::Round($duration.TotalMinutes, 1)
        Write-Log "Total duration: $durationMinutes minutes" "INFO"
    } catch {
        Write-Log "Total duration: Calculation error" "INFO"
    }
    
    Write-Log "Windows 11 Upgrade script completed at $(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')" "INFO"
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        try {
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } catch {
            Start-Sleep 2
        }
    }
}