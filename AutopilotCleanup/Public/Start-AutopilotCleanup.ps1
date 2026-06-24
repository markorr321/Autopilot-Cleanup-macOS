function Start-AutopilotCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(HelpMessage = "Client ID of the app registration to use for delegated auth")]
        [string]$ClientId,

        [Parameter(HelpMessage = "Tenant ID to use with the specified app registration")]
        [string]$TenantId,

        [Parameter(HelpMessage = "One or more serial numbers to target for removal. Bypasses the interactive selector.")]
        [string[]]$SerialNumber
    )

    $invokeParams = @{}
    if ($PSBoundParameters.ContainsKey('ClientId')) { $invokeParams['ClientId'] = $ClientId }
    if ($PSBoundParameters.ContainsKey('TenantId')) { $invokeParams['TenantId'] = $TenantId }
    if ($PSBoundParameters.ContainsKey('SerialNumber')) { $invokeParams['SerialNumber'] = $SerialNumber }
    if ($WhatIfPreference) { $invokeParams['WhatIf'] = $true }

    Invoke-AutopilotCleanup @invokeParams
}
