@{
    RootModule        = 'AutopilotCleanup.psm1'
    ModuleVersion     = '2.4.0'
    GUID              = '2c66f0a3-dcb1-4050-8913-142c0b2991cd'
    Author            = 'Mark Orr'
    CompanyName       = 'Orr365'
    Copyright         = '(c) 2025. All rights reserved.'
    Description       = 'Bulk removal tool for devices from Windows Autopilot, Microsoft Intune, and Microsoft Entra ID. Features a cross-platform GliderUI device selector, browser-based Microsoft Graph authentication, custom app registration support, automatic module installation, serial number validation, real-time deletion monitoring, fast bulk removal with CSV export, direct serial number targeting, parallel API fetching on PowerShell 7+, and WhatIf mode.'
    CompatiblePSEditions = @('Core')
    PowerShellVersion = '7.4'

    # Note: Microsoft.Graph.Authentication and GliderUI are required at runtime but not enforced here
    # to allow the module to load and handle installation interactively via Install-RequiredGraphModule
    RequiredModules   = @()

    FunctionsToExport = @(
        'Clear-AutopilotCleanupConfig'
        'Configure-AutopilotCleanup'
        'Connect-AutopilotGraph'
        'Get-AllAutopilotDevices'
        'Get-AutopilotDevice'
        'Get-EntraDeviceByName'
        'Get-GraphPagedResults'
        'Get-IntuneDevice'
        'Install-RequiredGraphModule'
        'Invoke-AutopilotCleanup'
        'Invoke-IntuneDeviceSync'
        'Invoke-IntuneDeviceWipe'
        'Remove-AutopilotDevice'
        'Remove-EntraDevices'
        'Remove-IntuneDevice'
        'Show-DeviceSelectionGrid'
        'Start-AutopilotCleanup'
        'Test-GraphConnection'
        'Test-IntuneDeviceRemoved'
        'Wait-ForDeviceWipe'
        'Write-ColorOutput'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Autopilot', 'Intune', 'EntraID', 'DeviceManagement', 'Cleanup', 'MicrosoftGraph', 'Windows', 'MacOS', 'Linux', 'Entra', 'DeviceCleanup', 'CrossPlatform', 'GliderUI', 'Avalonia')

            LicenseUri = 'https://github.com/markorr321/Autopilot-Cleanup/blob/main/LICENSE'

            ProjectUri = 'https://github.com/markorr321/Autopilot-Cleanup'

            ReleaseNotes = @'
## 2.4.0
- Switched default Microsoft Graph sign-in to browser-based authentication with account selection
- Browser auth now mirrors Entra-PIM by using MSAL and a system browser redirect instead of reusing cached Graph contexts
- Default auth no longer requires a TenantId; custom TenantId is only used when explicitly configured

## 2.3.0
- Cross-platform GliderUI device selector replaces the Windows-only WPF grid
- GliderUI added as a runtime dependency for interactive selection
- Module minimum PowerShell version updated to 7.4 to match GliderUI
- Start-AutopilotCleanup now has a real exported entry point
- Added -ForceLogin for tenant-aware reauthentication

## 2.2.4
- Minimum PowerShell version updated to 7.0
- README updates: consolidated features list, updated version history and example output

## 2.2.3
- Targeted API queries for -SerialNumber (no longer fetches entire tenant)
- WPF grid performance improvements (UI virtualization, CollectionView filtering, search debounce)

## 2.2.2
- Fix SerialNumber parameter variable collision causing type conversion errors during device removal

## 2.2.1
- Per-service progress bars during parallel fetch (page count and record count per service)
- Terminal indication when WPF device selection window is open
- Shared concurrent progress tracker for real-time thread job monitoring

## 2.2.0
- -SerialNumber parameter for direct device targeting (single or multiple), bypasses the WPF grid
- Parallel API fetching on PowerShell 7+ using thread jobs (Autopilot, Intune, Entra ID fetched concurrently)
- Automatic fallback to sequential fetch if parallel jobs fail
- Progress bars during pagination for large tenant data retrieval

## 2.1.0
- Custom app registration support (Configure-AutopilotCleanup / Clear-AutopilotCleanupConfig)
- Start-AutopilotCleanup module entry point
- Automatic update check from PowerShell Gallery
- Cleaner console UI - replaced heavy box-drawing with minimal section headers

## 2.0.0
- PowerShell module architecture (Public/Private function structure)
- WPF device selection grid with search and multi-select
- Fast bulk removal mode with CSV export
- GroupTag filtering
- Serial number validation
- Real-time deletion monitoring
- WhatIf mode
- Automatic module installation
'@

            Prerelease = ''

            RequireLicenseAcceptance = $false
        }
    }
}
