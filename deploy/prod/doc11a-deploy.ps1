#Requires -Version 5.1
<#
.SYNOPSIS
    Doc 11A — Surgery Set Setup deployment script.
    Verifies the 5 required warehouses exist, creates the Collection Set Item (child
    table) and Collection Set (parent) DocTypes with their fields and permissions,
    and creates the readiness-warning server script on Collection Set.

.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — create all artefacts (idempotent: creates only what is missing)
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{
    Authorization  = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
    }
    $Json      = $Body | ConvertTo-Json -Depth 30
    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $JsonBytes
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try {
        return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data
    } catch {
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
    } else {
        $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
        return [pscustomobject]@{ action = "updated"; name = $Updated.name }
    }
}

# ---------------------------------------------------------------------------
# 1) REQUIRED WAREHOUSES (verify only — all must exist from Doc 05A)
# ---------------------------------------------------------------------------
$RequiredWarehouses = @(
    [pscustomobject]@{ name = "Main - Inmed";                       is_group = 0 },
    [pscustomobject]@{ name = "Delivery In-Transit - Inmed";        is_group = 0 },
    [pscustomobject]@{ name = "Clients - Inmed";                    is_group = 1 },
    [pscustomobject]@{ name = "Return Pickup In-Transit - Inmed";   is_group = 0 },
    [pscustomobject]@{ name = "Returns - Inmed";                    is_group = 0 }
)

# ---------------------------------------------------------------------------
# 2) DOCTYPES
# ---------------------------------------------------------------------------

# --- 2a) Child table: Collection Set Item ---
$ChildTableFields = @(
    [ordered]@{ fieldname = "item";            fieldtype = "Link";       label = "Item";            options = "Item";                        reqd = 1; in_list_view = 1 },
    [ordered]@{ fieldname = "default_qty";     fieldtype = "Float";      label = "Default Qty";                                              reqd = 1; in_list_view = 1 },
    [ordered]@{ fieldname = "uom";             fieldtype = "Link";       label = "UOM";             options = "UOM" },
    [ordered]@{ fieldname = "group";           fieldtype = "Select";     label = "Group";           options = "`nTools / Instruments`nScrews`nNails`nPlates"; in_list_view = 1 },
    [ordered]@{ fieldname = "return_behavior"; fieldtype = "Select";     label = "Return Behavior"; options = "`nExpected Return (Tools)`nMay Be Used (Implants)"; in_list_view = 1 },
    [ordered]@{ fieldname = "is_optional";     fieldtype = "Check";      label = "Optional" },
    [ordered]@{ fieldname = "is_critical";     fieldtype = "Check";      label = "Critical" },
    [ordered]@{ fieldname = "notes";           fieldtype = "Small Text"; label = "Notes" }
)

$ChildTableBody = [ordered]@{
    module  = "Custom"
    custom  = 1
    istable = 1
    fields  = $ChildTableFields
}

# --- 2b) Parent DocType: Collection Set ---
$ParentFields = @(
    [ordered]@{ fieldname = "set_name";         fieldtype = "Data";       label = "Set Name";         reqd = 1; unique = 1; in_list_view = 1 },
    [ordered]@{ fieldname = "set_code";         fieldtype = "Data";       label = "Set Code";         in_list_view = 1 },
    [ordered]@{ fieldname = "is_active";        fieldtype = "Check";      label = "Is Active";        default = "1"; in_list_view = 1 },
    [ordered]@{ fieldname = "notes";            fieldtype = "Small Text"; label = "Notes" },
    [ordered]@{ fieldname = "readiness_status"; fieldtype = "Select";     label = "Readiness Status"; options = "`nReady`nShort`nCritical Short"; read_only = 1; in_list_view = 1 },
    [ordered]@{ fieldname = "readiness_note";   fieldtype = "Small Text"; label = "Readiness Note";   read_only = 1 },
    [ordered]@{ fieldname = "items";            fieldtype = "Table";      label = "Items";            options = "Collection Set Item" }
)

