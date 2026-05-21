param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 30 }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ action="created"; name=$C.name }
    }
    $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$U.name }
}

$BarcodeScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\ERPNext Barcode\GS1_FULL_WORKING_DRAFT.js"
$BarcodeClientScript = Get-Content $BarcodeScriptPath -Raw

$CustomFields = @(
    [pscustomobject]@{
        name="Purchase Receipt Item-custom_production_date"; dt="Purchase Receipt Item"; fieldname="custom_production_date"; label="Production Date"
        fieldtype="Date"; insert_after="custom_expiry_date"; read_only=1; allow_on_submit=1
    },
    [pscustomobject]@{
        name="Purchase Receipt Item-custom_scanned_gs1_barcode"; dt="Purchase Receipt Item"; fieldname="custom_scanned_gs1_barcode"; label="Scanned GS1 Barcode"
        fieldtype="Small Text"; insert_after="custom_production_date"; read_only=1; allow_on_submit=1
    },
    [pscustomobject]@{
        name="Purchase Receipt-custom_barcode_override_section"; dt="Purchase Receipt"; fieldname="custom_barcode_override_section"; label="Barcode Override"
        fieldtype="Section Break"; insert_after="items"
    },
    [pscustomobject]@{
        name="Purchase Receipt-custom_allow_expired_barcode_receipt"; dt="Purchase Receipt"; fieldname="custom_allow_expired_barcode_receipt"; label="Allow Expired Barcode Receipt"
        fieldtype="Check"; insert_after="custom_barcode_override_section"; default="0"
    },
    [pscustomobject]@{
        name="Purchase Receipt-custom_allow_future_production_date"; dt="Purchase Receipt"; fieldname="custom_allow_future_production_date"; label="Allow Future Production Date"
        fieldtype="Check"; insert_after="custom_allow_expired_barcode_receipt"; default="0"
    },
    [pscustomobject]@{
        name="Purchase Receipt-custom_barcode_override_reason"; dt="Purchase Receipt"; fieldname="custom_barcode_override_reason"; label="Barcode Override Reason"
        fieldtype="Small Text"; insert_after="custom_allow_future_production_date"
    }
)

function Build-CustomFieldBody ($f) {
    $Body = [ordered]@{ dt=$f.dt; fieldname=$f.fieldname; label=$f.label; fieldtype=$f.fieldtype }
    if ($f.PSObject.Properties["options"])         { $Body.options         = $f.options }
    if ($f.PSObject.Properties["insert_after"])    { $Body.insert_after    = $f.insert_after }
    if ($f.PSObject.Properties["read_only"])       { $Body.read_only       = $f.read_only }
    if ($f.PSObject.Properties["allow_on_submit"]) { $Body.allow_on_submit = $f.allow_on_submit }
    if ($f.PSObject.Properties["default"])         { $Body.default         = $f.default }
    return $Body
}

if ($Mode -eq "Check") {
    $Report = [ordered]@{ mode="Check"; custom_fields=@(); client_scripts=@() }
    foreach ($f in $CustomFields) {
        $E = Get-ErpDoc -DocType "Custom Field" -Name $f.name
        $Report.custom_fields += [pscustomobject]@{ name=$f.name; dt=$f.dt; fieldname=$f.fieldname; exists=($null -ne $E) }
    }
    $Cs = Get-ErpDoc -DocType "Client Script" -Name "GS1 Barcode Parser"
    $Report.client_scripts += [pscustomobject]@{ name="GS1 Barcode Parser"; exists=($null -ne $Cs); enabled=if($null -ne $Cs){$Cs.enabled}else{$null}; dt=if($null -ne $Cs){$Cs.dt}else{$null} }
    $Report | ConvertTo-Json -Depth 10
    return
}

$Results = [ordered]@{ mode="Deploy"; custom_fields=@(); client_scripts=@() }
foreach ($f in $CustomFields) {
    Write-Host "Deploying Custom Field: $($f.name)"
    $Results.custom_fields += Upsert-ErpDoc -DocType "Custom Field" -Name $f.name -Body (Build-CustomFieldBody $f)
}

Write-Host "Deploying Client Script: GS1 Barcode Parser"
$Results.client_scripts += Upsert-ErpDoc -DocType "Client Script" -Name "GS1 Barcode Parser" -Body ([ordered]@{
    dt      = "Purchase Receipt"
    view    = "Form"
    enabled = 1
    script  = $BarcodeClientScript
})

$Results | ConvertTo-Json -Depth 10
