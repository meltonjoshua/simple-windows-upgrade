# Windows 11 Upgrade Script - Fully Automatic Enterprise Edition
# Completely hands-off deployment for RMM/enterprise environments
# Run with: iex (iwr -Uri "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11-Fixed.ps1" -UseBasicParsing).Content

param(
    [switch]$NoProgress,
    [switch]$ForceRestart,
    [switch]$SkipHealthCheck
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
    param([switch]$AutoRestart)
    
    Write-Log "🔄 Checking Windows 10 update status..." "INFO"
    
    try {
        $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $currentBuild = [int]$OS.CurrentBuild
        
        if ($currentBuild -ge 19045) {
            Write-Log "✅ Windows 10 is already at latest build ($currentBuild)" "SUCCESS"
            return $true
        }
        
        if ($currentBuild -eq 19044) {
            Write-Log "🚀 Forcing immediate Windows 10 update to Build 19045..." "INFO"
            
            # Method 1: Aggressive UsoClient approach
            try {
                Write-Log "Method 1: Using UsoClient for immediate update..." "INFO"
                
                # Reset Windows Update components first
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Stop-Service BITS -Force -ErrorAction SilentlyContinue
                Stop-Service cryptsvc -Force -ErrorAction SilentlyContinue
                
                Start-Service wuauserv -ErrorAction SilentlyContinue
                Start-Service BITS -ErrorAction SilentlyContinue  
                Start-Service cryptsvc -ErrorAction SilentlyContinue
                
                # Force immediate scan and install
                Start-Process "UsoClient.exe" -ArgumentList "ScanInstallWait" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 15
                Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 10
                Start-Process "UsoClient.exe" -ArgumentList "StartInstall" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 5
                
                Write-Log "✅ UsoClient update commands executed" "SUCCESS"
            } catch {
                Write-Log "UsoClient method failed: $($_.Exception.Message)" "WARNING"
            }
            
            # Method 2: Direct Windows Update API
            try {
                Write-Log "Method 2: Using Windows Update API..." "INFO"
                
                $updateSession = New-Object -ComObject Microsoft.Update.Session
                $updateSearcher = $updateSession.CreateUpdateSearcher()
                $updateSearcher.Online = $true
                
                Write-Log "Searching for available updates..." "INFO"
                $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                
                if ($searchResult.Updates.Count -gt 0) {
                    Write-Log "Found $($searchResult.Updates.Count) available updates" "SUCCESS"
                    
                    # Focus on feature updates and cumulative updates
                    $criticalUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($update in $searchResult.Updates) {
                        if ($update.Title -like "*Feature update*" -or $update.Title -like "*Cumulative*" -or $update.Title -like "*Quality*") {
                            $criticalUpdates.Add($update) | Out-Null
                            Write-Log "Queued: $($update.Title)" "INFO"
                        }
                    }
                    
                    if ($criticalUpdates.Count -gt 0) {
                        Write-Log "Downloading $($criticalUpdates.Count) critical updates..." "INFO"
                        
                        $downloader = $updateSession.CreateUpdateDownloader()
                        $downloader.Updates = $criticalUpdates
                        $downloadResult = $downloader.Download()
                        
                        if ($downloadResult.ResultCode -eq 2) {
                            Write-Log "Installing updates..." "INFO"
                            
                            $installer = $updateSession.CreateUpdateInstaller()
                            $installer.Updates = $criticalUpdates
                            $installResult = $installer.Install()
                            
                            if ($installResult.ResultCode -eq 2) {
                                Write-Log "✅ Updates installed successfully" "SUCCESS"
                            } else {
                                Write-Log "Update installation result: $($installResult.ResultCode)" "WARNING"
                            }
                        }
                    }
                } else {
                    Write-Log "No updates found via Windows Update API" "INFO"
                }
            } catch {
                Write-Log "Windows Update API method failed: $($_.Exception.Message)" "WARNING"
            }
            
            # Method 3: PowerShell Get-WindowsUpdate (if available)
            try {
                Write-Log "Method 3: Checking for PowerShell Windows Update module..." "INFO"
                
                # Try to install/use PSWindowsUpdate module
                if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                    Write-Log "Installing PSWindowsUpdate module..." "INFO"
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
                    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction SilentlyContinue
                }
                
                if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                    Import-Module PSWindowsUpdate -Force
                    $updates = Get-WUList -MicrosoftUpdate
                    if ($updates) {
                        Write-Log "Found $($updates.Count) updates via PSWindowsUpdate" "SUCCESS"
                        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
                        Write-Log "Updates initiated via PSWindowsUpdate" "SUCCESS"
                    }
                }
            } catch {
                Write-Log "PSWindowsUpdate method failed: $($_.Exception.Message)" "WARNING"
            }
            
            # Method 4: Manual registry trigger
            try {
                Write-Log "Method 4: Triggering Windows Update via registry..." "INFO"
                
                # Force Windows Update detection
                $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
                Set-ItemProperty -Path $regPath -Name "AUOptions" -Value 4 -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regPath -Name "ScheduledInstallDay" -Value 0 -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $regPath -Name "ScheduledInstallTime" -Value 3 -Force -ErrorAction SilentlyContinue
                
                # Restart Windows Update service
                Restart-Service wuauserv -Force -ErrorAction SilentlyContinue
                
                Write-Log "Registry triggers applied" "SUCCESS"
            } catch {
                Write-Log "Registry method failed: $($_.Exception.Message)" "WARNING"
            }
            
            Write-Log "🔄 All update methods attempted - checking if restart is needed..." "INFO"
            
            # Check if restart is pending after update attempts
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
            
            if ($rebootRequired -and ($AutoRestart -or $ForceRestart)) {
                Write-Log "🔄 Updates require restart - scheduling automatic restart..." "INFO"
                Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "120", "/c", "Windows 10 update completed - restarting for Windows 11 upgrade" -WindowStyle Hidden
                return $false
            } elseif ($rebootRequired) {
                Write-Log "⚠️  Updates require restart but automatic restart is disabled" "WARNING"
                return $false
            } else {
                Write-Log "⚠️  No immediate restart required - attempting to continue with Windows 11 upgrade" "WARNING"
                return $true
            }
        }
        
        return $true
    } catch {
        Write-Log "Failed to update Windows 10: $($_.Exception.Message)" "WARNING"
        Write-Log "Continuing with Windows 11 upgrade attempt on current build" "WARNING"
        return $true
    }
}

