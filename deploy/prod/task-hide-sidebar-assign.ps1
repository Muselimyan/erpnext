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

Write-Host "=== Task - Hide Sidebar Assignment UI ===" -ForegroundColor Cyan

$ClientScriptName = "Task-Hide Sidebar Assignment"
$ClientScriptBody = @'
frappe.ui.form.on("Task", {
    refresh(frm) {
        hide_all_assignment_ui(frm);
    },
    
    after_save(frm) {
        // Hide assignment UI again after save (ERPNext rebuilds sidebar after save)
        hide_all_assignment_ui(frm);
    },
    
    before_save(frm) {
        // Auto-assign to current user if not assigned
        if (frm.is_new() && !frm.doc.custom_assign_to) {
            frm.set_value('custom_assign_to', frappe.session.user);
        }
    }
});

function hide_all_assignment_ui(frm) {
    // Hide ALL assignment UI - sidebar and any assign_to fields
    if (frm.sidebar && frm.sidebar.assigned_to_me) {
        frm.sidebar.assigned_to_me.wrapper.hide();
    }
    
    // Hide all assignment-related UI everywhere
    setTimeout(function() {
        // Hide sidebar sections
        $('[data-fieldname="assign_to"]').closest('.form-sidebar-item').hide();
        $('.assignments-section').hide();
        $('.sidebar-section.assignments').hide();
        $('.form-assignments').hide();
        $('.sidebar-label:contains("Assigned To")').closest('.form-sidebar-item').hide();
        
        // Hide any "Assign To" or "Assigned To" field in the form
        $('[data-fieldname="assign_to"]').hide();
        $('.frappe-control[data-fieldname="assign_to"]').hide();
        
        // Hide by label text "Assigned To" (catches any field with this label)
        $('.form-group').each(function() {
            var label = $(this).find('.control-label').text().trim();
            if (label === 'Assigned To' || label === 'Assign To') {
                $(this).hide();
            }
        });
    }, 100);
    
    // If there's a standard assign_to field, hide it
    if (frm.fields_dict.assign_to) {
        frm.set_df_property('assign_to', 'hidden', 1);
    }
    
    // Hide any field with "assigned" in the fieldname, INCLUDING custom_assign_to
    Object.keys(frm.fields_dict).forEach(function(fieldname) {
        if (fieldname.toLowerCase().includes('assign')) {
            frm.set_df_property(fieldname, 'hidden', 1);
        }
    });
}
'@

$ScriptDef = [ordered]@{
    name = $ClientScriptName
    dt = "Task"
    enabled = 1
    script_type = "Form"
    script = $ClientScriptBody
}

if ($Mode -eq "Deploy") {
    try {
        $Result = Upsert-ErpDoc -DocType "Client Script" -Name $ClientScriptName -Body $ScriptDef
        Write-Host "Client Script: $($Result.action)" -ForegroundColor Green
        
        [ordered]@{
            mode = "Deploy"
            client_script = $Result
        } | ConvertTo-Json -Depth 10
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
        throw
    }
} else {
    $Existing = Get-ErpDoc -DocType "Client Script" -Name $ClientScriptName
    [ordered]@{
        mode = "Check"
        client_script = [ordered]@{
            name = $ClientScriptName
            exists = ($null -ne $Existing)
        }
    } | ConvertTo-Json -Depth 10
}

Write-Host "`nDone! The sidebar assignment UI will be hidden." -ForegroundColor Cyan
Write-Host "Users should use the 'Assign To (User Email)' field in the form instead." -ForegroundColor White
