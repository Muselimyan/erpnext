Set-StrictMode -Off
$Config  = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$Name = "Task-before-save-dispatch-gates"
$Uri  = "$BaseUrl/api/resource/Server%20Script/$Name"

Write-Host "Fetching current script..." -ForegroundColor Cyan
$doc = (Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 60).data

# Add customer sync: Task customer -> Dispatch Case customer
$CustomerSync = @'
# Sync customer from Task to Dispatch Case
if doc.dispatch_case and doc.customer:
    dc_customer = frappe.db.get_value("Dispatch Case", doc.dispatch_case, "customer")
    if not dc_customer:
        frappe.db.set_value("Dispatch Case", doc.dispatch_case, "customer", doc.customer)

'@

$fixed = $doc.script
$changed = $false

if (-not $fixed.Contains('Sync customer from Task to Dispatch Case')) {
    # Insert customer sync right after the acceptance gate (or at the top if no gate)
    if ($fixed.Contains('You must Accept this task')) {
        # Find the end of the acceptance gate block and insert after it
        $marker = 'frappe.throw("You must Accept this task before making any changes or completing it.")'
        $idx = $fixed.IndexOf($marker)
        if ($idx -ge 0) {
            $endIdx = $fixed.IndexOf("`n", $idx + $marker.Length)
            if ($endIdx -lt 0) { $endIdx = $idx + $marker.Length }
            $fixed = $fixed.Substring(0, $endIdx + 1) + "`n" + $CustomerSync + $fixed.Substring($endIdx + 1)
            $changed = $true
        }
    } else {
        $fixed = $CustomerSync + $fixed
        $changed = $true
    }
}

if ($changed) {
    $Body = @{ script = $fixed } | ConvertTo-Json -Depth 10
    Write-Host "Adding customer sync to Before Save script..." -ForegroundColor Cyan
    $result = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60
    Write-Host "Done! Customer sync added." -ForegroundColor Green
} else {
    Write-Host "Customer sync already present. No changes needed." -ForegroundColor Green
}

# ===========================================================================
# FIX: Push full Task-Accept Start script (dirty save + mobile photo remove)
# ===========================================================================
Write-Host "`nFix: Updating Task-Accept Start client script..." -ForegroundColor Cyan
$CsName = "Task-Accept Start"
$CsUri = "$BaseUrl/api/resource/Client%20Script/$(([uri]::EscapeDataString($CsName)))"
$LocalScript = Get-Content (Join-Path $PSScriptRoot ".." "_temp_task_accept_server.js") -Raw

$Body2 = @{ script = $LocalScript } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri $CsUri -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body2)) -TimeoutSec 60 | Out-Null
Write-Host "Done! Task-Accept Start updated (dirty save fix + mobile photo remove)." -ForegroundColor Green
