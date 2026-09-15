# ==============================================================
# W1 - Unified access control (Group 11 financial tail rebuild)
#
# Consolidates six conflicting acceptance/permission checks into one gate per
# doctype, and removes the last three places that read Frappe's
# `flags.ignore_permissions` as a "skip our business rules" signal.
#
# Server:
#   NEW      Task-before-save-access-control
#   NEW      Dispatch-Case-before-save-access-control
#   UPDATE   Task-before-save-dispatch-gates      (access control removed,
#                                                  DC-conditional restructured)
#   UPDATE   Task-before-save-policy              (role checks removed)
#   DISABLE  Task-before-save-lock-unaccepted
#   DISABLE  Task-before-save-lock-completed
#   DISABLE  Dispatch-Case-before-save-lock-submitted
#   UPDATE   9 task_* / dispatch_case_* API scripts
#
# Client:
#   UPDATE   Task-Field-Editability          (adds tfe_can_complete + admin rule)
#   UPDATE   Task-Action Buttons             (delegates to TFE)
#   UPDATE   Task-Photo-System               (delegates to TFE)
#   UPDATE   Task-Account Details UI Cleanup (delegates to TFE)
#
# TEST ONLY. Credentials read from deploy/test/export.ps1.
#
#   powershell -ExecutionPolicy Bypass -File deploy\test\deploy\group-11-financial-tail\w1-unified-access-control.ps1 -Mode Check
#   powershell -ExecutionPolicy Bypass -File deploy\test\deploy\group-11-financial-tail\w1-unified-access-control.ps1 -Mode Deploy
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

Write-Host "W1 unified access control -> $BaseUrl  [Mode=$Mode]" -ForegroundColor Cyan
Write-Host ""

