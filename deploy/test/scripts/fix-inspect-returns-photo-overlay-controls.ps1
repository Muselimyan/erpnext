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
$BackupPath = Join-Path $PSScriptRoot ("_backup_Order_entry_barcode_hide_before_overlay_controls_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
Set-Content -Path $BackupPath -Value $Script -Encoding UTF8

$HelperStart = $Script.IndexOf("window.task_inspect_returns_preview_pack_photo = function(btn)")
if ($HelperStart -lt 0) { throw "Preview helper not found. No changes made." }
$HelperEnd = $Script.IndexOf("`n};", $HelperStart)
if ($HelperEnd -lt 0) {
    $HelperEnd = $Script.Length
} else {
    $HelperEnd = [Math]::Min($Script.Length, $HelperEnd + 4)
}

$NewHelper = @'
window.task_inspect_returns_preview_pack_photo = function(btn) {
    var url = btn && btn.getAttribute('data-pack-photo-url');
    var title = (btn && btn.getAttribute('data-pack-photo-title')) || 'Photo';
    if (!url) return false;
    $('#task-inspect-photo-fullscreen').remove();
    var zoom = 1;
    var overlay = $('<div id="task-inspect-photo-fullscreen" style="position:fixed;z-index:99999;left:0;top:0;width:100vw;height:100vh;background:rgba(0,0,0,0.94);display:flex;flex-direction:column;box-sizing:border-box;"></div>');
    var toolbar = $('<div style="flex:0 0 auto;display:flex;align-items:center;gap:8px;padding:10px;background:rgba(0,0,0,0.75);color:#fff;box-sizing:border-box;"></div>');
    var caption = $('<div style="flex:1;min-width:0;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>').text(title);
    var zoomOut = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">−</button>');
    var zoomIn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">+</button>');
    var reset = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 10px;font-weight:bold;">Reset</button>');
    var close = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 12px;font-weight:bold;">Close</button>');
    var viewport = $('<div style="flex:1 1 auto;overflow:auto;text-align:center;-webkit-overflow-scrolling:touch;touch-action:pan-x pan-y;display:flex;align-items:flex-start;justify-content:center;padding:12px;box-sizing:border-box;"></div>');
    var img = $('<img />').attr('src', url).attr('alt', title).css({maxWidth:'100%', width:'100%', height:'auto', objectFit:'contain', borderRadius:'6px', transformOrigin:'top center'});
    function applyZoom() {
        img.css({width:(zoom * 100) + '%', maxWidth:'none'});
    }
    zoomOut.on('click', function(e) { e.preventDefault(); e.stopPropagation(); zoom = Math.max(0.5, zoom - 0.25); applyZoom(); return false; });
    zoomIn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); zoom = Math.min(5, zoom + 0.25); applyZoom(); return false; });
    reset.on('click', function(e) { e.preventDefault(); e.stopPropagation(); zoom = 1; applyZoom(); viewport.scrollTop(0).scrollLeft(0); return false; });
    close.on('click', function(e) { e.preventDefault(); e.stopPropagation(); overlay.remove(); return false; });
    toolbar.append(caption).append(zoomOut).append(zoomIn).append(reset).append(close);
    viewport.append(img);
    overlay.append(toolbar).append(viewport);
    $('body').append(overlay);
    overlay.on('click', function(e) { if (e.target === overlay[0]) overlay.remove(); });
    return false;
};
'@

$Updated = $Script.Substring(0, $HelperStart) + $NewHelper + $Script.Substring($HelperEnd)
$Body = @{ script = $Updated } | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60 | Out-Null
Write-Host "Updated overlay controls on TEST only." -ForegroundColor Green
Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
