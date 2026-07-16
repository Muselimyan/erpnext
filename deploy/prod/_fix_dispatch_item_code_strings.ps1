$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Save-ClientScript([string]$Name, [string]$Dt, [string]$Script) {
    $body = @{
        doctype = "Client Script"
        name = $Name
        dt = $Dt
        view = "Form"
        enabled = 1
        script = $Script
    } | ConvertTo-Json -Depth 6 -Compress
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 10 | Out-Null
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "Updated Client Script: $Name" -ForegroundColor Green
    } catch {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "Created Client Script: $Name" -ForegroundColor Green
    }
}

$dispatchGuard = @'
frappe.ui.form.on("Dispatch Case", {
    before_save: function(frm) {
        (frm.doc.case_items || []).forEach(function(row) {
            if (row.item_code !== undefined && row.item_code !== null) {
                row.item_code = String(row.item_code);
            }
        });
    },
    validate: function(frm) {
        (frm.doc.case_items || []).forEach(function(row) {
            if (row.item_code !== undefined && row.item_code !== null) {
                row.item_code = String(row.item_code);
            }
        });
        frm.refresh_field("case_items");
    }
});
'@

$taskGuard = @'
frappe.ui.form.on("Task Product Line", {
    item_code: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
    },
    item_name: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_name !== undefined && row.item_name !== null) {
            row.item_name = String(row.item_name);
        }
    }
});

frappe.ui.form.on("Task", {
    validate: function(frm) {
        (frm.doc.custom_product_lines || []).forEach(function(row) {
            if (row.item_code !== undefined && row.item_code !== null) {
                row.item_code = String(row.item_code);
            }
            if (row.item_name !== undefined && row.item_name !== null) {
                row.item_name = String(row.item_name);
            }
        });
        frm.refresh_field("custom_product_lines");
    }
});
'@

Save-ClientScript -Name "Dispatch Case-Item Code String Guard" -Dt "Dispatch Case" -Script $dispatchGuard
Save-ClientScript -Name "Task Product Line-Item Code String Guard" -Dt "Task" -Script $taskGuard

Write-Host "Clearing cache..." -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 30 | Out-Null
    Write-Host "Cache cleared." -ForegroundColor Green
} catch {
    Write-Host "Cache clear failed/non-critical: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Done. Hard refresh ERPNext, then save the Dispatch Case again." -ForegroundColor Green
