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
def get_user_roles(user):
    if not user:
        return set([])
    roles = frappe.db.get_all("Has Role", filters={"parent": user}, pluck="role") or []
    if user == "Administrator":
        roles.append("System Manager")
    return set(roles)
def current_user_roles():
    return get_user_roles(frappe.session.user)
def has_any_role(user_roles, allowed_roles):
    return any(r in user_roles for r in (allowed_roles or []))
def is_admin_override(user_roles):
    return bool("System Manager" in user_roles or DIRECTOR_ROLE in user_roles or frappe.session.user == "Administrator")
def get_assigned_users(task_doc):
    try:
        return json.loads(task_doc.get("_assign") or "[]") or []
    except Exception:
        return []
def user_has_allowed_role(user, allowed_roles):
    return has_any_role(get_user_roles(user), allowed_roles)
if doc.task_kind and not doc.task_access_policy:
    doc.task_access_policy = doc.task_kind
if doc.task_access_policy and not frappe.db.exists("Task Access Policy", doc.task_access_policy):
    frappe.throw("Task Access Policy '" + doc.task_access_policy + "' does not exist. Create it so tasks remain visible.")
user_roles = current_user_roles()
allowed_roles = TASK_KIND_ALLOWED_ROLES.get(doc.task_kind) or []
if before and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        frappe.throw("You are not allowed to edit Task Kind '" + doc.task_kind + "'. Only the owning team can edit it, or Directors/System Manager.")
if is_becoming_completed and doc.task_kind and not is_admin_override(user_roles):
    if not has_any_role(user_roles, allowed_roles):
        roles_text = ", ".join(["'" + r + "'" for r in allowed_roles])
        frappe.throw("Only users with roles " + roles_text + " can complete Task Kind '" + doc.task_kind + "'.")
if is_becoming_completed and doc.task_kind == "Delivery":
    if not doc.warehouse_pickup_photo:
        frappe.throw("Warehouse Pickup Photo is required to complete a Delivery task.")
if is_becoming_completed and doc.task_kind == "Return drop-off at warehouse":
    if not doc.warehouse_dropoff_photo:
        frappe.throw("Warehouse Drop-off Photo is required to complete a Return drop-off at warehouse task.")
assigned_users = get_assigned_users(doc)
if doc.task_kind and doc.status not in ("Cancelled", "Open"):
    if len(assigned_users) != 1:
        frappe.throw("Each operational task must be assigned to exactly 1 user. Current assignee count: " + str(len(assigned_users)) + ".")
if doc.task_kind and len(assigned_users) == 1 and allowed_roles:
    owner = assigned_users[0]
    if not user_has_allowed_role(owner, allowed_roles):
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
    desired_contains_get_roles=$PolicyScript.Contains("frappe.get_roles")
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
