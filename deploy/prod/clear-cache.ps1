Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

Write-Host "`n=== Clearing ERPNext Cache ===" -ForegroundColor Cyan

try {
    # Clear cache using the correct API
    $uri = "$BaseUrl/api/method/frappe.clear_cache"
    $body = @{} | ConvertTo-Json
    $result = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
    
    Write-Host "SUCCESS: Cache cleared!" -ForegroundColor Green
    Write-Host "`nNow refresh your browser (Ctrl+F5) and try again." -ForegroundColor Yellow
    
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "Error: $errMsg" -ForegroundColor Red
    Write-Host "`nTrying alternative method..." -ForegroundColor Yellow
    
    try {
        # Alternative: reload doctype
        $uri2 = "$BaseUrl/api/method/frappe.desk.form.load.getdoctype"
        $body2 = @{ doctype = "Task"; with_parent = 1 } | ConvertTo-Json
        $result2 = Invoke-RestMethod -Uri $uri2 -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body2)) -TimeoutSec 30
        Write-Host "DocType reloaded. Refresh browser now." -ForegroundColor Green
    } catch {
        Write-Host "Alternative also failed. Please restart ERPNext bench." -ForegroundColor Red
    }
}
