# ==============================================================
# ERPNext Server Export  -  erpnext.am
# Outputs:
#   deploy/schema/*.json   one file per config / schema type
#   deploy/data/*.csv      one file per master-data type (max 20 rows)
#   deploy/export-summary.json
# Run with:  powershell -ExecutionPolicy Bypass -File export.ps1
# ==============================================================

param()

$BaseUrl = "https://erpnext.am"
$ApiKey  = "ac956c367264b27"
$ApiSec  = "f5162b01a25da38"
$H       = @{ Authorization = "token ${ApiKey}:${ApiSec}" }

$Root    = $PSScriptRoot
$SchemaD = Join-Path $Root "schema"
$DataD   = Join-Path $Root "data"

New-Item -ItemType Directory -Force -Path $SchemaD | Out-Null
New-Item -ItemType Directory -Force -Path $DataD   | Out-Null

$schemaStats = [ordered]@{}
$dataStats   = [ordered]@{}
$gaps        = [System.Collections.ArrayList]::new()

# -- low-level helpers ------------------------------------------------
# Use WebClient.DownloadData + explicit UTF-8 decode so Armenian/Unicode
# names are never mis-interpreted via the system code page (Windows-1252).

function fetch-utf8 {
    param([string]$url)
    $wc = New-Object System.Net.WebClient
    $wc.Headers["Authorization"] = $H.Authorization
    $bytes = $wc.DownloadData($url)                           # raw bytes
    return [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}

function api-list {
    param([string]$dt, [int]$lim = 500, [string]$filters = "")
    $enc = [uri]::EscapeDataString($dt)
    $url = $BaseUrl + "/api/resource/" + $enc + "?limit_page_length=" + $lim
    if ($filters) { $url = $url + "&filters=" + [uri]::EscapeDataString($filters) }
    try   { return (fetch-utf8 $url).data }
    catch { Write-Warning "  list  $dt : $($_.Exception.Message)"; return @() }
}

function api-get {
    param([string]$dt, [string]$name)
    $enc1 = [uri]::EscapeDataString($dt)
    $enc2 = [uri]::EscapeDataString($name)
    $url  = $BaseUrl + "/api/resource/" + $enc1 + "/" + $enc2
    try   { return (fetch-utf8 $url).data }
    catch { return $null }  # silent; caller decides whether to escalate
}

# Fallback for records with non-ASCII names: passes name as query param.
function api-get-method {
    param([string]$dt, [string]$name)
    $enc1 = [uri]::EscapeDataString($dt)
    $enc2 = [uri]::EscapeDataString($name)
    $url  = $BaseUrl + "/api/method/frappe.client.get?doctype=" + $enc1 + "&name=" + $enc2
    try   { return (fetch-utf8 $url).message }
    catch { Write-Warning "  get   $dt / $name : $($_.Exception.Message)"; return $null }
}

function flatten {
    param($rec)
    if ($null -eq $rec) { return [PSCustomObject]@{} }
    $out = [ordered]@{}
    foreach ($p in $rec.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v)                         { $out[$p.Name] = "" }
        elseif ($v -is [array])                   { $out[$p.Name] = ($v | ConvertTo-Json -Compress -Depth 3) }
        elseif ($v -is [PSCustomObject])          { $out[$p.Name] = ($v | ConvertTo-Json -Compress -Depth 3) }
        else                                       { $out[$p.Name] = $v }
    }
    [PSCustomObject]$out
}

function write-gap { param([string]$msg) $null = $gaps.Add($msg) }

# -- schema export (full JSON per record) ----------------------------

