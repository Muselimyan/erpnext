#Requires -Version 5.1
# Probe: verify ListView.method and ListView.get_args exist on Frappe v16.14.0.
# Creates a temporary Client Script, waits for user to check console, then deletes it.
param(
    [ValidateSet("Deploy", "Delete")]
    [string]$Mode = "Deploy"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path (Split-Path $PSScriptRoot) "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
if ($BaseUrl -ne "https://test.erpnext.am") { throw "Refusing non-test target: $BaseUrl" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }

$ScriptName = "_PROBE-ListView-API"

if ($Mode -eq "Deploy") {
    Write-Host "=== Deploying ListView API Probe ===" -ForegroundColor Cyan
    Write-Host "Target: $BaseUrl" -ForegroundColor Yellow

    $ProbeJS = @"
frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
var _probeOrig = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(lv) {
    if (_probeOrig) _probeOrig(lv);
    console.log('[PROBE] listview.method =', typeof lv.method, JSON.stringify(lv.method));
    console.log('[PROBE] listview.get_args =', typeof lv.get_args);
    console.log('[PROBE] listview.get_call_args =', typeof lv.get_call_args);
    console.log('[PROBE] listview.freeze_on_refresh =', lv.freeze_on_refresh);
    console.log('[PROBE] listview.start =', lv.start, 'page_length =', lv.page_length);
    console.log('[PROBE] get_args() sample =', JSON.stringify(lv.get_args()).substring(0, 500));
    frappe.show_alert({message: 'ListView probe complete - check browser console (F12)', indicator: 'blue'}, 10);
};
"@

    # Check if it already exists
    try {
        $Existing = Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Client Script')/$(Enc $ScriptName)" -Headers $Headers -Method Get -TimeoutSec 15
        Write-Host "  Probe already exists. Updating..." -ForegroundColor Yellow
        $UpdateBody = @{ script = $ProbeJS; enabled = 1; dt = "Task"; view = "List" } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Client Script')/$(Enc $ScriptName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($UpdateBody)) -TimeoutSec 30 | Out-Null
    } catch {
        Write-Host "  Creating probe script..." -ForegroundColor White
        $CreateBody = @{ name = $ScriptName; dt = "Task"; view = "List"; enabled = 1; script = $ProbeJS } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Client Script')" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($CreateBody)) -TimeoutSec 30 | Out-Null
    }

    # Clear cache
    Write-Host "  Clearing cache..." -ForegroundColor White
    try {
        ssh -i "$env:USERPROFILE\.ssh\vps_erpnext2" root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | Out-Null
        Write-Host "  Cache cleared." -ForegroundColor Green
    } catch {
        Write-Host "  WARNING: Could not clear cache. Clear manually:" -ForegroundColor Yellow
        Write-Host "  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "DONE. Now:" -ForegroundColor Green
    Write-Host "  1. Open https://test.erpnext.am/app/task in your browser" -ForegroundColor White
    Write-Host "  2. Press F12 to open DevTools -> Console" -ForegroundColor White
    Write-Host "  3. Look for [PROBE] messages" -ForegroundColor White
    Write-Host "  4. Share the output here" -ForegroundColor White
    Write-Host ""
    Write-Host "Expected:" -ForegroundColor Yellow
    Write-Host '  [PROBE] listview.method = string "frappe.client.get_list"' -ForegroundColor Gray
    Write-Host "  [PROBE] listview.get_args = function" -ForegroundColor Gray
    Write-Host "  [PROBE] listview.get_call_args = function" -ForegroundColor Gray
    Write-Host ""
    Write-Host "After checking, run: .\probe-listview-api.ps1 -Mode Delete" -ForegroundColor Yellow

} elseif ($Mode -eq "Delete") {
    Write-Host "=== Deleting ListView API Probe ===" -ForegroundColor Cyan
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc 'Client Script')/$(Enc $ScriptName)" -Headers $Headers -Method Delete -TimeoutSec 15 | Out-Null
        Write-Host "  Probe deleted." -ForegroundColor Green
    } catch {
        Write-Host "  Probe not found or already deleted." -ForegroundColor Yellow
    }
    # Clear cache
    try {
        ssh -i "$env:USERPROFILE\.ssh\vps_erpnext2" root@161.97.83.156 "docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" 2>&1 | Out-Null
        Write-Host "  Cache cleared." -ForegroundColor Green
    } catch {
        Write-Host "  WARNING: Could not clear cache. Clear manually." -ForegroundColor Yellow
    }
}
