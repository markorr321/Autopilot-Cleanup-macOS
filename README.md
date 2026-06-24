# Autopilot Cleanup macOS

PowerShell tool for removing devices from Windows Autopilot, Microsoft Intune, and Microsoft Entra ID from a macOS-friendly workflow.

This macOS port replaces the original Windows-only selection experience with a cross-platform GliderUI selector and switches sign-in to browser-based Microsoft Graph authentication with account selection.

## What Changed for macOS

- Browser-based Microsoft Graph sign-in
- Cross-platform GliderUI device selector
- PowerShell 7.4+ support on macOS
- Serial-number targeting from the terminal
- Optional custom app registration support

## Requirements

- macOS
- PowerShell 7.4 or later
- Microsoft Graph permissions:
  - `Device.ReadWrite.All`
  - `DeviceManagementManagedDevices.ReadWrite.All`
  - `DeviceManagementServiceConfig.ReadWrite.All`

The tool will prompt to install missing modules when needed:

- `Microsoft.Graph.Authentication`
- `GliderUI`

## Install

```powershell
git clone https://github.com/markorr321/Autopilot-Cleanup-macOS.git
cd "/Users/maorr/projects/irod/Autopilot-Cleanup"
Import-Module ./AutopilotCleanup/AutopilotCleanup.psd1 -Force
```

## Run

Default launch:

```powershell
Start-AutopilotCleanup
```

Direct script launch:

```powershell
pwsh ./Autopilot-Cleanup.ps1
```

## Single Device

Remove or target one device by serial number:

```powershell
Start-AutopilotCleanup -SerialNumber "YOUR-SERIAL-NUMBER"
```

Dry run:

```powershell
Start-AutopilotCleanup -SerialNumber "YOUR-SERIAL-NUMBER" -WhatIf
```

## Interactive Flow

1. Open the tool
2. Sign in through your system browser
3. Wait for device data to load
4. Select devices in the GliderUI window
5. Confirm cleanup
6. Monitor removal progress in PowerShell

## Custom App Registration

Use the default browser account picker:

```powershell
Start-AutopilotCleanup
```

Or use your own app registration:

```powershell
Start-AutopilotCleanup -ClientId "YOUR-APP-ID" -TenantId "YOUR-TENANT-ID"
```

To save custom values for future sessions:

```powershell
Configure-AutopilotCleanup
```

To go back to default browser auth:

```powershell
Clear-AutopilotCleanupConfig
```

## Notes

- Cleanup is permanent
- Deletion order is handled automatically
- The macOS port is focused on the modern interactive module workflow
- If browser sign-in feels stuck, run `Disconnect-MgGraph` and start again

## Main Files

- [Autopilot-Cleanup.ps1](/Users/maorr/projects/irod/Autopilot-Cleanup/Autopilot-Cleanup.ps1)
- [AutopilotCleanup.psd1](/Users/maorr/projects/irod/Autopilot-Cleanup/AutopilotCleanup/AutopilotCleanup.psd1)
- [Start-AutopilotCleanup.ps1](/Users/maorr/projects/irod/Autopilot-Cleanup/AutopilotCleanup/Public/Start-AutopilotCleanup.ps1)
- [Show-DeviceSelectionGrid.ps1](/Users/maorr/projects/irod/Autopilot-Cleanup/AutopilotCleanup/Private/Show-DeviceSelectionGrid.ps1)
