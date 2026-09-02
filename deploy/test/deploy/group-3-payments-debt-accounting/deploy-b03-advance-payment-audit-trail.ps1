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
function Upsert-ErpDoc { param([string]$DocType, [string]$Name, $Doc)
    try {
        Get-ErpDoc $DocType $Name | Out-Null
        $Body = @{}
        foreach ($Key in $Doc.Keys) { if ($Key -ne "doctype" -and $Key -ne "name") { $Body[$Key] = $Doc[$Key] } }
        return (Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data
    } catch {
        return (Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Doc).data
    }
}

$ChildDoctype = @{
    doctype = "DocType"
    name = "Dispatch Case Advance Payment"
    module = "Custom"
    custom = 1
    istable = 1
    editable_grid = 1
    fields = @(
        @{ label = "Payment Date"; fieldname = "payment_date"; fieldtype = "Datetime"; read_only = 1; in_list_view = 1; idx = 1 },
        @{ label = "Amount"; fieldname = "amount"; fieldtype = "Currency"; read_only = 1; in_list_view = 1; idx = 2 },
        @{ label = "Method"; fieldname = "method"; fieldtype = "Select"; options = "Cash`nBank Transfer`nCard"; read_only = 1; in_list_view = 1; idx = 3 },
        @{ label = "Reference"; fieldname = "reference"; fieldtype = "Data"; read_only = 1; in_list_view = 1; idx = 4 },
        @{ label = "Payment Entry"; fieldname = "payment_entry"; fieldtype = "Link"; options = "Payment Entry"; read_only = 1; in_list_view = 1; idx = 5 },
        @{ label = "Source Task"; fieldname = "source_task"; fieldtype = "Link"; options = "Task"; read_only = 1; in_list_view = 0; idx = 6 }
    )
    permissions = @()
}

$AdvancePaymentsField = @{
    doctype = "Custom Field"
    name = "Dispatch Case-advance_payments"
    dt = "Dispatch Case"
    label = "Advance Payments"
    fieldname = "advance_payments"
    fieldtype = "Table"
    options = "Dispatch Case Advance Payment"
    insert_after = "prepaid_payment_entry"
    read_only = 1
    allow_on_submit = 1
}

$ServerScriptPath = Join-Path $TestRoot "work\server\Task-after-save-advance-payment.py"
$LocalScript = Get-Content $ServerScriptPath -Raw
$CurrentScript = Get-ErpDoc "Server Script" "Task-after-save-advance-payment"

if ($Mode -eq "Check") {
    $childExists = $false
    $fieldExists = $false
    try { Get-ErpDoc "DocType" "Dispatch Case Advance Payment" | Out-Null; $childExists = $true } catch {}
    try { Get-ErpDoc "Custom Field" "Dispatch Case-advance_payments" | Out-Null; $fieldExists = $true } catch {}
    [pscustomobject]@{
        target = $BaseUrl
        child_doctype_exists = $childExists
        dispatch_case_advance_payments_field_exists = $fieldExists
        server_script = $CurrentScript.name
        server_script_disabled = $CurrentScript.disabled
        local_script_has_audit_trail = ([string]$LocalScript -match "advance_payments")
    } | ConvertTo-Json
    exit 0
}

Upsert-ErpDoc "DocType" "Dispatch Case Advance Payment" $ChildDoctype | Out-Null
Upsert-ErpDoc "Custom Field" "Dispatch Case-advance_payments" $AdvancePaymentsField | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc 'Task-after-save-advance-payment')" @{ script = $LocalScript } | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    child_doctype = "Dispatch Case Advance Payment"
    custom_field = "Dispatch Case-advance_payments"
    server_script = "Task-after-save-advance-payment"
    status = "updated"
} | ConvertTo-Json
