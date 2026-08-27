$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "Patching live Client Scripts that can turn item codes into numbers..." -ForegroundColor Cyan
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?fields=%5B%22name%22%2C%22dt%22%2C%22script%22%5D&limit_page_length=300" -Headers $Headers -Method Get -TimeoutSec 60
$patched = 0
foreach ($cs in $r.data) {
    $script = [string]$cs.script
    if (-not $script) { continue }
    $new = $script
    $new = $new -replace '\.data\("item"\)', '.attr("data-item")'
    $new = $new -replace "\.data\('item'\)", ".attr('data-item')"
    $new = $new -replace 'row\.item_code\s*=\s*item\.item_code\s*;', 'row.item_code = String(item.item_code || "");'
    $new = $new -replace 'nr\.item_code\s*=\s*row\.item\s*;', 'nr.item_code = String(row.item || "");'
    $new = $new -replace 'child\.item_code\s*=\s*item_code\s*;', 'child.item_code = String(item_code || "");'
    $new = $new -replace 'let item_code\s*=\s*line\.item_code \|\| line\.item_name\s*;', 'let item_code = String(line.item_code || line.item_name || "");'
    $new = $new -replace 'var item_code\s*=\s*line\.item_code \|\| line\.item_name\s*;', 'var item_code = String(line.item_code || line.item_name || "");'
    $new = $new -replace 'line => line\.item_code \|\| line\.item_name', 'line => String(line.item_code || line.item_name || "")'
    $new = $new -replace 'item_code:\s*\$\(this\)\.data\("item"\)', 'item_code: $(this).attr("data-item")'
    $new = $new -replace "item_code:\s*\`$\(this\)\.data\('item'\)", 'item_code: $(this).attr(''data-item'')'
    if ($new -ne $script) {
        $body = @{ script = $new } | ConvertTo-Json -Depth 5 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $cs.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
        Write-Host "  patched: $($cs.name)" -ForegroundColor Green
        $patched++
    }
}
Write-Host "Patched $patched Client Script(s)." -ForegroundColor Green

$guardName = "Dispatch Case-Item Code String Guard"
$dispatchGuard = @'
function dispatch_case_stringify_item_codes(frm) {
    (frm.doc.case_items || []).forEach(function(row) {
        if (row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
        if (row.item_name !== undefined && row.item_name !== null) {
            row.item_name = String(row.item_name);
        }
    });
}

frappe.ui.form.on("Dispatch Case", {
    before_save: function(frm) {
        dispatch_case_stringify_item_codes(frm);
    },
    validate: function(frm) {
        dispatch_case_stringify_item_codes(frm);
        frm.refresh_field("case_items");
    }
});

frappe.ui.form.on("Dispatch Case Item", {
    item_code: function(frm, cdt, cdn) {
        var row = locals[cdt][cdn];
        if (row && row.item_code !== undefined && row.item_code !== null) {
            row.item_code = String(row.item_code);
        }
    },
    case_items_add: function(frm) {
        dispatch_case_stringify_item_codes(frm);
    }
});
'@
$body = @{ doctype="Client Script"; name=$guardName; dt="Dispatch Case"; view="Form"; enabled=1; script=$dispatchGuard } | ConvertTo-Json -Depth 6 -Compress
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $guardName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Updated guard: $guardName" -ForegroundColor Green
} catch {
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Created guard: $guardName" -ForegroundColor Green
}

Write-Host "Re-saving patched Client Scripts completed. Hard refresh ERPNext before testing." -ForegroundColor Green
