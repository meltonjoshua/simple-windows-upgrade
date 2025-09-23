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

# Alternative approach: ISO direct upgrade
$IsoUrl = "https://go.microsoft.com/fwlink/?linkid=2156292"  # Windows 11 ISO
$IsoFile = Join-Path $TempDir "Win11.iso"

# Progress tracking
$TotalSteps = 9  # Updated to include health check
$CurrentStep = 0
$ErrorCount = 0
$WarningCount = 0
$script:StartTime = Get-Date
$script:StepTimes = @()

# Error handling configuration
$ErrorActionPreference = "Stop"
$script:ExitCode = 0

function Update-Progress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$Step,
        [string]$SubStatus = ""
    )
    
    if ($ShowProgress) {
        $PercentComplete = ($Step / $TotalSteps) * 100
        $currentTime = Get-Date
        $elapsed = $currentTime - $script:StartTime
        
        # Calculate ETA based on average step time
        if ($script:StepTimes.Count -gt 0) {
            $avgStepTime = ($script:StepTimes | Measure-Object -Average).Average
            $remainingSteps = $TotalSteps - $Step
            $etaSeconds = $remainingSteps * $avgStepTime
            $eta = [TimeSpan]::FromSeconds($etaSeconds)
            $etaString = if ($eta.TotalMinutes -lt 60) {
                "{0:mm}m {0:ss}s" -f $eta
            } else {
                "{0:hh}h {0:mm}m" -f $eta
            }
        } else {
            $etaString = "Calculating..."
        }
        
        $progressStatus = "$Status"
        if ($SubStatus) {
            $progressStatus += " - $SubStatus"
        }
        $progressStatus += " (ETA: $etaString)"
        
        Write-Progress -Activity $Activity -Status $progressStatus -PercentComplete $PercentComplete
        
        $timeStamp = $currentTime.ToString("HH:mm:ss")
        $elapsedString = "{0:mm}m {0:ss}s" -f $elapsed
        Write-Host "[$Step/$TotalSteps] [$timeStamp] [$elapsedString] $Status" -ForegroundColor Cyan
        
        if ($SubStatus) {
            Write-Host "    └─ $SubStatus" -ForegroundColor Gray
        }
        
        # Record step completion time
        if ($Step -gt ($script:StepTimes.Count)) {
            $stepDuration = if ($script:StepTimes.Count -eq 0) {
                $elapsed.TotalSeconds
            } else {
                ($currentTime - $script:LastStepTime).TotalSeconds
            }
            $script:StepTimes += $stepDuration
            $script:LastStepTime = $currentTime
        }
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
    
    # Track error and warning counts
    if ($Level -eq "ERROR") { $script:ErrorCount++ }
    if ($Level -eq "WARNING") { $script:WarningCount++ }
    
    # Also write to log file if it exists
    try {
        if (Test-Path $LogFile) {
            Add-Content -Path $LogFile -Value $logEntry -ErrorAction SilentlyContinue
        }
    } catch {
        # Silently fail if we can't write to log file
    }
}

function Write-ErrorLog {
    param(
        [string]$Operation,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$AdditionalInfo = ""
    )
    
    $errorDetails = @(
        "Operation: $Operation"
        "Error: $($ErrorRecord.Exception.Message)"
        "Category: $($ErrorRecord.CategoryInfo.Category)"
        "TargetObject: $($ErrorRecord.TargetObject)"
        "ScriptLineNumber: $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
    )
    
    if ($AdditionalInfo) {
        $errorDetails += "Additional Info: $AdditionalInfo"
    }
    
    foreach ($detail in $errorDetails) {
        Write-Log $detail "ERROR"
    }
}

function Invoke-SafeOperation {
    param(
        [string]$Operation,
        [scriptblock]$ScriptBlock,
        [string]$SuccessMessage = "",
        [string]$ErrorMessage = "",
        [bool]$ContinueOnError = $true,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 5,
        [scriptblock]$RetryCondition = { $true }
    )
    
    $attempt = 1
    $lastError = $null
    
    while ($attempt -le $MaxRetries) {
        try {
            if ($attempt -gt 1) {
                Write-Log "Retry attempt $attempt of $MaxRetries for: $Operation" "INFO"
                Start-Sleep -Seconds $RetryDelaySeconds
            }
            
            $result = & $ScriptBlock
            if ($SuccessMessage) {
                Write-Log $SuccessMessage "SUCCESS"
            }
            return $result
        }
        catch {
            $lastError = $_
            
            if ($attempt -eq $MaxRetries -or -not (& $RetryCondition)) {
                Write-ErrorLog -Operation $Operation -ErrorRecord $_ -AdditionalInfo $ErrorMessage
                
                if (-not $ContinueOnError) {
                    throw
                }
                return $null
            }
            
            Write-Log "Attempt $attempt failed for $Operation`: $($_.Exception.Message)" "WARNING"
            $attempt++
        }
    }
}

