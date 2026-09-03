param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$TestRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $TestRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 80
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

$AfterScriptName = "Sales-Invoice-after-submit-tender-update"
$AfterScriptPath = Join-Path $TestRoot "work\server\Sales-Invoice-after-submit-tender-update.py"
$AfterLocalScript = Get-Content $AfterScriptPath -Raw
$AfterCurrent = (Invoke-ErpRequest Get "/api/resource/$(Enc 'Server Script')/$(Enc $AfterScriptName)?fields=$(Enc '["name","disabled","script"]')").data

$BeforeScriptName = "Sales-Invoice-before-submit-tender-validation"
$BeforeScriptPath = Join-Path $TestRoot "work\server\Sales-Invoice-before-submit-tender-validation.py"
$BeforeLocalScriptWithHeader = Get-Content $BeforeScriptPath -Raw
$BeforeLocalScript = [regex]::Replace($BeforeLocalScriptWithHeader, '(?s)^# Name:.*?# ---\r?\n\r?\n?', '')
$BeforeExisting = $null
try {
    $BeforeExisting = (Invoke-ErpRequest Get "/api/resource/$(Enc 'Server Script')/$(Enc $BeforeScriptName)?fields=$(Enc '["name","disabled","script"]')").data
} catch {
    $BeforeExisting = $null
}

if ($Mode -eq "Check") {
    [pscustomobject]@{
        target = $BaseUrl
        after_server_script = $AfterCurrent.name
        after_disabled = $AfterCurrent.disabled
        live_has_manual_commit = ([string]$AfterCurrent.script -match "frappe\.db\.commit")
        local_blocks_duplicate_active_tenders = ([string]$AfterLocalScript -match "Multiple active Tender Agreements")
        local_blocks_oversupply = ([string]$AfterLocalScript -match "has only .* remaining")
        local_has_manual_commit = ([string]$AfterLocalScript -match "frappe\.db\.commit")
        before_server_script_exists = ($null -ne $BeforeExisting)
        before_local_validates_tender_price = ([string]$BeforeLocalScript -match "Invoice rate must equal tender price")
    } | ConvertTo-Json
    exit 0
}

$AfterUpdated = (Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $AfterScriptName)" @{ script = $AfterLocalScript }).data
if ($BeforeExisting) {
    $BeforeUpdated = (Invoke-ErpRequest Put "/api/resource/$(Enc 'Server Script')/$(Enc $BeforeScriptName)" @{ script = $BeforeLocalScript; disabled = 0 }).data
} else {
    $BeforeUpdated = (Invoke-ErpRequest Post "/api/resource/$(Enc 'Server Script')" @{
        name = $BeforeScriptName
        script_type = "DocType Event"
        reference_doctype = "Sales Invoice"
        doctype_event = "Before Submit"
        disabled = 0
        script = $BeforeLocalScript
    }).data
}
[pscustomobject]@{
    target = $BaseUrl
    after_updated = $AfterUpdated.name
    before_updated = $BeforeUpdated.name
    status = "updated"
} | ConvertTo-Json
