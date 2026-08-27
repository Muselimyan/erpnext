# System Status Check - Go-Live Readiness
# Checks all API-accessible items from the go-live action plan

param()

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Enc([string]$Value) { [uri]::EscapeDataString($Value) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body = $null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
    }
    $Json = $Body | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Json
}

function Get-ErpList {
    param([string]$DocType, [array]$Fields = @("name"), [array]$Filters = @(), [int]$Limit = 500)
    $FieldsJson = $Fields | ConvertTo-Json -Compress
    $Path = "/api/resource/$(Enc $DocType)?limit_page_length=$Limit&fields=$(Enc $FieldsJson)"
    if ($Filters.Count -gt 0) {
        $FiltersJson = $Filters | ConvertTo-Json -Compress -Depth 10
        $Path += "&filters=$(Enc $FiltersJson)"
    }
    return (Invoke-ErpRequest -Method Get -Path $Path).data
}

$Report = [ordered]@{
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    checks = [ordered]@{}
}

Write-Host "=== ERPNext Go-Live Status Check ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check example users
Write-Host "1. Checking example users..." -ForegroundColor Yellow
$ExampleEmails = @(
    "order.team@example.com",
    "inventory.team@example.com",
    "returns.team@example.com",
    "dispatch.coordinator@example.com",
    "driver.01@example.com",
    "accounting.team@example.com",
    "director.01@example.com",
    "order.creation.team@example.com",
    "finance.team@example.com"
)
$Users = Get-ErpList -DocType "User" -Fields @("name", "email", "enabled", "roles") -Limit 100
$ExampleUsers = $Users | Where-Object { $_.email -in $ExampleEmails }
$Report.checks.example_users = [ordered]@{
    total_found = $ExampleUsers.Count
    users = $ExampleUsers | ForEach-Object { [ordered]@{ email = $_.email; enabled = $_.enabled } }
}
Write-Host "   Found $($ExampleUsers.Count) example users" -ForegroundColor Green

# 2. Check Task Access Policy records
Write-Host "2. Checking Task Access Policy records..." -ForegroundColor Yellow
$RequiredPolicies = @(
    "Order entry",
    "Pack / prepare items",
    "Dispatch picking / hand-off",
    "Delivery",
    "Return to warehouse (aborted delivery / cancelled order)",
    "Pickup Returns",
    "Return drop-off at warehouse",
    "Returns processing / verification",
    "Returns restocking",
    "Invoice preparation / create invoice",
    "Debt Collection",
    "Distribute Payment",
    "Payment Received",
    "Discount Approval",
    "Purchase Approval",
    "Write-off Approval"
)
$Policies = Get-ErpList -DocType "Task Access Policy" -Fields @("name") -Limit 100
$PolicyNames = $Policies | ForEach-Object { $_.name }
$Missing = $RequiredPolicies | Where-Object { $_ -notin $PolicyNames }
$Report.checks.task_access_policies = [ordered]@{
    required = $RequiredPolicies.Count
    found = $Policies.Count
    missing = $Missing
}
if ($Missing.Count -eq 0) {
    Write-Host "   All $($RequiredPolicies.Count) Task Access Policies exist" -ForegroundColor Green
} else {
    Write-Host "   MISSING $($Missing.Count) policies: $($Missing -join ', ')" -ForegroundColor Red
}

# 3. Check draft Purchase Orders missing required fields
Write-Host "3. Checking draft Purchase Orders..." -ForegroundColor Yellow
$DraftPOs = Get-ErpList -DocType "Purchase Order" -Fields @("name", "purchase_reason", "requested_by", "docstatus") -Filters @(@("Purchase Order", "docstatus", "=", 0)) -Limit 100
$MissingFields = $DraftPOs | Where-Object { -not $_.purchase_reason -or -not $_.requested_by }
$Report.checks.draft_purchase_orders = [ordered]@{
    total_drafts = $DraftPOs.Count
    missing_required_fields = $MissingFields.Count
    problematic_pos = $MissingFields | ForEach-Object { $_.name }
}
if ($MissingFields.Count -eq 0) {
    Write-Host "   All $($DraftPOs.Count) draft POs have required fields" -ForegroundColor Green
} else {
    Write-Host "   PROBLEM: $($MissingFields.Count) draft POs missing purchase_reason or requested_by" -ForegroundColor Red
}

# 4. Check Tasks with wrong assignee count
Write-Host "4. Checking Tasks for governance issues..." -ForegroundColor Yellow
$Tasks = Get-ErpList -DocType "Task" -Fields @("name", "status", "_assign") -Filters @(@("Task", "status", "not in", @("Cancelled"))) -Limit 500
$BadTasks = @()
foreach ($Task in $Tasks) {
    if ($Task.status -in @("Working", "Completed")) {
        $Assignees = if ($Task._assign) { ($Task._assign | ConvertFrom-Json) } else { @() }
        if ($Assignees.Count -ne 1) {
            $BadTasks += [pscustomobject]@{
                name = $Task.name
                status = $Task.status
                assignee_count = $Assignees.Count
            }
        }
    }
}
$Report.checks.malformed_tasks = [ordered]@{
    total_active_tasks = $Tasks.Count
    bad_assignee_count = $BadTasks.Count
    problematic_tasks = $BadTasks
}
if ($BadTasks.Count -eq 0) {
    Write-Host "   All active tasks have correct assignee count" -ForegroundColor Green
} else {
    Write-Host "   PROBLEM: $($BadTasks.Count) tasks have 0 or 2+ assignees (will fail governance script)" -ForegroundColor Red
}

