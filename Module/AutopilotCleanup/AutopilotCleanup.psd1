@{
    # Script module or binary module file associated with this manifest
    RootModule = 'AutopilotCleanup.psm1'
    
    # Version number of this module
    ModuleVersion = '2.1.0'
    
    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')
    
    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    
    # Author of this module
    Author = 'Mark Orr'
    
    # Company or vendor of this module
    CompanyName = 'Unknown'
    
    # Copyright statement for this module
    Copyright = '(c) 2026 Mark Orr. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'PowerShell module for managing device cleanup across Windows Autopilot, Microsoft Intune, and Microsoft Entra ID. Provides interactive bulk device removal with GUI selection and single device removal by name or serial number.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @(
        @{ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0'}
    )
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Invoke-AutopilotCleanup',
        'Remove-AutopilotDeviceRecord',
        'Configure-AutopilotCleanup',
        'Clear-AutopilotCleanupConfig'
    )
    
    # Cmdlets to export from this module
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for discoverability in online galleries
            Tags = @('Autopilot', 'Intune', 'EntraID', 'AzureAD', 'DeviceManagement', 'Cleanup', 'Microsoft365', 'MicrosoftGraph')
            
            # A URL to the license for this module
            # LicenseUri = ''
            
            # A URL to the main website for this project
            ProjectUri = 'https://github.com/markorr321/Autopilot-Cleanup'
            
            # A URL to an icon representing this module
            # IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = @'
Version 2.1.0
- Converted to PowerShell module
- Added Remove-AutopilotDeviceRecord for single device removal
- Added Invoke-AutopilotCleanup for bulk removal with GUI
- Support for -Wipe parameter to factory reset devices
- Support for -SkipMonitoring for fast mode
- WhatIf support for preview mode
'@
            
            # Prerelease string of this module
            # Prerelease = ''
            
            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false
            
            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }
    
    # HelpInfo URI of this module
    # HelpInfoURI = ''
}
