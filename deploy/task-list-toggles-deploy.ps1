param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

function Invoke-ErpRequest {
    param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

function Get-ErpDoc {
    param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data }
    catch { return $null }
}

# ===========================================================================
# 1. Server Script: task_list_filtered API
# ===========================================================================

$ServerScriptName = "task_list_filtered"

$ServerScriptBody = @'
TASK_KIND_ALLOWED_ROLES = {
    "Order entry": ["Ops - Order Accepting", "Ops - Order Creating"],
    "Pack / prepare items": ["Ops - Inventory"],
    "Dispatch picking / hand-off": ["Ops - Delivery"],
    "Delivery": ["Delivery Driver", "Ops - Delivery"],
    "Return to warehouse (aborted delivery / cancelled order)": ["Delivery Driver", "Ops - Delivery"],
    "Pickup Returns": ["Delivery Driver", "Ops - Delivery", "Ops - Returns"],
    "Return drop-off at warehouse": ["Delivery Driver", "Ops - Delivery"],
    "Returns processing / verification": ["Ops - Returns", "Ops - Inventory"],
    "Returns restocking": ["Ops - Returns"],
    "Invoice preparation / create invoice": ["Ops - Accounting"],
    "Debt Collection": ["Ops - Finance", "Ops - Directors"],
    "Distribute Payment": ["Ops - Finance", "Ops - Directors"],
    "Payment Received": ["Ops - Finance", "Ops - Directors"],
    "Discount Approval": ["Ops - Directors"],
    "Purchase Approval": ["Ops - Directors"],
    "Write-off Approval": ["Ops - Directors"],
    "Other": ["Ops - Order Accepting", "Ops - Order Creating", "Ops - Inventory", "Ops - Returns", "Ops - Delivery", "Ops - Accounting", "Ops - Directors", "Ops - Finance", "Delivery Driver"],
    "Return Call": ["Ops - Returns", "Ops - Delivery"],
}

TEAM_PLACEHOLDERS = [
    "inventory.team@example.com",
    "delivery.team@example.com",
    "returns.team@example.com",
    "accounting.team@example.com",
    "finance.team@example.com",
    "order.creation.team@example.com",
    "order.team@example.com",
    "directors.team@example.com",
]

my_tasks = int(frappe.form_dict.get("my_tasks") or 0)
open_tasks = int(frappe.form_dict.get("open_tasks") or 0)
completed = int(frappe.form_dict.get("completed") or 0)

user = frappe.session.user
is_admin = user == "Administrator" or "System Manager" in frappe.get_roles(user)

# Get user roles
user_roles = set(frappe.get_roles(user))

# Find allowed task_kinds for this user
allowed_kinds = []
for kind, roles in TASK_KIND_ALLOWED_ROLES.items():
    if is_admin or any(r in user_roles for r in roles):
        allowed_kinds.append(kind)

if not allowed_kinds and not is_admin:
    frappe.response["message"] = []
    raise SystemExit

# Build conditions
conditions = []
params = {"user": user}

# Quote allowed_kinds for SQL
kind_list = ", ".join(["'" + k.replace("'", "''") + "'" for k in allowed_kinds])

none_selected = (not my_tasks and not open_tasks and not completed)

if none_selected:
    # Show all tasks user can do by role, any assignment, any status
    if is_admin:
        conditions.append("1=1")
    else:
        conditions.append("(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')")
else:
    # Build OR clauses for each toggle
    or_clauses = []

    # Determine status filter
    has_open = bool(open_tasks)
    has_completed = bool(completed)
    has_my = bool(my_tasks)

    # Status conditions
    if has_open and has_completed:
        status_not_cancelled = "status != 'Cancelled'"
    elif has_open:
        status_open = "status NOT IN ('Completed', 'Cancelled')"
    elif has_completed:
        status_completed = "status = 'Completed'"
    else:
        # Only "My Tasks" checked, default to not completed
        status_open = "status NOT IN ('Completed', 'Cancelled')"

    # Determine the actual status SQL
    if has_open and has_completed:
        status_sql = "status != 'Cancelled'"
    elif has_completed and not has_open:
        status_sql = "status = 'Completed'"
    else:
        status_sql = "status NOT IN ('Completed', 'Cancelled')"

    # Build team-available condition (not assigned to a specific other person)
    # _assign is a JSON array string like '["user@example.com"]' or null
    # Team-available means: _assign is null/empty, OR contains only team placeholders, OR contains current user
    placeholder_conditions = " OR ".join(["_assign LIKE '%" + tp + "%'" for tp in TEAM_PLACEHOLDERS])
    team_available_sql = "(_assign IS NULL OR _assign = '' OR _assign = '[]' OR _assign LIKE '%{user}%' OR ({ph}))".format(user=user.replace("'", "''"), ph=placeholder_conditions)

    if is_admin:
        role_match_sql = "1=1"
    else:
        role_match_sql = "(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')"

    if has_my:
        my_sql = "(_assign LIKE '%{user}%')".format(user=user.replace("'", "''"))
        or_clauses.append(my_sql)

    if has_open or has_completed:
        team_role_sql = "(" + role_match_sql + " AND " + team_available_sql + ")"
        or_clauses.append(team_role_sql)

    if or_clauses:
        assignment_sql = "(" + " OR ".join(or_clauses) + ")"
    else:
        assignment_sql = "1=1"

    conditions.append(status_sql)
    conditions.append(assignment_sql)

