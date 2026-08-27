$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Find the Client Script containing dispatch_task_accept
$r = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22script%22%5D&limit_page_length=200" -Headers $Headers -Method Get -TimeoutSec 60
$target = $r.data | Where-Object { $_.script -and $_.script.Contains('dispatch_task_accept') }

if (-not $target) {
    Write-Host "ERROR: Could not find Client Script with dispatch_task_accept" -ForegroundColor Red
    exit 1
}

Write-Host "Found: $($target.name)" -ForegroundColor Cyan

$original = $target.script
$fixed = $original

# Show current accept condition lines for debugging
$lines = $original -split "`n"
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'custom_accepted_by') {
        Write-Host "  BEFORE L$($i+1): $($lines[$i].TrimEnd())" -ForegroundColor Yellow
    }
}

# Fix 1: Remove "accepted_by !== current user" from accept button condition
$fixed = $fixed.Replace(' && frm.doc.custom_accepted_by !== frappe.session.user)', ')')

# Fix 2: Remove grey "Accepted" bar for current user (mobile)
# Match: if (window.innerWidth <= 768 && frm.doc.custom_accepted_by === frappe.session.user) { ... Accepted ... }
$fixed = $fixed -replace "if \(window\.innerWidth <= 768 && frm\.doc\.custom_accepted_by === frappe\.session\.user\) \{[^}]+\}", ''

# Fix 3: Also remove the desktop grey "Accepted" bar if it exists  
$fixed = $fixed -replace "if \(frm\.doc\.custom_accepted_by === frappe\.session\.user\) \{[^}]+Accepted[^}]+\}", ''

# Fix 4: Remove the accepted_by display toggle that hides the role field
$fixed = $fixed.Replace('if (frm.doc.custom_accepted_by) {', 'if (false && frm.doc.custom_accepted_by) {')

if ($fixed -eq $original) {
    Write-Host "`nNo matching patterns found. Dumping lines with 'accepted' for manual review:" -ForegroundColor Red
    for ($i=0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'accept') {
            Write-Host "  L$($i+1): $($lines[$i].TrimEnd())"
        }
    }
    exit
}

# Show what changed
$fixedLines = $fixed -split "`n"
for ($i=0; $i -lt $fixedLines.Count; $i++) {
    if ($fixedLines[$i] -match 'accepted_by|Accept.*Start') {
        Write-Host "  AFTER  L$($i+1): $($fixedLines[$i].TrimEnd())" -ForegroundColor Green
    }
}

$bodyJson = @{ script = $fixed } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $target.name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) -TimeoutSec 30 | Out-Null
Write-Host "`nDone. Accept button now visible to ALL users. Reload the Task form." -ForegroundColor Green