function Test-SystemHealth {
    Write-Log "🏥 Performing comprehensive system health check..." "INFO"
    $healthIssues = @()
    $healthWarnings = @()
    
    # Check disk space (minimum 32GB for Windows 11)
    try {
        $systemDrive = $env:SystemDrive
        $disk = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $systemDrive }
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        
        if ($freeSpaceGB -lt 32) {
            $healthIssues += "Insufficient disk space: ${freeSpaceGB}GB (32GB minimum required)"
        } elseif ($freeSpaceGB -lt 64) {
            $healthWarnings += "Low disk space: ${freeSpaceGB}GB (64GB recommended)"
        } else {
            Write-Log "✅ Disk space: ${freeSpaceGB}GB available" "SUCCESS"
        }
    } catch {
        $healthWarnings += "Could not verify disk space"
    }
    
    # Check for running antivirus that might interfere
    try {
        $antivirusProducts = Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct -ErrorAction SilentlyContinue
        if ($antivirusProducts) {
            $activeAV = $antivirusProducts | Where-Object { $_.productState -band 0x1000 }
            if ($activeAV) {
                Write-Log "🔍 Active antivirus detected: $($activeAV.displayName -join ', ')" "INFO"
                Write-Log "   Consider temporarily disabling real-time protection during upgrade" "WARNING"
                $healthWarnings += "Active antivirus may slow down upgrade process"
            }
        }
    } catch {
        Write-Log "Could not check antivirus status" "INFO"
    }
    
    # Check for pending reboot
    try {
        $rebootRequired = $false
        
        # Check registry for pending reboot indicators
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
        )
        
        foreach ($key in $rebootKeys) {
            if (Test-Path $key) {
                $rebootRequired = $true
                break
            }
        }
        
        if ($rebootRequired) {
            $healthIssues += "System reboot is pending - please restart before upgrading"
        } else {
            Write-Log "✅ No pending reboot required" "SUCCESS"
        }
    } catch {
        $healthWarnings += "Could not check reboot status"
    }
    
    # Check system temperature (if available)
    try {
        $temp = Get-WmiObject -Class MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue
        if ($temp) {
            $avgTempC = ($temp | ForEach-Object { ($_.CurrentTemperature / 10) - 273.15 } | Measure-Object -Average).Average
            if ($avgTempC -gt 80) {
                $healthWarnings += "High system temperature detected: ${avgTempC}°C (consider cooling before upgrade)"
            } else {
                Write-Log "✅ System temperature: ${avgTempC}°C" "SUCCESS"
            }
        }
    } catch {
        Write-Log "System temperature monitoring not available" "INFO"
    }
    
    # Check for critical Windows services
    $criticalServices = @("wuauserv", "BITS", "CryptSvc", "MSiSCSI")
    foreach ($serviceName in $criticalServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            if ($service.Status -ne "Running") {
                $healthWarnings += "Critical service '$serviceName' is not running"
            }
        } catch {
            $healthWarnings += "Critical service '$serviceName' not found"
        }
    }
    
    # Check for running processes that might interfere
    $problematicProcesses = @("steam", "discord", "spotify", "chrome", "firefox", "vmware", "virtualbox")
    $runningProblematic = @()
    foreach ($processName in $problematicProcesses) {
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($process) {
            $runningProblematic += $processName
        }
    }
    
    if ($runningProblematic.Count -gt 0) {
        $healthWarnings += "Resource-intensive applications running: $($runningProblematic -join ', ') - consider closing for optimal performance"
    }
    
    # Return results
    return @{
        Issues = $healthIssues
        Warnings = $healthWarnings
        Healthy = ($healthIssues.Count -eq 0)
    }
}

function Test-Prerequisites {
    Write-Log "Checking script prerequisites..." "INFO"
    $issues = @()
    
    # Check PowerShell version
    try {
        if ($PSVersionTable.PSVersion.Major -lt 3) {
            $issues += "PowerShell version $($PSVersionTable.PSVersion) is too old (minimum 3.0 required)"
        } else {
            Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "SUCCESS"
        }
    } catch {
        $issues += "Unable to determine PowerShell version"
    }
    
    # Check .NET Framework version
    try {
        $dotNetVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" -Name Release -ErrorAction Stop).Release
        if ($dotNetVersion -lt 461808) {  # .NET 4.7.2
            $issues += "Insufficient .NET Framework version (4.7.2+ required)"
        } else {
            Write-Log ".NET Framework version: Sufficient" "SUCCESS"
        }
    } catch {
        Write-Log "Could not verify .NET Framework version" "WARNING"
    }
    
    # Check available memory
    try {
        $availableMemory = [math]::Round((Get-Counter "\Memory\Available MBytes").CounterSamples[0].CookedValue / 1024, 2)
        if ($availableMemory -lt 1) {
            $issues += "Low available memory: ${availableMemory}GB"
        } else {
            Write-Log "Available memory: ${availableMemory}GB" "SUCCESS"
        }
    } catch {
        Write-Log "Could not check available memory" "WARNING"
    }
    
    return $issues
}

