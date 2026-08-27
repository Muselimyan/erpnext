#Requires -Version 5.1
param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config = Get-Content $ConfigPath -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Enc([string]$s) { [uri]::EscapeDataString($s) }
function Get-ErpDoc([string]$DocType, [string]$Name) {
    return (Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)?fields=[`"name`",`"script`",`"enabled`",`"modified`"]" -Headers $Headers -Method Get -TimeoutSec 30).data
}
function Put-ErpDoc([string]$DocType, [string]$Name, $Body) {
    $Json = $Body | ConvertTo-Json -Depth 20 -Compress
    return Invoke-RestMethod -Uri "$BaseUrl/api/resource/$(Enc $DocType)/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 60
}

$ScriptName = "Task-Accept Start"
$Client = Get-ErpDoc "Client Script" $ScriptName
$Script = [string]$Client.script

$Old = @'
                    btn.data("busy", true).prop("disabled", true).text("Saving...");
                    var timeoutId = setTimeout(function() {
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Timeout");
                        frappe.show_alert({message: "Complete Task timed out after 30 seconds. Please try again.", indicator: "red"}, 10);
                    }, 30000);
                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }
                    frm.save()
                        .then(function() {
                            btn.text("Completing...");
                            frm.doc.status = "Completed";
                            if (!frm.doc.completed_on) {
                                frm.doc.completed_on = frappe.datetime.get_today();
                            }
                            frm.dirty();
                            return frm.save();
                        })
'@

$New = @'
                    var hasUnsavedWork = frm.is_dirty();
                    btn.data("busy", true).prop("disabled", true).text(hasUnsavedWork ? "Saving..." : "Completing...");
                    var timeoutId = setTimeout(function() {
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Timeout");
                        frappe.show_alert({message: "Complete Task timed out after 30 seconds. Please try again.", indicator: "red"}, 10);
                    }, 30000);
                    function resetButton() {
                        clearTimeout(timeoutId);
                        btn.data("busy", false).prop("disabled", false).css("background-color", "#e74c3c").text("Complete Task");
                    }
                    var saveBeforeComplete = hasUnsavedWork ? frm.save() : Promise.resolve();
                    saveBeforeComplete
                        .then(function() {
                            if (frm.doc.status === "Completed") {
                                clearTimeout(timeoutId);
                                btn.css("background-color", "#27ae60").text("Completed ✓");
                                return frm.reload_doc();
                            }
                            btn.text("Completing...");
                            frm.doc.status = "Completed";
                            if (!frm.doc.completed_on) {
                                frm.doc.completed_on = frappe.datetime.get_today();
                            }
                            frm.dirty();
                            return frm.save();
                        })
'@

$HasNew = $Script -match 'var hasUnsavedWork = frm\.is_dirty\(\);[\s\S]*var saveBeforeComplete = hasUnsavedWork \? frm\.save\(\) : Promise\.resolve\(\);'
$HasOld = $Script.Contains($Old)

if ($Mode -eq "Check") {
    [pscustomobject]@{
        Target = $BaseUrl
        Script = $ScriptName
        Enabled = [bool]$Client.enabled
        HasRequestedDirtySaveLogic = [bool]$HasNew
        HasOldAlwaysSaveFirstBlock = [bool]$HasOld
        Modified = $Client.modified
    } | Format-List
    return
}

if (-not $HasNew) {
    if (-not $HasOld) {
        throw "Expected Complete Task block was not found in '$ScriptName'. No changes made."
    }
    $BackupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_before_dirty_complete_{0}.js" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    Set-Content -Path $BackupPath -Value $Script -Encoding UTF8
    $Script = $Script.Replace($Old, $New)
    Put-ErpDoc "Client Script" $ScriptName @{ script = $Script } | Out-Null
    Write-Host "Updated $ScriptName on $BaseUrl" -ForegroundColor Green
    Write-Host "Backup: $BackupPath" -ForegroundColor Yellow
} else {
    Write-Host "$ScriptName already has requested dirty-save logic." -ForegroundColor Green
}
