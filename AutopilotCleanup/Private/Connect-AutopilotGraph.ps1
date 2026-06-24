function Connect-AutopilotGraph {
    Write-ColorOutput "Connecting to Microsoft Graph..." "Yellow"

    $requiredScopes = @(
        "Device.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "DeviceManagementManagedDevices.PrivilegedOperations.All",
        "DeviceManagementServiceConfig.ReadWrite.All"
    )

    try {
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # ignore stale context cleanup errors
        }

        if (-not $script:AutopilotCleanupMSALAssemblyPaths) {
            $script:AutopilotCleanupMSALAssemblyPaths = @{}
        }
        if (-not $script:AutopilotCleanupMSALHelperCompiled) {
            $script:AutopilotCleanupMSALHelperCompiled = $false
        }

        if (-not (Initialize-AutopilotCleanupMSALAssemblies)) {
            throw "Could not initialize browser authentication dependencies."
        }
        $null = Initialize-AutopilotCleanupMSALHelper

        if (-not [string]::IsNullOrWhiteSpace($script:CustomClientId)) {
            Write-ColorOutput "Using custom app registration..." "Cyan"
            Write-ColorOutput "  Client ID: $($script:CustomClientId)" "Gray"
            if (-not [string]::IsNullOrWhiteSpace($script:CustomTenantId)) {
                Write-ColorOutput "  Tenant ID: $($script:CustomTenantId)" "Gray"
            }
        } else {
            Write-ColorOutput "Using default Microsoft Graph authentication..." "Cyan"
        }

        Write-ColorOutput "Opening browser for authentication..." "Cyan"
        Write-ColorOutput "Waiting for authentication response..." "Yellow"

        $accessToken = Get-AutopilotCleanupBrowserAccessToken -Scopes $requiredScopes
        if (-not $accessToken) {
            throw "Failed to acquire browser access token."
        }

        Write-ColorOutput "Authentication successful, connecting to Graph..." "Cyan"
        $secureToken = ConvertTo-SecureString $accessToken -AsPlainText -Force
        Connect-MgGraph -AccessToken $secureToken -NoWelcome -ErrorAction Stop | Out-Null

        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-ColorOutput "✓ Successfully connected to Microsoft Graph" "Green"
            return $true
        } else {
            Write-ColorOutput "✗ Connection failed" "Red"
            return $false
        }
    }
    catch {
        Write-ColorOutput "✗ Failed to connect to Microsoft Graph: $($_.Exception.Message)" "Red"
        return $false
    }
}
