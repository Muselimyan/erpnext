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
function Get-CustomDocPerm { param([string]$Parent, [string]$Role, [int]$Permlevel)
    $Filters = ConvertTo-Json @(@("parent", "=", $Parent), @("role", "=", $Role), @("permlevel", "=", $Permlevel)) -Compress
    try {
        $Result = Invoke-ErpRequest Get "/api/resource/$(Enc 'Custom DocPerm')?filters=$(Enc $Filters)&fields=$(Enc '["name"]')&limit_page_length=1"
        if ($Result.data -and $Result.data.Count -gt 0) { return $Result.data[0] }
    } catch {}
    return $null
}
function Upsert-CustomDocPerm { param([string]$Parent, [string]$Role, [int]$Permlevel, $Doc)
    $Existing = Get-CustomDocPerm $Parent $Role $Permlevel
    if ($Existing) {
        return (Invoke-ErpRequest Put "/api/resource/$(Enc 'Custom DocPerm')/$(Enc $Existing.name)" $Doc).data
    }
    return (Invoke-ErpRequest Post "/api/resource/$(Enc 'Custom DocPerm')" $Doc).data
}

$FinancialFields = @("sales_invoice", "prepaid_amount", "prepaid_payment_entry", "total_invoice_amount", "total_paid_amount", "outstanding_amount", "profit", "advance_payments")
$PricingFields = @("unit_price", "discount_pct")
$FinancialRoles = @("Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager")
$PricingRoles = @("Ops - Order Creating", "Ops - Accounting", "Ops - Finance", "Ops - Directors", "System Manager")
$ClientScriptName = "Dispatch Case-Price Visibility"
$ClientScriptPath = Join-Path $TestRoot "work\client\Dispatch Case-Price Visibility.js"
$ClientScriptWithHeader = Get-Content $ClientScriptPath -Raw
$ClientScript = [regex]::Replace($ClientScriptWithHeader, '(?s)^// Name:.*?// ---\r?\n\r?\n?', '')

$checks = [ordered]@{
    target = $BaseUrl
    mode = $Mode
    financial_fields = $FinancialFields
    pricing_fields = $PricingFields
    financial_roles = $FinancialRoles
    pricing_roles = $PricingRoles
    local_client_hides_profit = ([string]$ClientScriptWithHeader -match '"profit"')
    local_client_hides_advance_payments = ([string]$ClientScriptWithHeader -match '"advance_payments"')
    local_client_allows_order_creating_pricing = ([string]$ClientScriptWithHeader -match 'Ops - Order Creating')
}

if ($Mode -eq "Check") {
    $checks | ConvertTo-Json -Depth 20
    exit 0
}

foreach ($Field in $FinancialFields) {
    $SetterName = "Dispatch Case-$Field-permlevel"
    Upsert-ErpDoc "Property Setter" $SetterName @{
        doctype = "Property Setter"
        name = $SetterName
        doc_type = "Dispatch Case"
        field_name = $Field
        doctype_or_field = "DocField"
        property = "permlevel"
        property_type = "Int"
        value = "1"
    } | Out-Null
}

foreach ($Field in $PricingFields) {
    $SetterName = "Dispatch Case Item-$Field-permlevel"
    Upsert-ErpDoc "Property Setter" $SetterName @{
        doctype = "Property Setter"
        name = $SetterName
        doc_type = "Dispatch Case Item"
        field_name = $Field
        doctype_or_field = "DocField"
        property = "permlevel"
        property_type = "Int"
        value = "2"
    } | Out-Null
}

foreach ($Role in $FinancialRoles) {
    Upsert-CustomDocPerm "Dispatch Case" $Role 1 @{
        doctype = "Custom DocPerm"
        parent = "Dispatch Case"
        parenttype = "DocType"
        parentfield = "permissions"
        role = $Role
        permlevel = 1
        read = 1
        write = 1
        create = 0
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
        report = 1
        export = 1
        print = 1
        email = 1
        share = 1
    } | Out-Null
}

foreach ($Role in $PricingRoles) {
    Upsert-CustomDocPerm "Dispatch Case" $Role 2 @{
        doctype = "Custom DocPerm"
        parent = "Dispatch Case"
        parenttype = "DocType"
        parentfield = "permissions"
        role = $Role
        permlevel = 2
        read = 1
        write = 1
        create = 0
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
        report = 1
        export = 1
        print = 1
        email = 1
        share = 1
    } | Out-Null
}

Invoke-ErpRequest Put "/api/resource/$(Enc 'Client Script')/$(Enc $ClientScriptName)" @{ script = $ClientScript; enabled = 1 } | Out-Null

[pscustomobject]@{
    target = $BaseUrl
    status = "updated"
    financial_permlevel = 1
    pricing_permlevel = 2
    client_script = $ClientScriptName
} | ConvertTo-Json -Depth 20