where_clause = " AND ".join(conditions) if conditions else "1=1"
sql = "SELECT name FROM `tabTask` WHERE " + where_clause + " ORDER BY modified DESC LIMIT 500"

results = frappe.db.sql(sql, as_dict=True)
frappe.response["message"] = [r["name"] for r in results]
'@

Write-Host "`n=== 1. Server Script: $ServerScriptName ===" -ForegroundColor Cyan
$ExistingServer = Get-ErpDoc "Server Script" $ServerScriptName

if ($null -ne $ExistingServer) {
    Write-Host "Exists. Will update." -ForegroundColor Yellow
} else {
    Write-Host "Does not exist. Will create." -ForegroundColor Yellow
}

if ($Mode -eq "Deploy") {
    $Body = [ordered]@{
        script_type  = "API"
        api_method   = $ServerScriptName
        script       = $ServerScriptBody
        disabled     = 0
        allow_guest  = 0
    }

    if ($null -eq $ExistingServer) {
        $Body.name = $ServerScriptName
        try {
            $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/Server%20Script" -Body $Body).data
            Write-Host "Created: $($C.name)" -ForegroundColor Green
        } catch {
            Write-Host "ERROR creating: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        try {
            Invoke-ErpRequest -Method Put -Path "/api/resource/Server%20Script/$(Enc $ServerScriptName)" -Body $Body | Out-Null
            Write-Host "Updated." -ForegroundColor Green
        } catch {
            Write-Host "ERROR updating: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ===========================================================================
# 2. Client Script: Task List Toggle Filters
# ===========================================================================

$ClientScriptName = "Task-List Toggle Filters"

$FullClientScript = Get-Content (Join-Path (Join-Path $PSScriptRoot "..") "_temp_task_list.js") -Raw

Write-Host "`n=== 2. Client Script: $ClientScriptName ===" -ForegroundColor Cyan

# Check for existing client script with this name
$ExistingClient = Get-ErpDoc "Client Script" $ClientScriptName

# Also check the existing Global-Mobile Back Button List script
$ExistingList = Get-ErpDoc "Client Script" "Global-Mobile Back Button List"

if ($null -ne $ExistingClient) {
    Write-Host "Client Script '$ClientScriptName' exists. Will update." -ForegroundColor Yellow
} elseif ($null -ne $ExistingList) {
    Write-Host "Will update existing 'Global-Mobile Back Button List' script." -ForegroundColor Yellow
} else {
    Write-Host "Will create new Client Script." -ForegroundColor Yellow
}

if ($Mode -eq "Deploy") {
    if ($null -ne $ExistingClient) {
        # Update existing toggle script
        try {
            Invoke-ErpRequest -Method Put -Path "/api/resource/Client%20Script/$(Enc $ClientScriptName)" -Body @{ script = $FullClientScript } | Out-Null
            Write-Host "Updated '$ClientScriptName'." -ForegroundColor Green
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    } elseif ($null -ne $ExistingList) {
        # Update the existing list script with the combined code
        try {
            Invoke-ErpRequest -Method Put -Path "/api/resource/Client%20Script/$(Enc 'Global-Mobile Back Button List')" -Body @{ script = $FullClientScript } | Out-Null
            Write-Host "Updated 'Global-Mobile Back Button List' with toggle code." -ForegroundColor Green
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        # Create new
        $Body = [ordered]@{
            name     = $ClientScriptName
            dt       = "Task"
            view     = "List"
            script   = $FullClientScript
            enabled  = 1
        }
        try {
            $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/Client%20Script" -Body $Body).data
            Write-Host "Created: $($C.name)" -ForegroundColor Green
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`n=== Done ($Mode) ===" -ForegroundColor Cyan
