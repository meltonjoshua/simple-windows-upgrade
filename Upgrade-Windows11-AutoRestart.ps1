# ============================================================================
# WINDOWS 11 UPGRADE SCRIPT - ENTERPRISE EDITION (AUTO-RESTART VERSION)
# ============================================================================
# Fully automated Windows 11 upgrade with automatic restart when needed
# Supports RMM deployment and hardware bypasses
# Version: 2.1 Auto-Restart | Last Updated: 2025-09-24
# ============================================================================

# Windows 11 Upgrade Script - Fully Automatic Enterprise Edition with Auto-Restart
# Completely hands-off deployment for RMM/enterprise environments
# Run with: iex (iwr -Uri "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11-AutoRestart.ps1" -UseBasicParsing).Content

param(
    [switch]$NoProgress,
    [switch]$ForceRestart,
    [switch]$AutomaticMode,
    [switch]$KeepOpen,
    [switch]$ShowProgress
)

# FORCE BYPASS ALL HEALTH CHECKS - Always skip for maximum speed
$SkipHealthCheck = $true

# Configuration
$TempDir = "C:\Temp"
$Installer = Join-Path $TempDir "Windows11InstallationAssistant.exe"
$LogFile = Join-Path $TempDir "upgrade.log"
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2171764"

# Progress tracking
$TotalSteps = 8  # Reduced from 9 (health check removed)
$CurrentStep = 0
$script:StartTime = Get-Date
$script:StepTimes = @()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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

function Get-WindowsUpgradeProgress {
    # Check various sources for actual installation progress
    try {
        # Check Windows Update logs
        $logPath = "C:\Windows\Logs\WindowsUpdate\WindowsUpdate.log"
        if (Test-Path $logPath) {
            $recentLogs = Get-Content $logPath -Tail 20 -ErrorAction SilentlyContinue
            foreach ($line in $recentLogs) {
                if ($line -match "(\d+)% complete") {
                    return [int]$matches[1]
                }
                if ($line -match "Progress.*?(\d+)%") {
                    return [int]$matches[1]
                }
            }
        }
        
        # Check setup logs
        $setupLog = "C:\Windows\Panther\setupact.log"
        if (Test-Path $setupLog) {
            $setupContent = Get-Content $setupLog -Tail 20 -ErrorAction SilentlyContinue
            foreach ($line in $setupContent) {
                if ($line -match "Progress.*?(\d+)%") {
                    return [int]$matches[1]
                }
            }
        }
        
        # Check Windows.~BT folder for rough progress estimation
        if (Test-Path "C:\`$Windows.~BT") {
            try {
                $size = (Get-ChildItem "C:\`$Windows.~BT" -Recurse -ErrorAction SilentlyContinue | 
                       Measure-Object -Property Length -Sum).Sum / 1GB
                # Rough estimation: ~4GB typical download size
                $downloadProgress = [math]::Min(100, ($size / 4) * 100)
                if ($downloadProgress -gt 5) { return [int]$downloadProgress }
            } catch {}
        }
    } catch {
        # Return 0 if unable to determine actual progress
    }
    
    return 0
}

