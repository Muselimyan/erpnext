#Requires -Version 5.1
param()

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$MainUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$TestUrl = "https://test.erpnext.am"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupDir = Join-Path $PSScriptRoot "backups\workspace-sync-$Stamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-GetJsonUtf8([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers["Authorization"] = $Headers.Authorization
    $bytes = $wc.DownloadData($Url)
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}
function Get-Doc([string]$BaseUrl, [string]$DocType, [string]$Name) {
    try { return (Invoke-GetJsonUtf8 "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Convert-CleanDoc($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Array]) {
        $arr = New-Object System.Collections.ArrayList
        foreach ($item in $Obj) { $null = $arr.Add((Convert-CleanDoc $item)) }
        return ,@($arr)
    }
    if ($Obj -is [PSCustomObject]) {
        $propNames = @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
        $isChildRow = (($propNames -contains "parent") -and ($propNames -contains "parenttype") -and ($propNames -contains "parentfield"))
        $skip = @("modified", "modified_by", "creation", "owner", "idx", "docstatus", "_user_tags", "_comments", "_assign", "_liked_by", "parent", "parenttype", "parentfield")
        if ($isChildRow) { $skip += "name" }
        $ordered = [ordered]@{}
        foreach ($p in $Obj.PSObject.Properties) {
            if ($skip -contains $p.Name) { continue }
            $ordered[$p.Name] = Convert-CleanDoc $p.Value
        }
        if (($Obj.doctype -eq "Workspace Link") -and ($Obj.type -eq "Card Break") -and (-not $ordered.Contains("link_type"))) {
            $ordered["link_type"] = ""
        }
        return [PSCustomObject]$ordered
    }
    return $Obj
}
function Backup-Doc([string]$Name, $Doc) {
    if ($null -ne $Doc) { $Doc | ConvertTo-Json -Depth 80 | Set-Content (Join-Path $BackupDir (($Name -replace '[^a-zA-Z0-9._-]', '_') + ".json")) -Encoding UTF8 }
}
function Put-Workspace([string]$Name, $Doc) {
    $body = (Convert-CleanDoc $Doc) | ConvertTo-Json -Depth 80 -Compress
    Invoke-RestMethod -Uri "$MainUrl/api/resource/Workspace/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 | Out-Null
}
function Delete-Workspace([string]$Name) {
    Invoke-RestMethod -Uri "$MainUrl/api/resource/Workspace/$(Enc $Name)" -Headers $Headers -Method Delete -TimeoutSec 60 | Out-Null
}

Write-Host "=== Sync Main Workspaces to Test ===" -ForegroundColor Cyan
Write-Host "Test read-only: $TestUrl" -ForegroundColor Cyan
Write-Host "Main target   : $MainUrl" -ForegroundColor Cyan
Write-Host "Backup dir    : $BackupDir" -ForegroundColor Cyan

$tasksMain = Get-Doc $MainUrl "Workspace" "Tasks"
Backup-Doc "Tasks" $tasksMain
if ($null -ne $tasksMain) {
    Write-Host "Deleting Main-only Workspace / Tasks" -ForegroundColor Yellow
    Delete-Workspace "Tasks"
} else {
    Write-Host "Main Workspace / Tasks already absent" -ForegroundColor DarkGray
}

$integrationsTest = Get-Doc $TestUrl "Workspace" "Integrations"
if ($null -eq $integrationsTest) { throw "Test Workspace / Integrations not readable" }
$integrationsMain = Get-Doc $MainUrl "Workspace" "Integrations"
Backup-Doc "Integrations" $integrationsMain
Write-Host "Updating Main Workspace / Integrations from Test" -ForegroundColor Yellow
Put-Workspace "Integrations" $integrationsTest

try {
    Invoke-RestMethod -Uri "$MainUrl/api/method/frappe.clear_cache" -Headers $Headers -Method Post -TimeoutSec 60 | Out-Null
} catch {
    Write-Warning "Cache clear failed/forbidden; users may need Ctrl+F5. $($_.Exception.Message)"
}

Write-Host "Workspace sync complete." -ForegroundColor Green
