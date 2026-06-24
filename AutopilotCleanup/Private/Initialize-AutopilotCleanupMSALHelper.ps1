function Initialize-AutopilotCleanupMSALHelper {
    if ($script:AutopilotCleanupMSALHelperCompiled) {
        return $true
    }

    $referencedAssemblies = @(
        $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.IdentityModel.Abstractions'],
        $script:AutopilotCleanupMSALAssemblyPaths['Microsoft.Identity.Client']
    ) | Where-Object { $_ }

    if ($referencedAssemblies.Count -lt 1) {
        throw "Missing required MSAL assemblies."
    }

    $referencedAssemblies += @('netstandard', 'System.Linq', 'System.Threading.Tasks', 'System.Collections')

    $code = @"
using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Identity.Client;

public class AutopilotCleanupBrowserAuth
{
    public static string GetAccessToken(string clientId, string[] scopes, string tenantId = null)
    {
        try
        {
            var task = Task.Run(async () => await GetAccessTokenAsync(clientId, scopes, tenantId));
            if (task.Wait(TimeSpan.FromSeconds(180)))
            {
                return task.Result;
            }
            throw new TimeoutException("Authentication timed out");
        }
        catch (AggregateException ae)
        {
            if (ae.InnerException != null) throw ae.InnerException;
            throw;
        }
    }

    private static async Task<string> GetAccessTokenAsync(string clientId, string[] scopes, string tenantId)
    {
        var builder = PublicClientApplicationBuilder.Create(clientId)
            .WithRedirectUri("http://localhost");

        if (!string.IsNullOrEmpty(tenantId))
        {
            builder = builder.WithAuthority($"https://login.microsoftonline.com/{tenantId}");
        }

        IPublicClientApplication publicClientApp = builder.Build();

        using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(180)))
        {
            var webViewOptions = new SystemWebViewOptions
            {
                HtmlMessageSuccess = @"
<html>
<head>
    <meta charset='UTF-8'>
    <title>Authentication Successful - Autopilot Cleanup</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #0f766e 0%, #0369a1 100%); }
        .container { text-align: center; color: white; }
        .brand { font-size: 14px; letter-spacing: 4px; margin-bottom: 30px; opacity: 0.9; }
        .checkmark { font-size: 64px; margin-bottom: 20px; }
        h1 { margin: 0 0 10px 0; font-weight: 300; font-size: 28px; }
        p { margin: 0; opacity: 0.9; font-size: 16px; }
    </style>
</head>
<body>
    <div class='container'>
        <div class='brand'>[ A U T O P I L O T &nbsp; C L E A N U P ]</div>
        <div class='checkmark'>&#10003;</div>
        <h1>Authentication Successful</h1>
        <p>You can close this window and return to PowerShell.</p>
    </div>
</body>
</html>",
                HtmlMessageError = @"
<html>
<head>
    <meta charset='UTF-8'>
    <title>Authentication Failed - Autopilot Cleanup</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: linear-gradient(135deg, #dc2626 0%, #991b1b 100%); }
        .container { text-align: center; color: white; }
        .brand { font-size: 14px; letter-spacing: 4px; margin-bottom: 30px; opacity: 0.9; }
        .icon { font-size: 64px; margin-bottom: 20px; }
        h1 { margin: 0 0 10px 0; font-weight: 300; font-size: 28px; }
        p { margin: 0; opacity: 0.9; font-size: 16px; }
    </style>
</head>
<body>
    <div class='container'>
        <div class='brand'>[ A U T O P I L O T &nbsp; C L E A N U P ]</div>
        <div class='icon'>&#10005;</div>
        <h1>Authentication Failed</h1>
        <p>Please close this window and try again.</p>
    </div>
</body>
</html>"
            };

            var tokenBuilder = publicClientApp.AcquireTokenInteractive(scopes)
                .WithPrompt(Prompt.SelectAccount)
                .WithUseEmbeddedWebView(false)
                .WithSystemWebViewOptions(webViewOptions);

            var result = await tokenBuilder
                .ExecuteAsync(cts.Token)
                .ConfigureAwait(false);

            return result.AccessToken;
        }
    }
}
"@

    try {
        $null = [AutopilotCleanupBrowserAuth]
        $script:AutopilotCleanupMSALHelperCompiled = $true
        return $true
    }
    catch {
        # compile below
    }

    Add-Type -ReferencedAssemblies $referencedAssemblies -TypeDefinition $code -Language CSharp -ErrorAction Stop -IgnoreWarnings 3>$null
    $script:AutopilotCleanupMSALHelperCompiled = $true
    return $true
}
