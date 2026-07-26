#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Complete Task button to save first, then complete, with timeout failsafe.
.DESCRIPTION
    Current Complete Task button can hang indefinitely because frm.set_value() 
    promises don't resolve properly in some ERPNext versions.
    
    This fix:
    1. Saves current edits first
    2. Sets completion fields directly (synchronous)
    3. Saves completion
    4. Adds 30-second timeout failsafe
    5. Prevents double-clicks with busy flag
    
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — apply fix (idempotent)
.PARAMETER Target
    test — deploy to https://test.erpnext.am (default)
    main — deploy to https://erpnext.am
#>
param(
    [ValidateSet("Check","Deploy")]
    [string]$Mode = "Check",
    
    [ValidateSet("test","main")]
    [string]$Target = "test"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value

$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "=== Fix Complete Task Button (v2 with Failsafe) ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ClientScriptName = "Task-Accept Start"

if ($Mode -eq "Check") {
    Write-Host "`nChecking current state..." -ForegroundColor Cyan
    
    try {
        $data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ClientScriptName)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 25).data
        $script = $data.script
        
        $hasOldDoComplete = $script -match 'function doComplete\(\)'
        $hasDirectAssignment = $script -match 'frm\.doc\.status = "Completed"'
        $hasTimeoutFailsafe = $script -match 'setTimeout.*resetButton.*30000'
        $hasBusyFlag = $script -match 'if \(btn\.data\("busy"\)\) return'
        
        Write-Host "`nComplete Task button logic:" -ForegroundColor Cyan
        Write-Host "  Has old nested doComplete: $(if($hasOldDoComplete){'Yes - NEEDS FIX'}else{'No - OK'})" -ForegroundColor $(if($hasOldDoComplete){'Yellow'}else{'Green'})
        Write-Host "  Uses direct status assignment: $(if($hasDirectAssignment){'Yes - OK'}else{'No - NEEDS FIX'})" -ForegroundColor $(if($hasDirectAssignment){'Green'}else{'Yellow'})
        Write-Host "  Has timeout failsafe: $(if($hasTimeoutFailsafe){'Yes - OK'}else{'No - NEEDS FIX'})" -ForegroundColor $(if($hasTimeoutFailsafe){'Green'}else{'Yellow'})
        Write-Host "  Has busy flag: $(if($hasBusyFlag){'Yes - OK'}else{'No - NEEDS FIX'})" -ForegroundColor $(if($hasBusyFlag){'Green'}else{'Yellow'})
        
        if ($hasOldDoComplete -or -not $hasDirectAssignment -or -not $hasTimeoutFailsafe -or -not $hasBusyFlag) {
            Write-Host "`nRecommendation: Run with -Mode Deploy to apply fix" -ForegroundColor Yellow
        } else {
            Write-Host "`nStatus: Fix already applied" -ForegroundColor Green
        }
    } catch {
        Write-Host "`nERROR: $_" -ForegroundColor Red
    }
    
    return
}

# Deploy mode
Write-Host "`nApplying Complete Task fix..." -ForegroundColor Cyan

try {
    $data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ClientScriptName)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    $script = $data.script
    
    # Create backup
    $backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_v2_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".js")
    $script | Set-Content -Path $backupPath -Encoding UTF8
    Write-Host "Backup saved: $backupPath" -ForegroundColor Green
    
    # Define old pattern (the problematic nested doComplete with set_value promises)
    $oldPattern = @'
                btn.on("click", function() {
                    var originalStatus = frm.doc.status;
                    btn.prop("disabled", true).text("Saving...");
                    function doComplete() {
                        frm.set_value("status", "Completed");
                        if (!frm.doc.completed_on) {
                            frm.set_value("completed_on", frappe.datetime.get_today());
                        }
                        frm.save().then(function() {
                            btn.css("background-color", "#27ae60").text("Completed \u2713");
                            frm.reload_doc();
                        }).catch(function() {
                            frm.set_value("status", originalStatus);
                            btn.prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                        });
                    }
                    // Always save current field values first, then complete
                    frm.save().then(function() {
                        doComplete();
                    }).catch(function() {
                        btn.prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    });
                });
'@
    
    # Define new pattern (direct assignment, timeout failsafe, busy flag)
    $newPattern = @'
                btn.on("click", function() {
                    // Prevent double-clicks
                    if (btn.data("busy")) return;
                    
                    var originalStatus = frm.doc.status;
                    var originalCompletedOn = frm.doc.completed_on;
                    btn.data("busy", true).prop("disabled", true).text("Saving...");
                    
                    // Timeout failsafe: if button stays disabled for 30 seconds, reset it
                    var timeoutId = setTimeout(function() {
                        console.error("[CompleteTask] Timeout after 30 seconds");
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task (Timeout)");
                        frappe.show_alert({message: "Complete Task timed out. Please try again or contact support.", indicator: "red"}, 10);
                    }, 30000);
                    
                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }
                    
                    // Save current edits first, then set completion fields directly, then save completion
                    frm.save()
                        .then(function() {
                            btn.text("Completing...");
                            // Direct assignment (synchronous) to avoid promise issues
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
                            console.error("[CompleteTask] Error:", err);
                            // Restore original values
                            frm.doc.status = originalStatus;
                            if (frm.doc.completed_on !== originalCompletedOn) {
                                frm.doc.completed_on = originalCompletedOn || "";
                            }
                            resetButton();
                            frappe.show_alert({message: "Failed to complete task: " + (err.message || err), indicator: "red"}, 10);
                        });
                });
'@
    
    if (-not $script.Contains($oldPattern)) {
        Write-Host "WARNING: Could not find expected old pattern. Script may have already been modified." -ForegroundColor Yellow
        Write-Host "Current button click handler will be preserved." -ForegroundColor Yellow
        return
    }
    
    $updatedScript = $script.Replace($oldPattern, $newPattern)
    
    $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ClientScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    
    Write-Host "`nComplete Task button fixed with:" -ForegroundColor Green
    Write-Host "  - Direct status assignment (no promise issues)" -ForegroundColor White
    Write-Host "  - 30-second timeout failsafe" -ForegroundColor White
    Write-Host "  - Busy flag prevents double-clicks" -ForegroundColor White
    Write-Host "  - Error recovery with user alerts" -ForegroundColor White
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
}
