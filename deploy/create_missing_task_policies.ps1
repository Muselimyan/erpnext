# Create Missing Task Access Policy Records
# Safe to run multiple times (idempotent)

param()

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) { [uri]::EscapeDataString($Value) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
    }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Json
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try {
        return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
    }
    catch {
        return $null
    }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action = "created"; name = $Created.name }
    }
    return [pscustomobject]@{ action = "exists"; name = $Name }
}

$RequiredPolicies = @(
    "Order entry",
    "Pack / prepare items",
    "Dispatch picking / hand-off",
    "Delivery",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns",
    "Return drop-off at warehouse",
    "Returns processing / verification",
    "Returns restocking",
    "Invoice preparation / create invoice",
    "Debt Collection",
    "Distribute Payment",
    "Payment Received",
    "Discount Approval",
    "Purchase Approval",
    "Write-off Approval"
)

Write-Host "Creating Task Access Policy records..." -ForegroundColor Cyan
$Results = @()

foreach ($PolicyName in $RequiredPolicies) {
    $Body = [ordered]@{
        doctype = "Task Access Policy"
        policy_name = $PolicyName
    }
    $Result = Upsert-ErpDoc -DocType "Task Access Policy" -Name $PolicyName -Body $Body
    $Results += $Result
    if ($Result.action -eq "created") {
        Write-Host "  CREATED: $PolicyName" -ForegroundColor Green
    } else {
        Write-Host "  EXISTS:  $PolicyName" -ForegroundColor Gray
    }
}

$Created = ($Results | Where-Object { $_.action -eq "created" }).Count
$Existing = ($Results | Where-Object { $_.action -eq "exists" }).Count

Write-Host ""
Write-Host "Summary: $Created created, $Existing already existed" -ForegroundColor Cyan
