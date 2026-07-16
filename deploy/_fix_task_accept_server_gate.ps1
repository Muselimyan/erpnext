$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

$name = "Task-before-save-lock-unaccepted"
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $name)" -Headers $Headers -Method Get -TimeoutSec 30
$script = [string]$r.data.script
$old = @'
        # Lock: must accept before editing (skip for new docs being created)
        if not doc.is_new() and not doc.custom_accepted_by:
            frappe.throw('You must accept this task before you can edit it. Click Accept / Start Task first.')
'@
$new = @'
        # Lock: must accept before editing (skip for new docs being created)
        if not doc.is_new():
            accepted_by = doc.custom_accepted_by or frappe.db.get_value('Task', doc.name, 'custom_accepted_by')
            if not accepted_by:
                frappe.throw('You must accept this task before you can edit it. Click Accept / Start Task first.')
            if accepted_by != frappe.session.user:
                frappe.throw('Only the user who accepted this task (' + accepted_by + ') can edit it.')
'@
if ($script -notlike "*if not doc.is_new() and not doc.custom_accepted_by:*") {
    Write-Host "Expected old block not found; no change made." -ForegroundColor Yellow
} else {
    $script = $script.Replace($old, $new)
    if ($script -eq [string]$r.data.script) {
        $script = $script -replace "        # Lock: must accept before editing \(skip for new docs being created\)\n        if not doc\.is_new\(\) and not doc\.custom_accepted_by:\n            frappe\.throw\('You must accept this task before you can edit it\. Click Accept / Start Task first\.'\)", $new.TrimEnd()
    }
    $body = @{ script = $script } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$(Enc $name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
    Write-Host "Updated Server Script: $name" -ForegroundColor Green
}
