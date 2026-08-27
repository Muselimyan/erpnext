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
$Doc = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
$Script = [string]$Doc.data.script
$BackupPath = Join-Path $PSScriptRoot ("_backup_Order_entry_barcode_hide_before_no_download_overlay_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
Set-Content -Path $BackupPath -Value $Script -Encoding UTF8

$StartNeedle = "                    var html = '<div id=`"pack_prepare_preview_wrapper`""
$EndNeedle = '                    if (targetField && targetField.$wrapper)'
$Start = $Script.IndexOf($StartNeedle)
if ($Start -lt 0) { throw "Gallery HTML start not found. No changes made." }
$End = $Script.IndexOf($EndNeedle, $Start)
if ($End -lt 0) { throw "Gallery HTML end not found. No changes made." }

$NewGallery = @'
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
                        html += '<button type="button" class="btn btn-xs task-inspect-pack-photo-thumb" data-pack-photo-url="' + safeUrl + '" data-pack-photo-title="' + title + '" style="display:block;padding:0;border:0;background:transparent;line-height:0;">';
                        html += '<img src="' + safeUrl + '" title="' + title + '" style="width:76px;height:76px;object-fit:cover;border:1px solid #d1d8dd;border-radius:6px;background:#f8f9fa;cursor:pointer;" />';
                        html += '</button>';
                    });
                    html += '</div><div style="font-size:11px;color:#8d99a6;margin-top:6px;">Tap a photo to preview full size. Pinch to zoom on phone.</div></div>';
                    setTimeout(function() {
                        $('#pack_prepare_preview_wrapper').off('click.taskInspectPreview').on('click.taskInspectPreview', '.task-inspect-pack-photo-thumb', function(e) {
                            e.preventDefault();
                            e.stopPropagation();
                            if (window.task_inspect_returns_preview_pack_photo) window.task_inspect_returns_preview_pack_photo(this);
                            return false;
                        });
                    }, 0);

'@

$Updated = $Script.Substring(0, $Start) + $NewGallery + $Script.Substring($End)
$Helper = @'

window.task_inspect_returns_preview_pack_photo = function(btn) {
    var url = btn && btn.getAttribute('data-pack-photo-url');
    var title = (btn && btn.getAttribute('data-pack-photo-title')) || 'Photo';
    if (!url) return false;
    $('#task-inspect-photo-fullscreen').remove();
    var overlay = $('<div id="task-inspect-photo-fullscreen" style="position:fixed;z-index:99999;left:0;top:0;width:100vw;height:100vh;background:rgba(0,0,0,0.94);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:12px;box-sizing:border-box;"></div>');
    var close = $('<button type="button" style="position:absolute;right:12px;top:12px;z-index:2;background:#fff;color:#111;border:0;border-radius:18px;padding:7px 12px;font-weight:bold;">Close</button>');
    var caption = $('<div style="position:absolute;left:12px;top:14px;right:80px;color:#fff;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>').text(title);
    var scroll = $('<div style="width:100%;height:100%;overflow:auto;text-align:center;-webkit-overflow-scrolling:touch;touch-action:pan-x pan-y pinch-zoom;"></div>');
    var img = $('<img />').attr('src', url).attr('alt', title).css({maxWidth:'none', width:'100%', height:'auto', maxHeight:'none', objectFit:'contain', borderRadius:'6px'});
    scroll.append(img);
    overlay.append(close).append(caption).append(scroll);
    $('body').append(overlay);
    close.on('click', function(e) { e.preventDefault(); overlay.remove(); return false; });
    overlay.on('click', function(e) { if (e.target === overlay[0]) overlay.remove(); });
    return false;
};
'@

$HelperStart = $Updated.IndexOf("window.task_inspect_returns_preview_pack_photo = function(btn)")
if ($HelperStart -ge 0) {
    $Updated = $Updated.Substring(0, $HelperStart).TrimEnd() + $Helper
} else {
    $Updated += $Helper
}

$Body = @{ script = $Updated } | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60 | Out-Null
Write-Host "Patched no-download fullscreen overlay on TEST only." -ForegroundColor Green
Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
