Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest { 
    param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { 
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 
    }
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

Write-Host "`n=== Fixing Task Kind field options (removing trailing spaces) ===" -ForegroundColor Cyan

$TaskKindOptions = @"
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

try {
    # Get the Custom Field
    $uri = "$BaseUrl/api/resource/Custom Field/Task-task_kind"
    $field = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get -TimeoutSec 30
    
    Write-Host "Current options (showing first 100 chars):" -ForegroundColor Yellow
    Write-Host $field.data.options.Substring(0, [Math]::Min(100, $field.data.options.Length)) -ForegroundColor Gray
    
    # Update the options
    $field.data.options = $TaskKindOptions.Trim()
    
    Write-Host "`nUpdating field with clean options (no trailing spaces)..." -ForegroundColor Yellow
    $result = Invoke-ErpRequest -Method Put -Path "/api/resource/Custom Field/Task-task_kind" -Body $field.data
    
    Write-Host "SUCCESS: Task Kind field updated successfully!" -ForegroundColor Green
    Write-Host "`nRefresh your browser (Ctrl+F5) and try creating a Task again." -ForegroundColor Yellow
    
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "Error occurred: $errMsg" -ForegroundColor Red
}
