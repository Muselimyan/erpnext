$ErrorActionPreference = "Stop"

$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }
function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Get -TimeoutSec 30).data
}
function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 40 -Compress
    Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 30 | Out-Null
}
function Ensure-Helper([string]$Script) {
    $helper = @'

function account_details_entry_keep_next_assign_empty(frm) {
    if (!frm || !frm.doc) return;
    if (String(frm.doc.task_kind || "").trim() !== "Account Details: Entry") return;
    var nextAssign = String(frm.doc.custom_next_task_assign_to || "").trim();
    var currentAssign = String(frm.doc.custom_assigned_to || "").trim();
    if (nextAssign && (!currentAssign || nextAssign === currentAssign)) {
        frm.set_value("custom_next_task_assign_to", "");
    }
}
'@
    if ($Script -notmatch 'function account_details_entry_keep_next_assign_empty') { $Script += $helper }
    return $Script
}
function Add-AfterFirst([string]$Script, [string]$Needle, [string]$Insert) {
    $Insert = $Insert.Replace('`n', "`n")
    if ($Script.Contains($Insert.Trim())) { return $Script }
    if (-not $Script.Contains($Needle)) { throw "Insertion point not found: $Needle" }
    return $Script.Replace($Needle, $Needle + $Insert)
}

Write-Host "Patching Account Details Entry next assignment on PROD: $BaseUrl" -ForegroundColor Cyan

Put-ErpDoc "Custom Field" "Task-custom_next_task_assign_to" @{ hidden = 0; read_only = 0; depends_on = ""; label = "Next Task: Assign To" }
Write-Host "Updated Custom Field: Task-custom_next_task_assign_to" -ForegroundColor Green

foreach ($ClientName in @("Task-Accept Start", "Task-Account Details UI Cleanup")) {
    $Client = Get-ErpDoc "Client Script" $ClientName
    $Script = [string]$Client.script
    $Script = $Script.Replace("    custom_next_task_assign_to(frm) {`n        if (frm && frm.doc) frm._account_details_next_assign_touched = true;`n    },    custom_account_details_subject(frm) {", "    custom_account_details_subject(frm) {")
    $Script = $Script.Replace('if (!frm || !frm.doc || frm._account_details_next_assign_touched) return;', 'if (!frm || !frm.doc) return;')
    $Script = Ensure-Helper $Script
    if ($ClientName -eq "Task-Accept Start") {
        $Script = $Script.Replace('if (dispatchKinds.includes(frm.doc.task_kind)) {', 'if (dispatchKinds.includes(frm.doc.task_kind) || frm.doc.task_kind === "Account Details: Entry") {')
        $Script = Add-AfterFirst $Script 'account_details_entry_ui_cleanup(frm);' "`n        if (frm.doc.task_kind === `"Account Details: Entry`" && frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property(`"custom_next_task_assign_to`", `"hidden`", 0); frm.toggle_display(`"custom_next_task_assign_to`", true); }`n        account_details_entry_keep_next_assign_empty(frm);"
    } else {
        $Script = Add-AfterFirst $Script 'task_account_details_add_new_accept_button(frm);' "`n    if (taskKind === `"account details: entry`" && frm.fields_dict.custom_next_task_assign_to) { frm.set_df_property(`"custom_next_task_assign_to`", `"hidden`", 0); frm.toggle_display(`"custom_next_task_assign_to`", true); }`n    account_details_entry_keep_next_assign_empty(frm);"
        $Script = Add-AfterFirst $Script 'task_account_details_prepare_subject(frm);' "`n        account_details_entry_keep_next_assign_empty(frm);"
    }
    Put-ErpDoc "Client Script" $ClientName @{ script = $Script; enabled = 1; dt = "Task"; view = "Form" }
    Write-Host "Updated Client Script: $ClientName" -ForegroundColor Green
}

$ServerName = "Task-Account Details Default Assignment"
$Server = Get-ErpDoc "Server Script" $ServerName
$ServerScript = [string]$Server.script
$ServerScript = $ServerScript.Replace('if doc.get("custom_next_task_assign_to") and doc.get("custom_next_task_assign_to") == doc.get("custom_assigned_to"):', 'if doc.get("custom_next_task_assign_to") and (not doc.get("custom_assigned_to") or doc.get("custom_next_task_assign_to") == doc.get("custom_assigned_to")):')
Put-ErpDoc "Server Script" $ServerName @{ script = $ServerScript; disabled = 0 }
Write-Host "Updated Server Script: $ServerName" -ForegroundColor Green

$ProcessingName = "Task-after-save-account-details-processing"
$Processing = Get-ErpDoc "Server Script" $ProcessingName
$ProcessingScript = [string]$Processing.script
$ProcessingScript = $ProcessingScript -replace 'if assignee and assignee == doc\.get\("custom_assigned_to"\):', 'if assignee and (not doc.get("custom_assigned_to") or assignee == doc.get("custom_assigned_to")):'
Put-ErpDoc "Server Script" $ProcessingName @{ script = $ProcessingScript; disabled = 0 }
Write-Host "Updated Server Script: $ProcessingName" -ForegroundColor Green

Write-Host "Patch complete on PROD." -ForegroundColor Cyan
