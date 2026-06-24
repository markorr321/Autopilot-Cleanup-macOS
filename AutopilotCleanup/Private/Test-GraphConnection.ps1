function Test-GraphConnection {
    param(
        [string]$ExpectedTenantId,
        [string]$ExpectedClientId,
        [string[]]$RequiredScopes
    )

    try {
        $context = Get-MgContext
        if ($null -eq $context) {
            return $false
        }

        $tenantProperty = $context.PSObject.Properties['TenantId']
        $clientProperty = $context.PSObject.Properties['ClientId']
        $scopesProperty = $context.PSObject.Properties['Scopes']

        if (-not [string]::IsNullOrWhiteSpace($ExpectedTenantId)) {
            $currentTenantId = if ($tenantProperty) { [string]$tenantProperty.Value } else { $null }
            if ([string]::IsNullOrWhiteSpace($currentTenantId) -or $currentTenantId -ne $ExpectedTenantId) {
                return $false
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($ExpectedClientId)) {
            $currentClientId = if ($clientProperty) { [string]$clientProperty.Value } else { $null }
            if ([string]::IsNullOrWhiteSpace($currentClientId) -or $currentClientId -ne $ExpectedClientId) {
                return $false
            }
        }

        if ($RequiredScopes -and $RequiredScopes.Count -gt 0) {
            if (-not $scopesProperty -or $null -eq $scopesProperty.Value) {
                return $false
            }

            $currentScopes = @($scopesProperty.Value)
            foreach ($requiredScope in $RequiredScopes) {
                if ($requiredScope -notin $currentScopes) {
                    return $false
                }
            }
        }

        return $true
    }
    catch {
        return $false
    }
}
