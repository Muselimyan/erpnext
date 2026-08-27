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
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Upsert-ErpDoc { param([string]$DocType,[string]$Name,$Body)
    $Existing = Get-ErpDoc $DocType $Name
    if ($null -eq $Existing) { $Body.name=$Name; $C=(Invoke-ErpRequest Post "/api/resource/$(Enc $DocType)" $Body).data; return [pscustomobject]@{action="created";name=$C.name} }
    $U=(Invoke-ErpRequest Put "/api/resource/$(Enc $DocType)/$(Enc $Name)" $Body).data; return [pscustomobject]@{action="updated";name=$U.name}
}

Write-Host "=== Auto-fill Item Name in Dispatch Case ===" -ForegroundColor Cyan

$ClientScript = @'
frappe.ui.form.on("Dispatch Case Item", {
    item_code: function(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (row.item_code && !row.item_name) {
            // Fetch item name from Item master
            frappe.db.get_value("Item", row.item_code, "item_name", function(r) {
                if (r && r.item_name) {
                    frappe.model.set_value(cdt, cdn, "item_name", r.item_name);
                }
            });
        }
    }
});
'@

$ScriptDef = [ordered]@{
    name = "Dispatch Case Item-Auto Fill Item Name"
    dt = "Dispatch Case Item"
    enabled = 1
    script_type = "Form"
    script = $ClientScript
}

if ($Mode -eq "Deploy") {
    $Result = Upsert-ErpDoc -DocType "Client Script" -Name $ScriptDef.name -Body $ScriptDef
    Write-Host "Client Script: $($Result.action)" -ForegroundColor Green
    
    Write-Host "`nDone! Item Names will now auto-fill when you select an Item Code." -ForegroundColor Cyan
    Write-Host "Refresh browser (Ctrl+F5) and try adding items." -ForegroundColor White
}
else {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $ScriptDef.name
    Write-Host "Client Script exists: $($null -ne $Existing)" -ForegroundColor Gray
}
