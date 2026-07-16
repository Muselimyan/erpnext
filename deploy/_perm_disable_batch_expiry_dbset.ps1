$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

$ServerScriptName = "perm_disable_batch_expiry_dbset"
$Items = Import-Csv "C:\Users\Levon\.windsurf\PERM_quantity_items.csv"

$script = @'
codes_text = frappe.form_dict.get("codes") or ""
codes = []
for part in codes_text.split(","):
    code = part.strip()
    if code:
        codes.append(code)

updated = []
missing = []
for code in codes:
    exists = frappe.db.exists("Item", code)
    if exists:
        frappe.db.set_value("Item", code, "has_batch_no", 0, update_modified=False)
        frappe.db.set_value("Item", code, "has_expiry_date", 0, update_modified=False)
        updated.append(code)
    else:
        missing.append(code)

frappe.response["message"] = {"updated": updated, "missing": missing, "count": len(updated)}
'@

function Escape-Json([string]$s) {
    return $s.Replace('\', '\\').Replace('"', '\"').Replace("`r`n", '\n').Replace("`n", '\n').Replace("`t", '\t')
}

$bodyObj = @{
    name = $ServerScriptName
    script_type = "API"
    api_method = $ServerScriptName
    allow_guest = 0
    disabled = 0
    script = $script
}
$body = $bodyObj | ConvertTo-Json -Depth 5 -Compress

Write-Host "Creating/updating server script: $ServerScriptName"
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$ServerScriptName" -Headers $Headers -Method Get -TimeoutSec 20 | Out-Null
    $escaped = Escape-Json $script
    $putBody = "{`"script`":`"$escaped`",`"disabled`":0}"
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$ServerScriptName" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($putBody)) -TimeoutSec 30 | Out-Null
} catch {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
}

Write-Host "Disabling flags via db.set_value in chunks..."
$total = 0
$missingAll = @()
for ($i = 0; $i -lt $Items.Count; $i += 50) {
    $chunk = @($Items[$i..([Math]::Min($i+49, $Items.Count-1))])
    $codes = ($chunk | ForEach-Object { $_.ItemCode }) -join ","
    $callBody = @{ codes = $codes } | ConvertTo-Json -Compress
    $res = Invoke-RestMethod -Uri "$BaseUrl/api/method/$ServerScriptName" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($callBody)) -TimeoutSec 60
    $total += [int]$res.message.count
    if ($res.message.missing) { $missingAll += $res.message.missing }
    Write-Host "Updated $total / $($Items.Count)..."
}

Write-Host "Done. Updated flags for $total items." -ForegroundColor Green
if ($missingAll.Count -gt 0) {
    Write-Host "Missing item codes:" -ForegroundColor Red
    $missingAll | ForEach-Object { Write-Host $_ }
}