# 5. Check test customer record
Write-Host "5. Checking for test customer..." -ForegroundColor Yellow
$TestCustomer = Get-ErpList -DocType "Customer" -Fields @("name", "customer_name") -Filters @(@("Customer", "name", "=", "TEST01")) -Limit 1
$Report.checks.test_customer = [ordered]@{
    exists = ($TestCustomer.Count -gt 0)
    name = if ($TestCustomer.Count -gt 0) { $TestCustomer[0].customer_name } else { $null }
}
if ($TestCustomer.Count -gt 0) {
    Write-Host "   Test customer 'TEST01' still exists (should be deleted)" -ForegroundColor Yellow
} else {
    Write-Host "   No test customer found" -ForegroundColor Green
}

# 6. Check customers with debt_threshold_amd = 0
Write-Host "6. Checking customer debt thresholds..." -ForegroundColor Yellow
$Customers = Get-ErpList -DocType "Customer" -Fields @("name", "customer_name", "debt_threshold_amd") -Limit 500
$ZeroThreshold = $Customers | Where-Object { -not $_.debt_threshold_amd -or $_.debt_threshold_amd -eq 0 }
$Report.checks.customer_debt_thresholds = [ordered]@{
    total_customers = $Customers.Count
    zero_threshold_count = $ZeroThreshold.Count
    percentage_zero = [math]::Round(($ZeroThreshold.Count / $Customers.Count) * 100, 1)
}
if ($ZeroThreshold.Count -eq $Customers.Count) {
    Write-Host "   BLOCKER: ALL $($Customers.Count) customers have debt_threshold_amd = 0 (debt escalation disabled)" -ForegroundColor Red
} elseif ($ZeroThreshold.Count -gt 0) {
    Write-Host "   WARNING: $($ZeroThreshold.Count) / $($Customers.Count) customers have zero threshold" -ForegroundColor Yellow
} else {
    Write-Host "   All customers have debt thresholds set" -ForegroundColor Green
}

# 7. Check price lists
Write-Host "7. Checking price lists..." -ForegroundColor Yellow
$ItemPrices = Get-ErpList -DocType "Item Price" -Fields @("name", "price_list", "item_code", "price_list_rate") -Limit 1000
$StandardSelling = $ItemPrices | Where-Object { $_.price_list -eq "Standard Selling" }
$StandardBuying = $ItemPrices | Where-Object { $_.price_list -eq "Standard Buying" }
$Report.checks.price_lists = [ordered]@{
    standard_selling_count = $StandardSelling.Count
    standard_buying_count = $StandardBuying.Count
    total_item_prices = $ItemPrices.Count
}
if ($StandardSelling.Count -eq 0) {
    Write-Host "   BLOCKER: Standard Selling price list is EMPTY (orders cannot be priced)" -ForegroundColor Red
} else {
    Write-Host "   Standard Selling: $($StandardSelling.Count) prices" -ForegroundColor Green
}
if ($StandardBuying.Count -eq 0) {
    Write-Host "   WARNING: Standard Buying price list is EMPTY (profit reports will show 0)" -ForegroundColor Yellow
} else {
    Write-Host "   Standard Buying: $($StandardBuying.Count) prices" -ForegroundColor Green
}

# 8. Check items without tracking flags set
Write-Host "8. Checking item tracking configuration..." -ForegroundColor Yellow
$Items = Get-ErpList -DocType "Item" -Fields @("name", "item_name", "has_batch_no", "has_serial_no", "has_expiry_date") -Limit 500
$NoTracking = $Items | Where-Object { -not $_.has_batch_no -and -not $_.has_serial_no }
$Report.checks.item_tracking = [ordered]@{
    total_items = $Items.Count
    no_tracking_count = $NoTracking.Count
    batch_tracked = ($Items | Where-Object { $_.has_batch_no }).Count
    serial_tracked = ($Items | Where-Object { $_.has_serial_no }).Count
}
if ($NoTracking.Count -eq $Items.Count) {
    Write-Host "   WARNING: ALL $($Items.Count) items have no batch/serial tracking (decision needed before first stock transaction)" -ForegroundColor Yellow
} else {
    Write-Host "   $($NoTracking.Count) items untracked, $($Items.Count - $NoTracking.Count) have tracking enabled" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$Report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $PSScriptRoot "system-status-report.json") -Encoding UTF8
Write-Host "Full report saved to: system-status-report.json" -ForegroundColor Green
