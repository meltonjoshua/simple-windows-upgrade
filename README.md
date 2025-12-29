# Repository Contents

This repository contains two main projects:

1. **Windows 11 Upgrade Scripts** - PowerShell scripts for Windows 11 deployment
2. **GymApp** - Complete iOS fitness tracking application

---

## 📱 GymApp - iOS Fitness Tracker

A complete, production-ready iOS application built with SwiftUI for tracking workouts, exercises, and fitness progress.

### Quick Links
- [GymApp README](GymApp/README.md) - Comprehensive documentation
- [Quick Start Guide](GymApp/QUICK_START.md) - Get started quickly
- [App Overview](GymApp/APP_OVERVIEW.md) - Technical architecture details

### Features
- ✅ Workout tracking with sets, reps, and weights
- ✅ Exercise library with 10+ pre-loaded exercises
- ✅ Statistics and progress tracking
- ✅ User profile management
- ✅ Data persistence with UserDefaults
- ✅ Built with SwiftUI and modern iOS patterns

### Requirements
- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

### Getting Started
```bash
cd GymApp
open GymApp.xcodeproj
# Press Cmd+R in Xcode to build and run
```

---

## 💻 Simple Windows 11 Upgrade Script

A PowerShell script designed for silent deployment of Windows 11 upgrades through Remote Monitoring and Management (RMM) systems.

## Features

- **Silent Operation**: Runs without user interaction
- **Progress Tracking**: Visual progress bar and detailed status messages
- **Registry Bypass**: Sets registry keys to allow upgrades on unsupported hardware
- **Automatic Download**: Downloads the latest Windows 11 Installation Assistant
- **File Verification**: Verifies downloaded installer before execution
- **Logging**: Creates upgrade logs for monitoring and troubleshooting
- **RMM Compatible**: Returns proper exit codes for RMM integration

## Prerequisites

- **Administrative Rights**: Script must be run as Administrator
- **Internet Connection**: Required to download the Installation Assistant
- **Windows 10**: Target system should be running a compatible version of Windows 10

## Usage

### One-Line GitHub Execution

#### Option 1: Variable Method (Recommended)

```powershell
$url = "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11.ps1"; iex (iwr -UseBasicParsing $url).Content
```

#### Option 2: Direct Method

```powershell
iex (iwr -UseBasicParsing "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11.ps1").Content
```

#### Option 3: Short URL (for terminals with line wrapping issues)

```powershell
$u="https://tinyurl.com/win11-upgrade-script"; iex (iwr -UseBasicParsing $u).Content
```

⚠️ **IMPORTANT**: Run PowerShell as Administrator for registry modifications!

### Direct Execution

```powershell
# Basic execution
.\Upgrade-Windows11.ps1

# Keep PowerShell window open to view results
.\Upgrade-Windows11.ps1 -KeepOpen

# Run silently without progress bar (for automation)
.\Upgrade-Windows11.ps1 -ShowProgress:$false
```

### RMM Deployment

Deploy the script through your RMM system with administrative privileges. The script will:

1. **Initialize**: Create necessary temporary directories
2. **Configure Registry**: Set registry keys to bypass hardware compatibility checks
3. **Download**: Download the Windows 11 Installation Assistant with progress tracking
4. **Verify**: Verify the downloaded installer file
5. **Execute**: Run the upgrade silently with detailed status messages
6. **Complete**: Return exit code to the RMM system

### Progress Tracking

The script now includes:

- Visual progress bar showing completion percentage
- Step-by-step status messages
- File verification and size reporting
- Detailed logging of each action
- Clear success/error indicators
- **Auto-pause**: Keeps window open when run interactively
- **Manual control**: Use `-KeepOpen` parameter to force window to stay open

## Script Behavior

### Parameters

- `-KeepOpen`: Forces the PowerShell window to stay open after completion
- `-ShowProgress`: Controls progress bar display (default: `$true`)

### Automatic Detection

The script automatically detects:

- **Interactive sessions**: Keeps window open for manual execution
- **RMM/Automation**: Closes immediately for automated deployment
- **One-liner execution**: Optimized behavior for GitHub one-liner

### Registry Keys Modified

- `HKCU:\SOFTWARE\Microsoft\PCHC\UpgradeEligibility` = 1
- `HKLM:\SOFTWARE\Microsoft\PCHC\UpgradeEligibility` = 1
- `HKLM:\SYSTEM\Setup\MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU` = 1

### Files Created

- `C:\Temp\Windows11InstallationAssistant.exe` - Downloaded installer
- `C:\Temp\upgrade.log` - Installation logs

### Command Line Arguments Used

```cmd
/quietinstall /skipeula /auto upgrade /CopyLogs "C:\Temp\upgrade.log"
```

## Error Handling

- Download failures will return exit code 1
- Installation failures will return the installer's exit code
- All errors are logged for troubleshooting

## Security Considerations

⚠️ **Warning**: This script bypasses Windows 11 hardware compatibility checks. Use with caution and ensure you understand the implications:

- TPM and CPU requirements are bypassed
- Unsupported hardware may experience compatibility issues
- Microsoft support may be limited on unsupported systems

## License

This script is provided as-is for educational and deployment purposes. Use at your own risk.

## Support

For issues or questions:

1. Check the upgrade logs in `C:\Temp\upgrade.log`
2. Verify administrative privileges
3. Ensure internet connectivity
4. Review Windows 11 system requirements
