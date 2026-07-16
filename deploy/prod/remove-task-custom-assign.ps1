param()

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

Write-Host "=== Removing Custom Assignment Field and Hiding Script ===" -ForegroundColor Cyan

# 1. Disable the hiding client script
Write-Host "`n1. Disabling 'Task-Hide Sidebar Assignment' client script..." -ForegroundColor Yellow
try {
    $Result = Invoke-ErpRequest -Method Put -Path "/api/resource/Client Script/Task-Hide%20Sidebar%20Assignment" -Body @{enabled=0}
    Write-Host "   Client script disabled!" -ForegroundColor Green
} catch {
    Write-Host "   Could not disable (may not exist): $_" -ForegroundColor Gray
}

# 2. Delete the custom_assign_to field
Write-Host "`n2. Deleting 'Task-custom_assign_to' custom field..." -ForegroundColor Yellow
try {
    $Result = Invoke-ErpRequest -Method Delete -Path "/api/resource/Custom Field/Task-custom_assign_to"
    Write-Host "   Custom field deleted!" -ForegroundColor Green
} catch {
    Write-Host "   Could not delete (may not exist): $_" -ForegroundColor Gray
}

# 3. Remove the after_insert assignment script
Write-Host "`n3. Disabling 'Task-after-insert-assign' server script..." -ForegroundColor Yellow
try {
    $Result = Invoke-ErpRequest -Method Put -Path "/api/resource/Server Script/Task-after-insert-assign" -Body @{disabled=1}
    Write-Host "   Server script disabled!" -ForegroundColor Green
} catch {
    Write-Host "   Could not disable (may not exist): $_" -ForegroundColor Gray
}

Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "Now:" -ForegroundColor White
Write-Host "1. Refresh browser (Ctrl+F5)" -ForegroundColor White
Write-Host "2. The sidebar assignment will be visible after saving Task" -ForegroundColor White
Write-Host "3. The custom 'Assign To (User Email)' field is removed" -ForegroundColor White
