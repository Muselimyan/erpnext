# doc-resync-step4a-preview-customers.ps1
# Generates deploy/data/customers-preview.csv from the live (cleaned) warehouse tree.
# READ-ONLY — does not create any records.
# Review the CSV, then run doc-resync-step4b-create-customers.ps1 to deploy.

param()

# ── config ────────────────────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config  = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$H = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

$OutFile = Join-Path $PSScriptRoot "data\customers-preview.csv"

function Enc([string]$v) { [uri]::EscapeDataString($v) }
function Get-ErpList {
    param([string]$DocType, [array]$Fields = @("name"), [array]$Filters = @(), [int]$Limit = 500)
    $F   = ConvertTo-Json -InputObject @($Fields)  -Compress
    $Fil = if ($Filters.Count -gt 0) { ConvertTo-Json -InputObject $Filters -Compress -Depth 10 } else { '[]' }
    $Uri = "$BaseUrl/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $F)&filters=$(Enc $Fil)"
    try { return (Invoke-RestMethod -Uri $Uri -Headers $H -Method Get).data }
    catch { Write-Warning "GET $DocType failed: $_"; return @() }
}

# ── fetch warehouse tree ──────────────────────────────────────────────────────
Write-Host "Fetching warehouse tree from $BaseUrl ..."

$WH_FIELDS = @("name", "warehouse_name", "is_group", "parent_warehouse")

# Fetch ALL warehouses under the Clients - Inmed tree, then filter locally.
# This avoids nested-filter encoding issues for Armenian parent names.
$AllWH = Get-ErpList -DocType "Warehouse" -Fields $WH_FIELDS -Limit 2000

$HospitalNames = @{}
foreach ($w in ($AllWH | Where-Object { $_.parent_warehouse -eq "Clients - Inmed" -and [int]$_.is_group -eq 1 })) {
    $HospitalNames[$w.name] = $w
}
$Hospitals = @($HospitalNames.Values)

$Doctors = @($AllWH | Where-Object { $HospitalNames.ContainsKey($_.parent_warehouse) -and [int]$_.is_group -eq 0 })

Write-Host "  Hospitals found: $($Hospitals.Count)"
Write-Host "  Doctors found:   $($Doctors.Count)"

# ── helpers ───────────────────────────────────────────────────────────────────
$EM = [char]0x2014   # em-dash —

function Get-Code([string]$WarehouseName) {
    if ($WarehouseName -match '^([DH]\d+)') { return $Matches[1] }
    return ""
}

function Get-ShortName([string]$WarehouseName) {
    # "H001 — Aboxyan BK" -> "Aboxyan BK"
    $idx = $WarehouseName.IndexOf($EM)
    if ($idx -ge 0) { return $WarehouseName.Substring($idx + 1).Trim() }
    return $WarehouseName
}

function Get-DoctorName([string]$DoctorWhName, [string]$HospitalShortName) {
    # Strip "D### — " prefix
    $After = $DoctorWhName -replace "^D\d+ $EM ", ""
    # Strip hospital short name from end (if present)
    if ($HospitalShortName -and $After.EndsWith($HospitalShortName)) {
        $DocName = $After.Substring(0, $After.Length - $HospitalShortName.Length).Trim()
    } else {
        # Fallback: use everything after the code
        $DocName = $After
    }
    return $DocName
}

# Build hospital lookup: full_name -> short_name
$HospLookup = @{}
foreach ($h in $Hospitals) {
    $HospLookup[$h.name] = Get-ShortName $h.warehouse_name
}

# ── build rows ────────────────────────────────────────────────────────────────
$Rows = [System.Collections.ArrayList]::new()

# Pass 1 — hospitals
foreach ($h in $Hospitals) {
    $null = $Rows.Add([pscustomobject]@{
        client_code          = Get-Code $h.warehouse_name
        customer_name        = $h.warehouse_name
        client_kind          = "Hospital"
        customer_group       = "Commercial"
        hospital             = ""
        doctor_name          = ""
        debt_threshold_amd   = 0
        is_provisional       = 1
    })
}

# Pass 2 — doctors
foreach ($d in $Doctors) {
    $hospFullName  = $d.parent_warehouse           # "H001 — Aboxyan BK - Inmed"
    $hospShortName = $HospLookup[$hospFullName]    # "Aboxyan BK"
    $doctorName    = Get-DoctorName $d.warehouse_name $hospShortName

    # hospital field = the hospital's warehouse_name (= hospital customer's customer_name)
    $hospWH = $Hospitals | Where-Object { $_.name -eq $hospFullName } | Select-Object -First 1
    $hospCustomerName = if ($hospWH) { $hospWH.warehouse_name } else { $hospFullName }

    $null = $Rows.Add([pscustomobject]@{
        client_code          = Get-Code $d.warehouse_name
        customer_name        = $d.warehouse_name
        client_kind          = "Doctor"
        customer_group       = "Individual"
        hospital             = $hospCustomerName
        doctor_name          = $doctorName
        debt_threshold_amd   = 0
        is_provisional       = 1
    })
}

# Sort: hospitals first (by code), then doctors
$Sorted = $Rows | Sort-Object { if ($_.client_kind -eq "Hospital") { 0 } else { 1 } }, client_code

# ── write CSV ─────────────────────────────────────────────────────────────────
$Sorted | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Written: $OutFile  ($($Sorted.Count) rows)"
Write-Host "  Hospitals: $(($Sorted | Where-Object { $_.client_kind -eq 'Hospital' }).Count)"
Write-Host "  Doctors:   $(($Sorted | Where-Object { $_.client_kind -eq 'Doctor' }).Count)"
Write-Host ""
Write-Host "Review the CSV, then run doc-resync-step4b-create-customers.ps1 -Mode Deploy to create customers."
