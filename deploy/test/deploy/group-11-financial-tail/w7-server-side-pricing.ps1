# ==============================================================
# W7 - Server-side pricing (Group 11 financial tail rebuild)
#
# The selling price used to be whatever the browser sent, pre-filled from
# Item.standard_rate. That field is populated on ZERO items, which is why 94% of
# submitted Dispatch Case rows carried unit_price = 0 and the auto-created
# invoices were near-worthless. It also ignored the Price List and Tender
# Agreement architecture entirely.
#
# Price is now resolved on the server, in strict precedence:
#   active Tender Agreement -> customer-specific Item Price -> Standard Selling
#   -> refuse
# A client-supplied price is ignored. Deviations go through discount_pct, and a
# tender-priced item refuses any discount.
#
# Tender-first is what makes C2 unreachable: the Sales Invoice tender validator
# refuses any rate differing from the tender price, and the order-entry gate now
# also checks the tender REMAINING QUANTITY -- which pricing alone cannot fix
# and which otherwise deadlocks the invoice task after the goods have shipped.
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   ... -Mode Check
#   ... -Mode Deploy
# ==============================================================

param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$WorkDir = Join-Path $TestRoot "work"
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

if ($BaseUrl -notmatch "test\.erpnext\.am") {
    throw "Refusing to run: resolved base URL '$BaseUrl' is not the test instance."
}

Write-Host "W7 server-side pricing -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    # Explicit UTF-8 decode -- Invoke-RestMethod decodes responses as Latin-1
    # when no charset is declared, producing false "DIFFERS" for non-ASCII.
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    # -Encoding UTF8 is REQUIRED: PowerShell 5.1 reads BOM-less files as ANSI,
    # mangling non-ASCII before upload.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

$ServerScripts = @(
    @{ Name = "task_add_dispatch_product"; File = "server\task_add_dispatch_product.py"; Type = "API" },
    @{ Name = "task_update_dispatch_product"; File = "server\task_update_dispatch_product.py"; Type = "API" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" }
)

$ClientScripts = @(
    @{ Name = "Task-Product Work Area"; File = "client\Task-Product Work Area.js" }
)

Write-Host "[1] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-36} {1}" -f $s.Name, $state)
        } else {
            Write-Host ("  {0,-36} WOULD CREATE" -f $s.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-36} UPDATED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "API") { $doc.api_method = $s.Name }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-36} CREATED" -f $s.Name) -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "[2] Client scripts" -ForegroundColor Magenta
foreach ($c in $ClientScripts) {
    $path = Join-Path $WorkDir $c.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($c.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Client Script" $c.Name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if (([string]$existing.script) -eq $body) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-36} {1}" -f $c.Name, $state)
        } else {
            Write-Host ("  {0,-36} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-36} UPDATED" -f $c.Name) -ForegroundColor Green
        } else {
            Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = "Task"; view = "Form"; script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-36} CREATED" -f $c.Name) -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