function Enc([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-Erp { param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 180 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 180
}

function Get-ErpDoc { param([string]$DocType, [string]$Name)
    # Invoke-RestMethod decodes the JSON RESPONSE as Latin-1 when the server
    # does not declare a charset, which inflates every multi-byte character and
    # makes Check report a false "DIFFERS" for any script containing non-ASCII.
    # Download the raw bytes and decode them as UTF-8 explicitly instead.
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Authorization", "token $($ApiKey):$($ApiSec)")
        $text = $wc.DownloadString("$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)")
        return ($text | ConvertFrom-Json).data
    } catch { return $null }
}

function Read-WorkScript { param([string]$Path)
    # -Encoding UTF8 is REQUIRED. Windows PowerShell 5.1 reads BOM-less files as
    # ANSI by default, which mangles every non-ASCII character in the script --
    # the box-drawing characters used in section separators become mojibake on
    # the server. This is how the existing corruption in
    # Task-after-save-debt-closure.py's comments was introduced. Any new deploy
    # script in this repo must read source files as UTF-8.
    $raw = Get-Content $Path -Raw -Encoding UTF8
    $marker = if ($Path -like "*.js") { "// ---" } else { "# ---" }
    $i = $raw.IndexOf($marker)
    if ($i -lt 0) { return $raw }
    return $raw.Substring($i + $marker.Length).TrimStart("`r", "`n")
}

$changes = @()

# ── 1. New + updated server scripts ───────────────────────────────────
# name, file, reference_doctype, doctype_event, script_type
$ServerScripts = @(
    @{ Name = "Task-before-save-access-control"; File = "server\Task-before-save-access-control.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Dispatch-Case-before-save-access-control"; File = "server\Dispatch-Case-before-save-access-control.py"; Ref = "Dispatch Case"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-dispatch-gates"; File = "server\Task-before-save-dispatch-gates.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "Task-before-save-policy"; File = "server\Task-before-save-policy.py"; Ref = "Task"; Event = "Before Save"; Type = "DocType Event" },
    @{ Name = "task_create_dispatch_case"; File = "server\task_create_dispatch_case.py"; Type = "API" },
    @{ Name = "task_add_dispatch_product"; File = "server\task_add_dispatch_product.py"; Type = "API" },
    @{ Name = "task_update_dispatch_product"; File = "server\task_update_dispatch_product.py"; Type = "API" },
    @{ Name = "task_remove_dispatch_product"; File = "server\task_remove_dispatch_product.py"; Type = "API" },
    @{ Name = "task_apply_template"; File = "server\task_apply_template.py"; Type = "API" },
    @{ Name = "task_mark_item_packed"; File = "server\task_mark_item_packed.py"; Type = "API" },
    @{ Name = "task_mark_items_packed_batch"; File = "server\task_mark_items_packed_batch.py"; Type = "API" },
    @{ Name = "task_update_return_item_quantities"; File = "server\task_update_return_item_quantities.py"; Type = "API" },
    @{ Name = "dispatch_case_packing_scan"; File = "server\dispatch_case_packing_scan.py"; Type = "API" }
)

Write-Host "[1] Server scripts" -ForegroundColor Magenta
foreach ($s in $ServerScripts) {
    $path = Join-Path $WorkDir $s.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($s.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Server Script" $s.Name

    if ($Mode -eq "Check") {
        if ($existing) {
            $same = ([string]$existing.script) -eq $body
            $state = if ($same) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            $dis = if ($existing.disabled -eq 1) { " [disabled]" } else { "" }
            Write-Host ("  {0,-42} {1}{2}" -f $s.Name, $state, $dis)
        } else {
            Write-Host ("  {0,-42} WOULD CREATE ({1} chars)" -f $s.Name, $body.Length) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $s.Name)" @{ script = $body; disabled = 0 } | Out-Null
            Write-Host ("  {0,-42} UPDATED + ENABLED" -f $s.Name) -ForegroundColor Green
        } else {
            $doc = @{ doctype = "Server Script"; name = $s.Name; script_type = $s.Type; script = $body; disabled = 0 }
            if ($s.Ref) { $doc.reference_doctype = $s.Ref; $doc.doctype_event = $s.Event }
            if ($s.Type -eq "API") { $doc.api_method = $s.Name }
            Invoke-Erp Post "/api/resource/$(Enc 'Server Script')" $doc | Out-Null
            Write-Host ("  {0,-42} CREATED" -f $s.Name) -ForegroundColor Green
        }
        $changes += $s.Name
    }
}

# ── 2. Absorbed server scripts to disable ─────────────────────────────
$DisableServer = @(
    "Task-before-save-lock-unaccepted",
    "Task-before-save-lock-completed",
    "Dispatch-Case-before-save-lock-submitted"
)

Write-Host ""
Write-Host "[2] Absorbed server scripts (disable)" -ForegroundColor Magenta
foreach ($name in $DisableServer) {
    $existing = Get-ErpDoc "Server Script" $name
    if ($Mode -eq "Check") {
        if ($existing) {
            $state = if ($existing.disabled -eq 1) { "already disabled" } else { "ENABLED (will disable)" }
            Write-Host ("  {0,-42} {1}" -f $name, $state)
        } else {
            Write-Host ("  {0,-42} not found" -f $name) -ForegroundColor DarkGray
        }
    } else {
        if ($existing) {
            # Push the annotated body too, so the reason it is disabled travels
            # with the script rather than living only in the repo.
            $localName = switch ($name) {
                "Task-before-save-lock-unaccepted" { "server\Task-before-save-lock-unaccepted.py" }
                "Task-before-save-lock-completed" { "server\Task-before-save-lock-completed.py" }
                "Dispatch-Case-before-save-lock-submitted" { "server\Dispatch-Case-before-save-lock-submitted.py" }
            }
            $p = Join-Path $WorkDir $localName
            $payload = @{ disabled = 1 }
            if (Test-Path $p) { $payload.script = (Read-WorkScript $p) }
            Invoke-Erp Put "/api/resource/$(Enc 'Server Script')/$(Enc $name)" $payload | Out-Null
            Write-Host ("  {0,-42} DISABLED" -f $name) -ForegroundColor Green
            $changes += "$name (disabled)"
        } else {
            Write-Host ("  {0,-42} not found -- SKIP" -f $name) -ForegroundColor DarkGray
        }
    }
}

# ── 3. Client scripts ─────────────────────────────────────────────────
$ClientScripts = @(
    @{ Name = "Task-Field-Editability"; File = "client\Task-Field-Editability.js" },
    @{ Name = "Task-Action Buttons"; File = "client\Task-Action Buttons.js" },
    @{ Name = "Task-Photo-System"; File = "client\Task-Photo-System.js" },
    @{ Name = "Task-Account Details UI Cleanup"; File = "client\Task-Account Details UI Cleanup.js" }
)

Write-Host ""
Write-Host "[3] Client scripts" -ForegroundColor Magenta
foreach ($c in $ClientScripts) {
    $path = Join-Path $WorkDir $c.File
    if (-not (Test-Path $path)) { Write-Host "  ERROR missing file: $($c.File)" -ForegroundColor Red; continue }
    $body = Read-WorkScript $path
    $existing = Get-ErpDoc "Client Script" $c.Name

    if ($Mode -eq "Check") {
        if ($existing) {
            $same = ([string]$existing.script) -eq $body
            $state = if ($same) { "identical" } else { "DIFFERS (cur=$(([string]$existing.script).Length) new=$($body.Length))" }
            Write-Host ("  {0,-42} {1}" -f $c.Name, $state)
        } else {
            Write-Host ("  {0,-42} WOULD CREATE" -f $c.Name) -ForegroundColor Yellow
        }
    } else {
        if ($existing) {
            Invoke-Erp Put "/api/resource/$(Enc 'Client Script')/$(Enc $c.Name)" @{ script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-42} UPDATED" -f $c.Name) -ForegroundColor Green
        } else {
            Invoke-Erp Post "/api/resource/$(Enc 'Client Script')" @{ name = $c.Name; dt = "Task"; view = "Form"; script = $body; enabled = 1 } | Out-Null
            Write-Host ("  {0,-42} CREATED" -f $c.Name) -ForegroundColor Green
        }
        $changes += $c.Name
    }
}

Write-Host ""
if ($Mode -eq "Check") {
    Write-Host "Check complete. Re-run with -Mode Deploy to apply." -ForegroundColor Cyan
} else {
    Write-Host "Deploy complete: $($changes.Count) object(s) changed." -ForegroundColor Green
    Write-Host "Now run:  docker exec frappe-test-backend-1 bench --site test.erpnext.am clear-cache" -ForegroundColor Yellow
}