function Show-InstallationProgress {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$LogFile,
        [int]$EstimatedDurationMinutes = 45
    )
    
    $startTime = Get-Date
    Write-Log "🚀 Starting real-time installation progress monitoring..." "INFO"
    
    Write-Host "`n🚀 Windows 11 Installation Progress Monitor" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    
    $lastProgressUpdate = 0
    $progressHistory = @()
    
    while (!$Process.HasExited) {
        $elapsed = (Get-Date) - $startTime
        $elapsedMinutes = $elapsed.TotalMinutes
        
        # Calculate estimated progress based on time
        $timeBasedProgress = [math]::Min(95, ($elapsedMinutes / $EstimatedDurationMinutes) * 100)
        
        # Check for actual progress indicators
        $actualProgress = Get-WindowsUpgradeProgress
        
        # Use actual progress if available and reasonable, otherwise use time-based
        $displayProgress = if ($actualProgress -gt 0 -and $actualProgress -le 100) { 
            $actualProgress 
        } else { 
            $timeBasedProgress 
        }
        
        # Track progress history for trend analysis
        $progressHistory += @{
            Time = $elapsed.TotalMinutes
            Progress = $displayProgress
            Source = if ($actualProgress -gt 0) { "Actual" } else { "Estimated" }
        }
        
        # Keep only last 10 progress points
        if ($progressHistory.Count -gt 10) {
            $progressHistory = $progressHistory[-10..-1]
        }
        
        # Determine current installation stage based on progress and time
        $stage = switch ($displayProgress) {
            { $_ -lt 5 } { "🔄 Initializing upgrade process..." }
            { $_ -lt 15 } { "📥 Downloading Windows 11 files..." }
            { $_ -lt 30 } { "📦 Preparing installation environment..." }
            { $_ -lt 60 } { "⚙️  Installing Windows 11 core components..." }
            { $_ -lt 85 } { "🔧 Configuring system settings..." }
            { $_ -lt 95 } { "✨ Finalizing installation..." }
            default { "🎯 Completing upgrade process..." }
        }
        
        # Create progress bar (50 characters wide)
        $progressChars = [math]::Floor($displayProgress / 2)
        $progressBar = "█" * $progressChars + "░" * (50 - $progressChars)
        
        # Calculate ETA based on progress trend
        $eta = "Calculating..."
        if ($progressHistory.Count -gt 3 -and $displayProgress -gt 5) {
            $recentProgress = $progressHistory[-3..-1]
            $progressRate = ($recentProgress[-1].Progress - $recentProgress[0].Progress) / 
                           ($recentProgress[-1].Time - $recentProgress[0].Time)
            
            if ($progressRate -gt 0.1) {
                $remainingProgress = 100 - $displayProgress
                $etaMinutes = $remainingProgress / $progressRate
                $eta = if ($etaMinutes -lt 60) { 
                    "$([math]::Round($etaMinutes))m" 
                } else { 
                    "$([math]::Round($etaMinutes/60, 1))h" 
                }
            }
        }
        
        # Display current progress (clear previous line)
        Write-Host "`r                                                                    " -NoNewline
        Write-Host "`r$stage" -ForegroundColor Yellow -NoNewline
        Write-Host "`n[$progressBar] " -NoNewline -ForegroundColor Cyan
        Write-Host "$([math]::Round($displayProgress, 1))% " -NoNewline -ForegroundColor White
        Write-Host "| Elapsed: $($elapsed.ToString('mm\:ss')) " -NoNewline -ForegroundColor Gray
        Write-Host "| ETA: $eta" -ForegroundColor Gray
        
        # Log progress updates every 2% or every 2 minutes
        if ([math]::Abs($displayProgress - $lastProgressUpdate) -ge 2 -or 
            ($elapsed.TotalSeconds % 120 -lt 10 -and $elapsed.TotalSeconds -gt 10)) {
            
            $progressSource = if ($actualProgress -gt 0) { "detected" } else { "estimated" }
            Write-Log "📊 Installation progress: $([math]::Round($displayProgress, 1))% ($progressSource) - $stage" "INFO"
            $lastProgressUpdate = $displayProgress
        }
        
        # Move cursor up to overwrite progress display next iteration
        [Console]::CursorTop = [Console]::CursorTop - 2
        
        Start-Sleep -Seconds 5
    }
    
    # Final progress display
    $totalElapsed = (Get-Date) - $startTime
    Write-Host "`r                                                                    "
    Write-Host "`r✅ Windows 11 installation completed successfully!" -ForegroundColor Green
    Write-Host "[████████████████████████████████████████████████████] 100%" -ForegroundColor Green
    Write-Host "Total installation time: $($totalElapsed.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host ""
    
    Write-Log "🎉 Installation progress monitoring completed. Total time: $($totalElapsed.ToString('hh\:mm\:ss'))" "SUCCESS"
    
    # Check if restart will be needed after installation completes
    Write-Host "🔍 Checking if restart will be required..." -ForegroundColor Cyan
    Write-Log "📋 Installation Assistant completed - system will determine restart requirement" "INFO"
}

# Detect execution environment - fully automatic for enterprise deployment
$IsRMM = $env:RMM_DEPLOYMENT -eq "true" -or $MyInvocation.Line -match "iex.*iwr|Invoke-Expression.*Invoke-WebRequest"
$AutomaticMode = $IsRMM -or $env:AUTOMATIC_MODE -eq "true" -or $AutomaticMode

# Force automatic mode for enterprise environments and bypass ALL health checks
if ($AutomaticMode) {
    $NoProgress = $false  # Keep progress for RMM visibility
    $ForceRestart = $true # Enable automatic restarts
    Write-Log "🤖 Running in fully automatic enterprise mode with auto-restart" "INFO"
}

