#Requires -Version 5.1
param()

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
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

function Get-List([string]$BaseUrl, [string]$DocType, [int]$Limit = 5000, [string]$Filters = "") {
    $url = "$BaseUrl/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc '["name","modified"]')"
    if ($Filters) { $url += "&filters=$(Enc $Filters)" }
    try { return @((Get-JsonUtf8 $url).data) } catch { Write-Warning "list $BaseUrl $DocType failed: $($_.Exception.Message)"; return @() }
}

function Get-Doc([string]$BaseUrl, [string]$DocType, [string]$Name) {
    try { return (Get-JsonUtf8 "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}

function Normalize-Object($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Array]) {
        return @($Obj | ForEach-Object { Normalize-Object $_ })
    }
    if ($Obj -is [PSCustomObject]) {
        $skip = @("modified", "modified_by", "creation", "owner", "idx", "docstatus", "_user_tags", "_comments", "_assign", "_liked_by")
        $ordered = [ordered]@{}
        foreach ($p in @($Obj.PSObject.Properties | Sort-Object Name)) {
            if ($skip -contains $p.Name) { continue }
            $ordered[$p.Name] = Normalize-Object $p.Value
        }
        return [PSCustomObject]$ordered
    }
    return $Obj
}

function Get-Hash($Obj) {
    $json = (Normalize-Object $Obj) | ConvertTo-Json -Depth 50 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
}

$Checks = @(
    @{ DocType = "Custom Field"; Filter = "" },
    @{ DocType = "Property Setter"; Filter = "" },
    @{ DocType = "Client Script"; Filter = "" },
    @{ DocType = "Server Script"; Filter = "" },
    @{ DocType = "Workflow"; Filter = "" },
    @{ DocType = "Workspace"; Filter = "" },
    @{ DocType = "Print Format"; Filter = "" },
    @{ DocType = "Report"; Filter = '[["Report","is_standard","=","No"]]' },
    @{ DocType = "DocType"; Filter = '[["DocType","custom","=",1]]' },
    @{ DocType = "Task Access Policy"; Filter = "" },
    @{ DocType = "Role Profile"; Filter = "" }
)

$Report = [ordered]@{
    checked_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
    sites = $Sites
    doctypes = @()
}

Write-Host "=== Read-only test/main comparison ===" -ForegroundColor Cyan
foreach ($check in $Checks) {
    $dt = $check.DocType
    Write-Host "`n$dt" -ForegroundColor Yellow
    $testList = Get-List $Sites.test $dt 5000 $check.Filter
    $mainList = Get-List $Sites.main $dt 5000 $check.Filter
    $testNames = @($testList | ForEach-Object { $_.name })
    $mainNames = @($mainList | ForEach-Object { $_.name })
    $allNames = @($testNames + $mainNames | Sort-Object -Unique)
    $onlyTest = @($testNames | Where-Object { $mainNames -notcontains $_ } | Sort-Object)
    $onlyMain = @($mainNames | Where-Object { $testNames -notcontains $_ } | Sort-Object)
    $different = @()
    foreach ($name in $allNames) {
        if (($onlyTest -contains $name) -or ($onlyMain -contains $name)) { continue }
        $testDoc = Get-Doc $Sites.test $dt $name
        $mainDoc = Get-Doc $Sites.main $dt $name
        if ((Get-Hash $testDoc) -ne (Get-Hash $mainDoc)) { $different += $name }
    }
    Write-Host "  test count : $($testNames.Count)"
    Write-Host "  main count : $($mainNames.Count)"
    Write-Host "  only test  : $($onlyTest.Count)"
    Write-Host "  only main  : $($onlyMain.Count)"
    Write-Host "  different  : $($different.Count)"
    if ($onlyTest.Count) { Write-Host "    only test sample: $(@($onlyTest | Select-Object -First 10) -join '; ')" }
    if ($onlyMain.Count) { Write-Host "    only main sample: $(@($onlyMain | Select-Object -First 10) -join '; ')" }
    if ($different.Count) { Write-Host "    different sample: $(@($different | Select-Object -First 10) -join '; ')" }
    $Report.doctypes += [ordered]@{
        doctype = $dt
        test_count = $testNames.Count
        main_count = $mainNames.Count
        only_test = $onlyTest
        only_main = $onlyMain
        different = @($different | Sort-Object)
    }
}

$Out = Join-Path $PSScriptRoot "compare-test-main-readonly-result.json"
$Report | ConvertTo-Json -Depth 20 | Set-Content $Out -Encoding UTF8
Write-Host "`nResult saved: $Out" -ForegroundColor Green
