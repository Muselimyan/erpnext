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
$BackupPath = Join-Path $PSScriptRoot ("_backup_Order_entry_barcode_hide_before_gesture_zoom_pan_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
Set-Content -Path $BackupPath -Value $Script -Encoding UTF8

$HelperStart = $Script.IndexOf("window.task_inspect_returns_preview_pack_photo = function(btn)")
if ($HelperStart -lt 0) { throw "Preview helper not found. No changes made." }
$HelperEnd = $Script.IndexOf("`n};", $HelperStart)
if ($HelperEnd -lt 0) { $HelperEnd = $Script.Length } else { $HelperEnd = [Math]::Min($Script.Length, $HelperEnd + 4) }

$NewHelper = @'
window.task_inspect_returns_preview_pack_photo = function(btn) {
    var url = btn && btn.getAttribute('data-pack-photo-url');
    var title = (btn && btn.getAttribute('data-pack-photo-title')) || 'Photo';
    if (!url) return false;
    $('#task-inspect-photo-fullscreen').remove();

    var scale = 1, minScale = 0.5, maxScale = 6, x = 0, y = 0;
    var pointers = {}, dragStart = null, pinchStart = null;
    var overlay = $('<div id="task-inspect-photo-fullscreen" style="position:fixed;z-index:99999;left:0;top:0;width:100vw;height:100vh;background:rgba(0,0,0,0.94);display:flex;flex-direction:column;box-sizing:border-box;overflow:hidden;"></div>');
    var toolbar = $('<div style="flex:0 0 auto;display:flex;align-items:center;gap:8px;padding:10px;background:rgba(0,0,0,0.75);color:#fff;box-sizing:border-box;z-index:2;"></div>');
    var caption = $('<div style="flex:1;min-width:0;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>').text(title);
    var zoomOut = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">−</button>');
    var zoomIn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">+</button>');
    var reset = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 10px;font-weight:bold;">Reset</button>');
    var close = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 12px;font-weight:bold;">Close</button>');
    var viewport = $('<div style="position:relative;flex:1 1 auto;overflow:hidden;touch-action:none;cursor:grab;background:#111;"></div>');
    var img = $('<img />').attr('src', url).attr('alt', title).css({position:'absolute', left:'50%', top:'50%', maxWidth:'96%', maxHeight:'96%', transformOrigin:'center center', userSelect:'none', webkitUserSelect:'none', touchAction:'none', borderRadius:'6px'});

    function clampScale(v) { return Math.max(minScale, Math.min(maxScale, v)); }
    function clampPan() {
        var rect = viewport[0].getBoundingClientRect();
        var baseW = img[0].clientWidth || rect.width;
        var baseH = img[0].clientHeight || rect.height;
        var visibleEdge = 80;
        var maxX = Math.max(visibleEdge, (baseW * scale + rect.width) / 2 - visibleEdge);
        var maxY = Math.max(visibleEdge, (baseH * scale + rect.height) / 2 - visibleEdge);
        x = Math.max(-maxX, Math.min(maxX, x));
        y = Math.max(-maxY, Math.min(maxY, y));
    }
    function applyTransform() { clampPan(); img.css('transform', 'translate(calc(-50% + ' + x + 'px), calc(-50% + ' + y + 'px)) scale(' + scale + ')'); }
    function zoomAt(newScale, cx, cy) {
        newScale = clampScale(newScale);
        var rect = viewport[0].getBoundingClientRect();
        var dx = cx - (rect.left + rect.width / 2) - x;
        var dy = cy - (rect.top + rect.height / 2) - y;
        var factor = newScale / scale;
        x -= dx * (factor - 1);
        y -= dy * (factor - 1);
        scale = newScale;
        applyTransform();
    }
    function pointDistance(a, b) { var dx = a.clientX - b.clientX, dy = a.clientY - b.clientY; return Math.sqrt(dx * dx + dy * dy); }
    function pointMid(a, b) { return { clientX: (a.clientX + b.clientX) / 2, clientY: (a.clientY + b.clientY) / 2 }; }

    zoomOut.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale - 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
    zoomIn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale + 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
    reset.on('click', function(e) { e.preventDefault(); e.stopPropagation(); scale = 1; x = 0; y = 0; applyTransform(); return false; });
    close.on('click', function(e) { e.preventDefault(); e.stopPropagation(); overlay.remove(); return false; });
    viewport.on('wheel', function(e) { e.preventDefault(); var oe = e.originalEvent; zoomAt(scale * (oe.deltaY < 0 ? 1.12 : 0.88), oe.clientX, oe.clientY); return false; });
    viewport.on('pointerdown', function(e) {
        e.preventDefault(); viewport[0].setPointerCapture(e.originalEvent.pointerId); pointers[e.originalEvent.pointerId] = e.originalEvent;
        var ids = Object.keys(pointers);
        if (ids.length === 1) { dragStart = { clientX: e.originalEvent.clientX, clientY: e.originalEvent.clientY, x: x, y: y }; viewport.css('cursor', 'grabbing'); }
        if (ids.length === 2) { var p1 = pointers[ids[0]], p2 = pointers[ids[1]]; pinchStart = { dist: pointDistance(p1, p2), scale: scale, x: x, y: y, mid: pointMid(p1, p2) }; }
        return false;
    });
    viewport.on('pointermove', function(e) {
        if (!pointers[e.originalEvent.pointerId]) return false;
        pointers[e.originalEvent.pointerId] = e.originalEvent;
        var ids = Object.keys(pointers);
        if (ids.length >= 2 && pinchStart) {
            var p1 = pointers[ids[0]], p2 = pointers[ids[1]], mid = pointMid(p1, p2);
            x = pinchStart.x + (mid.clientX - pinchStart.mid.clientX);
            y = pinchStart.y + (mid.clientY - pinchStart.mid.clientY);
            scale = clampScale(pinchStart.scale * (pointDistance(p1, p2) / pinchStart.dist));
            applyTransform();
        } else if (ids.length === 1 && dragStart) {
            x = dragStart.x + (e.originalEvent.clientX - dragStart.clientX);
            y = dragStart.y + (e.originalEvent.clientY - dragStart.clientY);
            applyTransform();
        }
        return false;
    });
    viewport.on('pointerup pointercancel pointerleave', function(e) {
        delete pointers[e.originalEvent.pointerId];
        viewport.css('cursor', 'grab');
        dragStart = null;
        pinchStart = null;
        var ids = Object.keys(pointers);
        if (ids.length === 1) { var p = pointers[ids[0]]; dragStart = { clientX: p.clientX, clientY: p.clientY, x: x, y: y }; }
        return false;
    });

    toolbar.append(caption).append(zoomOut).append(zoomIn).append(reset).append(close);
    viewport.append(img);
    overlay.append(toolbar).append(viewport);
    $('body').append(overlay);
    applyTransform();
    return false;
};
'@

$Updated = $Script.Substring(0, $HelperStart) + $NewHelper + $Script.Substring($HelperEnd)
$Body = @{ script = $Updated } | ConvertTo-Json -Depth 20 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 60 | Out-Null
Write-Host "Updated gesture zoom/pan overlay on TEST only." -ForegroundColor Green
Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
