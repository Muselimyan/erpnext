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

$PolicyScript = @'
before = doc.get_doc_before_save()
before_status = before.status if before else None
is_becoming_completed = (doc.status == "Completed" and before_status != "Completed")
DIRECTOR_ROLE = "Ops - Directors"
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
}
current_user_role_rows = frappe.db.get_all("Has Role", filters={"parent": frappe.session.user}, pluck="role") or []
current_user_roles = set(current_user_role_rows)
if frappe.session.user == "Administrator":
    current_user_roles.add("System Manager")
allowed_roles = TASK_KIND_ALLOWED_ROLES.get(doc.task_kind) or []
is_admin = bool("System Manager" in current_user_roles or DIRECTOR_ROLE in current_user_roles or frappe.session.user == "Administrator")
if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind
if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw("Task Access Policy '" + doc.task_access_policy + "' does not exist. Create it so tasks remain visible.")
user_has_allowed_role = any(r in current_user_roles for r in allowed_roles)
if before and doc.task_kind and not is_admin and not user_has_allowed_role:
    frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'. Only the owning team can edit it, or Directors/System Manager.")
if is_becoming_completed and doc.task_kind and not is_admin and not user_has_allowed_role:
    roles_text = ", ".join(["'" + r + "'" for r in allowed_roles])
    frappe.throw("Only users with roles " + roles_text + " can complete Task Kind '" + doc.task_kind + "'.")
if is_becoming_completed and doc.task_kind == "Delivery":
    if not doc.warehouse_pickup_photo:
        frappe.throw("Warehouse Pickup Photo is required to complete a Delivery task.")
if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
    if not doc.warehouse_dropoff_photo:
        frappe.throw("Warehouse Drop-off Photo is required to complete a Return drop-off at warehouse task.")
try:
    assigned_users = json.loads(doc.get("_assign") or "[]") or []
except Exception:
    assigned_users = []
if doc.task_kind and doc.status not in ("Cancelled", "Open"):
    if len(assigned_users) != 1:
        frappe.throw("Each operational task must be assigned to exactly 1 user. Current assignee count: " + str(len(assigned_users)) + ".")
if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
    assigned_user = assigned_users[0]
    assigned_role_rows = frappe.db.get_all("Has Role", filters={"parent": assigned_user}, pluck="role") or []
    assigned_roles = set(assigned_role_rows)
    if assigned_user == "Administrator":
        assigned_roles.add("System Manager")
    assignee_allowed = any(r in assigned_roles for r in allowed_roles)
    if not assignee_allowed:
        roles_text = ", ".join(["'" + r + "'" for r in allowed_roles])
        frappe.throw("Task Kind '" + doc.task_kind + "' must be assigned to a user in the owning team. Allowed roles: " + roles_text + ".")
if is_becoming_completed:
    if len(assigned_users) != 1:
        frappe.throw("You must assign exactly 1 owner before completing this task.")
if is_becoming_completed and not doc.completed_at:
    doc.completed_at = now_datetime()
'@

$Existing = Get-ErpDoc -DocType "Server Script" -Name "Task-before-save-policy"
$Report = [ordered]@{
    mode=$Mode
    target="Task-before-save-policy"
    exists=($null -ne $Existing)
    current_contains_get_roles=if($null -ne $Existing){(([string]$Existing.script).Contains("frappe.get_roles"))}else{$null}
    current_contains_helper_functions=if($null -ne $Existing){(([string]$Existing.script).Contains("def get_user_roles") -or ([string]$Existing.script).Contains("def current_user_roles"))}else{$null}
    desired_contains_helper_functions=$PolicyScript.Contains("def ")
    would_change=if($null -ne $Existing){(([string]$Existing.script) -ne $PolicyScript)}else{$false}
    applied=$false
    error=$null
}

if ($Mode -eq "Deploy" -and $null -ne $Existing -and $Report.would_change) {
    try {
        $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/Server%20Script/$(Enc 'Task-before-save-policy')" -Body ([ordered]@{ script=$PolicyScript })).data
        $Report.applied = $true
        $Report.updated_name = $Updated.name
    } catch {
        $Report.error = $_.Exception.Message
    }
}

$Report | ConvertTo-Json -Depth 10
