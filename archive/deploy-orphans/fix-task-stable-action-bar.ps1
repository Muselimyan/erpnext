#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$Name = "Task-Accept Start"
Write-Host "=== Fix Task Stable Action Bar ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script
$hasBar = $script -match 'renderStableTaskActionBar'
Write-Host "Has stable action bar: $(if($hasBar){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasBar) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$helper = @'

function renderStableTaskActionBar(frm) {
    if (!frm || !frm.wrapper) return;
    var existing = $(frm.wrapper).find("#stable-task-action-bar");
    existing.remove();

    var subject = frm.doc.subject || frm.doc.name || "";
    var bar = $('<div id="stable-task-action-bar" style="margin:10px 0 14px 0;padding:10px 12px;border:1px solid #d1d8dd;border-radius:8px;background:#f8fafc;box-shadow:0 1px 3px rgba(0,0,0,0.06);"></div>');
    var subjectBox = $('<div style="font-size:13px;line-height:1.35;margin-bottom:8px;color:#1f2937;word-break:break-word;white-space:normal;"></div>');
    subjectBox.append($('<span style="font-weight:700;margin-right:6px;">Subject:</span>'));
    subjectBox.append($('<span></span>').text(subject));
    bar.append(subjectBox);

    var actions = $('<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;"></div>');
    var isOrderEntry = (frm.doc.task_kind === "Order entry");
    var operationalKinds = [
        "Order entry", "Pack / prepare items", "Dispatch picking / hand-off", "Delivery", "Return Call",
        "Pickup Returns", "Return drop-off at warehouse", "Returns processing / verification",
        "Returns restocking", "Invoice preparation / create invoice", "Debt Collection", "Debt Closure Approval", "Account details",
        "Discount Approval", "Purchase Approval", "Write-off Approval"
    ];

    function makeBtn(label, bg, color) {
        return $('<button type="button" class="btn btn-sm" style="background:' + bg + ';color:' + color + ';font-weight:700;border:none;border-radius:6px;padding:6px 12px;min-height:30px;"></button>').text(label);
    }

    if ((!frm.is_new() || isOrderEntry) && operationalKinds.includes(frm.doc.task_kind) && ["Open", "Working"].includes(frm.doc.status) && frm.doc.custom_accepted_by !== frappe.session.user) {
        var accept = makeBtn("Accept / Start Task", "#111827", "#fff");
        accept.on("click", function() {
            var doAccept = function() {
                frappe.call({
                    method: "dispatch_task_accept",
                    args: { task_name: frm.doc.name },
                    freeze: true,
                    freeze_message: __("Accepting task..."),
                    callback: function() { frm.reload_doc(); }
                });
            };
            if (frm.is_new() || frm.dirty()) {
                frm.save().then(function() { doAccept(); });
            } else {
                doAccept();
            }
        });
        actions.append(accept);
    }

    var productBtn = makeBtn("Products / Dispatch Work", "#eef2f7", "#111827");
    productBtn.css({"border":"1px solid #cbd5e1"});
    productBtn.on("click", function() {
        var target = $(frm.wrapper).find('.section-head:contains("Products / Dispatch Work")').first();
        if (target.length) {
            $('html, body').animate({scrollTop: target.offset().top - 90}, 250);
        } else {
            frappe.show_alert({message: "Products / Dispatch Work section is visible below.", indicator: "blue"}, 4);
        }
    });
    actions.append(productBtn);

    var save = makeBtn("Save", "#111827", "#fff");
    save.on("click", function() {
        save.prop("disabled", true).text("Saving...");
        frm.save().then(function() {
            save.prop("disabled", false).text("Save");
        }).catch(function() {
            save.prop("disabled", false).text("Save");
        });
    });
    actions.append(save);

    bar.append(actions);

    var formLayout = $(frm.wrapper).find(".form-layout").first();
    if (formLayout.length) {
        formLayout.prepend(bar);
    }
}
'@

if (-not $hasBar) {
    $script = $script + $helper
}

$refreshMarker = '    refresh(frm) {'
$insertCall = '        renderStableTaskActionBar(frm);'
if ($script -notmatch [regex]::Escape($insertCall)) {
    $idx = $script.IndexOf($refreshMarker)
    if ($idx -lt 0) { throw "Could not find refresh(frm) block" }
    $insertAt = $idx + $refreshMarker.Length
    $script = $script.Substring(0, $insertAt) + "`n" + $insertCall + $script.Substring($insertAt)
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_stable_bar_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Stable Task action bar deployed" -ForegroundColor Green
