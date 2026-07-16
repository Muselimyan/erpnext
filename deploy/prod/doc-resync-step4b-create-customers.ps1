param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

# ── config ────────────────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config  = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$H = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

$CsvPath = Join-Path $PSScriptRoot "data\customers-preview.csv"

function Enc([string]$v) { [uri]::EscapeDataString($v) }
function Invoke-Erp {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method }
    return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method -Body ($Body | ConvertTo-Json -Depth 20)
}
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-Erp -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

# ── load preview CSV ──────────────────────────────────────────────────────────
if (-not (Test-Path $CsvPath)) {
    Write-Error "Preview CSV not found: $CsvPath`nRun doc-resync-step4a-preview-customers.ps1 first."
    exit 1
}

$Rows = Import-Csv -Path $CsvPath -Encoding UTF8
Write-Host "Loaded $($Rows.Count) rows from $CsvPath"

$Hospitals = $Rows | Where-Object { $_.client_kind -eq "Hospital" }
$Doctors   = $Rows | Where-Object { $_.client_kind -eq "Doctor" }
Write-Host "  Hospitals: $($Hospitals.Count)   Doctors: $($Doctors.Count)"

if ($Mode -eq "Check") {
    # Show a sample and check for obvious issues
    $Issues = [System.Collections.ArrayList]::new()
    foreach ($r in $Rows) {
        if ([string]::IsNullOrWhiteSpace($r.client_code))   { $null = $Issues.Add("Missing client_code: $($r.customer_name)") }
        if ([string]::IsNullOrWhiteSpace($r.customer_name)) { $null = $Issues.Add("Missing customer_name on row $($r.client_code)") }
        if ($r.client_kind -eq "Doctor" -and [string]::IsNullOrWhiteSpace($r.hospital)) {
            $null = $Issues.Add("Doctor missing hospital: $($r.customer_name)")
        }
    }
    [ordered]@{
        mode          = "Check"
        csv_path      = $CsvPath
        total_rows    = $Rows.Count
        hospitals     = $Hospitals.Count
        doctors       = $Doctors.Count
        issues        = $Issues
        sample_hospitals = ($Hospitals | Select-Object -First 5 | Select-Object client_code, customer_name, client_kind)
        sample_doctors   = ($Doctors   | Select-Object -First 5 | Select-Object client_code, customer_name, hospital, doctor_name)
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ── Deploy: create in two passes ──────────────────────────────────────────────
# Pass 1 — hospitals (must exist before doctors can reference them)
$Results = [System.Collections.ArrayList]::new()

Write-Host "`nPass 1: Creating hospitals..."
foreach ($r in $Hospitals) {
    $Existing = Get-ErpDoc -DocType "Customer" -Name $r.customer_name
    if ($null -ne $Existing) {
        $null = $Results.Add([pscustomobject]@{ action = "skipped_exists"; name = $r.customer_name; kind = "Hospital" })
        continue
    }
    try {
        $Body = [ordered]@{
            doctype            = "Customer"
            customer_name      = $r.customer_name
            client_code        = $r.client_code
            client_kind        = "Hospital"
            customer_group     = "Commercial"
            territory          = "Armenia"
            debt_threshold_amd = [int]$r.debt_threshold_amd
            is_provisional     = [int]$r.is_provisional
        }
        $Created = (Invoke-Erp -Method Post -Path "/api/resource/Customer" -Body $Body).data
        $null = $Results.Add([pscustomobject]@{ action = "created"; name = $Created.name; kind = "Hospital" })
    }
    catch {
        $null = $Results.Add([pscustomobject]@{ action = "error"; name = $r.customer_name; kind = "Hospital"; error = $_.Exception.Message })
    }
}

Write-Host "Pass 2: Creating doctors..."
foreach ($r in $Doctors) {
    $Existing = Get-ErpDoc -DocType "Customer" -Name $r.customer_name
    if ($null -ne $Existing) {
        $null = $Results.Add([pscustomobject]@{ action = "skipped_exists"; name = $r.customer_name; kind = "Doctor" })
        continue
    }
    try {
        $Body = [ordered]@{
            doctype            = "Customer"
            customer_name      = $r.customer_name
            client_code        = $r.client_code
            client_kind        = "Doctor"
            customer_group     = "Individual"
            territory          = "Armenia"
            hospital           = $r.hospital
            doctor_name        = $r.doctor_name
            debt_threshold_amd = [int]$r.debt_threshold_amd
            is_provisional     = [int]$r.is_provisional
        }
        $Created = (Invoke-Erp -Method Post -Path "/api/resource/Customer" -Body $Body).data
        $null = $Results.Add([pscustomobject]@{ action = "created"; name = $Created.name; kind = "Doctor" })
    }
    catch {
        $null = $Results.Add([pscustomobject]@{ action = "error"; name = $r.customer_name; kind = "Doctor"; error = $_.Exception.Message })
    }
}

$Created = ($Results | Where-Object { $_.action -eq "created" }).Count
$Skipped = ($Results | Where-Object { $_.action -eq "skipped_exists" }).Count
$Errors  = ($Results | Where-Object { $_.action -eq "error" }).Count
Write-Host "Created: $Created  Skipped: $Skipped  Errors: $Errors"

[ordered]@{
    mode    = "Deploy"
    created = $Created
    skipped = $Skipped
    errors  = $Errors
    error_details = ($Results | Where-Object { $_.action -eq "error" })
} | ConvertTo-Json -Depth 10
