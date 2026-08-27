#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check",
    [ValidateSet("test", "main")]
    [string]$Target = "test"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$BaseUrl = if ($Target -eq "test") { "https://test.erpnext.am" } else { "https://erpnext.am" }
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    try { return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data } catch { return $null }
}
function Save-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $json = $Body | ConvertTo-Json -Depth 30 -Compress
    $existing = Get-ErpDoc $DocType $Name
    if ($existing) {
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
    } else {
        $Body.name = $Name
        $json = $Body | ConvertTo-Json -Depth 30 -Compress
        Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)" -Headers $Headers -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30 | Out-Null
    }
}

Write-Host "=== Restore Task List Toggles ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$ServerName = "task_list_filtered"
$ClientName = "Task-List Toggle Filters"
$server = Get-ErpDoc "Server Script" $ServerName
$client = Get-ErpDoc "Client Script" $ClientName
$global = Get-ErpDoc "Client Script" "Global-Mobile Back Button List"

$serverScript = if ($server) { $server.script } else { "" }
$clientScript = if ($client) { $client.script } elseif ($global) { $global.script } else { "" }

$hasServer = $serverScript -match 'task_list_filtered|TASK_KIND_ALLOWED_ROLES'
$hasAccountException = $serverScript -match 'ACCOUNT_DETAILS_MY_TASK_USERS'
$hasToggleClient = $clientScript -match 'task-toggle-bar' -and $clientScript -match 'My Tasks' -and $clientScript -match 'Open Tasks' -and $clientScript -match 'Completed'
$clientEnabled = $client -and [string]$client.enabled -eq "1" -and $client.dt -eq "Task" -and $client.view -eq "List"

Write-Host "Has task_list_filtered server: $(if($hasServer){'Yes'}else{'No'})"
Write-Host "Has Account details exception: $(if($hasAccountException){'Yes'}else{'No'})"
Write-Host "Has toggle client code: $(if($hasToggleClient){'Yes'}else{'No'})"
Write-Host "Has enabled Task List client script: $(if($clientEnabled){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasServer -and $hasAccountException -and $hasToggleClient -and $clientEnabled) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$backupPath = Join-Path $PSScriptRoot ("_backup_restore_task_list_toggles_" + $Target + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json")
@{ server = $server; client = $client; global = $global } | ConvertTo-Json -Depth 30 | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

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
    "Account details": ["Ops - Accounting", "Ops - Finance", "Ops - Directors"],
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

ACCOUNT_DETAILS_MY_TASK_USERS = [
    "sahakyan.oli1998@gmail.com",
    "ly.aghayan@gmail.com",
    "levonaghinyan77@gmail.com",
    "ghahramanyann@gmail.com",
    "karapetyansev@gmail.com",
]

my_tasks = int(frappe.form_dict.get("my_tasks") or 0)
open_tasks = int(frappe.form_dict.get("open_tasks") or 0)
completed = int(frappe.form_dict.get("completed") or 0)

user = frappe.session.user
role_rows = frappe.get_all("Has Role", filters={"parenttype": "User", "parent": user}, fields=["role"], limit_page_length=0)
user_roles = set([r.role for r in role_rows])
is_admin = user == "Administrator" or "System Manager" in user_roles

allowed_kinds = []
for kind, roles in TASK_KIND_ALLOWED_ROLES.items():
    if is_admin or any(r in user_roles for r in roles):
        allowed_kinds.append(kind)

if not allowed_kinds and not is_admin:
    frappe.response["message"] = []
    raise SystemExit

conditions = []
kind_list = ", ".join(["'" + k.replace("'", "''") + "'" for k in allowed_kinds])
none_selected = (not my_tasks and not open_tasks and not completed)

if none_selected:
    if is_admin:
        conditions.append("1=1")
    else:
        conditions.append("(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')")
else:
    or_clauses = []
    has_open = bool(open_tasks)
    has_completed = bool(completed)
    has_my = bool(my_tasks)

    if has_open and has_completed:
        status_sql = "status != 'Cancelled'"
    elif has_completed and not has_open:
        status_sql = "status = 'Completed'"
    else:
        status_sql = "status NOT IN ('Completed', 'Cancelled')"

    placeholder_conditions = " OR ".join(["_assign LIKE '%" + tp + "%'" for tp in TEAM_PLACEHOLDERS])
    safe_user = user.replace("'", "''")
    team_available_sql = "(_assign IS NULL OR _assign = '' OR _assign = '[]' OR _assign LIKE '%" + safe_user + "%' OR (" + placeholder_conditions + "))"

    if is_admin:
        role_match_sql = "1=1"
    else:
        role_match_sql = "(task_kind IN (" + kind_list + ") OR task_kind IS NULL OR task_kind = '')"

    if has_my:
        my_sql = "(_assign LIKE '%" + safe_user + "%')"
        if user in ACCOUNT_DETAILS_MY_TASK_USERS:
            my_sql = "(" + my_sql + " OR task_kind = 'Account details')"
        or_clauses.append(my_sql)

    if has_open or has_completed:
        team_role_sql = "(" + role_match_sql + " AND " + team_available_sql + ")"
        or_clauses.append(team_role_sql)

    assignment_sql = "(" + " OR ".join(or_clauses) + ")" if or_clauses else "1=1"
    conditions.append(status_sql)
    conditions.append(assignment_sql)

