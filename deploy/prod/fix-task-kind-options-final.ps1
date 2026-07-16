param()

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

Write-Host "=== Fixing Task Kind Options (Removing Trailing Spaces) ===" -ForegroundColor Cyan

# Correct options WITHOUT trailing spaces
$CorrectOptions = @"
Order entry
Pack / prepare items
Dispatch picking / hand-off
Delivery
Return to warehouse (aborted delivery / cancelled order)
Pickup Returns
Return drop-off at warehouse
Returns processing / verification
Invoice preparation / create invoice
Debt Collection
Distribute Payment
Discount Approval
Purchase Approval
Write-off Approval
"@

Write-Host "`nFetching current Task-task_kind field..." -ForegroundColor Yellow

try {
    $FieldUri = "$BaseUrl/api/resource/Custom Field/Task-task_kind"
    $CurrentField = (Invoke-RestMethod -Uri $FieldUri -Headers $Headers -Method Get).data
    
    Write-Host "Current options:" -ForegroundColor Yellow
    Write-Host $CurrentField.options -ForegroundColor Gray
    
    Write-Host "`nUpdating to correct options (no trailing spaces)..." -ForegroundColor Yellow
    
    $UpdateBody = @{
        options = $CorrectOptions.Trim()
    }
    
    $UpdateUri = "$BaseUrl/api/resource/Custom Field/Task-task_kind"
    $Result = Invoke-RestMethod -Uri $UpdateUri -Headers $Headers -Method Put -Body ($UpdateBody | ConvertTo-Json -Depth 10)
    
    Write-Host "SUCCESS: Task Kind options updated!" -ForegroundColor Green
    Write-Host "`nNew options:" -ForegroundColor Green
    Write-Host $CorrectOptions.Trim() -ForegroundColor White
    
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "`n=== Now clearing cache ===" -ForegroundColor Cyan

try {
    $ClearCacheUri = "$BaseUrl/api/method/frappe.desk.form.load.getdoctype"
    $CacheBody = @{
        doctype = "Task"
        with_parent = 1
    }
    Invoke-RestMethod -Uri $ClearCacheUri -Headers $Headers -Method Post -Body ($CacheBody | ConvertTo-Json)
    Write-Host "Cache cleared for Task DocType" -ForegroundColor Green
} catch {
    Write-Host "Cache clear may have failed, but that's OK - just refresh your browser" -ForegroundColor Yellow
}

Write-Host "`nDONE! Now:" -ForegroundColor Cyan
Write-Host "1. Refresh your browser (Ctrl+F5)" -ForegroundColor White
Write-Host "2. Try creating/saving a Task again" -ForegroundColor White
