# ============================================================================
# WINDOWS 11 UPGRADE SCRIPT - NO HEALTH CHECK VERSION
# ============================================================================
# Ultra-fast Windows 11 upgrade with NO health checks - Maximum speed!
# ============================================================================

param([switch]$NoProgress, [switch]$ForceRestart)

# Configuration
$TempDir = "C:\Temp"
$Installer = Join-Path $TempDir "Windows11InstallationAssistant.exe"
$LogFile = Join-Path $TempDir "upgrade.log"
$DownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2171764"

# Progress tracking
$TotalSteps = 6  # Minimal steps only
$CurrentStep = 0

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

# Force automatic mode
$AutomaticMode = $true
$ForceRestart = $true

Write-Log "⚡ ULTRA-FAST MODE: No health checks, maximum speed!" "INFO"

try {
    # Step 1: Initialize
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Initializing..." -ForegroundColor Cyan
    
    if (-not (Test-Path $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }
    "Windows 11 Upgrade Log - Started $(Get-Date)" | Out-File -FilePath $LogFile -Encoding UTF8
    Write-Log "⚡ Ultra-fast upgrade initialized" "SUCCESS"
    
    # Step 2: Check admin (essential only)
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Checking admin privileges..." -ForegroundColor Cyan
    
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $IsAdmin) {
        Write-Log "❌ Administrator privileges required" "ERROR"
        exit 1
    }
    Write-Log "✅ Running with Administrator privileges" "SUCCESS"
    
    # Step 3: Check Windows version
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Checking Windows version..." -ForegroundColor Cyan
    
    $OS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $currentBuild = [int]$OS.CurrentBuild
    Write-Log "Current Windows: $($OS.ProductName) Build $currentBuild" "INFO"
    
    if ($currentBuild -ge 22000) {
        Write-Log "✅ Already running Windows 11!" "SUCCESS"
        exit 0
    }
    
    # Step 4: Apply registry bypasses (essential)
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Applying hardware bypasses..." -ForegroundColor Cyan
    
    $regItems = @(
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassTPMCheck" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassSecureBootCheck" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassRAMCheck" },
        @{ Path = "HKLM:\SYSTEM\Setup\LabConfig"; Name = "BypassCPUCheck" },
        @{ Path = "HKLM:\SYSTEM\Setup\MoSetup"; Name = "AllowUpgradesWithUnsupportedTPMOrCPU" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"; Name = "AllowUpgradesWithUnsupportedTPMOrCPU" }
    )
    
    foreach ($item in $regItems) {
        try {
            if (-not (Test-Path $item.Path)) {
                New-Item -Path $item.Path -Force | Out-Null
            }
            New-ItemProperty -Path $item.Path -Name $item.Name -Value 1 -PropertyType DWord -Force | Out-Null
        } catch { }
    }
    Write-Log "✅ Applied all hardware bypasses" "SUCCESS"
    
    # Step 5: Download installer
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Downloading Windows 11 Installation Assistant..." -ForegroundColor Cyan
    
    if (Test-Path $Installer) {
        Remove-Item $Installer -Force -ErrorAction SilentlyContinue
    }
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($DownloadUrl, $Installer)
        
        if (Test-Path $Installer) {
            $FileSize = (Get-Item $Installer).Length
            Write-Log "✅ Downloaded successfully! Size: $([math]::Round($FileSize / 1MB, 2)) MB" "SUCCESS"
        } else {
            throw "Download failed"
        }
    } catch {
        Write-Log "❌ Download failed: $($_.Exception.Message)" "ERROR"
        exit 3
    }
    
    # Step 6: Run installer
    $CurrentStep++
    Write-Host "[$CurrentStep/$TotalSteps] Running Windows 11 installer..." -ForegroundColor Cyan
    
    $arguments = "/quietinstall /skipeula /auto upgrade /noreboot"
    Write-Log "🚀 Starting installer: $arguments" "INFO"
    
    try {
        $process = Start-Process -FilePath $Installer -ArgumentList $arguments -PassThru -Wait
        $exitCode = $process.ExitCode
        
        Write-Log "✅ Installer completed with exit code: $exitCode" "SUCCESS"
        
        if ($exitCode -eq 0) {
            Write-Log "🎉 Windows 11 upgrade successful!" "SUCCESS"
        } elseif ($exitCode -eq 3) {
            Write-Log "🔄 Restart required to complete upgrade" "INFO"
            if ($ForceRestart) {
                Write-Log "🔄 Scheduling restart in 60 seconds..." "INFO"
                Start-Process "shutdown.exe" -ArgumentList "/r", "/t", "60" -WindowStyle Hidden
            }
        } else {
            Write-Log "⚠️  Upgrade completed with code: $exitCode" "WARNING"
        }
        
    } catch {
        Write-Log "❌ Installer failed: $($_.Exception.Message)" "ERROR"
        exit 4
    }
    
    Write-Log "🎯 Ultra-fast upgrade process completed!" "SUCCESS"
    
} catch {
    Write-Log "❌ Critical error: $($_.Exception.Message)" "ERROR"
    exit 99
} finally {
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor Yellow
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Start-Sleep 2 }
}