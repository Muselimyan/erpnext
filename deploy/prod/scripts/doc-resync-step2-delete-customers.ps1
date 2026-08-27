param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

# ── config from export.ps1 ────────────────────────────────────────────────────
$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config  = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$H = @{ Authorization = "token ${ApiKey}:${ApiSec}"; "Content-Type" = "application/json" }

function Enc([string]$v) { [uri]::EscapeDataString($v) }

function Invoke-Erp {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method }
    return Invoke-RestMethod -Uri $Uri -Headers $H -Method $Method -Body ($Body | ConvertTo-Json -Depth 20)
}

function Get-ErpList {
    param([string]$DocType, [array]$Fields = @("name"), [array]$Filters = @(), [int]$Limit = 2000)
    $F   = ConvertTo-Json -InputObject @($Fields)  -Compress
    $Fil = ConvertTo-Json -InputObject @($Filters) -Compress -Depth 10
    $Path = "/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $F)&filters=$(Enc $Fil)"
    try { return (Invoke-Erp -Method Get -Path $Path).data }
    catch { Write-Warning "GET $DocType failed: $_"; return @() }
}

# Skip-list: system / default customers that must not be deleted
$SYSTEM_NAMES = @("Walk-In Customer", "All Customers")

# ── gather info ───────────────────────────────────────────────────────────────
$AllCustomers = Get-ErpList -DocType "Customer" -Fields @("name","client_code","client_kind") -Limit 2000
$CustomCustomers = $AllCustomers | Where-Object { $SYSTEM_NAMES -notcontains $_.name }

Write-Host "Total customers found: $($AllCustomers.Count)"
Write-Host "Deletable (non-system): $($CustomCustomers.Count)"

# Check for blocking transactions
$BlockingDocs = [System.Collections.ArrayList]::new()
foreach ($DocType in @("Sales Order", "Sales Invoice", "Payment Entry")) {
    $Rows = Get-ErpList -DocType $DocType -Fields @("name","docstatus") -Limit 5000
    foreach ($r in $Rows) {
        $null = $BlockingDocs.Add([pscustomobject]@{ doctype = $DocType; name = $r.name; docstatus = $r.docstatus })
    }
}

Write-Host "Blocking docs found: $($BlockingDocs.Count)"
$BlockingDocs | Group-Object doctype | ForEach-Object { Write-Host "  $($_.Name): $($_.Count)" }

if ($Mode -eq "Check") {
    [ordered]@{
        mode           = "Check"
        customers_total     = $AllCustomers.Count
        customers_deletable = $CustomCustomers.Count
        blocking_docs  = $BlockingDocs | Group-Object doctype | ForEach-Object { @{ $_.Name = $_.Count } }
        sample_customers = ($CustomCustomers | Select-Object -First 10).name
    } | ConvertTo-Json -Depth 10
    exit 0
}

# ── Deploy: delete blocking docs first, then customers ────────────────────────
$Results = [System.Collections.ArrayList]::new()

function Invoke-FrappeDelete([string]$DocType, [string]$Name, [int]$DocStatus) {
    try {
        if ($DocStatus -eq 1) {
            # Cancel via whitelisted method (body-based, no URL encoding issues)
            Invoke-Erp -Method Post -Path "/api/method/frappe.client.submit" -Body @{ doc = @{ doctype = $DocType; name = $Name; docstatus = 2 } } | Out-Null
        }
        # Delete via body-based method
        Invoke-Erp -Method Post -Path "/api/method/frappe.client.delete" -Body @{ doctype = $DocType; name = $Name } | Out-Null
        return [pscustomobject]@{ action = "deleted"; doctype = $DocType; name = $Name; ok = $true }
    }
    catch {
        return [pscustomobject]@{ action = "delete_failed"; doctype = $DocType; name = $Name; ok = $false; error = $_.Exception.Message }
    }
}

foreach ($Doc in $BlockingDocs) {
    $null = $Results.Add((Invoke-FrappeDelete -DocType $Doc.doctype -Name $Doc.name -DocStatus $Doc.docstatus))
}

foreach ($Cust in $CustomCustomers) {
    $null = $Results.Add((Invoke-FrappeDelete -DocType "Customer" -Name $Cust.name -DocStatus 0))
}

$ok  = ($Results | Where-Object ok).Count
$err = ($Results | Where-Object { -not $_.ok }).Count
Write-Host "Deleted: $ok  Errors: $err"

[ordered]@{
    mode    = "Deploy"
    deleted = $ok
    errors  = $err
    results = $Results
} | ConvertTo-Json -Depth 10
