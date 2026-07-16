$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Save-ServerScript([string]$Name, [string]$ApiMethod, [string]$Script) {
    $body = @{
        doctype = "Server Script"
        name = $Name
        script_type = "API"
        api_method = $ApiMethod
        allow_guest = 0
        disabled = 0
        script = $Script
    } | ConvertTo-Json -Depth 6 -Compress
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 10 | Out-Null
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "Updated Server Script: $Name" -ForegroundColor Green
    } catch {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "Created Server Script: $Name" -ForegroundColor Green
    }
}

$apiScript = @'
items = frappe.get_all("Item", fields=["name", "has_batch_no", "has_serial_no", "has_expiry_date"], limit_page_length=0)
changed = 0
for item in items:
    updates = {}
    if item.get("has_batch_no"):
        updates["has_batch_no"] = 0
    if item.get("has_serial_no"):
        updates["has_serial_no"] = 0
    if item.get("has_expiry_date"):
        updates["has_expiry_date"] = 0
    if updates:
        for fieldname, value in updates.items():
            frappe.db.set_value("Item", item.name, fieldname, value, update_modified=False)
        changed += 1
frappe.db.commit()
frappe.response["message"] = {"ok": True, "checked": len(items), "changed": changed}
'@

Save-ServerScript -Name "disable_all_item_batch_serial_for_now" -ApiMethod "disable_all_item_batch_serial_for_now" -Script $apiScript

Write-Host "Disabling batch/serial/expiry flags on all Items..." -ForegroundColor Cyan
$r = Invoke-RestMethod -Uri "$BaseUrl/api/method/disable_all_item_batch_serial_for_now" -Headers $Headers -Method Post -TimeoutSec 120
$r.message | ConvertTo-Json -Compress

Write-Host "Done. No Item should require Serial No, Batch No, or Expiry Date now." -ForegroundColor Green
