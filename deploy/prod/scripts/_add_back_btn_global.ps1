$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$backBtnScript = @"
// Back button: persistent across all pages once loaded
(function() {
    if (window._mobileBackInterval) return;
    function ensureBackBtn() {
        var btn = document.getElementById('mobile-back-btn');
        if (!btn) {
            btn = document.createElement('div');
            btn.id = 'mobile-back-btn';
            btn.textContent = '\u2190';
            btn.style.cssText = 'position:fixed;bottom:20px;left:20px;width:56px;height:56px;border-radius:50%;background:#1976d2;color:#fff;font-size:30px;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:99999;cursor:pointer;user-select:none;-webkit-tap-highlight-color:transparent;';
            btn.addEventListener('click', function() { history.back(); });
            btn.addEventListener('touchstart', function() { this.style.transform = 'scale(0.9)'; });
            btn.addEventListener('touchend', function() { this.style.transform = 'scale(1)'; });
            document.body.appendChild(btn);
        }
        btn.style.display = 'flex';
    }
    window._mobileBackInterval = setInterval(ensureBackBtn, 300);
    ensureBackBtn();
})();
"@

# Create Client Script on Dispatch Case List view
$csName = "Global-Mobile Back Button DC"
Write-Host "Creating Client Script: $csName (Dispatch Case, List)" -ForegroundColor Cyan
$body = @{
    doctype = "Client Script"
    name = $csName
    dt = "Dispatch Case"
    view = "List"
    enabled = 1
    script = $backBtnScript
}
$bodyJson = $body | ConvertTo-Json -Depth 5 -Compress
try {
    # Check if it already exists
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$([uri]::EscapeDataString($csName))" -Headers $Headers -Method Get -TimeoutSec 15 -ErrorAction SilentlyContinue
    # Update
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$([uri]::EscapeDataString($csName))" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
    Write-Host "  -> Updated existing." -ForegroundColor Green
} catch {
    # Create new
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
    Write-Host "  -> Created new." -ForegroundColor Green
}

Write-Host "`nDone. The back button will now load on Task OR Dispatch Case pages." -ForegroundColor Green
Write-Host "Close and reopen the browser to test." -ForegroundColor Yellow