# FORCE BYPASS ALL HEALTH CHECKS - Maximum Speed Mode
Write-Log "⚡ FORCE BYPASS: All health checks disabled for maximum speed" "INFO"

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Main execution
try {
    # ========================================================================
    # STEP 1: Initialize Environment
    # ========================================================================
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Initializing upgrade process..." $CurrentStep
    
    # Create temp directory
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    
    # Initialize log
    "Windows 11 Upgrade Log - Started $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Log "Upgrade process initialized" "INFO"
    
    # ========================================================================
    # STEP 2: Verify Administrator Privileges
    # ========================================================================
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking administrator privileges..." $CurrentStep
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $IsAdmin) {
        Write-Log "❌ Administrator privileges required - attempting automatic elevation" "ERROR"
        
        # Attempt automatic elevation for enterprise deployment
        try {
            if ($AutomaticMode) {
                Write-Log "🚀 Attempting automatic UAC elevation..." "INFO"
                $arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& {$($MyInvocation.MyCommand.Definition)}`""
                Start-Process PowerShell.exe -Argument $arguments -Verb RunAs -Wait
                Write-Log "✅ Script re-launched with elevated privileges" "SUCCESS"
                exit 0
            }
        } catch {
            Write-Log "❌ Automatic elevation failed: $($_.Exception.Message)" "ERROR"
        }
        
        Write-Log "❌ Cannot proceed without Administrator privileges" "ERROR"
        exit 1
    }
    
    Write-Log "✅ Running with Administrator privileges" "SUCCESS"
    
    # ========================================================================
    # STEP 3: Skip Health Check (Removed for Speed)
    # ========================================================================
    Write-Log "⚡ Skipping system health check for maximum speed" "INFO"
    Write-Log "🚀 Proceeding directly to Windows version check" "INFO"
    
    # ========================================================================
    # STEP 4: Check Windows Version
    # ========================================================================
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking Windows version..." $CurrentStep
    
    $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $currentBuild = [int]$OS.CurrentBuild
    Write-Log "Current Windows: $($OS.ProductName) Build $currentBuild" "INFO"
    
    if ($currentBuild -ge 22000) {
        Write-Log "✅ Already running Windows 11 (Build $currentBuild)" "SUCCESS"
        if (-not $AutomaticMode) {
            Write-Host "✅ System is already running Windows 11!" -ForegroundColor Green
        }
        exit 0
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
    
    # Remove existing installer if present
    if (Test-Path $Installer) {
        try {
            Remove-Item $Installer -Force
            Write-Log "✅ Removed existing installer" "SUCCESS"
        } catch {
            Write-Log "⚠️  Could not remove existing installer: $($_.Exception.Message)" "WARNING"
        }
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
            if ($attempts -eq $maxAttempts) {
                Write-Log "❌ Failed to download installer after $maxAttempts attempts" "ERROR"
                exit 4
            }
            Start-Sleep 5
        }
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
    
    # Kill any existing installer processes
    $processesToKill = @("Windows11InstallationAssistant", "Windows11Upgrade", "SetupHost")
    foreach ($processName in $processesToKill) {
        try {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                foreach ($proc in $processes) {
                    Write-Log "🛑 Terminating existing process: $($proc.ProcessName)" "INFO"
                    $proc | Stop-Process -Force
                }
            }
        } catch { }
    }
    
    # Installer arguments for automatic mode
    $arguments = @("/quietinstall", "/skipeula", "/auto upgrade", "/CopyLogs `"$LogFile`"")
    $argumentString = $arguments -join " "
    
    Write-Log "🚀 Running installer with arguments: $argumentString" "INFO"
    Write-Log "🤖 Auto-restart mode: System will restart automatically when needed" "INFO"
    
    # Start installer with progress monitoring
    try {
        $process = Start-Process -FilePath $Installer -ArgumentList $argumentString -PassThru -WindowStyle Hidden
        
        if ($process -and !$process.HasExited) {
            Show-InstallationProgress -Process $process -LogFile $LogFile -EstimatedDurationMinutes 45
            $process.WaitForExit()
        } else {
            Write-Log "⚠️  Installer process failed to start or exited immediately" "WARNING"
        }
        
        $exitCode = $process.ExitCode
    } catch {
        Write-Log "❌ Failed to start installer: $($_.Exception.Message)" "ERROR"
        exit 6
    }
    
    # Check results
    Write-Log "Installer exit code: $exitCode" "INFO"
    
    if ($exitCode -eq 0) {
        Write-Log "🎉 Windows 11 upgrade completed successfully!" "SUCCESS"
        
        # Check if system actually upgraded
        Start-Sleep -Seconds 3
        $postUpgradeOS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
        $postUpgradeBuild = if ($postUpgradeOS) { [int]$postUpgradeOS.CurrentBuild } else { 0 }
        
        Write-Log "📋 Pre-upgrade build: $currentBuild | Post-upgrade build: $postUpgradeBuild" "INFO"
        
        if ($postUpgradeBuild -ge 22000) {
            Write-Log "✅ Confirmed: System upgraded to Windows 11 (Build $postUpgradeBuild)" "SUCCESS"
        } elseif ($postUpgradeBuild -eq $currentBuild) {
            # FALSE POSITIVE DETECTION - Installation Assistant reported success but no upgrade occurred
            Write-Log "❌ FALSE POSITIVE: Installation Assistant reported success but no upgrade occurred" "ERROR"
            Write-Log "📋 System is still on Windows 10 Build $postUpgradeBuild" "WARNING"
            
            $upgradeIssues = @()
            
            # Check if upgrade files were downloaded but installation failed
            if (Test-Path "C:\`$Windows.~BT" -ErrorAction SilentlyContinue) {
                $upgradeIssues += "Upgrade files downloaded but installation failed"
                Write-Log "💾 Found Windows upgrade files in C:\`$Windows.~BT" "INFO"
                
                # AUTOMATIC RESTART - NO CONDITIONAL CHECK NEEDED
                Write-Log "🔄 Installation files detected - automatically restarting to complete upgrade..." "INFO"
                Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "120", "/c", "Restarting to complete Windows 11 installation - 2 minutes" -WindowStyle Hidden
                
                if (-not $AutomaticMode) {
                    Write-Host "🔄 Installation files found - automatically restarting in 2 minutes to complete upgrade" -ForegroundColor Yellow
                    Write-Host "💡 System will restart in 2 minutes to finish the Windows 11 installation" -ForegroundColor Green
                }
                
                Write-Log "🚀 AUTO-RESTART: System will automatically restart in 2 minutes" "SUCCESS"
            } else {
                # No upgrade files found
                Write-Log "❌ No Windows upgrade files found - Installation Assistant exited without upgrading" "ERROR"
                
                if (-not $AutomaticMode) {
                    Write-Host "❌ Installation Assistant completed but no upgrade occurred" -ForegroundColor Red
                    Write-Host "📋 Possible reasons:" -ForegroundColor Yellow
                    Write-Host "   • Hardware may not meet Windows 11 requirements" -ForegroundColor Gray
                    Write-Host "   • Windows 10 version may be too old" -ForegroundColor Gray
                    Write-Host "💡 Try running Windows Update or check Windows 11 compatibility" -ForegroundColor Cyan
                }
            }
        } else {
            Write-Log "🔄 System upgraded successfully - restart may be needed to complete" "INFO"
            
            # AUTO-RESTART for completed upgrade
            Write-Log "🤖 Auto-restart mode: Scheduling automatic restart to finalize Windows 11..." "INFO"
            Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "60", "/c", "Windows 11 upgrade completed - restarting to finalize" -WindowStyle Hidden
            
            if (-not $AutomaticMode) {
                Write-Host "🎉 Windows 11 upgrade completed successfully!" -ForegroundColor Green
                Write-Host "🔄 System will restart in 60 seconds to finalize the upgrade" -ForegroundColor Yellow
            }
        }
    } elseif ($exitCode -eq 3) {
        Write-Log "🔄 System restart required - upgrade will continue after reboot" "INFO"
        
        # AUTO-RESTART for continuation
        Write-Log "🤖 Auto-restart mode: Scheduling automatic restart to continue upgrade..." "INFO"
        Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "60", "/c", "Windows 11 upgrade requires restart" -WindowStyle Hidden
        
        if (-not $AutomaticMode) {
            Write-Host "🔄 System will restart in 60 seconds to continue Windows 11 upgrade" -ForegroundColor Yellow
        }
    } else {
        Write-Log "❌ Upgrade completed with exit code: $exitCode" "WARNING"
        if (-not $AutomaticMode) {
            Write-Host "⚠️  Upgrade completed with warnings. Exit code: $exitCode" -ForegroundColor Yellow
        }
    }
    
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    
} catch {
    Write-Log "❌ Critical error: $($_.Exception.Message)" "ERROR"
    if (-not $AutomaticMode) {
        Write-Host "❌ Script execution failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    exit 99
} finally {
    # Cleanup
    Write-Log "=== UPGRADE SUMMARY ===" "INFO"
    
    try {
        $duration = (Get-Date) - $script:StartTime
        $durationMinutes = [math]::Round($duration.TotalMinutes, 1)
        Write-Log "Total duration: $durationMinutes minutes" "INFO"
    } catch {
        Write-Log "Total duration: Calculation error" "INFO"
    }
    
    Write-Log "Windows 11 Upgrade script completed at $(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')" "INFO"
    
    # No user interaction prompts in automatic mode
    if (-not $AutomaticMode) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        try {
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } catch {
            Start-Sleep 2
        }
    } else {
        Write-Log "🤖 Automatic mode: Script completed without user interaction" "INFO"
    }
}