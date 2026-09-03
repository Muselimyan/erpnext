param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 80
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType, [string]$Name)
    return (Invoke-ErpRequest Get "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
}

$DebtPaymentScriptName = "Task-before-save-payment-recording"
$AdvancePaymentScriptName = "Task-after-save-advance-payment"
$DebtPaymentScriptPath = Join-Path $TestRoot "work\server\Task-before-save-payment-recording.py"
$AdvancePaymentScriptPath = Join-Path $TestRoot "work\server\Task-after-save-advance-payment.py"
$DebtPaymentScript = Get-Content $DebtPaymentScriptPath -Raw
$AdvancePaymentScript = Get-Content $AdvancePaymentScriptPath -Raw

$CashAccountExists = $false
$BankAccountExists = $false
try { Get-ErpDoc "Account" "Cash - Inmed" | Out-Null; $CashAccountExists = $true } catch {}
try { Get-ErpDoc "Account" "Bank - Inmed" | Out-Null; $BankAccountExists = $true } catch {}

$DebtLive = Get-ErpDoc "Server Script" $DebtPaymentScriptName
$AdvanceLive = Get-ErpDoc "Server Script" $AdvancePaymentScriptName

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        cash_account_exists = $CashAccountExists
        bank_account_exists = $BankAccountExists
        mapping = @{
            Cash = "Cash - Inmed"
            "Bank Transfer" = "Bank - Inmed"
            Card = "Bank - Inmed"
        }
        debt_script = $DebtLive.name
        advance_script = $AdvanceLive.name
        debt_local_uses_mapping = ([string]$DebtPaymentScript -match "paid_to_account" -and [string]$DebtPaymentScript -match "Bank - Inmed")
        advance_local_uses_mapping = ([string]$AdvancePaymentScript -match "paid_to_account" -and [string]$AdvancePaymentScript -match "Bank - Inmed")
        debt_local_hardcoded_paid_to_cash_only = ([string]$DebtPaymentScript -match '"paid_to"\s*:\s*"Cash - Inmed"')
        advance_local_hardcoded_paid_to_cash_only = ([string]$AdvancePaymentScript -match '"paid_to"\s*:\s*"Cash - Inmed"')
    } | ConvertTo-Json -Depth 10
    exit 0
}

if (-not $CashAccountExists) { throw "Missing account: Cash - Inmed" }
if (-not $BankAccountExists) { throw "Missing account: Bank - Inmed" }

Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $DebtPaymentScriptName)" @{ script = $DebtPaymentScript } | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $AdvancePaymentScriptName)" @{ script = $AdvancePaymentScript } | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    server_scripts = @($DebtPaymentScriptName, $AdvancePaymentScriptName)
    mapping = @{
        Cash = "Cash - Inmed"
        "Bank Transfer" = "Bank - Inmed"
        Card = "Bank - Inmed"
    }
    status = "updated"
} | ConvertTo-Json -Depth 10
