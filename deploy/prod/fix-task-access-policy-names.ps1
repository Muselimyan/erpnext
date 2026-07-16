#!/usr/bin/env pwsh
<#
.SYNOPSIS
Fix Task Access Policy names by removing trailing spaces
#>

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{
    Authorization  = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120
    }
    $Json = $Body | ConvertTo-Json -Depth 30
    $JsonBytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $JsonBytes -TimeoutSec 120
}

Write-Host "`n=== Fixing Task Access Policy names (removing trailing spaces) ===" -ForegroundColor Cyan

# Get all Task Access Policy records
$AllPolicies = (Invoke-ErpRequest -Method Get -Path "/api/resource/Task Access Policy?fields=[`"name`"]&limit_page_length=999").data

$Fixed = 0
$Skipped = 0

foreach ($policy in $AllPolicies) {
    $oldName = $policy.name
    $newName = $oldName.TrimEnd()
    
    if ($oldName -ne $newName) {
        Write-Host "Renaming: '$oldName' -> '$newName'" -ForegroundColor Yellow
        
        try {
            # Rename using the rename API
            $renameBody = @{
                doctype = "Task Access Policy"
                old = $oldName
                new = $newName
                merge = 0
            }
            Invoke-ErpRequest -Method Post -Path "/api/method/frappe.model.rename_doc.rename_doc" -Body $renameBody
            Write-Host "  [OK] Renamed successfully" -ForegroundColor Green
            $Fixed++
        } catch {
            Write-Host "  [ERROR] Failed to rename: $_" -ForegroundColor Red
        }
    } else {
        $Skipped++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Fixed: $Fixed" -ForegroundColor Green
Write-Host "Skipped (no trailing spaces): $Skipped" -ForegroundColor Gray
Write-Host "`nRefresh your browser and try accepting the task again!" -ForegroundColor Green
