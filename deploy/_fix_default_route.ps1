$ErrorActionPreference = "Stop"
$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

# Check current logged-in user
$me = Invoke-RestMethod -Uri "$BaseUrl/api/method/frappe.auth.get_logged_user" -Headers $Headers -Method Get -TimeoutSec 15
$user = $me.message
Write-Host "Logged in as: $user"

# Get current user home settings
$u = Invoke-RestMethod -Uri "$BaseUrl/api/resource/User/$([uri]::EscapeDataString($user))?fields=[`"name`",`"home_page`",`"default_route`"]" -Headers $Headers -Method Get -TimeoutSec 15
Write-Host "Current home_page: '$($u.data.home_page)'"

# Check System Settings default_home_page
$ss = Invoke-RestMethod -Uri "$BaseUrl/api/resource/System%20Settings?fields=[`"default_home_page`",`"setup_complete`"]" -Headers $Headers -Method Get -TimeoutSec 15
Write-Host "System default_home_page: '$($ss.data[0].default_home_page)'"
