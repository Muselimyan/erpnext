#Requires -Version 5.1
Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = "https://test.erpnext.am"
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$ScriptName = "Order entry - barcode scanning section - hide"
$Existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`",`"enabled`"]" -Headers $Headers -Method Get -TimeoutSec 30
$Script = [string]$Existing.data.script

$Old = @'
                    var html = '<div id="pack_prepare_preview_wrapper" style="margin-top:15px;padding:10px;border:1px solid #d1d8dd;border-radius:4px;background:#fafbfc;">';
                    html += '<label class="control-label" style="color:#6c757d;font-weight:bold;margin-bottom:8px;display:block;">Pack / Prepare Photos (' + files.length + ')</label>';
                    html += '<div style="display:flex;flex-wrap:wrap;gap:10px;">';
                    files.forEach(function(f) {
                        html += '<div style="position:relative;">';
                        html += '<img src="' + f.file_url + '" title="' + frappe.utils.escape_html(f.file_name || '') + '" style="max-width:380px;max-height:380px;border:1px solid #eaeaea;border-radius:4px;cursor:pointer;" onclick="window.open(this.src)" />';
                        html += '</div>';
                    });
                    html += '</div></div>';
'@

$Current = @'
                    var html = '<div id="pack_prepare_preview_wrapper" style="margin-top:12px;margin-bottom:12px;padding:10px;border:1px solid #d1d8dd;border-radius:6px;background:#fafbfc;max-width:100%;overflow:hidden;">';
                    html += '<label class="control-label" style="color:#6c757d;font-weight:bold;margin-bottom:8px;display:block;">Pack / Prepare Photos (' + files.length + ')</label>';
                    html += '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start;max-width:100%;">';
                    files.forEach(function(f) {
                        var url = f.file_url || '';
                        var title = frappe.utils.escape_html(f.file_name || 'Photo');
                        if (url.indexOf('/private/files/') === 0) {
                            url = '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
                        }
                        html += '<a href="' + url + '" target="_blank" style="display:block;text-decoration:none;line-height:0;">';
                        html += '<img src="' + url + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;cursor:pointer;" />';
                        html += '</a>';
                    });
                    html += '</div><div style="font-size:11px;color:#8d99a6;margin-top:6px;">Tap a photo to open full size.</div></div>';
'@

$New = @'
                    var html = '<div id="pack_prepare_preview_wrapper" style="margin-top:12px;margin-bottom:12px;padding:10px;border:1px solid #d1d8dd;border-radius:6px;background:#fafbfc;max-width:100%;overflow:hidden;">';
                    html += '<label class="control-label" style="color:#6c757d;font-weight:bold;margin-bottom:8px;display:block;">Pack / Prepare Photos (' + files.length + ')</label>';
                    html += '<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:flex-start;max-width:100%;">';
                    files.forEach(function(f) {
                        var url = f.file_url || '';
                        var title = frappe.utils.escape_html(f.file_name || 'Photo');
                        if (url.indexOf('/private/files/') === 0) {
                            url = '/api/method/frappe.utils.file_manager.download_file?file_url=' + encodeURIComponent(url);
                        }
                        var safeUrl = frappe.utils.escape_html(url);
                        html += '<button type="button" class="btn btn-xs" data-pack-photo-url="' + safeUrl + '" data-pack-photo-title="' + title + '" onclick="window.task_inspect_returns_preview_pack_photo(this)" style="display:block;padding:0;border:0;background:transparent;line-height:0;">';
                        html += '<img src="' + safeUrl + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;cursor:pointer;" />';
                        html += '</button>';
                    });
                    html += '</div><div style="font-size:11px;color:#8d99a6;margin-top:6px;">Tap a photo to preview full size.</div></div>';
'@

if ($Script -match 'data-pack-photo-url') {
    Write-Host "Inspect Returns pack photo gallery already opens an in-page preview on $BaseUrl" -ForegroundColor Green
    return
}
if ($Script.Contains($Current)) {
    $Old = $Current
} elseif (-not $Script.Contains($Old)) {
    throw "Expected Pack / Prepare photo gallery block not found. No changes made."
}

$BackupPath = Join-Path $PSScriptRoot ("_backup_Order_entry_barcode_hide_before_inspect_gallery_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
Set-Content -Path $BackupPath -Value $Script -Encoding UTF8
$Updated = $Script.Replace($Old, $New)
if ($Updated -notmatch 'frappe\.msgprint\(\{') {
    $Updated += @'

window.task_inspect_returns_preview_pack_photo = function(btn) {
    var url = btn && btn.getAttribute('data-pack-photo-url');
    var title = (btn && btn.getAttribute('data-pack-photo-title')) || 'Photo';
    if (!url) return;
    frappe.msgprint({
        title: title,
        wide: true,
        message: '<div style="text-align:center;width:100%;"><img src="' + url + '" style="max-width:100%;max-height:80vh;object-fit:contain;border-radius:6px;" /></div>'
    });
};
'@
}
$Body = @{ script = $Updated } | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60 | Out-Null
Write-Host "Updated Inspect Returns Pack / Prepare photo gallery on TEST only." -ForegroundColor Green
Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
