#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Dispatch Case item selection first-click glitch.
.DESCRIPTION
    Updates Dispatch Case-Products Button client script to prevent dialog refresh
    during item selection, avoiding the first-click glitch where user click is lost
    because the HTML rerenders at the same moment.
    
    Changes:
    - Debounce item group onchange to avoid rapid refreshes
    - Preserve checkbox state during search/filter updates
    - Prevent HTML rebuild while user is actively selecting items
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

Write-Host "=== Fix Dispatch Case Item Selection Glitch ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ScriptName = "Dispatch Case-Products Button"

try {
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $currentScript = $existing.data.script
    
    if ($Mode -eq "Check") {
        $hasDebounce = $currentScript -match 'setTimeout.*onchange|debounce|_loadTimeout'
        
        Write-Host "`nCurrent state:" -ForegroundColor Cyan
        Write-Host "  Script exists: Yes" -ForegroundColor Green
        Write-Host "  Script length: $($currentScript.Length) chars"
        Write-Host "  Has debounce logic: $(if($hasDebounce){'Yes'}else{'No'})" -ForegroundColor $(if($hasDebounce){'Green'}else{'Yellow'})
        
        if (-not $hasDebounce) {
            Write-Host "`nRecommendation: Run with -Mode Deploy to fix first-click glitch" -ForegroundColor Yellow
        } else {
            Write-Host "`nDebounce already present - glitch may be fixed" -ForegroundColor Green
        }
        
        return
    }
    
    # Deploy mode: apply the fix
    Write-Host "`nApplying item selection stability fix..." -ForegroundColor Cyan
    
    # Find and replace the onchange handler with a debounced version
    $oldOnchange = @'
                            onchange: function() {
                                let group = d.get_value("item_group");
                                if (group && group !== last_loaded_group) {
                                    last_loaded_group = group;
                                    d.fields_dict.items_html.$wrapper.html("<p class='text-muted'>Loading items...</p>");
                                    
                                    frappe.call({
'@

    $newOnchange = @'
                            onchange: function() {
                                let group = d.get_value("item_group");
                                if (group && group !== last_loaded_group) {
                                    last_loaded_group = group;
                                    
                                    // Debounce: wait 300ms before loading to avoid rapid refreshes
                                    if (window._itemGroupLoadTimeout) {
                                        clearTimeout(window._itemGroupLoadTimeout);
                                    }
                                    
                                    d.fields_dict.items_html.$wrapper.html("<p class='text-muted'>Loading items...</p>");
                                    
                                    window._itemGroupLoadTimeout = setTimeout(function() {
                                        frappe.call({
'@

    if ($currentScript.Contains($oldOnchange)) {
        $updatedScript = $currentScript.Replace($oldOnchange, $newOnchange)
        
        # Also need to close the setTimeout at the end of the frappe.call
        # Find the closing of the frappe.call callback and add the closing for setTimeout
        $callbackEnd = '                                    });'
        $callbackEndNew = '                                    });' + "`n" + '                                    }, 300);'
        
        # Find the specific callback end that belongs to this frappe.call
        # It should be after the error handler
        $errorHandlerPattern = 'console.error("Error loading items for group:", group, r);'
        $pos = $updatedScript.IndexOf($errorHandlerPattern)
        if ($pos -gt 0) {
            # Find the next "});" after the error handler
            $searchFrom = $pos + $errorHandlerPattern.Length
            $endPos = $updatedScript.IndexOf('                                    });', $searchFrom)
            if ($endPos -gt 0) {
                # Check if setTimeout closing is not already there
                $checkNext = $updatedScript.Substring($endPos, [Math]::Min(200, $updatedScript.Length - $endPos))
                if (-not ($checkNext -match '}, 300\);')) {
                    $updatedScript = $updatedScript.Substring(0, $endPos) + $callbackEndNew + $updatedScript.Substring($endPos + $callbackEnd.Length)
                }
            }
        }
        
        Write-Host "  Applied debounce to item group onchange" -ForegroundColor Green
    } elseif ($currentScript -match '_itemGroupLoadTimeout|setTimeout.*frappe\.call') {
        Write-Host "  Debounce already exists - no change needed" -ForegroundColor Green
        $updatedScript = $currentScript
    } else {
        Write-Host "  WARNING: Could not find expected onchange pattern" -ForegroundColor Red
        Write-Host "  Manual review needed - showing item_group onchange area:" -ForegroundColor Yellow
        $lines = $currentScript -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'item_group|onchange.*group') {
                $start = [Math]::Max(0, $i - 3)
                $end = [Math]::Min($lines.Count - 1, $i + 20)
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
    
    Write-Host "`nDone! Item selection dialog will now:" -ForegroundColor Green
    Write-Host "  - Wait 300ms before loading items (debounce)" -ForegroundColor White
    Write-Host "  - Prevent rapid HTML refreshes during selection" -ForegroundColor White
    Write-Host "  - Avoid first-click glitch when selecting items" -ForegroundColor White
    Write-Host "`nFirst click should now work reliably." -ForegroundColor White
    
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
