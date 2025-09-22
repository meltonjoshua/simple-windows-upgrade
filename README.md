# Simple Windows 11 Upgrade Script

A PowerShell script designed for silent deployment of Windows 11 upgrades through Remote Monitoring and Management (RMM) systems.

## Features

- **Silent Operation**: Runs without user interaction
- **Registry Bypass**: Sets registry keys to allow upgrades on unsupported hardware
- **Automatic Download**: Downloads the latest Windows 11 Installation Assistant
- **Logging**: Creates upgrade logs for monitoring and troubleshooting
- **RMM Compatible**: Returns proper exit codes for RMM integration

## Prerequisites

- **Administrative Rights**: Script must be run as Administrator
- **Internet Connection**: Required to download the Installation Assistant
- **Windows 10**: Target system should be running a compatible version of Windows 10

## Usage

### One-Line GitHub Execution

```powershell
iex (iwr -UseBasicParsing "https://raw.githubusercontent.com/meltonjoshua/simple-windows-upgrade/main/Upgrade-Windows11.ps1").Content
```

### Direct Execution

```powershell
.\Upgrade-Windows11.ps1
```

### RMM Deployment

Deploy the script through your RMM system with administrative privileges. The script will:

1. Create necessary temporary directories
2. Set registry keys to bypass hardware compatibility checks
3. Download the Windows 11 Installation Assistant
4. Run the upgrade silently
5. Return exit code to the RMM system

## Script Behavior

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
