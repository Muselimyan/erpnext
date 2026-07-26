#Requires -Version 5.1
<#
.SYNOPSIS
    Fix Account Detail Attachment child DocType metadata.
.DESCRIPTION
    Account Detail Attachment is a custom child DocType used by Task.custom_account_photos.
    It was incorrectly marked custom=0/module=Projects, causing Frappe to import a missing
    ERPNext controller module: erpnext.projects.doctype.account_detail_attachment.

    This script marks the DocType as custom=1 so Frappe uses the generic controller.
.PARAMETER Mode
    Check  — report current state without making changes (default)
    Deploy — apply metadata fix
.PARAMETER Target
    test — https://test.erpnext.am (default)
    main — https://erpnext.am
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

$DocTypeName = "Account Detail Attachment"

Write-Host "=== Fix Account Detail Attachment Custom DocType Metadata ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

try {
    $doc = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/DocType/$(Enc $DocTypeName)?fields=[`"name`",`"custom`",`"module`",`"istable`"]" -Headers $Headers -Method Get -TimeoutSec 30).data

    Write-Host "`nCurrent state:" -ForegroundColor Cyan
    Write-Host "  name: $($doc.name)"
    Write-Host "  custom: $($doc.custom)"
    Write-Host "  module: $($doc.module)"
    Write-Host "  istable: $($doc.istable)"

    if ($Mode -eq "Check") {
        if ([int]$doc.custom -eq 1) {
            Write-Host "`nOK: DocType is marked custom=1" -ForegroundColor Green
        } else {
            Write-Host "`nNeeds fix: DocType is custom=0 and may cause missing module import errors" -ForegroundColor Yellow
        }
        return
    }

    if ([int]$doc.custom -eq 1) {
        Write-Host "`nNo change needed." -ForegroundColor Green
        return
    }

    $body = @{ custom = 1 } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/DocType/$(Enc $DocTypeName)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null

    $after = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/DocType/$(Enc $DocTypeName)?fields=[`"name`",`"custom`",`"module`",`"istable`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
    Write-Host "`nFixed:" -ForegroundColor Green
    Write-Host "  custom: $($after.custom)"
    Write-Host "  module: $($after.module)"
    Write-Host "  istable: $($after.istable)"
} catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    throw
}
