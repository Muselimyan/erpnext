#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Complete Task button to always save current changes first, then complete.
.DESCRIPTION
    Updates Task-Accept Start client script to guarantee Complete Task button:
    1. Saves current field changes
    2. If save succeeds, sets status = Completed
    3. Saves again (triggers server validation/workflow)
    4. Reloads form
    If validation fails at any step, completion stops and task remains open.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — update the script (idempotent)
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

Write-Host "=== Fix Complete Task Save-First Behavior ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ScriptName = "Task-Accept Start"

try {
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $currentScript = $existing.data.script
    
    if ($Mode -eq "Check") {
        # Check if the fix is already applied
        $hasCorrectBehavior = $currentScript -match 'frm\.save\(\)\.then\(function\(\) \{\s*doComplete\(\);'
        
        Write-Host "`nCurrent state:" -ForegroundColor Cyan
        Write-Host "  Script exists: Yes" -ForegroundColor Green
        Write-Host "  Script length: $($currentScript.Length) chars"
        Write-Host "  Has save-first logic: $(if($hasCorrectBehavior){'Yes'}else{'No'})" -ForegroundColor $(if($hasCorrectBehavior){'Green'}else{'Yellow'})
        
        if (-not $hasCorrectBehavior) {
            Write-Host "`nRecommendation: Run with -Mode Deploy to apply fix" -ForegroundColor Yellow
        } else {
            Write-Host "`nNo changes needed - correct behavior already present" -ForegroundColor Green
        }
        
        return
    }
    
    # Deploy mode: apply the fix
    Write-Host "`nApplying Complete Task save-first fix..." -ForegroundColor Cyan
    
    # The fix: ensure Complete Task button always calls frm.save() first, then doComplete()
    # Pattern to find: the Complete Task button click handler
    # We need to ensure it ALWAYS saves first, not just when dirty
    
    $oldPattern = @'
                    if (frm.dirty()) {
                        frm.save().then(function() { doComplete(); }).catch(function() {
                            btn.prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                        });
                    } else {
                        doComplete();
                    }
'@

    $newPattern = @'
                    // Always save current field values first, then complete
                    frm.save().then(function() {
                        doComplete();
                    }).catch(function() {
                        btn.prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    });
'@

    if ($currentScript.Contains($oldPattern)) {
        $updatedScript = $currentScript.Replace($oldPattern, $newPattern)
        Write-Host "  Found and replaced conditional save pattern" -ForegroundColor Green
    } elseif ($currentScript -match 'frm\.save\(\)\.then\(function\(\) \{\s*doComplete\(\);') {
        Write-Host "  Correct pattern already exists - no change needed" -ForegroundColor Green
        $updatedScript = $currentScript
    } else {
        Write-Host "  WARNING: Could not find expected pattern - manual review needed" -ForegroundColor Red
        Write-Host "  Showing Complete Task button area:" -ForegroundColor Yellow
        $lines = $currentScript -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'complete-task-btn|doComplete') {
                $start = [Math]::Max(0, $i - 5)
                $end = [Math]::Min($lines.Count - 1, $i + 15)
                for ($j = $start; $j -le $end; $j++) {
                    Write-Host "  $($j+1): $($lines[$j])"
                }
                break
            }
        }
        return
    }
    
    # Update the script
    $body = @{ script = $updatedScript } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    
    Write-Host "`nDone! Complete Task button will now:" -ForegroundColor Green
    Write-Host "  1. Save current changes" -ForegroundColor White
    Write-Host "  2. Set status = Completed" -ForegroundColor White
    Write-Host "  3. Save again (triggers validation)" -ForegroundColor White
    Write-Host "  4. Reload form" -ForegroundColor White
    Write-Host "`nIf validation fails, task stays open with error message." -ForegroundColor White
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
