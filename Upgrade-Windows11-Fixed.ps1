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
    $warnings = @()
    
    # Check disk space (more lenient for automatic mode)
    try {
        $disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        
        if ($freeSpaceGB -lt 20) {
            $issues += "Critical: Insufficient disk space: ${freeSpaceGB}GB (20GB absolute minimum)"
        } elseif ($freeSpaceGB -lt 32) {
            $warnings += "Low disk space: ${freeSpaceGB}GB (32GB recommended, but proceeding)"
            Write-Log "⚠️  Low disk space: ${freeSpaceGB}GB (continuing anyway)" "WARNING"
        } else {
            Write-Log "✅ Disk space: ${freeSpaceGB}GB available" "SUCCESS"
        }
    } catch {
        $warnings += "Could not verify disk space - continuing anyway"
        Write-Log "Could not verify disk space - continuing anyway" "WARNING"
    }
    
    # Check for pending reboot (more intelligent detection)
    try {
        $rebootRequired = $false
        $rebootSources = @()
        
        # Check multiple reboot indicators
        $rebootChecks = @(
            @{ Key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"; Source = "Windows Update" },
            @{ Key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"; Source = "Component Based Servicing" },
            @{ Key = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Value = "PendingFileRenameOperations"; Source = "File Operations" }
        )
        
        foreach ($check in $rebootChecks) {
            if ($check.Value) {
                # Check for specific registry value
                $regValue = Get-ItemProperty -Path $check.Key -Name $check.Value -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.$($check.Value)) {
                    $rebootRequired = $true
                    $rebootSources += $check.Source
                }
            } else {
                # Check for registry key existence
                if (Test-Path $check.Key) {
                    $rebootRequired = $true
                    $rebootSources += $check.Source
                }
            }
        }
        
        if ($rebootRequired) {
            $rebootMessage = "Pending reboot detected from: $($rebootSources -join ', ')"
            
            # In automatic mode, this is a warning, not a blocking issue
            if ($AutomaticMode -or $ForceRestart) {
                $warnings += "$rebootMessage (will be handled automatically)"
                Write-Log "⚠️  $rebootMessage (automatic restart will be scheduled)" "WARNING"
            } else {
                $issues += "$rebootMessage - restart recommended before upgrade"
            }
        } else {
            Write-Log "✅ No pending reboot detected" "SUCCESS"
        }
    } catch {
        $warnings += "Could not check reboot status - continuing anyway"
        Write-Log "Could not check reboot status - continuing anyway" "WARNING"
    }
    
    # Check available memory (non-blocking)
    try {
        $memory = Get-WmiObject -Class Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        
        if ($totalMemoryGB -lt 4) {
            $warnings += "Low system memory: ${totalMemoryGB}GB (4GB+ recommended)"
            Write-Log "⚠️  Low memory: ${totalMemoryGB}GB (continuing with registry bypasses)" "WARNING"
        } else {
            Write-Log "✅ System memory: ${totalMemoryGB}GB" "SUCCESS"
        }
    } catch {
        $warnings += "Could not check system memory"
        Write-Log "Could not check system memory" "WARNING"
    }
    
    # Check system drive health (non-blocking)
    try {
        $systemDrive = $env:SystemDrive.Replace(":", "")
        $driveHealth = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        
        if ($driveHealth.Size -lt 120GB) {
            $warnings += "Small system drive: $([math]::Round($driveHealth.Size / 1GB, 0))GB total"
        }
        
        Write-Log "✅ System drive check completed" "SUCCESS"
    } catch {
        $warnings += "Could not check drive health"
        Write-Log "Could not check drive health" "WARNING"
    }
    
    # Summary
    $healthSummary = @{
        Issues = $issues
        Warnings = $warnings
        Healthy = ($issues.Count -eq 0)
        CriticalIssues = $issues.Count
        WarningCount = $warnings.Count
    }
    
    if ($healthSummary.Healthy) {
        Write-Log "✅ System health check passed" "SUCCESS"
        if ($warnings.Count -gt 0) {
            Write-Log "⚠️  $($warnings.Count) warnings noted but not blocking" "WARNING"
        }
    } else {
        Write-Log "❌ $($issues.Count) critical health issues detected" "ERROR"
    }
    
    return $healthSummary
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
    
    # Display warnings if any
    if ($healthCheck.Warnings -and $healthCheck.Warnings.Count -gt 0) {
        Write-Log "⚠️  System health warnings (non-blocking):" "WARNING"
        foreach ($warning in $healthCheck.Warnings) {
            Write-Log "  • $warning" "WARNING"
        }
    }
    
    # Handle critical issues
    if (-not $healthCheck.Healthy -and -not $SkipHealthCheck) {
        Write-Log "❌ Critical system health issues detected:" "ERROR"
        foreach ($issue in $healthCheck.Issues) {
            Write-Log "  • $issue" "ERROR"
        }
        
        if ($AutomaticMode) {
            Write-Log "🤖 Automatic mode: Treating critical issues as warnings" "WARNING"
            Write-Log "⚠️  Continuing despite critical issues in automatic mode" "WARNING"
        } else {
            Write-Log "❌ Health check failed - use -SkipHealthCheck to override" "ERROR"
            if (-not $AutomaticMode) {
                Write-Host "❌ Critical system health issues detected. Use -SkipHealthCheck to bypass." -ForegroundColor Red
            }
            exit 2
        }
    } elseif ($healthCheck.Healthy) {
        Write-Log "✅ System health check passed" "SUCCESS"
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
    
    # Check for and terminate any existing Windows 11 or setup-related processes
    $processesToKill = @(
        "Windows11InstallationAssistant",
        "Windows11Upgrade", 
        "SetupHost",
        "Windows11Setup",
        "Windows11MediaCreationTool",
        "MediaCreationTool*",
        "Windows10Upgrade*",
        "WindowsUpdateBox"
    )
    
    Write-Log "🔍 Checking for conflicting processes..." "INFO"
    $killedProcesses = 0
    
    foreach ($processPattern in $processesToKill) {
        try {
            # Handle wildcard patterns
            if ($processPattern -like "*`*") {
                $processes = Get-Process | Where-Object { $_.ProcessName -like $processPattern }
            } else {
                $processes = Get-Process -Name $processPattern -ErrorAction SilentlyContinue
            }
            
            if ($processes) {
                foreach ($proc in $processes) {
                    Write-Log "� Terminating conflicting process: $($proc.ProcessName) (PID: $($proc.Id))" "INFO"
                    try {
                        $proc | Stop-Process -Force
                        $killedProcesses++
                    } catch {
                        Write-Log "Could not terminate $($proc.ProcessName) - trying taskkill..." "WARNING"
                        Start-Process "taskkill" -ArgumentList "/F", "/PID", $proc.Id -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch {
            # Ignore errors for non-existent processes
        }
    }
    
    if ($killedProcesses -gt 0) {
        Write-Log "✅ Terminated $killedProcesses conflicting processes" "SUCCESS"
        Write-Log "⏳ Waiting 5 seconds for process cleanup..." "INFO"
        Start-Sleep -Seconds 5
    } else {
        Write-Log "✅ No conflicting processes found" "SUCCESS"
    }
    
    # Also check for running installer files directly
    try {
        $runningInstallers = Get-Process | Where-Object { 
            $_.Path -and (
                $_.Path -like "*Windows11InstallationAssistant*" -or
                $_.Path -like "*Windows11*" -or
                $_.ProcessName -like "*setup*" -or
                $_.ProcessName -like "*upgrade*"
            )
        }
        
        foreach ($installer in $runningInstallers) {
            Write-Log "🛑 Terminating installer process: $($installer.ProcessName) at $($installer.Path)" "INFO"
            try {
                $installer | Stop-Process -Force
                Start-Sleep -Seconds 2
            } catch {
                Write-Log "Could not terminate installer process" "WARNING"
            }
        }
    } catch {
        # Ignore errors
    }
    
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
    
    # Add retry logic for the installer with different approaches
    $maxRetries = 3
    $retryCount = 0
    $installerSuccess = $false
    
    while ($retryCount -lt $maxRetries -and -not $installerSuccess) {
        $retryCount++
        
        if ($retryCount -gt 1) {
            Write-Log "🔄 Installer attempt $retryCount of $maxRetries..." "INFO"
            
            # More aggressive cleanup between retries
            Write-Log "🧹 Performing aggressive cleanup before retry..." "INFO"
            
            # Kill any remaining processes
            Get-Process | Where-Object { 
                $_.ProcessName -like "*Windows11*" -or 
                $_.ProcessName -like "*setup*" -or 
                $_.ProcessName -like "*upgrade*" 
            } | ForEach-Object {
                try { $_ | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
            }
            
            # Remove temp files
            if (Test-Path $Installer) {
                Remove-Item $Installer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                # Re-download if needed
                try {
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $Installer -UseBasicParsing -TimeoutSec 60
                    Write-Log "✅ Re-downloaded installer for retry" "SUCCESS"
                } catch {
                    Write-Log "❌ Failed to re-download installer" "ERROR"
                    continue
                }
            }
            
            Start-Sleep -Seconds 5
        }
        
        try {
            Write-Log "▶️  Starting installer process (attempt $retryCount)..." "INFO"
            
            # Try with different startup methods
            if ($retryCount -eq 1) {
                # Standard method
                $process = Start-Process -FilePath $Installer -ArgumentList $argumentString -PassThru -WindowStyle Hidden -Wait
            } elseif ($retryCount -eq 2) {
                # Alternative method - visible window
                $process = Start-Process -FilePath $Installer -ArgumentList $argumentString -PassThru -Wait
            } else {
                # Last resort - minimal arguments
                $simpleArgs = @("/quietinstall", "/auto upgrade")
                $process = Start-Process -FilePath $Installer -ArgumentList ($simpleArgs -join " ") -PassThru -Wait
            }
            
            $installerSuccess = $true
            Write-Log "✅ Installer process completed with exit code: $($process.ExitCode)" "SUCCESS"
            
        } catch {
            Write-Log "❌ Installer attempt $retryCount failed: $($_.Exception.Message)" "ERROR"
            if ($retryCount -lt $maxRetries) {
                Write-Log "🔄 Will retry in 10 seconds..." "INFO"
                Start-Sleep -Seconds 10
            }
        }
    }
    
    if (-not $installerSuccess) {
        Write-Log "❌ Installer failed after $maxRetries attempts" "ERROR"
        Write-Log "💡 Try running manually: $Installer /quietinstall /auto upgrade" "INFO"
        exit 6
    }
    
    # Step 9: Check results
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Checking upgrade results..." $CurrentStep
    
    $exitCode = $process.ExitCode
    Write-Log "Installer exit code: $exitCode" "INFO"
    
    # Interpret exit codes for Windows 11 Installation Assistant
    $exitCodeMeaning = switch ($exitCode) {
        0 { "Success - Upgrade completed successfully" }
        1 { "General error or user cancellation" }
        2 { "Invalid command line arguments" }
        3 { "System restart required to continue upgrade" }
        4 { "Insufficient disk space" }
        5 { "Another instance is running or access denied" }
        6 { "Unsupported operating system" }
        7 { "Network connection error" }
        8 { "Windows Update service unavailable" }
        9 { "Hardware compatibility check failed" }
        10 { "User account control (UAC) restriction" }
        -1 { "Unexpected error occurred" }
        default { "Unknown exit code - check Windows 11 compatibility" }
    }
    
    Write-Log "Exit code meaning: $exitCodeMeaning" "INFO"
    
    if ($exitCode -eq 0) {
        Write-Log "🎉 Windows 11 upgrade completed successfully!" "SUCCESS"
        if (-not $AutomaticMode) {
            Write-Host "🎉 Windows 11 upgrade completed successfully!" -ForegroundColor Green
        }
    } elseif ($exitCode -eq 3) {
        Write-Log "🔄 System restart required - upgrade will continue after reboot" "INFO"
        if ($AutomaticMode -or $ForceRestart) {
            Write-Log "🤖 Scheduling automatic restart..." "INFO"
            
            # Create scheduled task to continue after restart
            $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"iex (iwr -Uri 'https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11-Fixed.ps1' -UseBasicParsing).Content`""
            $taskTrigger = New-ScheduledTaskTrigger -AtStartup
            $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            
            try {
                Register-ScheduledTask -TaskName "ContinueWindows11Upgrade" -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Force
                Write-Log "✅ Scheduled task created for post-restart continuation" "SUCCESS"
            } catch {
                Write-Log "⚠️  Could not create scheduled task: $($_.Exception.Message)" "WARNING"
            }
            
            Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "60", "/c", "Windows 11 upgrade requires restart - continuing in 60 seconds" -WindowStyle Hidden
        } else {
            Write-Log "⚠️  Manual restart required to complete upgrade" "WARNING"
        }
    } elseif ($exitCode -eq 5) {
        Write-Log "⚠️  Exit code 5: Another instance may be running or access denied" "WARNING"
        Write-Log "🔄 This often indicates the upgrade is already in progress in background" "INFO"
        Write-Log "💡 Check Task Manager for Windows11InstallationAssistant or wait a few minutes" "INFO"
        
        # Check if upgrade is actually in progress
        $upgradeProcesses = Get-Process | Where-Object { 
            $_.ProcessName -like "*Windows11*" -or 
            $_.ProcessName -like "*setup*" -or 
            $_.MainWindowTitle -like "*Windows 11*"
        }
        
        if ($upgradeProcesses) {
            Write-Log "✅ Found active upgrade processes - upgrade likely in progress" "SUCCESS"
            foreach ($proc in $upgradeProcesses) {
                Write-Log "Active: $($proc.ProcessName) (PID: $($proc.Id))" "INFO"
            }
        } else {
            Write-Log "❌ No active upgrade processes found - may need manual intervention" "WARNING"
        }
        
        if (-not $AutomaticMode) {
            Write-Host "⚠️  Upgrade initiated but needs verification. Check if Windows 11 upgrade is running in background." -ForegroundColor Yellow
        }
    } else {
        Write-Log "❌ Upgrade completed with exit code: $exitCode ($exitCodeMeaning)" "WARNING"
        if (-not $AutomaticMode) {
            Write-Host "⚠️  Upgrade completed with warnings. Exit code: $exitCode - $exitCodeMeaning" -ForegroundColor Yellow
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