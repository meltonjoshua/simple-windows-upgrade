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
$TotalSteps = 8
$CurrentStep = 0
$ErrorCount = 0
$WarningCount = 0

# Error handling configuration
$ErrorActionPreference = "Stop"
$script:ExitCode = 0

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
        [bool]$ContinueOnError = $true
    )
    
    try {
        $result = & $ScriptBlock
        if ($SuccessMessage) {
            Write-Log $SuccessMessage "SUCCESS"
        }
        return $result
    }
    catch {
        Write-ErrorLog -Operation $Operation -ErrorRecord $_ -AdditionalInfo $ErrorMessage
        
        if (-not $ContinueOnError) {
            throw
        }
        return $null
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
    $process = Start-Process -FilePath $customInstaller -ArgumentList $argumentString -PassThru -WorkingDirectory $customInstallDir -ErrorAction Stop
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
