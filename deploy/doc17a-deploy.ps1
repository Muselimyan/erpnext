#Requires -Version 5.1
<#
.SYNOPSIS
    Doc 17A - Purchase Cost and Valuation deployment script.
    Creates:
      - Custom Field: Item-hs_code
      - Custom Field: Item-import_tax_rate
      - Client Script: LCV-import-duty-prefill (Landed Cost Voucher form)
.PARAMETER Mode
    Check  - report current state without making changes (default)
    Deploy - create / update all artefacts (idempotent)
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
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json))
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

# ---------------------------------------------------------------------------
# ARTEFACT DEFINITIONS
# ---------------------------------------------------------------------------

$CustomFields = @(
    [pscustomobject]@{
        name         = "Item-hs_code"
        dt           = "Item"
        fieldname    = "hs_code"
        label        = "HS Code"
        fieldtype    = "Data"
        insert_after = "brand"
        description  = "Harmonized System commodity code - determines import tax category."
    },
    [pscustomobject]@{
        name         = "Item-import_tax_rate"
        dt           = "Item"
        fieldname    = "import_tax_rate"
        label        = "Import Tax Rate (%)"
        fieldtype    = "Float"
        insert_after = "hs_code"
        description  = "Fixed import tax rate for this items HS code. Used to pre-fill LCV import duty."
    }
)

$LcvClientScript = @'
frappe.ui.form.on('Landed Cost Voucher', {
    refresh: function(frm) {
        if (frm.doc.docstatus === 0) {
            frm.add_custom_button(__('Pre-fill Import Duty'), function() {
                prefill_import_duty(frm);
            }, __('Tools'));
        }
    }
});

function prefill_import_duty(frm) {
    var items = frm.doc.items || [];
    if (!items.length) {
        frappe.msgprint(__('No items loaded. Add Purchase Receipts and click "Get Items from Purchase Receipts" first.'));
        return;
    }

    var item_codes = [];
    items.forEach(function(r) { if (r.item_code && item_codes.indexOf(r.item_code) === -1) item_codes.push(r.item_code); });

    frappe.call({
        method: 'frappe.client.get_list',
        args: {
            doctype: 'Item',
            filters: [['item_code', 'in', item_codes]],
            fields: ['item_code', 'import_tax_rate'],
            limit_page_length: 500
        },
        callback: function(r) {
            if (!r.message) return;

            var rate_map = {};
            (r.message || []).forEach(function(row) {
                rate_map[row.item_code] = flt(row.import_tax_rate) || 0;
            });

            var total_duty = 0;
            items.forEach(function(row) {
                var rate = rate_map[row.item_code] || 0;
                total_duty += flt(row.amount) * rate / 100.0;
            });
            total_duty = Math.round(total_duty * 100) / 100;

            if (total_duty <= 0) {
                frappe.msgprint(__('Import duty calculated as 0. Ensure import_tax_rate is set on the Item records in this receipt.'));
                return;
            }

            // Update existing Import Duty row or insert a new one
            var taxes = frm.doc.taxes || [];
            var existing = null;
            for (var i = 0; i < taxes.length; i++) {
                if (taxes[i].description === 'Import Duty') { existing = taxes[i]; break; }
            }

            if (existing) {
                frappe.model.set_value(existing.doctype, existing.name, 'amount', total_duty);
            } else {
                var row = frm.add_child('taxes');
                row.description = 'Import Duty';
                row.amount = total_duty;
            }
            frm.refresh_field('taxes');

            frappe.show_alert({
                message: __('Import Duty pre-filled: {0} AMD. Set Expense Account and confirm before submitting.', [format_number(total_duty)]),
                indicator: 'green'
            }, 8);
        }
    });
}
'@

# ---------------------------------------------------------------------------
# CHECK MODE
# ---------------------------------------------------------------------------
if ($Mode -eq "Check") {
    Write-Host "=== Doc 17A - Check Mode ==="
    $Results = [ordered]@{ mode="Check"; custom_fields=@(); client_scripts=@() }
    foreach ($f in $CustomFields) {
        $E = Get-ErpDoc -DocType "Custom Field" -Name $f.name
        $Results.custom_fields += [pscustomobject]@{ name=$f.name; exists=($null -ne $E) }
    }
    $E = Get-ErpDoc -DocType "Client Script" -Name "LCV-import-duty-prefill"
    $Results.client_scripts += [pscustomobject]@{ name="LCV-import-duty-prefill"; exists=($null -ne $E) }
    $Results | ConvertTo-Json -Depth 5
    return
}

# ---------------------------------------------------------------------------
# DEPLOY MODE
# ---------------------------------------------------------------------------
Write-Host "=== Doc 17A - Deploy Mode ==="
$Results = [ordered]@{ mode="Deploy"; custom_fields=@(); client_scripts=@() }

# -- Custom Fields --
foreach ($f in $CustomFields) {
    $Body = [ordered]@{
        dt           = $f.dt
        fieldname    = $f.fieldname
        label        = $f.label
        fieldtype    = $f.fieldtype
        insert_after = $f.insert_after
        description  = $f.description
    }
    try {
        $R = Upsert-ErpDoc -DocType "Custom Field" -Name $f.name -Body $Body
        $Results.custom_fields += $R
    } catch {
        $Results.custom_fields += [pscustomobject]@{ action="error"; name=$f.name; error=$_.Exception.Message }
    }
}

# -- Client Script: LCV import duty pre-fill --
$CsBody = [ordered]@{
    dt      = "Landed Cost Voucher"
    view    = "Form"
    enabled = 1
    script  = $LcvClientScript
}
try {
    $R = Upsert-ErpDoc -DocType "Client Script" -Name "LCV-import-duty-prefill" -Body $CsBody
    $Results.client_scripts += $R
} catch {
    $Results.client_scripts += [pscustomobject]@{ action="error"; name="LCV-import-duty-prefill"; error=$_.Exception.Message }
}

# ---------------------------------------------------------------------------
# OUTPUT + POST-DEPLOY VERIFICATION
# ---------------------------------------------------------------------------
$Results | ConvertTo-Json -Depth 10

Write-Host "`n=== Post-deploy verification ==="
$Snap = [ordered]@{ custom_fields=@(); client_scripts=@() }
foreach ($f in $CustomFields) {
    $E = Get-ErpDoc -DocType "Custom Field" -Name $f.name
    $Snap.custom_fields += [pscustomobject]@{ name=$f.name; exists=($null -ne $E) }
}
$E = Get-ErpDoc -DocType "Client Script" -Name "LCV-import-duty-prefill"
$Snap.client_scripts += [pscustomobject]@{ name="LCV-import-duty-prefill"; exists=($null -ne $E) }
$Snap | ConvertTo-Json -Depth 5
