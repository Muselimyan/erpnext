param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

# ── config ────────────────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config  = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$H = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

function Enc([string]$v) { [uri]::EscapeDataString($v) }
function Invoke-Erp {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method }
    return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method -Body ($Body | ConvertTo-Json -Depth 20)
}
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-Erp -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}
function Upsert-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Existing = Get-ErpDoc -DocType $DocType -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $r = (Invoke-Erp -Method Post -Path "/api/resource/$(Enc $DocType)" -Body $Body).data
        return [pscustomobject]@{ name = $Name; action = "created"; result = $r.name }
    }
    $r = (Invoke-Erp -Method Put -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ name = $Name; action = "updated"; result = $r.name }
}

# ── field definitions ─────────────────────────────────────────────────────────
# Existing chain: client_code -> client_kind -> debt_threshold_amd -> is_provisional
# We insert: hospital after is_provisional, doctor_name after hospital

$Fields = @(
    [pscustomobject]@{
        name = "Customer-hospital"
        body = [ordered]@{
            doctype       = "Custom Field"
            dt            = "Customer"
            label         = "Hospital"
            fieldname     = "hospital"
            fieldtype     = "Link"
            options       = "Customer"
            insert_after  = "is_provisional"
            reqd          = 0
            read_only     = 0
        }
    },
    [pscustomobject]@{
        name = "Customer-doctor_name"
        body = [ordered]@{
            doctype       = "Custom Field"
            dt            = "Customer"
            label         = "Doctor Name"
            fieldname     = "doctor_name"
            fieldtype     = "Data"
            insert_after  = "hospital"
            reqd          = 0
            read_only     = 0
        }
    }
)

if ($Mode -eq "Check") {
    $Status = foreach ($F in $Fields) {
        $Doc = Get-ErpDoc -DocType "Custom Field" -Name $F.name
        [pscustomobject]@{
            name      = $F.name
            exists    = ($null -ne $Doc)
            fieldtype = $Doc.fieldtype
            options   = $Doc.options
        }
    }
    [ordered]@{ mode = "Check"; fields = $Status } | ConvertTo-Json -Depth 10
    exit 0
}

$Results = foreach ($F in $Fields) {
    Upsert-ErpDoc -DocType "Custom Field" -Name $F.name -Body $F.body
}

[ordered]@{ mode = "Deploy"; results = $Results } | ConvertTo-Json -Depth 10
