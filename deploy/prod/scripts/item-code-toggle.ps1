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
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

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

Write-Host "=== Item Code Toggle - Show/Hide Item Codes ===" -ForegroundColor Cyan

# Client script for Dispatch Case
$DispatchCaseScript = @'
frappe.ui.form.on("Dispatch Case", {
    refresh: function(frm) {
        // Store toggle state on form object
        if (frm._item_code_visible === undefined) {
            frm._item_code_visible = false;
        }
        
        // Add toggle button for Item Codes
        if (!frm.is_new()) {
            // Remove existing toggle button if present
            frm.page.btn_secondary.find('.btn-show-item-codes').remove();
            
            // Add toggle button to toolbar
            let btn = frm.page.add_inner_button(__('Show Item Codes'), function() {
                frm._item_code_visible = !frm._item_code_visible;
                toggle_item_code_visibility(frm);
                
                // Update button text and appearance
                if (frm._item_code_visible) {
                    $(btn).text(__('Hide Item Codes'));
                    $(btn).removeClass('btn-default').addClass('btn-primary');
                } else {
                    $(btn).text(__('Show Item Codes'));
                    $(btn).removeClass('btn-primary').addClass('btn-default');
                }
            }).addClass('btn-show-item-codes');
            
            // Initialize - hide Item Codes by default
            setTimeout(function() {
                toggle_item_code_visibility(frm);
            }, 300);
        }
    }
});

function toggle_item_code_visibility(frm) {
    if (!frm.fields_dict.case_items || !frm.fields_dict.case_items.grid) {
        console.log("No case_items grid found");
        return;
    }
    
    let grid = frm.fields_dict.case_items.grid;
    let show = frm._item_code_visible || false;
    
    console.log("Toggle item_code visibility:", show);
    
    // Method 1: Try using grid.update_docfield_property
    try {
        grid.update_docfield_property('item_code', 'hidden', show ? 0 : 1);
        grid.update_docfield_property('item_code', 'in_list_view', show ? 1 : 0);
        console.log("Updated docfield properties");
    } catch(e) {
        console.log("Method 1 failed:", e);
    }
    
    // Method 2: Direct jQuery manipulation
    setTimeout(function() {
        let wrapper = frm.fields_dict.case_items.wrapper;
        if (show) {
            $(wrapper).find('[data-fieldname="item_code"]').show();
            console.log("Showing item_code columns");
        } else {
            $(wrapper).find('[data-fieldname="item_code"]').hide();
            console.log("Hiding item_code columns");
        }
    }, 100);
    
    // Method 3: Refresh grid
    grid.refresh();
}
'@

$ClientScripts = @(
    [pscustomobject]@{
        name = "Dispatch Case-Item Code Toggle"
        dt = "Dispatch Case"
        script = $DispatchCaseScript
    }
)

$Report = [ordered]@{ mode=$Mode; client_scripts=@() }

if ($Mode -eq "Deploy") {
    foreach ($Script in $ClientScripts) {
        $ScriptDef = [ordered]@{
            name = $Script.name
            dt = $Script.dt
            enabled = 1
            script_type = "Form"
            script = $Script.script
        }
        
        $Result = Upsert-ErpDoc -DocType "Client Script" -Name $Script.name -Body $ScriptDef
        $Report.client_scripts += $Result
        Write-Host "Client Script '$($Script.name)': $($Result.action)" -ForegroundColor Green
    }
    
    $Report | ConvertTo-Json -Depth 10
} else {
    foreach ($Script in $ClientScripts) {
        $Existing = Get-ErpDoc -DocType "Client Script" -Name $Script.name
        $Report.client_scripts += [ordered]@{
            name = $Script.name
            exists = ($null -ne $Existing)
        }
    }
    $Report | ConvertTo-Json -Depth 10
}

Write-Host "`n=== Done! ===" -ForegroundColor Cyan
Write-Host "Dispatch Case now has a 'Show Item Codes' toggle above the items table." -ForegroundColor White
Write-Host "- Default: Item Codes HIDDEN (clean view)" -ForegroundColor White
Write-Host "- Toggle ON: Item Codes VISIBLE (technical view)" -ForegroundColor White
Write-Host "- Resets on page refresh (non-persistent)" -ForegroundColor White