# Detect execution environment - fully automatic for enterprise deployment
$IsRMM = $env:RMM_DEPLOYMENT -eq "true" -or $MyInvocation.Line -match "iex.*iwr|Invoke-Expression.*Invoke-WebRequest"
$AutomaticMode = $IsRMM -or $env:AUTOMATIC_MODE -eq "true"

# Force automatic mode for enterprise environments
if ($AutomaticMode) {
    $NoProgress = $false  # Keep progress for RMM visibility
    $ForceRestart = $true # Enable automatic restarts
    Write-Log "🤖 Running in fully automatic enterprise mode" "INFO"
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
    
    # Step 3: System health check
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Performing system health check..." $CurrentStep
    
    $healthCheck = Test-SystemHealth
    if (-not $healthCheck.Healthy -and -not $SkipHealthCheck) {
        Write-Log "⚠️  System health issues detected (non-critical in automatic mode):" "WARNING"
        foreach ($issue in $healthCheck.Issues) {
            Write-Log "  • $issue" "WARNING"
        }
        
        if ($AutomaticMode) {
            Write-Log "🤖 Automatic mode: Continuing despite health warnings" "INFO"
        } else {
            Write-Log "❌ Health check failed - use -SkipHealthCheck to override" "ERROR"
            exit 2
        }
    }
    
    # Step 4: Check Windows version and update if needed
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
    
    if ($currentBuild -eq 19044) {
        Write-Log "🔄 Windows 10 Build 19044 detected - automatic update required..." "INFO"
        $updateResult = Update-Windows10ToLatest -AutoRestart:$ForceRestart
        
        if (-not $updateResult -and $ForceRestart) {
            Write-Log "🔄 System restart scheduled - Windows 11 upgrade will continue after restart" "INFO"
            
            # Create scheduled task to continue upgrade after restart
            $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"iex (iwr -Uri 'https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11-Fixed.ps1' -UseBasicParsing).Content`""
            $taskTrigger = New-ScheduledTaskTrigger -AtStartup
            $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            try {
                Register-ScheduledTask -TaskName "ContinueWindows11Upgrade" -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Force
                Write-Log "✅ Scheduled task created to continue upgrade after restart" "SUCCESS"
            } catch {
                Write-Log "⚠️  Could not create scheduled task: $($_.Exception.Message)" "WARNING"
            }
            
            exit 3
        } elseif (-not $updateResult) {
            Write-Log "⚠️  Windows 10 update recommended but continuing with current build" "WARNING"
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
        if (-not $AutomaticMode) {
            Write-Host "❌ Could not download Windows 11 Installation Assistant" -ForegroundColor Red
        }
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
    
    # Step 8: Run installer with automatic restart
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Starting Windows 11 upgrade..." $CurrentStep
    
    # Automatic restart arguments for enterprise deployment
    $arguments = if ($AutomaticMode -or $ForceRestart) {
        @("/quietinstall", "/skipeula", "/auto upgrade", "/CopyLogs `"$LogFile`"")  # Allow automatic restart
    } else {
        @("/quietinstall", "/skipeula", "/auto upgrade", "/CopyLogs `"$LogFile`"", "/noreboot")  # No auto restart
    }
    
    $argumentString = $arguments -join " "
    
    Write-Log "🚀 Running installer with arguments: $argumentString" "INFO"
    Write-Log "🤖 Automatic mode: System will restart automatically when upgrade completes" "INFO"
    
    # Clean up scheduled task if it exists (in case this is the post-restart run)
    try {
        Unregister-ScheduledTask -TaskName "ContinueWindows11Upgrade" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "✅ Cleaned up restart continuation task" "SUCCESS"
    } catch { }
    
    $process = Start-Process -FilePath $Installer -ArgumentList $argumentString -PassThru -WindowStyle Hidden -Wait
    
    # Step 9: Check results
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking upgrade results..." $CurrentStep
    
    $exitCode = $process.ExitCode
    Write-Log "Installer exit code: $exitCode" "INFO"
    
    if ($exitCode -eq 0) {
        Write-Log "🎉 Windows 11 upgrade completed successfully!" "SUCCESS"
        if (-not $AutomaticMode) {
            Write-Host "🎉 Windows 11 upgrade completed successfully!" -ForegroundColor Green
        }
    } else {
        Write-Log "❌ Upgrade completed with exit code: $exitCode" "WARNING"
        if (-not $AutomaticMode) {
            Write-Host "⚠️  Upgrade completed with warnings. Check log for details." -ForegroundColor Yellow
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
    
    # Safe duration calculation
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