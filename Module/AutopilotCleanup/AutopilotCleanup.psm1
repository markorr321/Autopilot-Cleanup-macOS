#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    PowerShell module for managing device cleanup across Windows Autopilot, Microsoft Intune, and Microsoft Entra ID.

.DESCRIPTION
    This module provides functions to remove devices from Microsoft's endpoint management ecosystem.
    
    Main Functions:
    - Invoke-AutopilotCleanup: Interactive bulk device removal with GUI selection
    - Remove-AutopilotDeviceRecord: Remove a single device by name or serial number
    
.NOTES
    Author: Mark Orr
    Version: 2.1
#>

# Module-level variables
$script:MonitoringMode = $false
$script:NoLoggingMode = $false
$script:WhatIfMode = $false

#region Helper Functions

function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Install-RequiredModules {
    [CmdletBinding()]
    param([string[]]$ModuleNames)
    
    Write-ColorOutput "Checking required PowerShell modules..." "Yellow"
    
    $missingModules = @()
    
    foreach ($moduleName in $ModuleNames) {
        if (Get-Module -ListAvailable -Name $moduleName) {
            Write-ColorOutput "✓ Module '$moduleName' is already installed" "Green"
        } else {
            Write-ColorOutput "✗ Module '$moduleName' is not installed" "Red"
            $missingModules += $moduleName
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-ColorOutput ""
        Write-ColorOutput "The following modules need to be installed:" "Yellow"
        $missingModules | ForEach-Object { Write-ColorOutput "  - $_" "Cyan" }
        Write-ColorOutput ""
        
        $install = Read-Host "Would you like to install missing modules? (Y/N)"
        
        if ($install -eq 'Y' -or $install -eq 'y') {
            foreach ($module in $missingModules) {
                try {
                    Write-ColorOutput "Installing module: $module..." "Yellow"
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
                    Write-ColorOutput "✓ Successfully installed $module" "Green"
                }
                catch {
                    Write-ColorOutput "✗ Failed to install $module : $($_.Exception.Message)" "Red"
                    return $false
                }
            }
            return $true
        }
        else {
            Write-ColorOutput "Cannot proceed without required modules. Exiting." "Red"
            return $false
        }
    }
    
    Write-ColorOutput "All required modules are installed." "Green"
    return $true
}

function Test-GraphConnection {
    [CmdletBinding()]
    param()
    
    try {
        $context = Get-MgContext
        if ($null -eq $context) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

# Browser-based authentication with custom app registration (PKCE flow)
function Connect-MgGraphWithBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,
        
        [Parameter(Mandatory)]
        [string]$TenantId,
        
        [string[]]$Scopes,
        
        [string]$RedirectUri = "http://127.0.0.1:8400/"
    )
    
    try {
        # Build authorization URL with PKCE
        $scopeString = ($Scopes -join " ")
        $state = [guid]::NewGuid().ToString()
        
        # Generate PKCE code verifier and challenge
        $codeVerifier = -join ((65..90) + (97..122) + (48..57) + 45, 46, 95, 126 | Get-Random -Count 64 | ForEach-Object { [char]$_ })
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $codeVerifierBytes = [System.Text.Encoding]::ASCII.GetBytes($codeVerifier)
        $codeVerifierHash = $sha256.ComputeHash($codeVerifierBytes)
        $codeChallenge = [Convert]::ToBase64String($codeVerifierHash) -replace '\+', '-' -replace '/', '_' -replace '=', ''
        
        $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?client_id=$ClientId&response_type=code&redirect_uri=$([uri]::EscapeDataString($RedirectUri))&response_mode=query&scope=$([uri]::EscapeDataString($scopeString))&state=$state&code_challenge=$codeChallenge&code_challenge_method=S256"
        
        # Start HTTP listener to capture auth code automatically
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($RedirectUri)
        $listener.Start()
        
        Write-ColorOutput "Opening browser for authentication..." "Cyan"
        
        # Open browser automatically
        Start-Process $authUrl
        
        Write-ColorOutput "Waiting for authentication response..." "Yellow"
        
        # Wait for the callback
        $code = $null
        $returnedState = $null
        $error_desc = $null
        
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            # Check if this request has a code or error
            $queryParams = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)
            $code = $queryParams["code"]
            $returnedState = $queryParams["state"]
            $error_desc = $queryParams["error_description"]
            
            # Send response to browser
            if ($code -or $error_desc) {
                $responseString = "<html><head><meta charset='UTF-8'><style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#1a1a2e;color:#fff;}</style></head><body><div style='text-align:center;'><h1 style='color:#4ade80;'>Authentication Successful!</h1><p>You can close this window and return to PowerShell.</p></div></body></html>"
            } else {
                $responseString = "<html><body></body></html>"
            }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
            
            # If we got a code or error, stop listening
            if ($code -or $error_desc) {
                $listener.Stop()
                break
            }
        }
        
        if ($error_desc) {
            Write-ColorOutput "Authentication error: $error_desc" "Red"
            return $false
        }
        
        if (-not $code) {
            Write-ColorOutput "No authorization code received" "Red"
            return $false
        }
        
        if ($returnedState -ne $state) {
            Write-ColorOutput "State mismatch - possible security issue" "Red"
            return $false
        }
        
        Write-ColorOutput "Authorization code received, exchanging for token..." "Cyan"
        
        # Exchange code for token with PKCE code verifier
        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $ClientId
            scope         = $scopeString
            code          = $code
            redirect_uri  = $RedirectUri
            grant_type    = "authorization_code"
            code_verifier = $codeVerifier
        }
        
        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        } catch {
            $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($errorDetails) {
                Write-ColorOutput "Token exchange failed: $($errorDetails.error) - $($errorDetails.error_description)" "Red"
            } else {
                Write-ColorOutput "Token exchange failed: $($_.Exception.Message)" "Red"
            }
            return $false
        }
        
        if ($tokenResponse.access_token) {
            $secureToken = ConvertTo-SecureString $tokenResponse.access_token -AsPlainText -Force
            Connect-MgGraph -AccessToken $secureToken -NoWelcome | Out-Null
            Write-ColorOutput "✓ Successfully connected to Microsoft Graph (Custom App)" "Green"
            return $true
        } else {
            Write-ColorOutput "Failed to obtain access token" "Red"
            return $false
        }
    } catch {
        Write-ColorOutput "Authentication error: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Connect-ToGraph {
    [CmdletBinding()]
    param()
    
    Write-ColorOutput "Connecting to Microsoft Graph..." "Yellow"

    $requiredScopes = @(
        "Device.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementManagedDevices.PrivilegedOperations.All",
        "DeviceManagementServiceConfig.ReadWrite.All"
    )

    try {
        # Check for custom app registration via environment variables
        $clientId = $env:AUTOPILOTCLEANUP_CLIENTID
        $tenantId = $env:AUTOPILOTCLEANUP_TENANTID
        
        if ($clientId -and $tenantId) {
            Write-ColorOutput "Using custom app registration (from environment variables)..." "Cyan"
            return Connect-MgGraphWithBrowser -ClientId $clientId -TenantId $tenantId -Scopes $requiredScopes
        }
        
        # Default: Use WAM authentication
        $WarningPreference = 'SilentlyContinue'
        Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop | Out-Null
        $WarningPreference = 'Continue'
        Write-ColorOutput "✓ Successfully connected to Microsoft Graph" "Green"
        return $true
    }
    catch {
        $WarningPreference = 'Continue'
        Write-ColorOutput "✗ Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Get-GraphPagedResults {
    [CmdletBinding()]
    param([string]$Uri)
    
    $allResults = @()
    $currentUri = $Uri
    
    do {
        try {
            $response = Invoke-MgGraphRequest -Uri $currentUri -Method GET
            if ($response.value) {
                $allResults += $response.value
            }
            $currentUri = $response.'@odata.nextLink'
        }
        catch {
            Write-ColorOutput "Error getting paged results: $($_.Exception.Message)" "Red"
            break
        }
    } while ($currentUri)
    
    return $allResults
}

#endregion Helper Functions

#region Device Query Functions

function Get-AutopilotDeviceInternal {
    [CmdletBinding()]
    param(
        [string]$DeviceName,
        [string]$SerialNumber = $null
    )
    
    $AutopilotDevice = $null
    
    if ($SerialNumber) {
        try {
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$SerialNumber')"
            $AutopilotDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
            
            if ($AutopilotDevice) {
                return $AutopilotDevice
            } else {
                if (-not $script:MonitoringMode) {
                    Write-ColorOutput "Device with serial $SerialNumber not found in Autopilot" "Yellow"
                }
            }
        }
        catch {
            Write-ColorOutput "Error searching Autopilot by serial number: $($_.Exception.Message)" "Yellow"
        }
    }
    
    return $AutopilotDevice
}

function Get-IntuneDeviceInternal {
    [CmdletBinding()]
    param(
        [string]$DeviceName,
        [string]$SerialNumber = $null
    )
    
    $IntuneDevice = $null
    
    if ($DeviceName) {
        try {
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=deviceName eq '$DeviceName'"
            $IntuneDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
            
            if ($IntuneDevice) {
                return $IntuneDevice
            }
        }
        catch {
            Write-ColorOutput "Error searching Intune by device name: $($_.Exception.Message)" "Yellow"
        }
    }
    
    if (-not $IntuneDevice -and $SerialNumber) {
        try {
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=serialNumber eq '$SerialNumber'"
            $IntuneDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
        }
        catch {
            Write-ColorOutput "Error searching Intune by serial number: $($_.Exception.Message)" "Yellow"
        }
    }
    
    return $IntuneDevice
}

function Get-EntraDeviceByNameInternal {
    [CmdletBinding()]
    param(
        [string]$DeviceName,
        [string]$SerialNumber = $null,
        [string]$EntraDeviceId = $null
    )

    $AADDevices = @()

    try {
        if ($EntraDeviceId) {
            $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$EntraDeviceId'"
            $AADDevices = (Invoke-MgGraphRequest -Uri $uri -Method GET).value
            if ($AADDevices -and $AADDevices.Count -gt 0) {
                Write-ColorOutput "  Found Entra device by Azure AD Device ID" "Green"
            }
        }

        if ((-not $AADDevices -or $AADDevices.Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($DeviceName)) {
            $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=displayName eq '$DeviceName'"
            $AADDevices = (Invoke-MgGraphRequest -Uri $uri -Method GET).value
        }
        
        if (-not $AADDevices -or $AADDevices.Count -eq 0) {
            if (-not $script:MonitoringMode) {
                Write-ColorOutput "  - Entra ID (not found)" "Yellow"
            }
            return @()
        }
        
        if ($AADDevices.Count -gt 1) {
            Write-ColorOutput "Found $($AADDevices.Count) devices with name '$DeviceName' in Entra ID. Will process all duplicates." "Yellow"
        }
        
        if ($SerialNumber) {
            $validatedDevices = @()
            foreach ($AADDevice in $AADDevices) {
                $deviceSerial = $null
                if ($AADDevice.physicalIds) {
                    foreach ($physicalId in $AADDevice.physicalIds) {
                        if ($physicalId -match '\[SerialNumber\]:(.+)') {
                            $deviceSerial = $matches[1].Trim()
                            break
                        }
                    }
                }
                
                if (-not $deviceSerial -or $deviceSerial -eq $SerialNumber) {
                    $validatedDevices += $AADDevice
                    if ($deviceSerial) {
                        Write-ColorOutput "Validated Entra device: $($AADDevice.displayName) (Serial: $deviceSerial)" "Green"
                    }
                } else {
                    Write-ColorOutput "Skipping Entra ID device with ID $($AADDevice.id) - serial number mismatch (Device: $deviceSerial, Expected: $SerialNumber)" "Yellow"
                }
            }
            return $validatedDevices
        }
        
        return $AADDevices
    }
    catch {
        Write-ColorOutput "Error searching for Entra devices: $($_.Exception.Message)" "Red"
        return @()
    }
}

#endregion Device Query Functions

#region Device Removal Functions

function Remove-AutopilotDeviceInternal {
    [CmdletBinding()]
    param(
        [string]$DeviceName,
        [string]$SerialNumber = $null
    )
    
    $AutopilotDevice = Get-AutopilotDeviceInternal -DeviceName $DeviceName -SerialNumber $SerialNumber
    
    if (-not $AutopilotDevice) {
        Write-ColorOutput "  - Autopilot (not found)" "Yellow"
        return @{ Success = $false; Found = $false; Error = "Device not found" }
    }
    
    try {
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities/$($AutopilotDevice.id)"
        
        if ($script:WhatIfMode) {
            Write-ColorOutput "WHATIF: Would remove Autopilot device: $($AutopilotDevice.displayName) (Serial: $($AutopilotDevice.serialNumber))" "Yellow"
            return @{ Success = $true; Found = $true; Error = $null }
        } else {
            Invoke-MgGraphRequest -Uri $uri -Method DELETE
            Write-ColorOutput "  ✓ Autopilot" "Green"
            return @{ Success = $true; Found = $true; Error = $null }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        if ($errorMsg -like "*BadRequest*" -or $errorMsg -like "*Bad Request*") {
            if ($errorMsg -like "*already*" -or $errorMsg -like "*pending*") {
                Write-ColorOutput "⚠ Device $SerialNumber already queued for deletion from Autopilot" "Yellow"
                return @{ Success = $true; Found = $true; Error = "Already queued for deletion" }
            } else {
                Write-ColorOutput "⚠ Device $SerialNumber cannot be deleted from Autopilot (may already be processing)" "Yellow"
                return @{ Success = $true; Found = $true; Error = "Cannot delete - likely already processing" }
            }
        }
        elseif ($errorMsg -like "*NotFound*" -or $errorMsg -like "*Not Found*") {
            Write-ColorOutput "⚠ Device $SerialNumber no longer exists in Autopilot (already removed)" "Yellow"
            return @{ Success = $true; Found = $true; Error = "Already removed" }
        }
        else {
            Write-ColorOutput "✗ Error removing device $SerialNumber from Autopilot: $errorMsg" "Red"
            return @{ Success = $false; Found = $true; Error = $errorMsg }
        }
    }
}

function Remove-IntuneDeviceInternal {
    [CmdletBinding()]
    param(
        [string]$DeviceName,
        [string]$SerialNumber = $null
    )
    
    $IntuneDevice = Get-IntuneDeviceInternal -DeviceName $DeviceName -SerialNumber $SerialNumber
    
    if (-not $IntuneDevice) {
        Write-ColorOutput "  - Intune (not found)" "Yellow"
        return @{ Success = $false; Found = $false; Error = "Device not found" }
    }
    
    try {
        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($IntuneDevice.id)"
        
        if ($script:WhatIfMode) {
            Write-ColorOutput "WHATIF: Would remove Intune device: $($IntuneDevice.deviceName) (Serial: $($IntuneDevice.serialNumber))" "Yellow"
            return @{ Success = $true; Found = $true; Error = $null }
        } else {
            Invoke-MgGraphRequest -Uri $uri -Method DELETE
            Write-ColorOutput "  ✓ Intune" "Green"
            return @{ Success = $true; Found = $true; Error = $null }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-ColorOutput "✗ Error removing device $DeviceName from Intune: $errorMsg" "Red"
        return @{ Success = $false; Found = $true; Error = $errorMsg }
    }
}

function Remove-EntraDevicesInternal {
    [CmdletBinding()]
    param(
        [array]$Devices,
        [string]$DeviceName,
        [string]$SerialNumber = $null
    )
    
    if (-not $Devices -or $Devices.Count -eq 0) {
        return @{ Success = $false; DeletedCount = 0; FailedCount = 0; Errors = @() }
    }
    
    $deletedCount = 0
    $failedCount = 0
    $allErrors = @()
    
    foreach ($AADDevice in $Devices) {
        $deviceSerial = $null
        if ($AADDevice.physicalIds) {
            foreach ($physicalId in $AADDevice.physicalIds) {
                if ($physicalId -match '\[SerialNumber\]:(.+)') {
                    $deviceSerial = $matches[1].Trim()
                    break
                }
            }
        }
        
        try {
            if ($script:WhatIfMode) {
                Write-ColorOutput "WHATIF: Would remove Entra ID device: $($AADDevice.displayName) (ID: $($AADDevice.id), Serial: $deviceSerial)" "Yellow"
                $deletedCount++
            } else {
                $uri = "https://graph.microsoft.com/v1.0/devices/$($AADDevice.id)"
                Invoke-MgGraphRequest -Uri $uri -Method DELETE
                $deletedCount++
                Write-ColorOutput "  ✓ Entra ID" "Green"
            }
        }
        catch {
            $failedCount++
            $errorMsg = $_.Exception.Message
            $allErrors += $errorMsg
            Write-ColorOutput "✗ Error removing device $DeviceName (ID: $($AADDevice.id)) from Entra ID: $errorMsg" "Red"
        }
    }
    
    $success = $deletedCount -gt 0 -and $failedCount -eq 0
    if ($deletedCount -gt 0 -and $failedCount -gt 0) {
        Write-ColorOutput "Partial success: Deleted $deletedCount device(s), failed to delete $failedCount device(s) from Entra ID." "Yellow"
    }
    
    return @{
        Success = $success
        DeletedCount = $deletedCount
        FailedCount = $failedCount
        Errors = $allErrors
    }
}

function Invoke-IntuneDeviceWipeInternal {
    [CmdletBinding()]
    param(
        [string]$ManagedDeviceId,
        [bool]$KeepEnrollmentData = $false,
        [bool]$KeepUserData = $false
    )
    
    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$ManagedDeviceId/wipe"
    $body = @{}
    if ($KeepEnrollmentData) { $body.keepEnrollmentData = $true }
    if ($KeepUserData) { $body.keepUserData = $true }
    
    try {
        if ($body.Count -gt 0) {
            Invoke-MgGraphRequest -Uri $uri -Method POST -Body ($body | ConvertTo-Json)
        } else {
            Invoke-MgGraphRequest -Uri $uri -Method POST
        }
        return $true
    }
    catch {
        Write-ColorOutput "Error sending wipe command: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Invoke-IntuneDeviceSyncInternal {
    [CmdletBinding()]
    param([string]$ManagedDeviceId)
    
    try {
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$ManagedDeviceId/syncDevice" -Method POST
        return $true
    }
    catch { return $false }
}

function Wait-ForDeviceWipeInternal {
    [CmdletBinding()]
    param(
        [string]$ManagedDeviceId,
        [string]$DeviceName,
        [int]$TimeoutMinutes = 30,
        [int]$PollIntervalSeconds = 30
    )
    
    $timeoutSeconds = $TimeoutMinutes * 60
    $startTime = Get-Date
    
    while ($true) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        if ($elapsed -ge $timeoutSeconds) {
            Write-ColorOutput "✗ TIMEOUT - Wipe did not complete within $TimeoutMinutes minutes" "Red"
            return $false
        }
        
        $device = Get-IntuneDeviceInternal -DeviceName $DeviceName
        $timestamp = Get-Date -Format "HH:mm:ss"
        $elapsedFormatted = [math]::Round($elapsed, 0)
        
        if ($null -eq $device) {
            Write-ColorOutput "[$timestamp] ✓ Device removed from Intune (wipe complete)" "Green"
            return $true
        }
        
        $state = $device.managementState
        switch ($state) {
            "wipePending" { Write-ColorOutput "[$timestamp] IN PROGRESS - Wipe pending ($elapsedFormatted`s)" "Yellow" }
            "retirePending" { Write-ColorOutput "[$timestamp] IN PROGRESS - Retire pending ($elapsedFormatted`s)" "Yellow" }
            default { Write-ColorOutput "[$timestamp] WAITING - State: $state ($elapsedFormatted`s)" "Gray" }
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}

#endregion Device Removal Functions

#region WPF Device Selection Grid

function Show-DeviceSelectionGrid {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Devices,
        [string]$Title = "Select Devices to Remove from All Services"
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $script:deviceList = [System.Collections.ArrayList]::new()
    foreach ($device in $Devices) {
        $null = $script:deviceList.Add([PSCustomObject]@{
            Selected     = $false
            DisplayName  = $device.DisplayName
            SerialNumber = $device.SerialNumber
            Model        = $device.Model
            GroupTag     = $device.GroupTag
            IntuneFound  = $device.IntuneFound
            EntraFound   = $device.EntraFound
            IntuneName   = $device.IntuneName
            EntraName    = $device.EntraName
            Original     = $device
        })
    }

    $script:filteredList = [System.Collections.ArrayList]::new($script:deviceList)

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="700" Width="1200" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBox Name="SearchBox" Grid.Row="0" Margin="0,0,0,10" Padding="5" FontSize="14"/>
        <TextBlock Grid.Row="0" Margin="5,5,0,0" Foreground="Gray" IsHitTestVisible="False" Name="SearchPlaceholder">Search devices...</TextBlock>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
            <Button Name="SelectAllBtn" Content="Select All" Padding="10,5" Margin="0,0,10,0"/>
            <Button Name="ClearAllBtn" Content="Clear All" Padding="10,5" Margin="0,0,10,0"/>
            <TextBlock Name="CountLabel" VerticalAlignment="Center" Foreground="Gray" FontSize="14"/>
        </StackPanel>

        <ListView Name="DeviceList" Grid.Row="2" SelectionMode="Multiple">
            <ListView.View>
                <GridView>
                    <GridViewColumn Width="40">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <CheckBox IsChecked="{Binding Selected, Mode=TwoWay}" Margin="5,0,0,0"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Display Name" Width="200" DisplayMemberBinding="{Binding DisplayName}"/>
                    <GridViewColumn Header="Serial Number" Width="130" DisplayMemberBinding="{Binding SerialNumber}"/>
                    <GridViewColumn Header="Model" Width="180" DisplayMemberBinding="{Binding Model}"/>
                    <GridViewColumn Header="Group Tag" Width="120" DisplayMemberBinding="{Binding GroupTag}"/>
                    <GridViewColumn Header="In Intune" Width="80" DisplayMemberBinding="{Binding IntuneFound}"/>
                    <GridViewColumn Header="In Entra" Width="80" DisplayMemberBinding="{Binding EntraFound}"/>
                    <GridViewColumn Header="Intune Name" Width="150" DisplayMemberBinding="{Binding IntuneName}"/>
                    <GridViewColumn Header="Entra Name" Width="150" DisplayMemberBinding="{Binding EntraName}"/>
                </GridView>
            </ListView.View>
        </ListView>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Name="CancelBtn" Content="Cancel" Padding="20,10" Margin="0,0,10,0"/>
            <Button Name="DeleteBtn" Content="Delete Selected" Padding="20,10" Background="#FF4444" Foreground="White"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $searchBox = $window.FindName("SearchBox")
    $searchPlaceholder = $window.FindName("SearchPlaceholder")
    $selectAllBtn = $window.FindName("SelectAllBtn")
    $clearAllBtn = $window.FindName("ClearAllBtn")
    $countLabel = $window.FindName("CountLabel")
    $deviceListView = $window.FindName("DeviceList")
    $cancelBtn = $window.FindName("CancelBtn")
    $deleteBtn = $window.FindName("DeleteBtn")

    $deviceListView.ItemsSource = $script:filteredList

    $updateCount = {
        $selected = ($script:deviceList | Where-Object { $_.Selected }).Count
        $total = $script:filteredList.Count
        $countLabel.Text = "$selected selected of $total devices"
    }

    & $updateCount

    $searchBox.Add_TextChanged({
        $searchText = $searchBox.Text.ToLower()
        $searchPlaceholder.Visibility = if ($searchText) { "Collapsed" } else { "Visible" }
        
        $script:filteredList.Clear()
        foreach ($device in $script:deviceList) {
            if (-not $searchText -or 
                $device.DisplayName.ToLower().Contains($searchText) -or 
                $device.SerialNumber.ToLower().Contains($searchText) -or
                $device.Model.ToLower().Contains($searchText) -or
                $device.GroupTag.ToLower().Contains($searchText)) {
                $null = $script:filteredList.Add($device)
            }
        }
        $deviceListView.Items.Refresh()
        & $updateCount
    })

    $selectAllBtn.Add_Click({
        foreach ($device in $script:filteredList) {
            $device.Selected = $true
        }
        $deviceListView.Items.Refresh()
        & $updateCount
    })

    $clearAllBtn.Add_Click({
        foreach ($device in $script:deviceList) {
            $device.Selected = $false
        }
        $deviceListView.Items.Refresh()
        & $updateCount
    })

    $deviceListView.Add_MouseLeftButtonUp({
        $deviceListView.Items.Refresh()
        & $updateCount
    })

    $script:selectedDevices = @()
    
    $cancelBtn.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $deleteBtn.Add_Click({
        $script:selectedDevices = $script:deviceList | Where-Object { $_.Selected } | ForEach-Object { $_.Original }
        if ($script:selectedDevices.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Please select at least one device.", "No Selection", "OK", "Warning")
            return
        }
        $window.DialogResult = $true
        $window.Close()
    })

    $result = $window.ShowDialog()
    
    if ($result) {
        return $script:selectedDevices
    }
    return @()
}

#endregion WPF Device Selection Grid

#region Exported Functions

<#
.SYNOPSIS
    Remove a single device from Autopilot, Intune, and Entra ID.

.DESCRIPTION
    Searches for a device by name and/or serial number and removes it from all Microsoft endpoint management services.

.PARAMETER DeviceName
    The display name of the device to remove.

.PARAMETER SerialNumber
    The serial number of the device to remove.

.PARAMETER Wipe
    If specified, sends a wipe command to the device before removing records.

.PARAMETER SkipMonitoring
    If specified, skips the removal status monitoring (fast mode).

.PARAMETER WhatIf
    Preview mode - shows what would be deleted without performing actual deletions.

.NOTES
    To use a custom app registration instead of WAM authentication, set these environment variables:
    - AUTOPILOT_CLIENT_ID: Your Application (Client) ID
    - AUTOPILOT_TENANT_ID: Your Entra ID Tenant ID

.EXAMPLE
    Remove-AutopilotDeviceRecord -SerialNumber "ABC123"

.EXAMPLE
    Remove-AutopilotDeviceRecord -DeviceName "DESKTOP-001" -Wipe

.EXAMPLE
    Remove-AutopilotDeviceRecord -SerialNumber "ABC123" -WhatIf
#>
function Remove-AutopilotDeviceRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [string]$DeviceName,
        
        [Parameter(Mandatory=$false)]
        [string]$SerialNumber,
        
        [Parameter(Mandatory=$false)]
        [switch]$Wipe,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipMonitoring,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    if (-not $DeviceName -and -not $SerialNumber) {
        Write-ColorOutput "You must specify either -DeviceName or -SerialNumber (or both)." "Red"
        return
    }
    
    $script:WhatIfMode = $WhatIf.IsPresent
    $script:NoLoggingMode = $SkipMonitoring.IsPresent
    $script:MonitoringMode = $false
    
    Clear-Host
    Write-ColorOutput "=================================================" "Magenta"
    Write-ColorOutput "    Autopilot Device Cleanup" "Magenta"
    Write-ColorOutput "=================================================" "Magenta"
    
    if ($WhatIf) {
        Write-ColorOutput "Mode: WHATIF (No actual deletions will be performed)" "Yellow"
    }
    Write-ColorOutput ""
    
    # Check modules and connection
    $requiredModules = @('Microsoft.Graph.Authentication')
    if (-not (Install-RequiredModules -ModuleNames $requiredModules)) {
        return
    }
    Write-ColorOutput ""
    
    if (-not (Test-GraphConnection)) {
        if (-not (Connect-ToGraph)) {
            return
        }
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "═══════════════════════════════════════════════════" "Cyan"
    Write-ColorOutput "  Single Device Mode" "Cyan"
    Write-ColorOutput "═══════════════════════════════════════════════════" "Cyan"
    Write-ColorOutput ""
    
    if ($DeviceName) { Write-ColorOutput "  Device Name:   $DeviceName" "White" }
    if ($SerialNumber) { Write-ColorOutput "  Serial Number: $SerialNumber" "White" }
    Write-ColorOutput ""
    
    Write-ColorOutput "Searching for device..." "Yellow"
    $script:MonitoringMode = $true
    
    # Search Autopilot
    $autopilotDevice = $null
    if ($SerialNumber) {
        try {
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$SerialNumber')"
            $autopilotDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
        } catch { }
    }
    if (-not $autopilotDevice -and $DeviceName) {
        try {
            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(displayName,'$DeviceName')"
            $autopilotDevice = (Invoke-MgGraphRequest -Uri $uri -Method GET).value | Select-Object -First 1
        } catch { }
    }
    
    # Search Intune
    $intuneDevice = Get-IntuneDeviceInternal -DeviceName $DeviceName -SerialNumber $SerialNumber
    
    # Search Entra ID
    $entraDevices = Get-EntraDeviceByNameInternal -DeviceName $DeviceName -SerialNumber $SerialNumber
    
    $script:MonitoringMode = $false
    
    # Show results
    Write-ColorOutput ""
    Write-ColorOutput "Search Results:" "Cyan"
    if ($autopilotDevice) {
        Write-ColorOutput "  ✓ Autopilot: $($autopilotDevice.displayName) (Serial: $($autopilotDevice.serialNumber))" "Green"
    } else {
        Write-ColorOutput "  ✗ Autopilot: Not found" "Yellow"
    }
    
    if ($intuneDevice) {
        Write-ColorOutput "  ✓ Intune: $($intuneDevice.deviceName) (Serial: $($intuneDevice.serialNumber))" "Green"
    } else {
        Write-ColorOutput "  ✗ Intune: Not found" "Yellow"
    }
    
    if ($entraDevices -and $entraDevices.Count -gt 0) {
        foreach ($entraDevice in $entraDevices) {
            Write-ColorOutput "  ✓ Entra ID: $($entraDevice.displayName) (ID: $($entraDevice.deviceId))" "Green"
        }
    } else {
        Write-ColorOutput "  ✗ Entra ID: Not found" "Yellow"
    }
    
    if (-not $autopilotDevice -and -not $intuneDevice -and (-not $entraDevices -or $entraDevices.Count -eq 0)) {
        Write-ColorOutput ""
        Write-ColorOutput "Device not found in any service." "Red"
        return
    }
    
    # Confirm
    Write-ColorOutput ""
    if (-not $WhatIf) {
        $actionText = if ($Wipe) { "WIPE and DELETE" } else { "DELETE" }
        $confirm = Read-Host "Do you want to $actionText this device from all services where it was found? (Y/N)"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-ColorOutput "Operation cancelled." "Yellow"
            return
        }
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "Processing deletion..." "Yellow"
    
    $resolvedDeviceName = if ($autopilotDevice) { $autopilotDevice.displayName } 
                          elseif ($intuneDevice) { $intuneDevice.deviceName } 
                          elseif ($entraDevices) { $entraDevices[0].displayName }
                          else { $DeviceName }
    
    $resolvedSerialNumber = if ($autopilotDevice) { $autopilotDevice.serialNumber }
                            elseif ($intuneDevice) { $intuneDevice.serialNumber }
                            else { $SerialNumber }
    
    # Wipe if requested
    if ($Wipe -and $intuneDevice -and -not $WhatIf) {
        Write-ColorOutput "Sending wipe command..." "Yellow"
        $wipeSuccess = Invoke-IntuneDeviceWipeInternal -ManagedDeviceId $intuneDevice.id
        if ($wipeSuccess) {
            Write-ColorOutput "  ✓ Wipe command sent" "Green"
            if (-not $SkipMonitoring) {
                Write-ColorOutput "Waiting for wipe to complete..." "Yellow"
                $null = Wait-ForDeviceWipeInternal -ManagedDeviceId $intuneDevice.id -DeviceName $resolvedDeviceName -TimeoutMinutes 30
            }
        } else {
            Write-ColorOutput "  ✗ Failed to send wipe command" "Red"
        }
    }
    
    # Delete from each service
    $intuneRemovalSuccess = $false
    if ($intuneDevice) {
        $intuneResult = Remove-IntuneDeviceInternal -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
        $intuneRemovalSuccess = $intuneResult.Success
    }
    
    $autopilotRemovalSuccess = $false
    if ($autopilotDevice) {
        $autopilotResult = Remove-AutopilotDeviceInternal -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
        $autopilotRemovalSuccess = $autopilotResult.Success
    }
    
    $entraRemovalSuccess = $false
    if ($entraDevices -and $entraDevices.Count -gt 0) {
        $entraResult = Remove-EntraDevicesInternal -Devices $entraDevices -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
        $entraRemovalSuccess = $entraResult.Success
    }
    
    # Monitor if not skipped
    if (-not $SkipMonitoring -and -not $WhatIf -and ($intuneRemovalSuccess -or $autopilotRemovalSuccess -or $entraRemovalSuccess)) {
        Write-ColorOutput ""
        Write-ColorOutput "Monitoring device removal..." "Cyan"
        
        $startTime = Get-Date
        $maxMonitorMinutes = 30
        $endTime = $startTime.AddMinutes($maxMonitorMinutes)
        $checkInterval = 5
        
        $intuneRemoved = -not $intuneRemovalSuccess
        $autopilotRemoved = -not $autopilotRemovalSuccess
        $entraRemoved = -not $entraRemovalSuccess
        
        $script:MonitoringMode = $true
        
        do {
            Start-Sleep -Seconds $checkInterval
            $currentTime = Get-Date
            $elapsedMinutes = [math]::Round(($currentTime - $startTime).TotalMinutes, 1)
            
            if (-not $intuneRemoved) {
                Write-ColorOutput "Waiting for device to be removed from Intune (Elapsed: $elapsedMinutes min)" "Yellow"
                $intuneCheck = Get-IntuneDeviceInternal -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
                if (-not $intuneCheck) {
                    $intuneRemoved = $true
                    Write-ColorOutput "✓ Device removed from Intune" "Green"
                }
            }
            
            if ($intuneRemoved -and -not $autopilotRemoved) {
                Write-ColorOutput "Waiting for device to be removed from Autopilot (Elapsed: $elapsedMinutes min)" "Yellow"
                $autopilotCheck = Get-AutopilotDeviceInternal -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
                if (-not $autopilotCheck) {
                    $autopilotRemoved = $true
                    Write-ColorOutput "✓ Device removed from Autopilot" "Green"
                }
            }
            
            if ($autopilotRemoved -and $intuneRemoved -and -not $entraRemoved) {
                Write-ColorOutput "Waiting for device to be removed from Entra ID (Elapsed: $elapsedMinutes min)" "Yellow"
                $entraCheck = Get-EntraDeviceByNameInternal -DeviceName $resolvedDeviceName -SerialNumber $resolvedSerialNumber
                if (-not $entraCheck -or $entraCheck.Count -eq 0) {
                    $entraRemoved = $true
                    Write-ColorOutput "✓ Device removed from Entra ID" "Green"
                }
            }
            
            if ($autopilotRemoved -and $intuneRemoved -and $entraRemoved) {
                $elapsedTime = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
                
                Write-ColorOutput ""
                Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
                Write-ColorOutput "  ✓ DEVICE SUCCESSFULLY REMOVED" "Green"
                Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
                Write-ColorOutput "  Name:           $resolvedDeviceName" "White"
                Write-ColorOutput "  Serial Number:  $resolvedSerialNumber" "White"
                Write-ColorOutput "  Elapsed Time:   $elapsedTime minutes" "White"
                Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
                
                try {
                    [System.Console]::Beep(800, 300)
                    [System.Console]::Beep(1000, 300)
                    [System.Console]::Beep(1200, 500)
                } catch { }
                
                break
            }
            
        } while ((Get-Date) -lt $endTime)
        
        $script:MonitoringMode = $false
        
        if ((Get-Date) -ge $endTime) {
            Write-ColorOutput ""
            Write-ColorOutput "⚠ Monitoring timeout reached after $maxMonitorMinutes minutes" "Red"
        }
    } else {
        Write-ColorOutput ""
        Write-ColorOutput "═══════════════════════════════════════════════════" "Green"
        Write-ColorOutput "  Device Deletion Complete" "Green"
        Write-ColorOutput "═══════════════════════════════════════════════════" "Green"
    }
}

<#
.SYNOPSIS
    Interactive bulk device cleanup with GUI selection.

.DESCRIPTION
    Launches the full Autopilot Cleanup interface with device grid selection,
    allowing bulk removal of devices from Autopilot, Intune, and Entra ID.

.PARAMETER WhatIf
    Preview mode - shows what would be deleted without performing actual deletions.

.NOTES
    To use a custom app registration instead of WAM authentication, set these environment variables:
    - AUTOPILOT_CLIENT_ID: Your Application (Client) ID
    - AUTOPILOT_TENANT_ID: Your Entra ID Tenant ID

.EXAMPLE
    Invoke-AutopilotCleanup

.EXAMPLE
    Invoke-AutopilotCleanup -WhatIf
#>
function Invoke-AutopilotCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    $script:WhatIfMode = $WhatIf.IsPresent
    $script:MonitoringMode = $false
    $script:NoLoggingMode = $false
    
    Clear-Host
    Write-ColorOutput "=================================================" "Magenta"
    Write-ColorOutput "    Intune and Autopilot Cleanup PS" "Magenta"
    Write-ColorOutput "=================================================" "Magenta"
    
    if ($WhatIf) {
        Write-ColorOutput "Mode: WHATIF (No actual deletions will be performed)" "Yellow"
    }
    Write-ColorOutput ""
    
    # Check modules
    $requiredModules = @('Microsoft.Graph.Authentication')
    if (-not (Install-RequiredModules -ModuleNames $requiredModules)) {
        return
    }
    Write-ColorOutput ""
    
    # Connect to Graph
    if (-not (Test-GraphConnection)) {
        if (-not (Connect-ToGraph)) {
            return
        }
    }
    
    # Fetch all devices
    Write-ColorOutput "Fetching all Autopilot devices..." "Yellow"
    $autopilotDevices = Get-GraphPagedResults -Uri "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities"
    Write-ColorOutput "Found $($autopilotDevices.Count) Autopilot devices" "Green"
    
    if ($autopilotDevices.Count -eq 0) {
        Write-ColorOutput "No Autopilot devices found." "Red"
        return
    }
    
    Write-ColorOutput "Fetching all Intune devices..." "Yellow"
    $allIntuneDevices = Get-GraphPagedResults -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
    Write-ColorOutput "Found $($allIntuneDevices.Count) Intune devices" "Green"
    
    Write-ColorOutput "Fetching all Entra ID devices..." "Yellow"
    $allEntraDevices = Get-GraphPagedResults -Uri "https://graph.microsoft.com/v1.0/devices"
    Write-ColorOutput "Found $($allEntraDevices.Count) Entra ID devices" "Green"
    
    # Build lookup tables
    $intuneBySerial = @{}
    $intuneByName = @{}
    foreach ($device in $allIntuneDevices) {
        if ($device.serialNumber) { $intuneBySerial[$device.serialNumber] = $device }
        if ($device.deviceName) { $intuneByName[$device.deviceName] = $device }
    }
    
    $entraByName = @{}
    $entraByDeviceId = @{}
    foreach ($device in $allEntraDevices) {
        if ($device.displayName) {
            if (-not $entraByName.ContainsKey($device.displayName)) { $entraByName[$device.displayName] = @() }
            $entraByName[$device.displayName] += $device
        }
        if ($device.deviceId) { $entraByDeviceId[$device.deviceId] = $device }
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "Enriching device information..." "Cyan"
    $enrichedDevices = foreach ($device in $autopilotDevices) {
        $intuneDevice = $null
        if ($device.serialNumber -and $intuneBySerial.ContainsKey($device.serialNumber)) {
            $intuneDevice = $intuneBySerial[$device.serialNumber]
        } elseif ($device.displayName -and $intuneByName.ContainsKey($device.displayName)) {
            $intuneDevice = $intuneByName[$device.displayName]
        }
        
        $entraDevice = $null
        if ($device.azureActiveDirectoryDeviceId -and $entraByDeviceId.ContainsKey($device.azureActiveDirectoryDeviceId)) {
            $entraDevice = $entraByDeviceId[$device.azureActiveDirectoryDeviceId]
        } elseif ($device.displayName -and $entraByName.ContainsKey($device.displayName)) {
            $entraDevice = $entraByName[$device.displayName] | Select-Object -First 1
        }
        
        $displayName = if ($device.displayName -and $device.displayName -ne "") { $device.displayName } 
                       elseif ($intuneDevice -and $intuneDevice.deviceName) { $intuneDevice.deviceName } 
                       elseif ($entraDevice -and $entraDevice.displayName) { $entraDevice.displayName } 
                       elseif ($device.serialNumber) { "Device-$($device.serialNumber)" } 
                       else { "Unknown-$($device.id.Substring(0,8))" }
        
        [PSCustomObject]@{
            AutopilotId = $device.id
            DisplayName = $displayName
            SerialNumber = $device.serialNumber
            Model = $device.model
            Manufacturer = $device.manufacturer
            GroupTag = if ($device.groupTag) { $device.groupTag } else { "None" }
            IntuneFound = if ($intuneDevice) { "Yes" } else { "No" }
            IntuneId = if ($intuneDevice) { $intuneDevice.id } else { $null }
            IntuneName = if ($intuneDevice) { $intuneDevice.deviceName } else { "N/A" }
            EntraFound = if ($entraDevice) { "Yes" } else { "No" }
            EntraId = if ($entraDevice) { $entraDevice.id } else { $null }
            EntraDeviceId = if ($entraDevice -and $entraDevice.deviceId) { $entraDevice.deviceId } elseif ($device.azureActiveDirectoryDeviceId) { $device.azureActiveDirectoryDeviceId } else { $null }
            EntraName = if ($entraDevice) { $entraDevice.displayName } else { "N/A" }
            _AutopilotDevice = $device
            _IntuneDevice = $intuneDevice
            _EntraDevice = $entraDevice
        }
    }
    
    # Show selection grid
    Write-ColorOutput "Opening device selection window..." "Cyan"
    $selectedDevices = Show-DeviceSelectionGrid -Devices $enrichedDevices
    
    if (-not $selectedDevices -or $selectedDevices.Count -eq 0) {
        Write-ColorOutput "No devices selected." "Yellow"
        return
    }
    
    # Show action menu
    $validChoice = $false
    $performWipe = $false
    while (-not $validChoice) {
        Write-ColorOutput ""
        Write-ColorOutput "═══════════════════════════════════════════════════" "Magenta"
        Write-ColorOutput "  Selected $($selectedDevices.Count) device(s)" "Cyan"
        Write-ColorOutput "═══════════════════════════════════════════════════" "Magenta"
        Write-ColorOutput ""
        Write-ColorOutput "What action do you want to perform?" "Cyan"
        Write-ColorOutput ""
        Write-ColorOutput "  STANDARD (monitors removal status):" "White"
        Write-ColorOutput "  [1] Remove records only" "White"
        Write-ColorOutput "  [2] WIPE device(s) + remove all records" "Red"
        Write-ColorOutput ""
        Write-ColorOutput "  FAST (skips status checks, exports CSV):" "Green"
        Write-ColorOutput "  [3] Remove records only" "Green"
        Write-ColorOutput "  [4] WIPE device(s) + remove all records" "Red"
        Write-ColorOutput ""
        Write-ColorOutput "  [5] Cancel" "Gray"
        Write-ColorOutput ""
        
        $actionChoice = Read-Host "Enter your choice (1-5)"
        
        switch ($actionChoice) {
            "1" { $performWipe = $false; $validChoice = $true; Write-ColorOutput "`nMode: Remove records only" "Cyan" }
            "2" {
                $performWipe = $true; $validChoice = $true
                Write-ColorOutput "`nMode: WIPE and remove records" "Yellow"
                Write-ColorOutput "`n⚠️  WARNING: This will FACTORY RESET the selected device(s)!" "Red"
                $wipeConfirm = Read-Host "Type 'WIPE' to confirm"
                if ($wipeConfirm -ne 'WIPE') { Write-ColorOutput "Wipe cancelled." "Yellow"; return }
            }
            "3" { $performWipe = $false; $script:NoLoggingMode = $true; $validChoice = $true; Write-ColorOutput "`nMode: Remove records only - SKIP STATUS CHECKS" "Cyan" }
            "4" {
                $performWipe = $true; $script:NoLoggingMode = $true; $validChoice = $true
                Write-ColorOutput "`nMode: WIPE and remove records - SKIP STATUS CHECKS" "Yellow"
                Write-ColorOutput "`n⚠️  WARNING: This will FACTORY RESET the selected device(s)!" "Red"
                $wipeConfirm = Read-Host "Type 'WIPE' to confirm"
                if ($wipeConfirm -ne 'WIPE') { Write-ColorOutput "Wipe cancelled." "Yellow"; return }
            }
            "5" { Write-ColorOutput "Cancelled." "Yellow"; return }
            default { Write-ColorOutput "Invalid choice. Please try again." "Red" }
        }
    }
    
    # Process devices
    $results = @()
    foreach ($selectedDevice in $selectedDevices) {
        $fullDevice = $enrichedDevices | Where-Object { $_.SerialNumber -eq $selectedDevice.SerialNumber }
        $deviceName = $fullDevice.DisplayName
        $serialNumber = $fullDevice.SerialNumber
        
        Write-ColorOutput ""
        Write-ColorOutput "════════════════════════════════════════════════════════════" "Cyan"
        Write-ColorOutput "Processing: $deviceName (Serial: $serialNumber)" "Cyan"
        Write-ColorOutput "════════════════════════════════════════════════════════════" "Cyan"
        
        # Wipe if requested
        if ($performWipe -and -not $WhatIf) {
            $intuneDevice = Get-IntuneDeviceInternal -DeviceName $deviceName -SerialNumber $serialNumber
            if ($intuneDevice) {
                Write-ColorOutput "`nSending wipe command..." "Yellow"
                $wipeResult = Invoke-IntuneDeviceWipeInternal -ManagedDeviceId $intuneDevice.id
                if ($wipeResult) {
                    Write-ColorOutput "✓ Wipe command sent" "Green"
                    if (-not $script:NoLoggingMode) {
                        Invoke-IntuneDeviceSyncInternal -ManagedDeviceId $intuneDevice.id | Out-Null
                        $null = Wait-ForDeviceWipeInternal -ManagedDeviceId $intuneDevice.id -DeviceName $deviceName -TimeoutMinutes 30
                    }
                }
            }
        }
        
        # Remove from services
        Write-ColorOutput "Removing records..." "Cyan"
        $null = Remove-IntuneDeviceInternal -DeviceName $deviceName -SerialNumber $serialNumber
        $null = Remove-AutopilotDeviceInternal -DeviceName $deviceName -SerialNumber $serialNumber
        
        $entraDeviceId = $fullDevice.EntraDeviceId
        $entraDevices = Get-EntraDeviceByNameInternal -DeviceName $deviceName -SerialNumber $serialNumber -EntraDeviceId $entraDeviceId
        if ($entraDevices -and $entraDevices.Count -gt 0) {
            $null = Remove-EntraDevicesInternal -Devices $entraDevices -DeviceName $deviceName -SerialNumber $serialNumber
        }
        
        $results += [PSCustomObject]@{
            DisplayName = $deviceName
            SerialNumber = $serialNumber
            DeviceId = $entraDeviceId
            Wiped = $performWipe
        }
        
        Write-ColorOutput ""
        Write-ColorOutput "✓ Device processed: $deviceName" "Green"
    }
    
    # Export CSV in fast mode
    if ($script:NoLoggingMode -and $results.Count -gt 0) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path -Path $PWD -ChildPath "DeviceRemoval_$timestamp.csv"
        
        $csvData = foreach ($result in $results) {
            [PSCustomObject]@{
                "Device Display Name" = $result.DisplayName
                "Serial Number" = $result.SerialNumber
                "Device ID" = if ($result.DeviceId) { $result.DeviceId } else { "N/A" }
                "Wipe Sent" = if ($result.Wiped) { "Yes" } else { "No" }
                "Processed Time" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        
        try {
            $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            Write-ColorOutput ""
            Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
            Write-ColorOutput "  CSV EXPORT COMPLETE" "Green"
            Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
            Write-ColorOutput "  File: $csvPath" "White"
            Write-ColorOutput "  Devices: $($results.Count)" "White"
            Write-ColorOutput "════════════════════════════════════════════════════════════" "Green"
        }
        catch {
            Write-ColorOutput "Failed to export CSV: $($_.Exception.Message)" "Red"
        }
    }
    
    Write-ColorOutput ""
    Write-ColorOutput "═══════════════════════════════════════════════════" "Green"
    Write-ColorOutput "  Cleanup Complete - $($results.Count) device(s) processed" "Green"
    Write-ColorOutput "═══════════════════════════════════════════════════" "Green"
}

#endregion Exported Functions

#region Configuration Functions

<#
.SYNOPSIS
    Configure AutopilotCleanup with custom app registration credentials.

.DESCRIPTION
    Interactively prompts for ClientId and TenantId and saves them as user-level
    environment variables. Once configured, the module will automatically use
    these credentials for browser-based PKCE authentication.

.EXAMPLE
    Configure-AutopilotCleanup
#>
function Configure-AutopilotCleanup {
    [CmdletBinding()]
    param()

    Write-Host "`nAutopilotCleanup Configuration" -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "`nThis will configure your custom app registration for AutopilotCleanup."
    Write-Host "These settings will be saved as user-level environment variables.`n"

    # Prompt for ClientId
    $clientId = Read-Host "Enter your App Registration Client ID"
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        Write-Host "ClientId cannot be empty. Configuration cancelled." -ForegroundColor Yellow
        return
    }

    # Prompt for TenantId
    $tenantId = Read-Host "Enter your Tenant ID"
    if ([string]::IsNullOrWhiteSpace($tenantId)) {
        Write-Host "TenantId cannot be empty. Configuration cancelled." -ForegroundColor Yellow
        return
    }

    # Set user-level environment variables
    try {
        [System.Environment]::SetEnvironmentVariable('AUTOPILOTCLEANUP_CLIENTID', $clientId, 'User')
        [System.Environment]::SetEnvironmentVariable('AUTOPILOTCLEANUP_TENANTID', $tenantId, 'User')

        # Also set for current session
        $env:AUTOPILOTCLEANUP_CLIENTID = $clientId
        $env:AUTOPILOTCLEANUP_TENANTID = $tenantId

        Write-Host "`nConfiguration saved successfully!" -ForegroundColor Green
        Write-Host "The module will now use browser-based authentication with your app registration.`n" -ForegroundColor Green
    }
    catch {
        Write-Host "`nFailed to save configuration: $_" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    Clears the saved AutopilotCleanup configuration.

.DESCRIPTION
    Removes the user-level environment variables for ClientId and TenantId.
    After clearing, the module will use the default WAM authentication flow.

.EXAMPLE
    Clear-AutopilotCleanupConfig
#>
function Clear-AutopilotCleanupConfig {
    [CmdletBinding()]
    param()

    try {
        [System.Environment]::SetEnvironmentVariable('AUTOPILOTCLEANUP_CLIENTID', $null, 'User')
        [System.Environment]::SetEnvironmentVariable('AUTOPILOTCLEANUP_TENANTID', $null, 'User')

        # Also clear from current session
        $env:AUTOPILOTCLEANUP_CLIENTID = $null
        $env:AUTOPILOTCLEANUP_TENANTID = $null

        Write-Host "AutopilotCleanup configuration cleared successfully." -ForegroundColor Green
        Write-Host "The module will now use WAM authentication.`n" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to clear configuration: $_" -ForegroundColor Red
    }
}

#endregion Configuration Functions

# Export module members
Export-ModuleMember -Function @(
    'Invoke-AutopilotCleanup',
    'Remove-AutopilotDeviceRecord',
    'Configure-AutopilotCleanup',
    'Clear-AutopilotCleanupConfig'
)
