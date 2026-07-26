#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Dispatch Case item selection first-click/rerender glitch (v2).
.DESCRIPTION
    Designed for the current live script version that has search_items and
    dc_products_render_items(). Adds selected checkbox preservation and debounced
    search rerendering without changing Search & Add Item behavior.
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

Write-Host "=== Fix Dispatch Case Item Selection Glitch v2 ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ScriptName = "Dispatch Case-Products Button"

try {
    $existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)?fields=[`"name`",`"script`"]" -Headers $Headers -Method Get -TimeoutSec 30
    $script = $existing.data.script

    $hasFix = ($script -match 'let selected_items = \{\};') -and
              ($script -match '_dcProductsSearchTimeout') -and
              ($script -match 'dc_products_render_items\(dialog, items, query, selected_items\)') -and
              ($script -match 'selected_items\[item\.name\]')

    if ($Mode -eq "Check") {
        Write-Host "`nCurrent state:" -ForegroundColor Cyan
        Write-Host "  Script exists: Yes" -ForegroundColor Green
        Write-Host "  Script length: $($script.Length) chars"
        Write-Host "  Has selection preservation fix: $(if($hasFix){'Yes'}else{'No'})" -ForegroundColor $(if($hasFix){'Green'}else{'Yellow'})
        if (-not $hasFix) {
            Write-Host "`nRecommendation: Run with -Mode Deploy to apply v2 fix" -ForegroundColor Yellow
        }
        return
    }

    if ($hasFix) {
        Write-Host "`nSelection preservation fix already present - no change needed" -ForegroundColor Green
        return
    }

    Write-Host "`nApplying v2 item selection stability fix..." -ForegroundColor Cyan

    $script = $script.Replace('                let all_items = [];', "                let all_items = [];`r`n                let selected_items = {};")
    $script = $script.Replace('                                            dc_products_render_items(d, all_items, "");', '                                            dc_products_render_items(d, all_items, "", selected_items);')
    $script = $script.Replace('                                dc_products_render_items(d, all_items, query);', "                                if (window._dcProductsSearchTimeout) { clearTimeout(window._dcProductsSearchTimeout); }`r`n                                window._dcProductsSearchTimeout = setTimeout(function() {`r`n                                    dc_products_render_items(d, all_items, query, selected_items);`r`n                                }, 200);")
    $showReplacement = @'
                d.show();
                d.$wrapper.on("change", ".item-checkbox", function() {
                    let item_code = $(this).attr("data-item");
                    if (item_code) {
                        selected_items[item_code] = $(this).is(":checked");
                    }
                });
'@
    $script = $script.Replace('                d.show();', $showReplacement.TrimEnd())
    $script = $script.Replace('function dc_products_render_items(dialog, items, query) {', "function dc_products_render_items(dialog, items, query, selected_items) {`r`n    selected_items = selected_items || {};")

    $oldCheckbox = 'html += "<td><input type=''checkbox'' class=''item-checkbox'' style=''width:22px;height:22px;min-width:22px;min-height:22px;aspect-ratio:1/1;cursor:pointer'' data-item=''" + item.name + "'' data-item-name=''" + (item.item_name || item.name) + "'' data-price=''" + (item.standard_rate || 0) + "''></td>";'
    $newCheckbox = 'html += "<td><input type=''checkbox'' class=''item-checkbox'' style=''width:22px;height:22px;min-width:22px;min-height:22px;aspect-ratio:1/1;cursor:pointer'' " + (selected_items[item.name] ? "checked " : "") + "data-item=''" + item.name + "'' data-item-name=''" + (item.item_name || item.name) + "'' data-price=''" + (item.standard_rate || 0) + "''></td>";'

    $lastIndex = $script.LastIndexOf($oldCheckbox)
    if ($lastIndex -lt 0) {
        Write-Host "  ERROR: Could not find category-render checkbox line" -ForegroundColor Red
        return
    }
    $script = $script.Substring(0, $lastIndex) + $newCheckbox + $script.Substring($lastIndex + $oldCheckbox.Length)

    $body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null

    Write-Host "`nDone! Item category dialog now preserves checkbox selection across rerenders and debounces search." -ForegroundColor Green
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