$ParentPermissions = @(
    [ordered]@{ role = "Ops - Inventory"; read = 1; write = 1; create = 1; delete = 0; permlevel = 0 },
    [ordered]@{ role = "Ops - Directors"; read = 1; write = 1; create = 1; delete = 0; permlevel = 0 },
    [ordered]@{ role = "Ops - Delivery";  read = 1; write = 0; create = 0; delete = 0; permlevel = 0 }
)

$ParentDocTypeBody = [ordered]@{
    module      = "Custom"
    custom      = 1
    autoname    = "field:set_name"
    fields      = $ParentFields
    permissions = $ParentPermissions
}

# ---------------------------------------------------------------------------
# 3) SERVER SCRIPT — readiness warning on Surgery Set Type (Validate event)
# ---------------------------------------------------------------------------
$ReadinessScript = @'
MAIN_WH = "Main - Inmed"

missing_lines = []
critical_lines = []

for row in (doc.items or []):
    item_code = row.item
    required_qty = float(row.default_qty or 0)
    if item_code and required_qty > 0:
        bin_row = frappe.db.get_value(
            "Bin",
            {"item_code": item_code, "warehouse": MAIN_WH},
            ["projected_qty"],
            as_dict=True,
        )

        projected = float((bin_row or {}).get("projected_qty") or 0)
        shortage = required_qty - projected

        if shortage > 0:
            line = (
                str(item_code) + ": need " + str(required_qty)
                + ", projected " + str(projected)
                + ", short " + str(shortage)
            )
            missing_lines.append(line)
            if int(row.is_critical or 0) == 1:
                critical_lines.append(line)

if critical_lines:
    doc.readiness_status = "Critical Short"
    doc.readiness_note = "Critical shortages:\n" + "\n".join(critical_lines)
    frappe.msgprint(doc.readiness_note, title="Collection Set readiness warning")
elif missing_lines:
    doc.readiness_status = "Short"
    doc.readiness_note = "Shortages:\n" + "\n".join(missing_lines)
    frappe.msgprint(doc.readiness_note, title="Collection Set readiness warning")
else:
    doc.readiness_status = "Ready"
    doc.readiness_note = ""
'@

$ServerScript = [pscustomobject]@{
    name              = "Collection-Set-validate-readiness"
    script_type       = "DocType Event"
    reference_doctype = "Collection Set"
    doctype_event     = "Before Save"
    event_frequency   = "All"
    allow_guest       = 0
    disabled          = 0
    enable_rate_limit = 0
    script            = $ReadinessScript
}

# ---------------------------------------------------------------------------
# CHECK MODE — report current state
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    $Report = [ordered]@{
        mode           = "Check"
        warehouses     = @()
        doctypes       = @()
        server_scripts = @()
    }

    foreach ($W in $RequiredWarehouses) {
        $E = Get-ErpDoc -DocType "Warehouse" -Name $W.name
        $Report.warehouses += [pscustomobject]@{
            name   = $W.name
            exists = ($null -ne $E)
            is_group_expected = $W.is_group
            is_group_actual   = if ($null -ne $E) { $E.is_group } else { $null }
        }
    }

    foreach ($Dt in @("Collection Set Item", "Collection Set")) {
        $E = Get-ErpDoc -DocType "DocType" -Name $Dt
        $Report.doctypes += [pscustomobject]@{
            name   = $Dt
            exists = ($null -ne $E)
        }
    }

    $S = Get-ErpDoc -DocType "Server Script" -Name $ServerScript.name
    $Report.server_scripts += [pscustomobject]@{
        name     = $ServerScript.name
        exists   = ($null -ne $S)
        disabled = if ($null -ne $S) { $S.disabled } else { $null }
    }

    $Report | ConvertTo-Json -Depth 10
    return
}

