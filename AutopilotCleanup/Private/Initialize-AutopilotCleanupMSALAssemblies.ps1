function Initialize-AutopilotCleanupMSALAssemblies {
    if (-not $script:AutopilotCleanupMSALAssemblyPaths) {
        $script:AutopilotCleanupMSALAssemblyPaths = @{}
    }

    $graphAuthModule = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $graphAuthModule) {
        Write-Verbose "Microsoft.Graph.Authentication module not found for MSAL assembly loading."
        return $false
    }

    $moduleBase = $graphAuthModule.ModuleBase
    $msalCandidates = @(
        (Join-Path $moduleBase 'Dependencies/Core/Microsoft.Identity.Client.dll'),
        (Join-Path $moduleBase 'Dependencies/Desktop/Microsoft.Identity.Client.dll'),
        (Join-Path $moduleBase 'Dependencies/Microsoft.Identity.Client.dll')
    )
    $abstractionCandidates = @(
        (Join-Path $moduleBase 'Dependencies/Microsoft.IdentityModel.Abstractions.dll'),
        (Join-Path $moduleBase 'Dependencies/Core/Microsoft.IdentityModel.Abstractions.dll'),
        (Join-Path $moduleBase 'Dependencies/Desktop/Microsoft.IdentityModel.Abstractions.dll')
    )

    $msalDll = $msalCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $abstractionsDll = $abstractionCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $msalDll) {
        Write-Verbose "Microsoft.Identity.Client.dll could not be located under Microsoft.Graph.Authentication."
        return $false
    }

    $loadedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies()

    if ($abstractionsDll) {
        $loadedAbstractions = $loadedAssemblies | Where-Object { $_.GetName().Name -eq 'Microsoft.IdentityModel.Abstractions' } | Select-Object -First 1
        if (-not $loadedAbstractions) {
            [void][System.Reflection.Assembly]::LoadFrom($abstractionsDll)
            $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.IdentityModel.Abstractions'] = $abstractionsDll
        } else {
            $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.IdentityModel.Abstractions'] = $loadedAbstractions.Location
        }
    }

    $loadedMsal = $loadedAssemblies | Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } | Select-Object -First 1
    if (-not $loadedMsal) {
        [void][System.Reflection.Assembly]::LoadFrom($msalDll)
        $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.Identity.Client'] = $msalDll
    } else {
        $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.Identity.Client'] = $loadedMsal.Location
    }

    return $true
}
