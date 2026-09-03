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
    name = "Sales Invoice Tender Fulfillment"
    module = "Custom"
    custom = 1
    istable = 1
    editable_grid = 1
    fields = @(
        @{ label = "Tender Agreement"; fieldname = "tender_agreement"; fieldtype = "Link"; options = "Tender Agreement"; read_only = 1; in_list_view = 1; idx = 1 },
        @{ label = "Item Code"; fieldname = "item_code"; fieldtype = "Link"; options = "Item"; read_only = 1; in_list_view = 1; idx = 2 },
        @{ label = "Quantity"; fieldname = "quantity"; fieldtype = "Float"; read_only = 1; in_list_view = 1; idx = 3 },
        @{ label = "Sales Invoice Item"; fieldname = "sales_invoice_item"; fieldtype = "Data"; read_only = 1; in_list_view = 0; idx = 4 },
        @{ label = "Applied At"; fieldname = "applied_at"; fieldtype = "Datetime"; read_only = 1; in_list_view = 1; idx = 5 }
    )
    permissions = @()
}

$FulfillmentField = @{
    doctype = "Custom Field"
    name = "Sales Invoice-tender_fulfillments"
    dt = "Sales Invoice"
    label = "Tender Fulfillments"
    fieldname = "tender_fulfillments"
    fieldtype = "Table"
    options = "Sales Invoice Tender Fulfillment"
    insert_after = "items"
    read_only = 1
    allow_on_submit = 1
}

$SubmitScriptName = "Sales-Invoice-after-submit-tender-update"
$CancelScriptName = "Sales-Invoice-on-cancel-tender-reversal"
$SubmitScript = Get-Content (Join-Path $TestRoot "work\server\Sales-Invoice-after-submit-tender-update.py") -Raw
$CancelScript = Get-Content (Join-Path $TestRoot "work\server\Sales-Invoice-on-cancel-tender-reversal.py") -Raw

$CancelServerScript = @{
    doctype = "Server Script"
    name = $CancelScriptName
    script_type = "DocType Event"
    reference_doctype = "Sales Invoice"
    doctype_event = "On Cancel"
    disabled = 0
    script = $CancelScript
}

if ($Mode -eq "Check") {
    $childExists = $false
    $fieldExists = $false
    $cancelExists = $false
    try { Get-ErpDoc "DocType" "Sales Invoice Tender Fulfillment" | Out-Null; $childExists = $true } catch {}
    try { Get-ErpDoc "Custom Field" "Sales Invoice-tender_fulfillments" | Out-Null; $fieldExists = $true } catch {}
    try { Get-ErpDoc "Server Script" $CancelScriptName | Out-Null; $cancelExists = $true } catch {}
    [pscustomobject]@{
        target = $BaseUrl
        child_doctype_exists = $childExists
        sales_invoice_tender_fulfillments_field_exists = $fieldExists
        cancel_script_exists = $cancelExists
        local_submit_writes_fulfillment_rows = ([string]$SubmitScript -match "tender_fulfillments")
        local_cancel_reverses_fulfillment_rows = ([string]$CancelScript -match "tender_fulfillments")
    } | ConvertTo-Json
    exit 0
}

Upsert-ErpDoc "DocType" "Sales Invoice Tender Fulfillment" $ChildDoctype | Out-Null
Upsert-ErpDoc "Custom Field" "Sales Invoice-tender_fulfillments" $FulfillmentField | Out-Null
Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $SubmitScriptName)" @{ script = $SubmitScript } | Out-Null
Upsert-ErpDoc "Server Script" $CancelScriptName $CancelServerScript | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    child_doctype = "Sales Invoice Tender Fulfillment"
    custom_field = "Sales Invoice-tender_fulfillments"
    submit_script = $SubmitScriptName
    cancel_script = $CancelScriptName
    status = "updated"
} | ConvertTo-Json
