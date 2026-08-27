$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Step 1: Count all tasks
$countR = Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.client.get_count?doctype=Task" -Headers $Headers -Method Get -TimeoutSec 30
$total = $countR.message
Write-Host "Total Tasks to delete: $total" -ForegroundColor Yellow

if ($total -eq 0) {
    Write-Host "No tasks found. Done." -ForegroundColor Green
    exit
}

# Step 2: Fetch all task names in batches
$allNames = @()
$offset = 0
$batch = 100
while ($offset -lt $total) {
    $r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task?fields=[`"name`"]&limit_start=$offset&limit_page_length=$batch&order_by=name+asc" -Headers $Headers -Method Get -TimeoutSec 30
    foreach ($t in $r.data) { $allNames += $t.name }
    $offset += $batch
}
Write-Host "Fetched $($allNames.Count) task names." -ForegroundColor Cyan

# Step 3: Delete each task
$deleted = 0
$errors = 0
foreach ($name in $allNames) {
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task/$(Enc $name)" -Headers $Headers -Method Delete -TimeoutSec 30 | Out-Null
        $deleted++
        if ($deleted % 20 -eq 0) { Write-Host "  Deleted $deleted / $($allNames.Count)..." }
    } catch {
        $msg = $_.Exception.Message
        # If linked, try force delete via method
        try {
            Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.client.delete" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes((@{ doctype="Task"; name=$name } | ConvertTo-Json -Compress))) -TimeoutSec 30 | Out-Null
            $deleted++
            if ($deleted % 20 -eq 0) { Write-Host "  Deleted $deleted / $($allNames.Count)..." }
        } catch {
            Write-Host "  SKIP $name : $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }
}

Write-Host "`nDeleted: $deleted  Errors: $errors" -ForegroundColor Green
