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
Write-Host "=== Complete Task Fix v3 ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script

$hasOld = $script -match 'function doComplete\(\)'
$hasNew = $script -match 'var savePromise = frm\.is_dirty\(\) \? frm\.save\(\) : Promise\.resolve\(\);'
$hasTimeout = $script -match 'Complete Task timed out after 30 seconds'
$hasBusy = $script -match 'btn\.data\("busy"\)'

Write-Host "Old doComplete: $(if($hasOld){'Yes'}else{'No'})"
Write-Host "New savePromise: $(if($hasNew){'Yes'}else{'No'})"
Write-Host "Timeout failsafe: $(if($hasTimeout){'Yes'}else{'No'})"
Write-Host "Busy flag: $(if($hasBusy){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasNew -and $hasTimeout -and $hasBusy -and -not $hasOld) {
        Write-Host "Status: fixed" -ForegroundColor Green
    } else {
        Write-Host "Status: needs deploy" -ForegroundColor Yellow
    }
    return
}

$startMarker = '                btn.on("click", function() {'
$endMarker = '                statusField.$wrapper.append(btn);'
$start = $script.IndexOf($startMarker)
$end = $script.IndexOf($endMarker, $start)

if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
    throw "Could not locate Complete Task click handler block"
}

$newHandler = @'
                btn.on("click", function() {
                    if (btn.data("busy")) return;

                    var originalStatus = frm.doc.status;
                    var originalCompletedOn = frm.doc.completed_on;
                    btn.data("busy", true).prop("disabled", true).text("Saving...");

                    var timeoutId = setTimeout(function() {
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Timeout - Try Again");
                        frappe.show_alert({message: "Complete Task timed out after 30 seconds. Please try again.", indicator: "red"}, 10);
                    }, 30000);

                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }

                    var savePromise = frm.is_dirty() ? frm.save() : Promise.resolve();
                    savePromise.then(function() {
                            btn.text("Completing...");
                            frm.doc.status = "Completed";
                            if (!frm.doc.completed_on) {
                                frm.doc.completed_on = frappe.datetime.get_today();
                            }
                            frm.dirty();
                            return frm.save();
                        })
                        .then(function() {
                            clearTimeout(timeoutId);
                            btn.css("background-color", "#27ae60").text("Completed \u2713");
                            return frm.reload_doc();
                        })
                        .catch(function(err) {
                            frm.doc.status = originalStatus;
                            if (frm.doc.completed_on !== originalCompletedOn) {
                                frm.doc.completed_on = originalCompletedOn || "";
                            }
                            resetButton();
                            frappe.show_alert({message: "Failed: " + (err.message || err), indicator: "red"}, 10);
                        });
                });
'@

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_v3_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$updated = $script.Substring(0, $start) + $newHandler + $script.Substring($end)
$body = @{ script = $updated } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null

Write-Host "Complete Task v3 deployed" -ForegroundColor Green