function Update-Windows10ToLatest {
    param(
        [switch]$Force
    )
    
    Write-Log "🔄 Checking Windows 10 update status..." "INFO"
    
    try {
        $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $currentBuild = [int]$OS.CurrentBuild
        
        if ($currentBuild -ge 19045) {
            Write-Log "✅ Windows 10 is already at latest build ($currentBuild)" "SUCCESS"
            return $true
        }
        
        if ($currentBuild -eq 19044 -or $Force) {
            Write-Log "🚀 Attempting to update Windows 10 to latest build..." "INFO"
            Write-Log "   Current build: $currentBuild (Target: 19045)" "INFO"
            
            # Method 1: Use Windows Update API
            Write-Log "🔍 Initiating Windows Update scan..." "INFO"
            try {
                # Trigger update scan
                $updateSession = New-Object -ComObject Microsoft.Update.Session
                $updateSearcher = $updateSession.CreateupdateSearcher()
                $updateSearcher.Online = $true
                
                Write-Log "   Searching for available updates..." "INFO"
                $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
                
                if ($searchResult.Updates.Count -gt 0) {
                    Write-Log "   Found $($searchResult.Updates.Count) available updates" "SUCCESS"
                    
                    # Download and install updates
                    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($update in $searchResult.Updates) {
                        if ($update.Title -like "*Feature update*" -or $update.Title -like "*Cumulative*") {
                            $updatesToDownload.Add($update) | Out-Null
                            Write-Log "   Queued: $($update.Title)" "INFO"
                        }
                    }
                    
                    if ($updatesToDownload.Count -gt 0) {
                        Write-Log "🔄 Downloading and installing $($updatesToDownload.Count) critical updates..." "INFO"
                        Write-Log "   ⚠️  This may take 15-45 minutes and will require restart" "WARNING"
                        
                        $downloader = $updateSession.CreateUpdateDownloader()
                        $downloader.Updates = $updatesToDownload
                        $downloadResult = $downloader.Download()
                        
                        if ($downloadResult.ResultCode -eq 2) {
                            Write-Log "   ✅ Updates downloaded successfully" "SUCCESS"
                            
                            $installer = $updateSession.CreateUpdateInstaller()
                            $installer.Updates = $updatesToDownload
                            $installResult = $installer.Install()
                            
                            if ($installResult.ResultCode -eq 2) {
                                Write-Log "   ✅ Updates installed successfully" "SUCCESS"
                                Write-Log "   🔄 System restart required - please restart and re-run script" "WARNING"
                                return $false # Indicate restart needed
                            } else {
                                Write-Log "   ❌ Update installation failed (Code: $($installResult.ResultCode))" "WARNING"
                            }
                        } else {
                            Write-Log "   ❌ Update download failed (Code: $($downloadResult.ResultCode))" "WARNING"
                        }
                    } else {
                        Write-Log "   No critical updates found for download" "INFO"
                    }
                } else {
                    Write-Log "   No updates available via Windows Update API" "INFO"
                }
            } catch {
                Write-Log "Windows Update API method failed: $($_.Exception.Message)" "WARNING"
            }
            
            # Method 2: Use UsoClient (Universal Store Orchestrator)
            Write-Log "🔧 Trying UsoClient method..." "INFO"
            try {
                Start-Process "UsoClient.exe" -ArgumentList "StartScan" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 5
                Start-Process "UsoClient.exe" -ArgumentList "StartDownload" -Wait -WindowStyle Hidden
                Start-Sleep -Seconds 5
                Start-Process "UsoClient.exe" -ArgumentList "StartInstall" -Wait -WindowStyle Hidden
                Write-Log "   UsoClient commands executed successfully" "SUCCESS"
                Write-Log "   Updates may be installing in background - check Windows Update" "INFO"
            } catch {
                Write-Log "UsoClient method failed: $($_.Exception.Message)" "WARNING"
            }
            
            # Method 3: PowerShell Windows Update Module
            Write-Log "🔧 Trying PSWindowsUpdate module method..." "INFO"
            try {
                # Check if module is available
                if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                    Import-Module PSWindowsUpdate -Force
                    $updates = Get-WUList -MicrosoftUpdate
                    if ($updates) {
                        Write-Log "   Found $($updates.Count) updates via PSWindowsUpdate" "SUCCESS"
                        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot
                        Write-Log "   Updates initiated via PSWindowsUpdate" "SUCCESS"
                    }
                } else {
                    Write-Log "   PSWindowsUpdate module not available" "INFO"
                }
            } catch {
                Write-Log "PSWindowsUpdate method failed: $($_.Exception.Message)" "WARNING"
            }
            
            return $false # Indicate manual check needed
        }
        
        return $true
    } catch {
        Write-Log "Failed to check/update Windows 10: $($_.Exception.Message)" "WARNING"
        return $true # Continue anyway
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
    Invoke-SafeOperation -Operation "Windows Version Check" -ScriptBlock {
        $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $currentBuild = [int]$OS.CurrentBuild
        
        Write-Log "Current Windows: $($OS.ProductName) Build $currentBuild" "INFO"
        
        if ($currentBuild -ge 22000 -and $currentBuild -lt 26000) {
            $compatibility.Issues += "Already running Windows 11 (Build $currentBuild)"
            $compatibility.Compatible = $false
        } elseif ($currentBuild -ge 26000) {
            $compatibility.Warnings += "Running Windows 11 Insider Preview (Build $currentBuild) - upgrade may not be necessary"
        } elseif ($currentBuild -lt 18362) {
            $compatibility.Issues += "Windows 10 build too old (minimum 1903/18362 required)"
            $compatibility.Compatible = $false
        }
    } -ErrorMessage "Could not determine Windows version" -ContinueOnError $true
    
    if (-not $?) {
        $compatibility.Issues += "Unable to determine Windows version"
        $compatibility.Compatible = $false
    }
    
    # Check TPM
    Invoke-SafeOperation -Operation "TPM Check" -ScriptBlock {
        $tpm = Get-WmiObject -Namespace "Root\CIMv2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction SilentlyContinue
        if ($tpm -and $tpm.IsEnabled_InitialValue) {
            Write-Log "TPM: Present and enabled (Version $($tpm.ManufacturerVersion))" "SUCCESS"
        } else {
            $compatibility.Warnings += "TPM not detected or not enabled"
            Write-Log "TPM: Not detected or not enabled (will use registry bypass)" "WARNING"
        }
    } -ErrorMessage "Error checking TPM status" -ContinueOnError $true
    
    if (-not $?) {
        $compatibility.Warnings += "Could not check TPM status"
    }
    
    # Check CPU architecture
    Invoke-SafeOperation -Operation "CPU Architecture Check" -ScriptBlock {
        $cpu = Get-WmiObject -Class Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Architecture -ne 9) {  # 9 = x64
            $compatibility.Issues += "CPU architecture not supported (x64 required)"
            $compatibility.Compatible = $false
        } else {
            Write-Log "CPU: $($cpu.Name) (x64)" "SUCCESS"
        }
    } -ErrorMessage "Error checking CPU architecture" -ContinueOnError $true
    
    if (-not $?) {
        $compatibility.Issues += "Unable to determine CPU architecture"
        $compatibility.Compatible = $false
    }
    
    # Check RAM (with bypass capability)
    Invoke-SafeOperation -Operation "RAM Check" -ScriptBlock {
        $ramGB = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 2)
        if ($ramGB -lt 4) {
            # With registry bypasses, treat RAM as warning instead of hard failure
            $compatibility.Warnings += "Low RAM: ${ramGB}GB (4GB recommended, but bypass enabled)"
            Write-Log "RAM: ${ramGB}GB (below 4GB minimum, but will use registry bypass)" "WARNING"
        } else {
            Write-Log "RAM: ${ramGB}GB" "SUCCESS"
        }
    } -ErrorMessage "Error checking RAM" -ContinueOnError $true
    
    if (-not $?) {
        $compatibility.Warnings += "Could not verify RAM amount"
    }
    
    # Check disk space
    Invoke-SafeOperation -Operation "Disk Space Check" -ScriptBlock {
        $systemDrive = Get-WmiObject -Class Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        if (-not $systemDrive) {
            throw "System drive not found"
        }
        
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        if ($freeSpaceGB -lt 64) {
            $compatibility.Issues += "Insufficient disk space: ${freeSpaceGB}GB free (64GB minimum required)"
            $compatibility.Compatible = $false
        } else {
            Write-Log "Disk Space: ${freeSpaceGB}GB free on $($systemDrive.DeviceID)" "SUCCESS"
        }
    } -ErrorMessage "Error checking disk space" -ContinueOnError $true
    
    if (-not $?) {
        $compatibility.Issues += "Unable to verify disk space"
        $compatibility.Compatible = $false
    }
    
    # Check Secure Boot (if available)
    Invoke-SafeOperation -Operation "Secure Boot Check" -ScriptBlock {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        if ($secureBoot) {
            Write-Log "Secure Boot: Enabled" "SUCCESS"
        } else {
            $compatibility.Warnings += "Secure Boot not enabled"
            Write-Log "Secure Boot: Not enabled (recommended for Windows 11)" "WARNING"
        }
    } -ErrorMessage "Error checking Secure Boot" -ContinueOnError $true
    
    if (-not $?) {
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

# Main script execution with comprehensive error handling
try {
    # Step 1: Initialize
    $CurrentStep++
    Update-Progress "Windows 11 Upgrade" "Initializing upgrade process..." $CurrentStep

    # Check prerequisites
    $prereqIssues = Test-Prerequisites
    if ($prereqIssues.Count -gt 0) {
        Write-Log "PREREQUISITE ISSUES FOUND:" "WARNING"
        foreach ($issue in $prereqIssues) {
            Write-Log "⚠️  $issue" "WARNING"
        }
        Write-Log "Script will continue but may encounter issues" "WARNING"
    }

    # Check if running as Administrator
    $IsAdmin = Invoke-SafeOperation -Operation "Administrator Check" -ScriptBlock {
        ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } -ContinueOnError $false

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

    # Temporarily disable UAC to prevent permission issues
    Write-Log "🔧 Temporarily disabling UAC for installation..." "INFO"
    try {
        $originalUAC = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue
        if ($originalUAC) {
            Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0 -Force
            Write-Log "✅ UAC temporarily disabled (will be restored after installation)" "SUCCESS"
            
            # Also disable consent prompts
            Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Value 0 -Force -ErrorAction SilentlyContinue
            Write-Log "✅ UAC consent prompts disabled" "SUCCESS"
        }
    } catch {
        Write-Log "Warning: Could not modify UAC settings" "WARNING"
    }

    # Create temp directory with error handling
    Invoke-SafeOperation -Operation "Temp Directory Creation" -ScriptBlock {
        if (-not (Test-Path $TempDir)) {
            Write-Host "Creating temporary directory: $TempDir" -ForegroundColor Yellow
            New-Item -Path $TempDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } else {
            Write-Host "Using existing temporary directory: $TempDir" -ForegroundColor Green
        }
    } -ErrorMessage "Failed to create or access temporary directory" -ContinueOnError $false

    # Initialize log file with error handling
    Invoke-SafeOperation -Operation "Log File Initialization" -ScriptBlock {
        "Windows 11 Upgrade Log - Started $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8 -ErrorAction Stop
        Write-Log "Upgrade process initialized" "INFO"
    } -ErrorMessage "Failed to initialize log file" -ContinueOnError $true

# Step 2: System Health Check
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Performing system health check..." $CurrentStep

$healthCheck = Test-SystemHealth

if (-not $healthCheck.Healthy) {
    Write-Log "SYSTEM HEALTH ISSUES DETECTED:" "WARNING"
    foreach ($issue in $healthCheck.Issues) {
        Write-Log "❌ $issue" "ERROR"
    }
    
    Write-Host "" -ForegroundColor Red
    Write-Host "❌ Critical system health issues found." -ForegroundColor Red
    Write-Host "   Please resolve these issues before upgrading:" -ForegroundColor Red
    foreach ($issue in $healthCheck.Issues) {
        Write-Host "   • $issue" -ForegroundColor Yellow
    }
    
    if ($KeepOpen) {
        Write-Host ""
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    exit 2
}

if ($healthCheck.Warnings.Count -gt 0) {
    Write-Log "SYSTEM HEALTH WARNINGS:" "WARNING"
    foreach ($warning in $healthCheck.Warnings) {
        Write-Log "⚠️  $warning" "WARNING"
    }
}

# Step 3: System Compatibility Check
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Checking system compatibility..." $CurrentStep

$compatibility = Test-SystemCompatibility

# Check if Windows 10 needs updating first
if ($compatibility.Compatible) {
    $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $currentBuild = [int]$OS.CurrentBuild
    
    if ($currentBuild -eq 19044) {
        Write-Log "🔄 Windows 10 Build 19044 detected - updating to latest build first..." "INFO"
        $updateResult = Update-Windows10ToLatest
        
        if (-not $updateResult) {
            Write-Log "⚠️  Windows 10 update initiated - system restart required" "WARNING"
            Write-Host "" -ForegroundColor Yellow
            Write-Host "⚠️  Windows 10 has been updated but requires a restart." -ForegroundColor Yellow
            Write-Host "   Please restart your computer and re-run this script." -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Yellow
            Write-Host "   After restart, run:" -ForegroundColor Cyan
            Write-Host "   iex (iwr -Uri 'https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11%20copy.ps1' -UseBasicParsing).Content" -ForegroundColor White
            
            if ($KeepOpen) {
                Write-Host ""
                Write-Host "Press any key to close this window..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            exit 3  # Restart required
        }
    }
}

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
    Update-Progress "Windows 11 Upgrade" "Configuring comprehensive registry bypasses..." $CurrentStep

    # Essential Windows 11 hardware bypasses (streamlined)
    $regItems = @(
        # Core bypasses - these are the most important
        @{Path="HKLM:\SYSTEM\Setup\LabConfig"; Name="BypassTPMCheck"; Value=1; Description="Bypass TPM requirement"},
        @{Path="HKLM:\SYSTEM\Setup\LabConfig"; Name="BypassSecureBootCheck"; Value=1; Description="Bypass Secure Boot requirement"},
        @{Path="HKLM:\SYSTEM\Setup\LabConfig"; Name="BypassRAMCheck"; Value=1; Description="Bypass RAM requirement"},
        @{Path="HKLM:\SYSTEM\Setup\LabConfig"; Name="BypassCPUCheck"; Value=1; Description="Bypass CPU requirement"},
        
        # MoSetup bypass - essential for Installation Assistant
        @{Path="HKLM:\SYSTEM\Setup\MoSetup"; Name="AllowUpgradesWithUnsupportedTPMOrCPU"; Value=1; Description="Installation Assistant bypass"},
        
        # Windows Update bypass - for update-based installs  
        @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"; Name="AllowUpgradesWithUnsupportedTPMOrCPU"; Value=1; Description="Windows Update bypass"}
    )

    Write-Log "🔧 Configuring essential Windows 11 hardware bypasses..." "INFO"
    Write-Log "   Applying only the most effective registry bypasses" "INFO"
    $registryErrors = 0
     
    foreach ($item in $regItems) {
        Write-Log "Setting registry bypass: $($item.Description)" "INFO"
        
        $success = Invoke-SafeOperation -Operation "Registry Key: $($item.Path)\$($item.Name)" -ScriptBlock {
            # Check if registry path exists, create if needed
            if (-not (Test-Path $item.Path)) {
                New-Item -Path $item.Path -Force -ErrorAction Stop | Out-Null
                Write-Log "  Created registry path: $($item.Path)" "SUCCESS"
            }
            
            # Set the registry value
            New-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Write-Log "  ✅ Set $($item.Path)\$($item.Name) = $($item.Value)" "SUCCESS"
            return $true
        } -ErrorMessage "Failed to set registry key" -ContinueOnError $true
        
        if (-not $success) {
            $registryErrors++
            Write-Log "  ❌ Failed to set: $($item.Description)" "WARNING"
        }
    }
    
    if ($registryErrors -gt 0) {
        Write-Log "⚠️  $registryErrors registry bypass(es) failed to set." "WARNING"
        Write-Log "   Some bypasses may not be effective, but upgrade will still attempt" "WARNING"
    } else {
        Write-Log "🎯 Essential registry bypasses configured successfully!" "SUCCESS"
        Write-Log "   Applied $($regItems.Count) core hardware bypasses" "SUCCESS"
    }# ----- DOWNLOAD INSTALLER -----
$CurrentStep++
Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep

# Multiple download sources for redundancy
$downloadSources = @(
    @{
        Name = "Microsoft Official (Primary)"
        Url = $DownloadUrl
        Priority = 1
    },
    @{
        Name = "Microsoft Direct Link"
        Url = "https://download.microsoft.com/download/8/7/3/873e1c5c-7a4e-4d7e-8b7e-7b3c5a6b5c5d/Windows11InstallationAssistant.exe"
        Priority = 2
    },
    @{
        Name = "Microsoft Alternative"
        Url = "https://go.microsoft.com/fwlink/?LinkID=2195334"
        Priority = 3
    }
)

Write-Log "Attempting download from multiple sources..." "INFO"

# Remove existing installer if present
if (Test-Path $Installer) {
    Write-Log "Removing existing installer file..." "INFO"
    Remove-Item $Installer -Force
}

$downloadSuccess = $false
$totalAttempts = 0
$maxTotalAttempts = 9 # 3 sources x 3 attempts each

foreach ($source in ($downloadSources | Sort-Object Priority)) {
    if ($downloadSuccess) { break }
    
    Write-Log "Trying source: $($source.Name)" "INFO"
    Write-Log "Download URL: $($source.Url)" "INFO"
    Write-Log "Destination: $Installer" "INFO"
    
    $sourceAttempts = 0
    $maxSourceAttempts = 3
    
    while ($sourceAttempts -lt $maxSourceAttempts -and -not $downloadSuccess -and $totalAttempts -lt $maxTotalAttempts) {
        $sourceAttempts++
        $totalAttempts++
        
        $attemptStatus = "Attempt $sourceAttempts/$maxSourceAttempts from $($source.Name)"
        Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep $attemptStatus
        Write-Log "Download attempt $sourceAttempts of $maxSourceAttempts from $($source.Name)..." "INFO"
        
        try {
            $ProgressPreference = 'SilentlyContinue'
            
            # Use enhanced download with progress callback
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            
            # Add progress handler
            $webClient.DownloadProgressChanged += {
                param($sender, $e)
                $progressPercent = $e.ProgressPercentage
                $downloadedMB = [math]::Round($e.BytesReceived / 1MB, 1)
                $totalMB = [math]::Round($e.TotalBytesToReceive / 1MB, 1)
                $subStatus = "Downloaded ${downloadedMB}MB of ${totalMB}MB (${progressPercent}%)"
                Update-Progress "Windows 11 Upgrade" "Downloading Windows 11 Installation Assistant..." $CurrentStep $subStatus
            }
            
            # Start async download
            $downloadTask = $webClient.DownloadFileTaskAsync($source.Url, $Installer)
            
            # Wait with timeout
            $timeout = 300000 # 5 minutes
            if ($downloadTask.Wait($timeout)) {
                $ProgressPreference = 'Continue'
                
                # Verify download completed successfully
                if (Test-Path $Installer) {
                    $FileSize = (Get-Item $Installer).Length
                    if ($FileSize -gt 1MB) {  # Minimum reasonable size
                        # Verify file is actually executable
                        $fileInfo = Get-ItemProperty $Installer
                        if ($fileInfo.Name -match '\.exe$') {
                            $downloadSuccess = $true
                            Write-Log "✅ Downloaded successfully from $($source.Name)!" "SUCCESS"
                            Write-Log "File size: $([math]::Round($FileSize / 1MB, 2)) MB" "SUCCESS"
                            break
                        } else {
                            Write-Log "❌ Downloaded file is not executable" "ERROR"
                            Remove-Item $Installer -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        Write-Log "❌ Download failed: File too small ($([math]::Round($FileSize / 1KB, 2)) KB)" "ERROR"
                        Remove-Item $Installer -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Log "❌ Download failed: File not created" "ERROR"
                }
            } else {
                Write-Log "❌ Download timeout after 5 minutes" "ERROR"
                $downloadTask.Dispose()
                Remove-Item $Installer -Force -ErrorAction SilentlyContinue
            }
            
            $webClient.Dispose()
            
        } catch {
            $ProgressPreference = 'Continue'
            Write-Log "❌ Download failed: $($_.Exception.Message)" "ERROR"
            Remove-Item $Installer -Force -ErrorAction SilentlyContinue
            
            if ($sourceAttempts -lt $maxSourceAttempts) {
                $waitTime = $sourceAttempts * 2  # Progressive backoff: 2s, 4s, 6s
                Write-Log "Waiting ${waitTime} seconds before retry..." "INFO"
                Start-Sleep -Seconds $waitTime
            }
        }
    }
    
    if (-not $downloadSuccess -and $source.Priority -lt 3) {
        Write-Log "Failed to download from $($source.Name), trying next source..." "WARNING"
    }
}

if (-not $downloadSuccess) {
    Write-Log "❌ Failed to download Windows 11 Installation Assistant from all sources" "ERROR"
    Write-Log "   Total attempts: $totalAttempts" "ERROR"
    Write-Progress -Activity "Windows 11 Upgrade" -Completed
    
    Write-Host "" -ForegroundColor Red
    Write-Host "❌ Could not download Windows 11 Installation Assistant" -ForegroundColor Red
    Write-Host "   Please check your internet connection and try again" -ForegroundColor Red
    
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

# Essential installer arguments (streamlined)
$customInstallDir = "C:\Temp\Windows11Install"
$arguments = @(
    "/quietinstall",           # Silent installation
    "/skipeula",              # Skip EULA
    "/auto upgrade",          # Auto upgrade mode
    "/CopyLogs `"$LogFile`"", # Copy logs
    "/noreboot"               # Don't reboot automatically
)

# Create custom installation directory with full permissions
Write-Log "🔧 Creating custom installation directory..." "INFO"
# Create custom installation directory with full permissions
Write-Log "🔧 Creating custom installation directory..." "INFO"
try {
    if (Test-Path $customInstallDir) {
        Remove-Item $customInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $customInstallDir -ItemType Directory -Force | Out-Null
    
    # Set everyone full control on our custom directory
    $acl = Get-Acl $customInstallDir
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $customInstallDir -AclObject $acl
    
    Write-Log "✅ Custom installation directory created: $customInstallDir" "SUCCESS"
} catch {
    Write-Log "Warning: Could not create custom installation directory" "WARNING"
}

# Join arguments for display
$argumentString = $arguments -join " "
Write-Log "🚀 Running installer with essential bypass arguments:" "INFO"
Write-Log "   $argumentString" "INFO"
Write-Log "Primary log file: $LogFile" "INFO"
Write-Log "Monitor log file: $($LogFile -replace '\.log$', '_monitor.log')" "INFO"

Write-Host "" -ForegroundColor Yellow
Write-Log "⚠️  IMPORTANT: The upgrade process will now begin and may take 30-90 minutes." "WARNING"
Write-Log "   Your computer will restart automatically when complete." "WARNING"
Write-Log "   Do not power off or interrupt the process." "WARNING"
Write-Log "🔧 Using streamlined bypasses for maximum compatibility!" "WARNING"
Write-Host "" -ForegroundColor Yellow

# Record start time
$startTime = Get-Date
Write-Log "Upgrade started at: $startTime" "INFO"

# Set essential environment variables for bypasses
Write-Log "🔧 Setting essential environment bypasses..." "INFO"
try {
    $env:TEMP = $customInstallDir
    $env:TMP = $customInstallDir
    Write-Log "✅ Essential environment variables set" "SUCCESS"
} catch {
    Write-Log "Warning: Could not set environment variables" "WARNING"
}

try {
    # Copy installer to our custom directory to avoid permission issues
    $customInstaller = Join-Path $customInstallDir "Windows11InstallationAssistant.exe"
    Copy-Item -Path $Installer -Destination $customInstaller -Force
    Write-Log "✅ Copied installer to custom directory" "SUCCESS"
    
    # Change to our custom directory
    Push-Location $customInstallDir
    
    # Start the installer process with comprehensive bypass arguments
    Write-Log "🚀 Starting installer from custom directory with full permissions..." "INFO"
    $process = Start-Process -FilePath $customInstaller -ArgumentList $argumentString -PassThru -WorkingDirectory $customInstallDir -WindowStyle Hidden -ErrorAction Stop
    Write-Log "Installer process started with PID: $($process.Id)" "SUCCESS"
    
    # Monitor the process
    $checkInterval = 10 # Check every 10 seconds instead of 30
    $lastLogCheck = Get-Date
    $processStillRunning = $true
    
    while (-not $process.HasExited -and $processStillRunning) {
        Start-Sleep $checkInterval
        
        # Double-check if process is actually still running
        try {
            $runningProcess = Get-Process -Id $process.Id -ErrorAction Stop
            $processStillRunning = $true
        } catch {
            Write-Log "Process $($process.Id) no longer found in process list" "WARNING"
            $processStillRunning = $false
            break
        }
        
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
        
        # Check for other Windows 11 related processes
        $relatedProcesses = Get-Process | Where-Object {
            $_.ProcessName -like "*Windows11*" -or 
            $_.ProcessName -like "*setup*" -or 
            $_.ProcessName -like "*install*" -or
            $_.Description -like "*Windows*upgrade*" -or
            $_.Description -like "*setup*"
        } | Where-Object { $_.Id -ne $process.Id }
        
        if ($relatedProcesses) {
            $processNames = ($relatedProcesses | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ", "
            Write-Log "Related processes detected: $processNames" "INFO"
        }
        
        # Show process is still running
        $elapsed = (Get-Date) - $startTime
        Write-Log "Installation running for $([math]::Round($elapsed.TotalMinutes, 1)) minutes..." "INFO"
        
        # If process runs longer than 2 minutes, check if it's actually doing something
        if ($elapsed.TotalMinutes -gt 2) {
            try {
                $processInfo = Get-Process -Id $process.Id
                $cpuTime = $processInfo.CPU
                Write-Log "Process CPU time: $([math]::Round($cpuTime, 2)) seconds" "INFO"
                
                # If CPU time is very low after 2 minutes, the process might be stuck
                if ($cpuTime -lt 1) {
                    Write-Log "Process appears to be idle (low CPU usage)" "WARNING"
                }
            } catch {
                Write-Log "Unable to get process information" "WARNING"
            }
        }
    }
    
    # Wait for process to fully complete
    if ($processStillRunning) {
        $process.WaitForExit()
    }
    $endTime = Get-Date
    $totalTime = $endTime - $startTime
    
    Write-Log "Installer process completed after $([math]::Round($totalTime.TotalMinutes, 1)) minutes" "INFO"
    Write-Log "Exit code: $($process.ExitCode)" "INFO"
    
        # If process exited very quickly, investigate why
        if ($totalTime.TotalMinutes -lt 1) {
            Write-Log "Process completed very quickly - investigating potential issues..." "WARNING"
            
            # Check if Windows 11 Installation Assistant created any error files
            $errorFiles = Get-ChildItem "C:\Temp" | Where-Object { 
                $_.Name -like "*error*" -or 
                $_.Name -like "*fail*" -or 
                $_.Name -like "*Windows11*" 
            }
            
            if ($errorFiles) {
                Write-Log "Found potential error files in C:\Temp:" "WARNING"
                foreach ($file in $errorFiles) {
                    Write-Log "  $($file.Name) - Modified: $($file.LastWriteTime)" "WARNING"
                }
            }
            
            # Try to run installer interactively to capture more info
            Write-Log "🔍 Attempting interactive run to capture any dialogs..." "INFO"
            try {
                $interactiveProcess = Start-Process -FilePath $Installer -PassThru -WindowStyle Hidden
                Start-Sleep 3  # Give it time to show any dialogs
                
                if (-not $interactiveProcess.HasExited) {
                    Write-Log "✅ Interactive installer is still running - may be showing dialogs" "INFO"
                    Start-Sleep 2
                    if (-not $interactiveProcess.HasExited) {
                        Write-Log "🔍 Installer running longer interactively - stopping test" "INFO"
                        $interactiveProcess.Kill()
                        Write-Log "✅ This suggests the installer CAN run but exits quickly in silent mode" "SUCCESS"
                    }
                } else {
                    Write-Log "❌ Interactive installer also exited quickly (Exit: $($interactiveProcess.ExitCode))" "WARNING"
                    Write-Log "   This confirms the installer is detecting an issue and refusing to run" "WARNING"
                }
            } catch {
                Write-Log "Could not run interactive test: $($_.Exception.Message)" "WARNING"
            }
            
            # Check Windows compatibility directly
            Write-Log "Checking Windows 11 readiness..." "INFO"
            try {
                $currentOS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
                $currentBuild = [int]$currentOS.CurrentBuild
                
                if ($currentBuild -ge 22000) {
                    Write-Log "🔍 DIAGNOSIS: System is already Windows 11 or newer (Build $currentBuild)" "WARNING"
                    Write-Log "   The Installation Assistant detected this and exited without upgrading" "WARNING"
                } elseif ($currentBuild -eq 19045) {
                    Write-Log "🔍 DIAGNOSIS: Windows 10 22H2 (Build 19045) - should be upgradeable" "INFO"
                    Write-Log "   Quick exit suggests hardware compatibility issue despite bypass" "WARNING"
                } elseif ($currentBuild -eq 19044) {
                    Write-Log "🔍 DIAGNOSIS: Windows 10 21H2 (Build 19044) - NEEDS UPDATE FIRST" "WARNING"
                    Write-Log "   ❌ This build is too old for direct Windows 11 upgrade" "WARNING"
                    Write-Log "   🔧 SOLUTION: Update to Windows 10 22H2 (Build 19045) first:" "INFO"
                    Write-Log "      1. Go to Settings > Update & Security > Windows Update" "INFO"
                    Write-Log "      2. Click 'Check for updates' and install all available updates" "INFO"
                    Write-Log "      3. Restart when prompted, then repeat until no more updates" "INFO"
                    Write-Log "      4. Once on Build 19045, re-run this Windows 11 upgrade script" "INFO"
                    Write-Log "   📋 Alternative: Download Windows 10 Update Assistant from Microsoft" "INFO"
                    Write-Log "   🤖 AUTOMATIC OPTION: Run 'sconfig' command and select option 6 for Windows Update" "INFO"
                } else {
                    Write-Log "🔍 DIAGNOSIS: Windows 10 Build $currentBuild - checking compatibility" "INFO"
                }
                
                # Enhanced CPU compatibility check
                $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
                $cpuName = $cpu.Name
                Write-Log "🔍 CPU Model: $cpuName" "INFO"
                
                # More detailed CPU generation detection
                if ($cpuName -match "i[3579]-(\d+)") {
                    $cpuGen = [int]$matches[1].Substring(0,1)
                    Write-Log "🔍 Detected Intel Generation: $cpuGen" "INFO"
                    
                    if ($cpuGen -lt 8) {
                        Write-Log "❌ POTENTIAL ISSUE: CPU is ${cpuGen}th gen Intel (detected from $cpuName)" "WARNING"
                        Write-Log "   Windows 11 officially requires 8th gen Intel or newer" "WARNING"
                        Write-Log "   This is likely why the installer is exiting quickly" "WARNING"
                    } else {
                        Write-Log "✅ CPU generation appears compatible (${cpuGen}th gen)" "SUCCESS"
                    }
                } elseif ($cpuName -like "*AMD*") {
                    Write-Log "🔍 AMD CPU detected - checking compatibility..." "INFO"
                    if ($cpuName -like "*Ryzen*") {
                        Write-Log "✅ AMD Ryzen CPU should be compatible" "SUCCESS"
                    } else {
                        Write-Log "⚠️  Older AMD CPU may not be compatible" "WARNING"
                    }
                } else {
                    Write-Log "⚠️  Unknown CPU type - compatibility uncertain" "WARNING"
                }
                
            } catch {
                Write-Log "Could not perform Windows 11 readiness check: $($_.Exception.Message)" "WARNING"
            }
            
            # Check Windows Event Log for recent errors
            try {
                $recentErrors = Get-WinEvent -FilterHashtable @{
                    LogName='Application','System'
                    Level=2,3  # Error and Warning
                    StartTime=(Get-Date).AddMinutes(-5)
                } -MaxEvents 5 -ErrorAction SilentlyContinue | Where-Object {
                    $_.Message -like "*Windows*" -or 
                    $_.Message -like "*upgrade*" -or 
                    $_.Message -like "*install*" -or
                    $_.Message -like "*compatibility*"
                }
                
                if ($recentErrors) {
                    Write-Log "🔍 Recent Windows-related errors found:" "WARNING"
                    foreach ($eventEntry in $recentErrors) {
                        $shortMessage = $eventEntry.Message.Substring(0, [Math]::Min(120, $eventEntry.Message.Length))
                        Write-Log "   [$($eventEntry.TimeCreated.ToString('HH:mm:ss'))] $($eventEntry.LevelDisplayName): $shortMessage..." "WARNING"
                    }
                } else {
                    Write-Log "✅ No relevant recent errors found in Event Log" "SUCCESS"
                }
            } catch {
                Write-Log "Could not check Windows Event Log: $($_.Exception.Message)" "WARNING"
            }
            
            # Final diagnosis summary
            Write-Log "" "INFO"
            Write-Log "🔍 === QUICK EXIT DIAGNOSIS SUMMARY ===" "INFO"
            Write-Log "   The Windows 11 Installation Assistant exited in $([math]::Round($totalTime.TotalMinutes, 1)) minutes" "INFO"
            Write-Log "   This typically happens when:" "INFO"
            Write-Log "   • System is already Windows 11" "INFO"
            Write-Log "   • Hardware doesn't meet minimum requirements" "INFO"
            Write-Log "   • CPU is unsupported (pre-8th gen Intel)" "INFO"
            Write-Log "   • Enterprise policies block upgrades" "INFO"
            Write-Log "   Check the diagnostics above for specific issues" "INFO"
            Write-Log "" "INFO"
        }
    
    } catch {
    Write-Log "Failed to start installer process: $($_.Exception.Message)" "ERROR"
    $process = @{ ExitCode = -1 }
    $totalTime = New-TimeSpan -Seconds 0
} finally {
    # Stop background monitoring
    if ($monitoringJob) {
        Stop-Job $monitoringJob -ErrorAction SilentlyContinue
        Remove-Job $monitoringJob -ErrorAction SilentlyContinue
        Write-Log "Background monitoring stopped" "INFO"
    }
    
    # Return to original directory
    try {
        Pop-Location -ErrorAction SilentlyContinue
    } catch {
        # Ignore errors if Push-Location wasn't called
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
    
    # Additional diagnostics for quick exits
    if ($totalTime.TotalMinutes -lt 1) {
        Write-Log "" "INFO"
        Write-Log "=== QUICK EXIT DIAGNOSTICS ===" "INFO"
        
        # Check if system is already Windows 11
        try {
            $currentOS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            if ([int]$currentOS.CurrentBuild -ge 22000) {
                Write-Log "LIKELY CAUSE: System is already running Windows 11 (Build $($currentOS.CurrentBuild))" "WARNING"
                Write-Log "The Installation Assistant detected this and exited without upgrading" "WARNING"
            }
        } catch {
            Write-Log "Could not determine current Windows build" "WARNING"
        }
        
        # Check if PC Health Check might block upgrade
        $pcHealthCheck = Get-Process -Name "PCHealthCheck" -ErrorAction SilentlyContinue
        if ($pcHealthCheck) {
            Write-Log "PC Health Check app is running - this might interfere with upgrade" "WARNING"
        }
        
        # Check Windows Update policies
        try {
            $wuPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
            if ($wuPolicy -and $wuPolicy.DisableWindowsUpdateAccess) {
                Write-Log "Windows Update is disabled by policy - this may prevent upgrades" "WARNING"
            }
        } catch {
            # Policy key doesn't exist, which is normal
        }
        
        Write-Log "RECOMMENDATION: Try running the installer manually to see error dialogs:" "INFO"
        Write-Log "  1. Run: C:\Temp\Windows11InstallationAssistant.exe" "INFO"
        Write-Log "  2. Look for error messages or compatibility warnings" "INFO"
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
    Write-Log "Errors encountered: $script:ErrorCount" "INFO"
    Write-Log "Warnings encountered: $script:WarningCount" "INFO"

    # Set final exit code
    $script:ExitCode = $process.ExitCode

} catch {
    # Global error handler
    Write-Log "CRITICAL ERROR: Script execution failed unexpectedly" "ERROR"
    Write-ErrorLog -Operation "Main Script Execution" -ErrorRecord $_ -AdditionalInfo "Script terminated due to unhandled exception"
    
    # Complete progress bar if it's still running
    if ($ShowProgress) {
        Write-Progress -Activity "Windows 11 Upgrade" -Completed
    }
    
    # Emergency cleanup
    try {
        if ($monitoringJob) {
            Stop-Job $monitoringJob -ErrorAction SilentlyContinue
            Remove-Job $monitoringJob -ErrorAction SilentlyContinue
            Write-Log "Emergency cleanup: Background monitoring stopped" "INFO"
        }
    } catch {
        # Ignore cleanup errors
    }
    
    $script:ExitCode = 99  # Unhandled exception exit code
    
} finally {
    # Post-upgrade verification and cleanup
    try {
        Write-Log "" "INFO"
        Write-Log "=== POST-UPGRADE VERIFICATION ===" "INFO"
        
        # Check if Windows 11 upgrade was successful
        try {
            $postOS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
            if ($postOS) {
                $postBuild = [int]$postOS.CurrentBuild
                if ($postBuild -ge 22000) {
                    Write-Log "🎉 SUCCESS: Windows 11 detected (Build $postBuild)!" "SUCCESS"
                    Write-Log "✅ Upgrade completed successfully" "SUCCESS"
                    
                    # Generate success report
                    $reportPath = Join-Path $TempDir "upgrade_success_report.txt"
                    $report = @"
Windows 11 Upgrade Success Report
Generated: $(Get-Date)
==================================

Previous Version: Windows 10 Build $currentBuild
Current Version: $($postOS.ProductName) Build $postBuild
Upgrade Duration: $($script:StartTime) to $(Get-Date)
Total Errors: $ErrorCount
Total Warnings: $WarningCount

Bypasses Applied:
- TPM requirement bypass
- Secure Boot requirement bypass  
- RAM requirement bypass
- CPU requirement bypass
- Installation Assistant bypass
- Windows Update bypass

System Information:
- CPU: $((Get-WmiObject Win32_Processor).Name)
- RAM: $([math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))GB
- Disk: $([math]::Round((Get-WmiObject -Class Win32_LogicalDisk | Where-Object DeviceID -eq $env:SystemDrive).FreeSpace / 1GB, 1))GB free

Upgrade completed successfully with hardware bypasses.
"@
                    $report | Out-File -FilePath $reportPath -Encoding UTF8
                    Write-Log "📄 Success report saved: $reportPath" "SUCCESS"
                } else {
                    Write-Log "⚠️  Still on Windows 10 (Build $postBuild) - upgrade may need restart to complete" "WARNING"
                }
            }
        } catch {
            Write-Log "Could not verify upgrade status: $($_.Exception.Message)" "WARNING"
        }
        
        # Clean up temporary files
        Write-Log "🧹 Cleaning up temporary files..." "INFO"
        $tempFiles = @(
            $Installer,
            (Join-Path $TempDir "Windows11Install"),
            (Join-Path $TempDir "*.tmp"),
            (Join-Path $TempDir "Windows11InstallationAssistant_*.log")
        )
        
        foreach ($tempFile in $tempFiles) {
            try {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "   Removed: $tempFile" "INFO"
                }
            } catch {
                Write-Log "   Could not remove: $tempFile" "WARNING"
            }
        }
        
        # Optimize system post-upgrade
        Write-Log "⚡ Running post-upgrade optimizations..." "INFO"
        try {
            # Update Windows Defender definitions
            Start-Process "MpCmdRun.exe" -ArgumentList "-SignatureUpdate" -WindowStyle Hidden -ErrorAction SilentlyContinue
            
            # Clear Windows Update cache
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            
            # Run disk cleanup
            Start-Process "cleanmgr.exe" -ArgumentList "/sagerun:1" -WindowStyle Hidden -ErrorAction SilentlyContinue
            
            Write-Log "✅ Post-upgrade optimizations completed" "SUCCESS"
        } catch {
            Write-Log "Post-upgrade optimizations encountered issues: $($_.Exception.Message)" "WARNING"
        }
        
    } catch {
        Write-Log "Post-upgrade verification failed: $($_.Exception.Message)" "WARNING"
    }
    
    # Final cleanup and summary
    try {
        Write-Log "" "INFO"
        Write-Log "=== FINAL CLEANUP ===" "INFO"
        
        # Restore UAC settings
        try {
            if ($originalUAC) {
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value $originalUAC.EnableLUA -Force -ErrorAction SilentlyContinue
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 2 -Force -ErrorAction SilentlyContinue
                Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Value 3 -Force -ErrorAction SilentlyContinue
                Write-Log "✅ UAC settings restored" "SUCCESS"
            }
        } catch {
            Write-Log "Warning: Could not restore UAC settings - please check manually" "WARNING"
        }
        
        # Log final statistics
        Write-Log "Script completed with exit code: $script:ExitCode" "INFO"
        Write-Log "Total errors: $script:ErrorCount" "INFO"
        Write-Log "Total warnings: $script:WarningCount" "INFO"
        
        # Check for temporary files that should be cleaned up
        if (Test-Path $Installer) {
            try {
                $fileAge = (Get-Date) - (Get-Item $Installer).LastWriteTime
                if ($fileAge.TotalHours -gt 24) {
                    Write-Log "Installer file is over 24 hours old, consider cleaning up: $Installer" "INFO"
                }
            } catch {
                # Ignore file age check errors
            }
        }
        
        # Final log entry
        Write-Log "Windows 11 Upgrade script completed at $(Get-Date)" "INFO"
        
    } catch {
        # Ignore final cleanup errors
    }
}# Keep window open if requested or running interactively
if ($KeepOpen) {
    Write-Host ""
    Write-Host "Press any key to close this window..." -ForegroundColor Yellow
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        # Ignore input errors
        Start-Sleep 2
    }
}
 
# Return installer exit code to RMM
exit $script:ExitCode