# ---------------------------------------------------------------------------
# DEPLOY MODE
# ---------------------------------------------------------------------------
$Results = [ordered]@{
    mode           = "Deploy"
    warehouses     = @()
    doctypes       = @()
    server_scripts = @()
}

# -- Verify warehouses (report only; creation not needed — all present from Doc 05A) --
foreach ($W in $RequiredWarehouses) {
    $E = Get-ErpDoc -DocType "Warehouse" -Name $W.name
    if ($null -eq $E) {
        $Results.warehouses += [pscustomobject]@{ status = "MISSING - create manually via Doc 05A"; name = $W.name }
    } else {
        $Results.warehouses += [pscustomobject]@{ status = "ok"; name = $W.name }
    }
}

# -- Collection Set Item (child table) --
$ChildDoc = Get-ErpDoc -DocType "DocType" -Name "Collection Set Item"
if ($null -ne $ChildDoc) {
    if (-not $ChildDoc.istable) {
        # Was created without istable=1; fix it
        $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/$(Enc 'Collection Set Item')" -Body ([ordered]@{ istable = 1 })).data
        $Results.doctypes += [pscustomobject]@{ action = "fixed-istable"; name = $Updated.name }
    } else {
        $Results.doctypes += [pscustomobject]@{ action = "exists"; name = "Collection Set Item" }
    }
} else {
    $ChildTableBody.name = "Collection Set Item"
    $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $ChildTableBody).data
    $Results.doctypes += [pscustomobject]@{ action = "created"; name = $Created.name }
}
Start-Sleep -Seconds 2

# -- Collection Set (parent) —
# Must be created AFTER the child table exists
$ParentExists = $null -ne (Get-ErpDoc -DocType "DocType" -Name "Collection Set")
if ($ParentExists) {
    $Results.doctypes += [pscustomobject]@{ action = "exists"; name = "Collection Set" }
} else {
    $ParentDocTypeBody.name = "Collection Set"
    $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/DocType" -Body $ParentDocTypeBody).data
    $Results.doctypes += [pscustomobject]@{ action = "created"; name = $Created.name }
}

# -- Server Script --
$Results.server_scripts += Upsert-ErpDoc -DocType "Server Script" -Name $ServerScript.name -Body ([ordered]@{
    script_type       = $ServerScript.script_type
    reference_doctype = $ServerScript.reference_doctype
    doctype_event     = $ServerScript.doctype_event
    event_frequency   = $ServerScript.event_frequency
    allow_guest       = $ServerScript.allow_guest
    disabled          = $ServerScript.disabled
    enable_rate_limit = $ServerScript.enable_rate_limit
    script            = $ServerScript.script
})

# ---------------------------------------------------------------------------
# FINAL CHECK SNAPSHOT
# ---------------------------------------------------------------------------
$Snapshot = [ordered]@{
    mode           = "Deploy/Verify"
    warehouses     = @()
    doctypes       = @()
    server_scripts = @()
}

foreach ($W in $RequiredWarehouses) {
    $E = Get-ErpDoc -DocType "Warehouse" -Name $W.name
    $Snapshot.warehouses += [pscustomobject]@{ name = $W.name; exists = ($null -ne $E) }
}

foreach ($Dt in @("Collection Set Item", "Collection Set")) {
    $E = Get-ErpDoc -DocType "DocType" -Name $Dt
    $Snapshot.doctypes += [pscustomobject]@{ name = $Dt; exists = ($null -ne $E) }
}

$S = Get-ErpDoc -DocType "Server Script" -Name $ServerScript.name
$Snapshot.server_scripts += [pscustomobject]@{
    name     = $ServerScript.name
    exists   = ($null -ne $S)
    disabled = if ($null -ne $S) { $S.disabled } else { $null }
}

$Results | ConvertTo-Json -Depth 10
Write-Host "`n--- Post-deploy verification ---"
$Snapshot | ConvertTo-Json -Depth 10