function export-schema {
    param([string]$dt, [string]$file, [string]$filters = "", [scriptblock]$keep = $null)
    Write-Host "schema  $($dt.PadRight(22))" -NoNewline
    $list = api-list $dt 500 $filters
    $recs = @()
    foreach ($item in $list) {
        $full = api-get $dt $item.name
        if ($null -eq $full) { continue }
        if ($keep -and -not (& $keep $full)) { continue }
        $recs += $full
    }
    $n = $recs.Count
    Write-Host " $n"
    if ($n -eq 0) { write-gap "$dt : none configured" }
    @{ count = $n; records = $recs } |
        ConvertTo-Json -Depth 20 |
        Set-Content (Join-Path $SchemaD "$file.json") -Encoding UTF8
    $schemaStats[$file] = $n
}

# -- data export (CSV, max N rows, per-record fetch with fallback) ---

function export-data {
    param([string]$dt, [string]$file, [int]$lim = 20)
    Write-Host "data    $($dt.PadRight(22))" -NoNewline
    $list = api-list $dt $lim
    if ($list.Count -eq 0) {
        Write-Host " 0  *** GAP ***"
        write-gap "$dt : no records"
        Set-Content (Join-Path $DataD "$file.csv") "" -Encoding UTF8
        $dataStats[$file] = 0
        return
    }
    $recs = @()
    foreach ($item in $list) {
        $full = api-get $dt $item.name
        if ($null -eq $full) {
            # Fallback: frappe.client.get (passes name as query param, handles Unicode)
            $full = api-get-method $dt $item.name
        }
        if ($null -ne $full) {
            $recs += flatten $full
        } else {
            # Last resort: use the list stub (has at least name)
            $recs += flatten $item
        }
    }
    $n = @($recs).Count
    Write-Host " $n"
    @($recs) | Export-Csv (Join-Path $DataD "$file.csv") -NoTypeInformation -Encoding UTF8
    $dataStats[$file] = $n
}

# ==============================================================
# SCHEMA EXPORTS
# ==============================================================

Write-Host ""
Write-Host "-- Schema --"

export-schema "Custom Field"    "custom-fields"
export-schema "Notification"    "notifications"
export-schema "Client Script"   "client-scripts"
export-schema "Server Script"   "server-scripts"
export-schema "Workflow"        "workflows"
export-schema "Property Setter" "property-setters"
export-schema "Role Profile"    "role-profiles"
export-schema "Workspace"       "workspaces"

# Print Formats – custom (non-standard) only
export-schema "Print Format" "print-formats" "" { param($r) $r.standard -ne "Yes" }

# Reports – non-standard (custom) only
export-schema "Report" "reports" '[["Report","is_standard","=","No"]]'

# ==============================================================
# DATA EXPORTS
# ==============================================================

Write-Host ""
Write-Host "-- Data --"

export-data "Company"        "company"          50
export-data "User"           "users"            50
export-data "Role"           "roles"           200
export-data "Warehouse"      "warehouses"      500
export-data "Item Group"     "item-groups"     200
export-data "Item"           "items"            20
export-data "UOM"            "uoms"            200
export-data "Customer"       "customers"        20
export-data "Customer Group" "customer-groups" 200
export-data "Territory"      "territories"     200
export-data "Supplier"       "suppliers"        50
export-data "Supplier Group" "supplier-groups" 200
export-data "Price List"     "price-lists"      50
export-data "Item Price"     "item-prices"      20
export-data "Brand"          "brands"           50

# ==============================================================
# SUMMARY
# ==============================================================

$summary = [ordered]@{
    exported_at  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    base_url     = $BaseUrl
    schema       = $schemaStats
    data         = $dataStats
    gaps_count   = $gaps.Count
    gaps         = @($gaps)
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content (Join-Path $Root "export-summary.json") -Encoding UTF8

Write-Host ""
Write-Host "============================================================"
Write-Host "Export complete"
Write-Host "  Schema files : $(($schemaStats.Keys | Measure-Object).Count)"
Write-Host "  Data CSV files: $(($dataStats.Keys  | Measure-Object).Count)"
Write-Host "  Gaps detected : $($gaps.Count)"
if ($gaps.Count -gt 0) {
    Write-Host ""
    Write-Host "Gaps:"
    $gaps | ForEach-Object { Write-Host "  >>  $_" }
}
