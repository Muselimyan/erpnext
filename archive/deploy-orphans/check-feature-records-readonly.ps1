#Requires -Version 5.1
param()

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "prod\export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)" }
$Sites = @{ test = "https://test.erpnext.am"; main = "https://erpnext.am" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-JsonUtf8([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers["Authorization"] = $Headers.Authorization
    $bytes = $wc.DownloadData($Url)
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}
function Get-List([string]$BaseUrl, [string]$DocType) {
    $url = "$BaseUrl/api/resource/$(Enc $DocType)?limit_page_length=5000&fields=$(Enc '["name","modified"]')"
    try { return @((Get-JsonUtf8 $url).data) } catch { Write-Warning "list $BaseUrl $DocType failed: $($_.Exception.Message)"; return @() }
}

$Checks = @("Surgical Kit Template", "Surgical Kit Template Item", "Telegram Settings", "Telegram Notification User", "Account Detail Attachment")
$Report = [ordered]@{ checked_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"); sites = $Sites; doctypes = @() }

Write-Host "=== Feature setup records read-only comparison ===" -ForegroundColor Cyan
foreach ($dt in $Checks) {
    Write-Host "`n$dt" -ForegroundColor Yellow
    $testList = Get-List $Sites.test $dt
    $mainList = Get-List $Sites.main $dt
    $testNames = @($testList | ForEach-Object { $_.name })
    $mainNames = @($mainList | ForEach-Object { $_.name })
    $onlyTest = @($testNames | Where-Object { $mainNames -notcontains $_ } | Sort-Object)
    $onlyMain = @($mainNames | Where-Object { $testNames -notcontains $_ } | Sort-Object)
    Write-Host "  test count : $($testNames.Count)"
    Write-Host "  main count : $($mainNames.Count)"
    Write-Host "  only test  : $($onlyTest.Count)"
    Write-Host "  only main  : $($onlyMain.Count)"
    if ($onlyTest.Count) { Write-Host "    only test sample: $(@($onlyTest | Select-Object -First 20) -join '; ')" }
    if ($onlyMain.Count) { Write-Host "    only main sample: $(@($onlyMain | Select-Object -First 20) -join '; ')" }
    $Report.doctypes += [ordered]@{ doctype = $dt; test_count = $testNames.Count; main_count = $mainNames.Count; only_test = $onlyTest; only_main = $onlyMain }
}

$Out = Join-Path $PSScriptRoot "check-feature-records-readonly-result.json"
$Report | ConvertTo-Json -Depth 20 | Set-Content $Out -Encoding UTF8
Write-Host "`nResult saved: $Out" -ForegroundColor Green
