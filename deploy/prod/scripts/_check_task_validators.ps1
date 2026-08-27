$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }

# Check Server Scripts for Task
Write-Host "=== Server Scripts for Task ===" -ForegroundColor Cyan
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script?filters=%5B%5B%22reference_doctype%22%2C%22%3D%22%2C%22Task%22%5D%2C%5B%22disabled%22%2C%22%3D%22%2C0%5D%5D&fields=%5B%22name%22%2C%22script_type%22%2C%22doctype_event%22%5D&limit_page_length=50" -Headers $Headers -Method Get -TimeoutSec 30
foreach ($ss in $r.data) {
    Write-Host "  $($ss.name) | type=$($ss.script_type) | event=$($ss.doctype_event)"
}

# Check Server Scripts for Dispatch Case
Write-Host "`n=== Server Scripts for Dispatch Case ===" -ForegroundColor Cyan
$r2 = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script?filters=%5B%5B%22reference_doctype%22%2C%22%3D%22%2C%22Dispatch%20Case%22%5D%2C%5B%22disabled%22%2C%22%3D%22%2C0%5D%5D&fields=%5B%22name%22%2C%22script_type%22%2C%22doctype_event%22%5D&limit_page_length=50" -Headers $Headers -Method Get -TimeoutSec 30
foreach ($ss in $r2.data) {
    Write-Host "  $($ss.name) | type=$($ss.script_type) | event=$($ss.doctype_event)"
}

# Check the specific task status
Write-Host "`n=== Task Ortopetik current state ===" -ForegroundColor Cyan
$tasks = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Task?filters=%5B%5B%22subject%22%2C%22like%22%2C%22%25Ortopetik%25%22%5D%5D&fields=%5B%22name%22%2C%22subject%22%2C%22status%22%2C%22dispatch_case%22%2C%22task_kind%22%5D&limit_page_length=5" -Headers $Headers -Method Get -TimeoutSec 15
foreach ($t in $tasks.data) {
    Write-Host "  $($t.name) | subject=$($t.subject) | status=$($t.status) | DC=$($t.dispatch_case) | kind=$($t.task_kind)"
}

# Check DC-2026-00087 items
Write-Host "`n=== DC-2026-00087 Items ===" -ForegroundColor Cyan
try {
    $dc = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Dispatch%20Case/DC-2026-00087" -Headers $Headers -Method Get -TimeoutSec 15
    $items = $dc.data.items
    if ($items -and $items.Count -gt 0) {
        Write-Host "  $($items.Count) items found"
    } else {
        Write-Host "  NO ITEMS (empty)" -ForegroundColor Red
    }
} catch { Write-Host "  (error fetching)" -ForegroundColor Red }
