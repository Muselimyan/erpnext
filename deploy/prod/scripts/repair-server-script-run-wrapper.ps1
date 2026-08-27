param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
}

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 30 }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30
}

function Get-ErpDoc {
    param([string]$DocType, [string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

$ListPath = "/api/resource/Server%20Script?fields=%5B%22name%22,%22disabled%22,%22reference_doctype%22,%22doctype_event%22%5D&limit_page_length=500"
$Scripts = (Invoke-ErpRequest -Method Get -Path $ListPath).data
$Report = [ordered]@{ mode=$Mode; scanned=0; candidates=@(); applied=@(); errors=@() }

foreach ($Row in ($Scripts | ForEach-Object { $_ })) {
    $Report.scanned += 1
    $Doc = Get-ErpDoc -DocType "Server Script" -Name $Row.name
    if ($null -eq $Doc -or [string]::IsNullOrEmpty($Doc.script)) { continue }

    $Original = [string]$Doc.script
    $Fixed = $Original -replace 'def _run\(', 'def run_script(' -replace '(^|\n)_run\(\)', '$1run_script()'
    $NeedsFix = ($Fixed -ne $Original)

    if ($NeedsFix) {
        $Report.candidates += [pscustomobject]@{
            name=$Doc.name
            reference_doctype=$Doc.reference_doctype
            doctype_event=$Doc.doctype_event
            disabled=$Doc.disabled
        }

        if ($Mode -eq "Deploy") {
            try {
                $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/Server%20Script/$(Enc $Doc.name)" -Body ([ordered]@{ script=$Fixed })).data
                $Report.applied += [pscustomobject]@{ name=$Updated.name; action="updated" }
            } catch {
                $Report.errors += [pscustomobject]@{ name=$Doc.name; error=$_.Exception.Message }
            }
        }
    }
}

$Report.summary = [ordered]@{
    candidate_count = @($Report.candidates).Count
    applied_count   = @($Report.applied).Count
    error_count     = @($Report.errors).Count
}

$Report | ConvertTo-Json -Depth 10
