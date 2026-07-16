param()

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "=== Checking Item Groups and Items ===" -ForegroundColor Cyan

# Get all Item Groups
$ItemGroupsUri = "$BaseUrl/api/resource/Item Group?fields=[`"name`",`"item_group_name`"]&limit_page_length=500"
try {
    $ItemGroupsResponse = Invoke-RestMethod -Uri $ItemGroupsUri -Headers $Headers -Method Get
    $ItemGroups = $ItemGroupsResponse.data
    
    Write-Host "`nFound $($ItemGroups.Count) Item Groups:" -ForegroundColor Green
    $ItemGroups | ForEach-Object {
        Write-Host "  - $($_.name)" -ForegroundColor White
    }
} catch {
    Write-Host "Error fetching Item Groups: $_" -ForegroundColor Red
    exit 1
}

# For each group, count items
Write-Host "`n=== Items per Group ===" -ForegroundColor Cyan
foreach ($group in $ItemGroups | Select-Object -First 20) {
    $ItemsUri = "$BaseUrl/api/resource/Item?filters=[[`"item_group`",`"=`",`"$(Enc $group.name)`"]]&fields=[`"name`"]&limit_page_length=1000"
    try {
        $ItemsResponse = Invoke-RestMethod -Uri $ItemsUri -Headers $Headers -Method Get
        $ItemCount = $ItemsResponse.data.Count
        
        if ($ItemCount -gt 0) {
            Write-Host "  $($group.name): $ItemCount items" -ForegroundColor Green
        } else {
            Write-Host "  $($group.name): 0 items" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  $($group.name): Error - $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Sample Items (first 10) ===" -ForegroundColor Cyan
$SampleItemsUri = "$BaseUrl/api/resource/Item?fields=[`"name`",`"item_name`",`"item_group`"]&limit_page_length=10"
try {
    $SampleResponse = Invoke-RestMethod -Uri $SampleItemsUri -Headers $Headers -Method Get
    $SampleResponse.data | ForEach-Object {
        Write-Host "  - $($_.item_name) ($($_.name)) in group: $($_.item_group)" -ForegroundColor White
    }
} catch {
    Write-Host "Error fetching sample items: $_" -ForegroundColor Red
}
