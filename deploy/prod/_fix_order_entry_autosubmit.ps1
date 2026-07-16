$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$csName = "Task-before-save-dispatch-gates"
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $csName)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$original = $r.data.script

# Replace the throw with auto-submit
$old = @'
    dc_docstatus = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "docstatus")
    if dc_docstatus != 1:
        frappe.throw("Submit the Dispatch Case before completing the Order entry task.")
'@

$new = @'
    dc_docstatus = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "docstatus")
    if dc_docstatus != 1:
        dc_doc = frappe.get_doc("Dispatch Case", doc.dispatch_case)
        if not dc_doc.items or len(dc_doc.items) == 0:
            frappe.throw("Add at least one product to the Dispatch Case before completing.")
        dc_doc.submit()
'@

if (-not $original.Contains($old)) {
    Write-Host "Exact pattern not found. Trying alternate match..." -ForegroundColor Yellow
    # Try with different whitespace
    $old2 = '    dc_docstatus = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "docstatus")' + "`n" + '    if dc_docstatus != 1:' + "`n" + '        frappe.throw("Submit the Dispatch Case before completing the Order entry task.")'
    if ($original.Contains($old2)) {
        $original = $original.Replace($old2, $new)
        Write-Host "Matched with alternate whitespace." -ForegroundColor Green
    } else {
        # Use regex
        $original = $original -replace 'dc_docstatus = frappe\.db\.get_value\("Dispatch Case", doc\.dispatch_case, "docstatus"\)\s+if dc_docstatus != 1:\s+frappe\.throw\("Submit the Dispatch Case before completing the Order entry task\."\)', ($new.TrimStart() -replace '\\','\\\\')
        Write-Host "Used regex replacement." -ForegroundColor Yellow
    }
    $fixed = $original
} else {
    $fixed = $original.Replace($old, $new)
}

$bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $csName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
Write-Host "Fixed. DC will now auto-submit when you complete the Order Entry task." -ForegroundColor Green
