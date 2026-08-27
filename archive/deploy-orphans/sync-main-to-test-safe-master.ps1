#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
$MainUrl = "https://erpnext.am"
$TestUrl = "https://test.erpnext.am"

$Records = @(
    @{ DocType = "Company"; Name = "InMED" },
    @{ DocType = "User"; Name = "ai-agent@internal.com" },
    @{ DocType = "User"; Name = "artakn7@gmail.com" },
    @{ DocType = "User"; Name = "artursemerjyan91@gmail.com" },
    @{ DocType = "User"; Name = "emalumyan4@gmail.com" },
    @{ DocType = "User"; Name = "ghahramanyann@gmail.com" },
    @{ DocType = "User"; Name = "karapetyansev@gmail.com" },
    @{ DocType = "User"; Name = "levonaghinyan77@gmail.com" },
    @{ DocType = "User"; Name = "ly.aghayan@gmail.com" },
    @{ DocType = "User"; Name = "sahakyan.oli1998@gmail.com" },
    @{ DocType = "User"; Name = "vagramyankaren@gmail.com" },
    @{ DocType = "User"; Name = "zaruhi.melikyan@gmail.com" }
)

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-GetJsonUtf8([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Headers["Authorization"] = $Headers.Authorization
    $bytes = $wc.DownloadData($Url)
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}
function Get-ErpDoc([string]$BaseUrl, [string]$DocType, [string]$Name) {
    try { return (Invoke-GetJsonUtf8 "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}
function Remove-ReadOnlyFields($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Array]) { return @($Obj | ForEach-Object { Remove-ReadOnlyFields $_ }) }
    if ($Obj -is [PSCustomObject]) {
        $skip = @("modified", "modified_by", "creation", "owner", "_user_tags", "_comments", "_assign", "_liked_by", "last_login", "last_active", "last_ip")
        $ordered = [ordered]@{}
        foreach ($p in @($Obj.PSObject.Properties)) {
            if ($skip -contains $p.Name) { continue }
            $ordered[$p.Name] = Remove-ReadOnlyFields $p.Value
        }
        return [PSCustomObject]$ordered
    }
    return $Obj
}
function ConvertTo-StableObject($Obj) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Array]) { return @($Obj | ForEach-Object { ConvertTo-StableObject $_ }) }
    if ($Obj -is [PSCustomObject]) {
        $skip = @("modified", "modified_by", "creation", "owner", "idx", "docstatus", "_user_tags", "_comments", "_assign", "_liked_by", "last_login", "last_active", "last_ip")
        $ordered = [ordered]@{}
        foreach ($p in @($Obj.PSObject.Properties | Sort-Object Name)) {
            if ($skip -contains $p.Name) { continue }
            $ordered[$p.Name] = ConvertTo-StableObject $p.Value
        }
        return [PSCustomObject]$ordered
    }
    return $Obj
}
function Get-ObjectHash($Obj) {
    $json = (ConvertTo-StableObject $Obj) | ConvertTo-Json -Depth 50 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
}
function Save-ErpDoc([string]$BaseUrl, [string]$DocType, [string]$Name, $Doc) {
    $body = Remove-ReadOnlyFields $Doc
    $json = $body | ConvertTo-Json -Depth 50 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 60 | Out-Null
}

Write-Host "=== Main -> Test safe master sync ===" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow

$changed = @()
$errors = @()
foreach ($record in $Records) {
    $dt = $record.DocType
    $name = $record.Name
    Write-Host "`n$dt / $name" -ForegroundColor White
    $mainDoc = Get-ErpDoc $MainUrl $dt $name
    $testDoc = Get-ErpDoc $TestUrl $dt $name
    if (-not $mainDoc -or -not $testDoc) {
        Write-Host "  missing on one side" -ForegroundColor Red
        $errors += "$dt / $name missing on one side"
        continue
    }
    if ((Get-ObjectHash $mainDoc) -eq (Get-ObjectHash $testDoc)) {
        Write-Host "  already same"
        continue
    }
    $changed += "$dt / $name"
    if ($Mode -eq "Deploy") {
        try {
            Save-ErpDoc $TestUrl $dt $name $mainDoc
            Write-Host "  updated test from main" -ForegroundColor Green
        } catch {
            Write-Host "  update failed: $($_.Exception.Message)" -ForegroundColor Red
            $errors += "$dt / $name : $($_.Exception.Message)"
        }
    } else {
        Write-Host "  would update test from main" -ForegroundColor Yellow
    }
}

Write-Host "`nSummary" -ForegroundColor Cyan
Write-Host "  Different records: $($changed.Count)"
Write-Host "  Errors: $($errors.Count)"
if ($errors.Count) { $errors | ForEach-Object { Write-Host "  error: $_" -ForegroundColor Red } }
