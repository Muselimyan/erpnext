param(
    [ValidateSet("Check", "Deploy", "Verify")]
    [string]$Mode = "Check"
)

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) {
    return [uri]::EscapeDataString($Value)
}

function Invoke-ErpRequest {
    param(
        [string]$Method,
        [string]$Path,
        $Body = $null
    )

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

function Get-ErpList {
    param(
        [string]$DocType,
        [array]$Fields = @("name"),
        [array]$Filters = @(),
        [int]$Limit = 20
    )

    $FieldsJson = $Fields | ConvertTo-Json -Compress
    $Path = "/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $FieldsJson)"
    if ($Filters.Count -gt 0) {
        $FiltersJson = $Filters | ConvertTo-Json -Compress -Depth 10
        $Path += "&filters=$(Enc $FiltersJson)"
    }
    return (Invoke-ErpRequest -Method Get -Path $Path).data
}

function Upsert-ErpDoc {
    param([string]$DocType, [string]$Name, $Body)

    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "created"; result = $Created.name }
    }

    $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ doctype = $DocType; name = $Name; action = "updated"; result = $Updated.name }
}

function Get-CustomDocPerms {
    param([string]$RoleName, [string]$DocTypeName)
    # Use 3-tuple filters (no DocType prefix) — 4-tuples cause KeyError on Custom DocPerm.
    $Filters = @(
        @("role",   "=", $RoleName),
        @("parent", "=", $DocTypeName)
    )
    try {
        return Get-ErpList -DocType "Custom DocPerm" -Fields @("name", "role", "parent", "read", "write", "create") -Filters $Filters -Limit 5
    } catch {
        return $null
    }
}

function Upsert-CustomDocPerm {
    param(
        [string]$RoleName,
        [string]$DocTypeName,
        [int]$Read = 1,
        [int]$Write = 0,
        [int]$Create = 0,
        [int]$Delete = 0,
        [int]$Permlevel = 0
    )

    $Existing = Get-CustomDocPerms -RoleName $RoleName -DocTypeName $DocTypeName

    $Body = [ordered]@{
        doctype     = "Custom DocPerm"
        role        = $RoleName
        parent      = $DocTypeName
        parenttype  = "DocType"
        parentfield = "permissions"
        permlevel   = $Permlevel
        read        = $Read
        write       = $Write
        create      = $Create
        delete      = $Delete
        submit      = 0
        cancel      = 0
        amend       = 0
    }

    if ($Existing -and $Existing.Count -gt 0) {
        $ExistingName = $Existing[0].name
        $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/$(Enc 'Custom DocPerm')/$(Enc $ExistingName)" -Body $Body).data
        return [pscustomobject]@{ doctype = "Custom DocPerm"; role = $RoleName; parent = $DocTypeName; action = "updated"; result = $ExistingName }
    }

    $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/$(Enc 'Custom DocPerm')" -Body $Body).data
    return [pscustomobject]@{ doctype = "Custom DocPerm"; role = $RoleName; parent = $DocTypeName; action = "created"; result = $Created.name }
}

# =============================================================================
# ROLES
# =============================================================================

$Roles = @(
    [pscustomobject]@{
        name = "Ops - Purchasing"
        body = [ordered]@{ doctype = "Role"; role_name = "Ops - Purchasing"; desk_access = 1; disabled = 0 }
    },
    [pscustomobject]@{
        name = "Ops - Purchasing Lead"
        body = [ordered]@{ doctype = "Role"; role_name = "Ops - Purchasing Lead"; desk_access = 1; disabled = 0 }
    }
)

# =============================================================================
# CUSTOM FIELDS
# =============================================================================

$CustomFields = @(
    [pscustomobject]@{
        name = "Item-reorder_change_reason"
        body = [ordered]@{
            doctype      = "Custom Field"
            dt           = "Item"
            label        = "Reorder Change Reason"
            fieldname    = "reorder_change_reason"
            fieldtype    = "Small Text"
            insert_after = "reorder_levels"
            reqd         = 0
            read_only    = 0
        }
    }
)

# =============================================================================
# ITEM ROLE PERMISSIONS  (Doc 08 §7.2)
# =============================================================================
# Ops - Purchasing       : Read only  (buyers can view items but not edit thresholds)
# Ops - Purchasing Lead  : Read+Write (threshold owners)

$DocPerms = @(
    [pscustomobject]@{ role = "Ops - Purchasing";      parent = "Item"; read = 1; write = 0; create = 0; delete = 0 },
    [pscustomobject]@{ role = "Ops - Purchasing Lead"; parent = "Item"; read = 1; write = 1; create = 0; delete = 0 }
)

