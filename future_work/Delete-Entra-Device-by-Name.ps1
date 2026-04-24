<#
.SYNOPSIS
    Deletes Entra ID devices by user with interactive selection.

.DESCRIPTION
    This script prompts for a user name, searches for the user in Entra ID,
    lists all devices registered to that user, and allows you to select 
    individual devices to delete one by one.

.NOTES
    Requires Microsoft.Graph.Authentication module
    Required permissions: Device.ReadWrite.All, User.Read.All
#>

#region Helper Functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Connect-ToGraph {
    Write-ColorOutput "Connecting to Microsoft Graph..." "Yellow"

    $requiredScopes = @(
        "Device.ReadWrite.All",
        "User.Read.All"
    )

    try {
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

function Get-EntraUserByName {
    param(
        [string]$UserName
    )

    try {
        # First try exact match on userPrincipalName (for email searches)
        $uri = "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$UserName'&`$select=id,displayName,userPrincipalName,mail"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        $users = @($response.value)
        
        # If no exact match, try startsWith on displayName and userPrincipalName
        if ($users.Count -eq 0) {
            $uri = "https://graph.microsoft.com/v1.0/users?`$filter=startsWith(displayName,'$UserName') or startsWith(userPrincipalName,'$UserName')&`$select=id,displayName,userPrincipalName,mail"
            $response = Invoke-MgGraphRequest -Uri $uri -Method GET
            $users = @($response.value)
        }

        if (-not $users -or $users.Count -eq 0) {
            Write-ColorOutput "No users found matching '$UserName'" "Yellow"
            return @()
        }

        return $users
    }
    catch {
        Write-ColorOutput "Error searching for users: $($_.Exception.Message)" "Red"
        return @()
    }
}

function Get-UserRegisteredDevices {
    param(
        [string]$UserId
    )

    try {
        $uri = "https://graph.microsoft.com/v1.0/users/$UserId/registeredDevices"
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET
        $devices = $response.value

        # Handle pagination
        while ($response.'@odata.nextLink') {
            $response = Invoke-MgGraphRequest -Uri $response.'@odata.nextLink' -Method GET
            $devices += $response.value
        }

        return $devices
    }
    catch {
        Write-ColorOutput "Error getting user's devices: $($_.Exception.Message)" "Red"
        return @()
    }
}

function Remove-EntraDevice {
    param(
        [object]$Device
    )

    $deviceName = $Device.displayName
    $deviceId = $Device.id
    
    Write-Host "    Calling Graph API to delete device..." -ForegroundColor DarkGray
    
    try {
        $uri = "https://graph.microsoft.com/v1.0/devices/$deviceId"
        Invoke-MgGraphRequest -Uri $uri -Method DELETE -ErrorAction Stop
        Write-Host "    API call successful" -ForegroundColor DarkGreen
        return $true
    }
    catch {
        Write-Host "    API ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Show-DeviceList {
    param(
        [array]$Devices
    )
    
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        $device = $Devices[$i]
        # Extract serial number if available
        $serial = "N/A"
        if ($device.physicalIds) {
            foreach ($physicalId in $device.physicalIds) {
                if ($physicalId -match '\[SerialNumber\]:(.+)') {
                    $serial = $matches[1].Trim()
                    break
                }
            }
        }

        Write-Host "[$($i + 1)] $($device.displayName)"
        Write-Host "    Device ID: $($device.id)"
        Write-Host "    OS: $($device.operatingSystem) $($device.operatingSystemVersion)"
        Write-Host "    Serial: $serial"
        Write-Host "    Trust Type: $($device.trustType)"
        Write-Host ""
    }
}
#endregion

#region Main Script
Write-Host ""
Write-ColorOutput "=== Delete Entra Devices by User ===" "Cyan"
Write-Host ""

# Connect to Graph first
if (-not (Connect-ToGraph)) {
    exit 1
}

# Prompt for user name
Write-Host ""
$UserSearch = Read-Host "Enter user name to search for (display name or UPN)"

if ([string]::IsNullOrWhiteSpace($UserSearch)) {
    Write-ColorOutput "User name cannot be empty. Exiting." "Red"
    exit 1
}

Write-Host ""
Write-ColorOutput "Searching for user: $UserSearch" "Yellow"

# Search for users
$users = Get-EntraUserByName -UserName $UserSearch

if ($users.Count -eq 0) {
    Write-ColorOutput "No users found. Exiting." "Yellow"
    exit 0
}

# If multiple users found, let user select
$selectedUser = $null
$userArray = @()
foreach ($u in $users) {
    if ($u) { $userArray += $u }
}
$users = $userArray

if ($users.Count -eq 0) {
    Write-ColorOutput "No valid users found. Exiting." "Yellow"
    exit 0
}

if ($users.Count -eq 1) {
    $selectedUser = $users[0]
    $userName = if ($selectedUser.displayName) { $selectedUser.displayName } else { "(No display name)" }
    $userUpn = if ($selectedUser.userPrincipalName) { $selectedUser.userPrincipalName } elseif ($selectedUser.mail) { $selectedUser.mail } else { $selectedUser.id }
    Write-ColorOutput "Found user: $userName ($userUpn)" "Green"
}
else {
    Write-Host ""
    Write-ColorOutput "Found $($users.Count) user(s):" "Cyan"
    Write-Host ""
    $index = 1
    foreach ($user in $users) {
        $userName = if ($user.displayName) { $user.displayName } else { "(No display name)" }
        $userUpn = if ($user.userPrincipalName) { $user.userPrincipalName } elseif ($user.mail) { $user.mail } else { $user.id }
        Write-Host "[$index] $userName - $userUpn"
        $index++
    }
    Write-Host ""
    $userChoice = Read-Host "Select user number (1-$($users.Count))"
    
    if ($userChoice -match '^\d+$' -and [int]$userChoice -ge 1 -and [int]$userChoice -le $users.Count) {
        $selectedUser = $users[[int]$userChoice - 1]
    }
    else {
        Write-ColorOutput "Invalid selection. Exiting." "Red"
        exit 1
    }
}

# Get user's registered devices
Write-Host ""
$userName = if ($selectedUser.displayName) { $selectedUser.displayName } else { $selectedUser.userPrincipalName }
Write-ColorOutput "Getting devices for: $userName" "Yellow"

$devices = Get-UserRegisteredDevices -UserId $selectedUser.id

if (-not $devices -or $devices.Count -eq 0) {
    Write-ColorOutput "No devices found for this user." "Yellow"
    exit 0
}

# Convert to array for indexing
$deviceList = @($devices)

# Display found devices
Write-Host ""
Write-ColorOutput "Found $($deviceList.Count) device(s) for $($selectedUser.displayName):" "Cyan"
Write-Host ""

Show-DeviceList -Devices $deviceList

# Selection menu
Write-ColorOutput "=== Selection Options ===" "Cyan"
Write-Host "Enter device number(s) to delete:"
Write-Host "  - Single device: Enter number (e.g., '1')"
Write-Host "  - Multiple devices: Comma-separated (e.g., '1,3,5')"
Write-Host "  - Range: Use dash (e.g., '1-5')"
Write-Host "  - All devices: Enter 'all'"
Write-Host "  - Exit: Enter 'q' or 'quit'"
Write-Host ""

while ($true) {
    $selection = Read-Host "Select device(s) to delete"
    
    if ($selection -eq 'q' -or $selection -eq 'quit' -or $selection -eq '') {
        Write-ColorOutput "Exiting selection mode." "Yellow"
        break
    }
    
    $indicesToDelete = @()
    
    if ($selection -eq 'all') {
        $confirmAll = Read-Host "Are you sure you want to delete ALL $($deviceList.Count) devices? (Y/N)"
        if ($confirmAll -eq 'Y' -or $confirmAll -eq 'y') {
            $indicesToDelete = 0..($deviceList.Count - 1)
        }
        else {
            Write-ColorOutput "Cancelled. Select individual devices or 'q' to quit." "Yellow"
            continue
        }
    }
    else {
        # Parse selection (supports: 1, 1-5, 1,3,5, or combinations like 1-3,5,7-9)
        $parts = $selection -split ','
        foreach ($part in $parts) {
            $part = $part.Trim()
            if ($part -match '^(\d+)-(\d+)$') {
                # Range: 1-5
                $start = [int]$matches[1]
                $end = [int]$matches[2]
                for ($i = $start; $i -le $end; $i++) {
                    if ($i -ge 1 -and $i -le $deviceList.Count) {
                        $indicesToDelete += ($i - 1)
                    }
                }
            }
            elseif ($part -match '^\d+$') {
                # Single number
                $num = [int]$part
                if ($num -ge 1 -and $num -le $deviceList.Count) {
                    $indicesToDelete += ($num - 1)
                }
            }
        }
        $indicesToDelete = $indicesToDelete | Select-Object -Unique | Sort-Object
    }
    
    if ($indicesToDelete.Count -eq 0) {
        Write-ColorOutput "Invalid selection. Please enter valid device number(s)." "Yellow"
        continue
    }
    
    # Show selected devices and confirm
    Write-Host ""
    Write-ColorOutput "You selected $($indicesToDelete.Count) device(s) to delete:" "Yellow"
    foreach ($idx in $indicesToDelete) {
        Write-Host "  - $($deviceList[$idx].displayName)"
    }
    Write-Host ""
    
    $confirm = Read-Host "Confirm deletion? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-ColorOutput "Skipped. Select more devices or 'q' to quit." "Yellow"
        continue
    }
    
    # Delete selected devices
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host "         STARTING DEVICE DELETION          " -ForegroundColor Yellow  
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($idx in $indicesToDelete) {
        $device = $deviceList[$idx]
        $deviceName = $device.displayName
        $deviceId = $device.id
        
        Write-Host ">>> Processing: $deviceName" -ForegroundColor White
        
        $result = Remove-EntraDevice -Device $device
        
        if ($result -eq $true) {
            Write-Host "    [SUCCESS] $deviceName has been DELETED" -ForegroundColor Green
        }
        else {
            Write-Host "    [FAILED] $deviceName could not be deleted" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "            DELETION COMPLETE              " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter to continue"
    
    # Remove deleted devices from list
    $remainingDevices = @()
    for ($i = 0; $i -lt $deviceList.Count; $i++) {
        if ($i -notin $indicesToDelete) {
            $remainingDevices += $deviceList[$i]
        }
    }
    $deviceList = $remainingDevices
    
    if ($deviceList.Count -eq 0) {
        Write-ColorOutput "All devices have been processed." "Green"
        break
    }
    
    # Show remaining devices
    Write-Host ""
    Write-ColorOutput "Remaining $($deviceList.Count) device(s):" "Cyan"
    Write-Host ""
    Show-DeviceList -Devices $deviceList
}

# Done
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "               COMPLETE                " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Disconnect from Graph
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-ColorOutput "Disconnected from Microsoft Graph" "Yellow"
#endregion
