function Get-AutopilotCleanupBrowserAccessToken {
    param(
        [string[]]$Scopes
    )

    if (-not $script:AutopilotCleanupMSALHelperCompiled) {
        $null = Initialize-AutopilotCleanupMSALHelper
    }

    $clientId = if ($script:CustomClientId) { $script:CustomClientId } else { '14d82eec-204b-4c2f-b7e8-296a70dab67e' }
    $tenantId = $script:CustomTenantId

    $scopeArray = $Scopes | ForEach-Object {
        if ($_ -notlike 'https://*') {
            "https://graph.microsoft.com/$_"
        } else {
            $_
        }
    }

    return [AutopilotCleanupBrowserAuth]::GetAccessToken($clientId, $scopeArray, $tenantId)
}
