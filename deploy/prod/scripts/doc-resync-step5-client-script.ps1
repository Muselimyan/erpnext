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

# ── client script definition ──────────────────────────────────────────────────
$ScriptName = "SO-hospital-doctor-autofill"

$ScriptBody = @'
frappe.ui.form.on('Sales Order', {
    customer(frm) {
        const clear = () => {
            frm.set_value('hospital', '');
            frm.set_value('doctor_name', '');
        };
        if (!frm.doc.customer) { clear(); return; }
        frappe.db.get_doc('Customer', frm.doc.customer).then(c => {
            if (c.client_kind === 'Doctor') {
                frm.set_value('hospital',     c.hospital     || '');
                frm.set_value('doctor_name',  c.doctor_name  || '');
            } else {
                // Hospital customer: hospital = itself, doctor left blank
                frm.set_value('hospital',     c.customer_name || '');
                frm.set_value('doctor_name',  '');
            }
        });
    }
});
'@

$ScriptDoc = [ordered]@{
    doctype  = "Client Script"
    dt       = "Sales Order"
    view     = "Form"
    enabled  = 1
    script   = $ScriptBody
}

if ($Mode -eq "Check") {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $ScriptName
    [ordered]@{
        mode          = "Check"
        script_name   = $ScriptName
        exists        = ($null -ne $Existing)
        enabled       = $Existing.enabled
        dt            = $Existing.dt
        script_length = if ($Existing.script) { $Existing.script.Length } else { 0 }
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ── Deploy ────────────────────────────────────────────────────────────────────
$Existing = Get-ErpDoc -DocType "Client Script" -Name $ScriptName
if ($null -eq $Existing) {
    $ScriptDoc.name = $ScriptName
    $Result = (Invoke-Erp -Method Post -Path "/api/resource/Client Script" -Body $ScriptDoc).data
    Write-Host "Created Client Script: $($Result.name)"
} else {
    $Result = (Invoke-Erp -Method Put -Path "/api/resource/Client Script/$(Enc $ScriptName)" -Body $ScriptDoc).data
    Write-Host "Updated Client Script: $($Result.name)"
}

# Verify
$Verify = Get-ErpDoc -DocType "Client Script" -Name $ScriptName
[ordered]@{
    mode    = "Deploy"
    name    = $Result.name
    action  = if ($null -eq $Existing) { "created" } else { "updated" }
    verify  = [ordered]@{
        exists  = ($null -ne $Verify)
        enabled = $Verify.enabled
        dt      = $Verify.dt
    }
} | ConvertTo-Json -Depth 10
