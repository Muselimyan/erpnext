$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }

# Read the original template
$scriptContent = Get-Content (Join-Path $PSScriptRoot "..\\_temp_task_accept.js") -Raw -Encoding UTF8

# Remove the desktop accept button (lines 209-228) since it's now in Task-Dispatch Packing Usability
# Remove from "            frm.add_custom_button(__("Accept / Start Task")" to the closing of that block
$scriptContent = $scriptContent -replace '(?s)\s{12}frm\.add_custom_button\(__\("Accept / Start Task"\), function\(\) \{\s*var doAccept = function\(\).*?\}\);\s*\}\);', ''

Write-Host "Restoring 'Task-Accept Start' with full UI logic..." -ForegroundColor Cyan
$body = @{ script = $scriptContent } | ConvertTo-Json -Depth 5 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc 'Task-Accept Start')" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 | Out-Null
Write-Host "Restored. Complete button, field hiding, mobile UI all back." -ForegroundColor Green
Write-Host "Reload the Task form now." -ForegroundColor Yellow