# =============================================================================
# SERVER SCRIPTS
# =============================================================================

$ItemReorderGovernance = @'
before = doc.get_doc_before_save()

if not before:
    pass
else:
    # Standard ERPNext fieldname for Item Reorder child table.
    # If your instance uses a different name, change this value.
    REORDER_FIELDNAME = "reorder_levels"

    def normalize(rows):
        out = []
        for r in (rows or []):
            out.append({
                "warehouse": r.warehouse,
                "reorder_level": float(getattr(r, "warehouse_reorder_level", 0) or 0),
                "reorder_qty": float(getattr(r, "warehouse_reorder_qty", 0) or 0),
            })
        return out

    before_rows = normalize(before.get(REORDER_FIELDNAME) or [])
    after_rows  = normalize(doc.get(REORDER_FIELDNAME) or [])

    if before_rows != after_rows:
        if not (doc.reorder_change_reason or "").strip():
            frappe.throw(
                "Reorder Change Reason is required when changing reorder thresholds "
                "(Doc 08 governance rule)."
            )
'@

$ServerScripts = @(
    [pscustomobject]@{
        name               = "Item-before-save-reorder-governance"
        reference_doctype  = "Item"
        doctype_event      = "Before Save"
        script             = $ItemReorderGovernance
    }
)

# =============================================================================
# STATUS SNAPSHOT  (used by Check and Verify modes)
# =============================================================================

function Get-StatusSnapshot {
    $RoleStatus = foreach ($R in $Roles) {
        $Doc = Get-ErpDoc -DocType "Role" -Name $R.name
        [pscustomobject]@{ name = $R.name; exists = ($null -ne $Doc); disabled = $Doc.disabled }
    }

    $FieldStatus = foreach ($F in $CustomFields) {
        $Doc = Get-ErpDoc -DocType "Custom Field" -Name $F.name
        [pscustomobject]@{ name = $F.name; exists = ($null -ne $Doc); dt = $Doc.dt; fieldtype = $Doc.fieldtype; reqd = $Doc.reqd }
    }

    $ScriptStatus = foreach ($S in $ServerScripts) {
        $Doc = Get-ErpDoc -DocType "Server Script" -Name $S.name
        [pscustomobject]@{ name = $S.name; exists = ($null -ne $Doc); reference_doctype = $Doc.reference_doctype; doctype_event = $Doc.doctype_event; disabled = $Doc.disabled }
    }

    $PermStatus = foreach ($P in $DocPerms) {
        $Rows = Get-CustomDocPerms -RoleName $P.role -DocTypeName $P.parent
        [pscustomobject]@{
            role   = $P.role
            parent = $P.parent
            exists = ($Rows -and $Rows.Count -gt 0)
            rows   = $Rows
        }
    }

    [ordered]@{
        mode        = $Mode
        logged_user = (Invoke-ErpRequest -Method Get -Path "/api/method/frappe.auth.get_logged_user").message
        roles              = $RoleStatus
        custom_fields      = $FieldStatus
        server_scripts     = $ScriptStatus
        custom_doc_perms   = $PermStatus
    }
}

# =============================================================================
# EXECUTION
# =============================================================================

if ($Mode -eq "Check") {
    Get-StatusSnapshot | ConvertTo-Json -Depth 12
    exit 0
}

$Results = @()

foreach ($R in $Roles) {
    $Results += Upsert-ErpDoc -DocType "Role" -Name $R.name -Body $R.body
}

foreach ($F in $CustomFields) {
    $Results += Upsert-ErpDoc -DocType "Custom Field" -Name $F.name -Body $F.body
}

foreach ($S in $ServerScripts) {
    $Body = [ordered]@{
        doctype           = "Server Script"
        script_type       = "DocType Event"
        event_frequency   = "All"
        reference_doctype = $S.reference_doctype
        doctype_event     = $S.doctype_event
        allow_guest       = 0
        disabled          = 0
        enable_rate_limit = 0
        script            = $S.script
    }
    $Results += Upsert-ErpDoc -DocType "Server Script" -Name $S.name -Body $Body
}

foreach ($P in $DocPerms) {
    $Results += Upsert-CustomDocPerm `
        -RoleName    $P.role `
        -DocTypeName $P.parent `
        -Read        $P.read `
        -Write       $P.write `
        -Create      $P.create `
        -Delete      $P.delete
}

[ordered]@{
    mode         = $Mode
    results      = $Results
    verification = Get-StatusSnapshot
} | ConvertTo-Json -Depth 12