where_clause = " AND ".join(conditions) if conditions else "1=1"
sql = "SELECT name FROM `tabTask` WHERE " + where_clause + " ORDER BY modified DESC LIMIT 500"
results = frappe.db.sql(sql, as_dict=True)
frappe.response["message"] = [r["name"] for r in results]
'@

$ClientScriptBody = @'
frappe.listview_settings['Task'] = frappe.listview_settings['Task'] || {};
var _taskToggleOrigOnload = frappe.listview_settings['Task'].onload;
frappe.listview_settings['Task'].onload = function(listview) {
    if (_taskToggleOrigOnload) _taskToggleOrigOnload(listview);
    var TOGGLE_STATE = { my_tasks: 1, open_tasks: 1, completed: 0 };
    window._taskToggleState = TOGGLE_STATE;

    function renderToggleBar() {
        var $wrapper = $(listview.page.wrapper);
        $wrapper.find('#task-toggle-bar').remove();
        var bar = $('<div id="task-toggle-bar" style="display:flex;gap:8px;padding:8px 12px;background:#f7f7f7;border-bottom:1px solid #d1d8dd;position:sticky;top:0;z-index:100;flex-wrap:wrap;align-items:center;"></div>');
        [
            { key: 'my_tasks', label: 'My Tasks' },
            { key: 'open_tasks', label: 'Open Tasks' },
            { key: 'completed', label: 'Completed' }
        ].forEach(function(t) {
            var lbl = $('<label style="display:flex;align-items:center;gap:5px;cursor:pointer;font-size:13px;font-weight:500;margin:0;padding:6px 10px;border-radius:6px;background:#fff;border:1px solid #d1d8dd;user-select:none;"></label>');
            var cb = $('<input type="checkbox" style="width:16px;height:16px;cursor:pointer;accent-color:#1976d2;">');
            cb.prop('checked', !!TOGGLE_STATE[t.key]);
            cb.on('change', function() {
                TOGGLE_STATE[t.key] = this.checked ? 1 : 0;
                applyToggleFilter();
            });
            lbl.append(cb).append($('<span></span>').text(t.label));
            bar.append(lbl);
        });
        var $listArea = $wrapper.find('.frappe-list').first();
        if ($listArea.length) $listArea.before(bar);
        else $wrapper.find('.page-body').first().prepend(bar);
    }

    function cleanTaskListRoute() {
        var cleanPath = '/desk/task/view/list';
        if (window.location.pathname === cleanPath && window.location.search) {
            window.history.replaceState(window.history.state || {}, document.title, cleanPath);
        }
    }

    function applyToggleFilter() {
        cleanTaskListRoute();
        frappe.call({
            method: 'task_list_filtered',
            args: {
                my_tasks: TOGGLE_STATE.my_tasks,
                open_tasks: TOGGLE_STATE.open_tasks,
                completed: TOGGLE_STATE.completed
            },
            callback: function(r) {
                var names = (r && r.message) || [];
                window._taskToggleNames = names;
                var lv = cur_list || listview;
                lv.filter_area.clear().then(function() {
                    if (names.length > 0) lv.filter_area.add('Task', 'name', 'in', names);
                    else lv.filter_area.add('Task', 'name', '=', '__no_task_toggle_results__');
                    lv.refresh();
                    setTimeout(cleanTaskListRoute, 50);
                    setTimeout(cleanTaskListRoute, 300);
                    setTimeout(cleanTaskListRoute, 1000);
                });
            },
            error: function() {
                var lv = cur_list || listview;
                lv.filter_area.clear().then(function() { lv.refresh(); });
            }
        });
    }

    setTimeout(function() {
        cleanTaskListRoute();
        renderToggleBar();
        applyToggleFilter();
    }, 300);
};
'@

Save-ErpDoc "Server Script" $ServerName @{ script_type = "API"; api_method = $ServerName; script = $ServerScriptBody; disabled = 0; allow_guest = 0; enable_rate_limit = 0 }
Save-ErpDoc "Client Script" $ClientName @{ dt = "Task"; view = "List"; enabled = 1; script = $ClientScriptBody }
Write-Host "Task list toggles restored" -ForegroundColor Green
