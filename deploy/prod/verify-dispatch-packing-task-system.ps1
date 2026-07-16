param()

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Exists-ErpDoc { param([string]$DocType,[string]$Name)
    try { Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)" | Out-Null; return $true } catch { return $false }
}

$ExpectedCustomFields = @(
    "Dispatch Case-custom_packing_scan_barcode",
    "Dispatch Case-custom_packing_scan_qty",
    "Dispatch Case-custom_packing_scan_result",
    "Dispatch Case-custom_packing_last_warning",
    "Dispatch Case-custom_packing_problem_status",
    "Dispatch Case-custom_packing_problem_summary",
    "Dispatch Case-custom_problem_alert_sent",
    "Dispatch Case Item-custom_packing_status",
    "Dispatch Case Item-custom_scanned_qty",
    "Dispatch Case Item-custom_remaining_qty",
    "Dispatch Case Item-custom_fefo_warning",
    "Dispatch Case Item-custom_problem_reason",
    "Dispatch Case Item-custom_problem_alert_sent",
    "Task-custom_is_team_queue_task",
    "Task-custom_team_queue_role",
    "Task-custom_team_queue_status",
    "Task-custom_accepted_by",
    "Task-custom_accepted_at",
    "Task-custom_team_notified"
)
$ExpectedServerScripts = @(
    "dispatch_case_packing_scan",
    "dispatch_task_accept",
    "Task-team-queue-notify",
    "Dispatch Case-packing-problem-alerts",
    "dispatch_task_queue_backfill",
    "Task-dispatch-queue-integration"
)
$ExpectedClientScripts = @(
    "Dispatch Case-Packing Scan",
    "Task-Accept Start",
    "Task-Team Queue",
    "Dispatch Case-Packing Problem Alerts"
)

$Report = [ordered]@{ custom_fields=@(); server_scripts=@(); client_scripts=@(); api_checks=@(); summary=[ordered]@{} }
foreach($n in $ExpectedCustomFields){ $Report.custom_fields += [pscustomobject]@{name=$n; exists=(Exists-ErpDoc "Custom Field" $n)} }
foreach($n in $ExpectedServerScripts){ $Report.server_scripts += [pscustomobject]@{name=$n; exists=(Exists-ErpDoc "Server Script" $n)} }
foreach($n in $ExpectedClientScripts){ $Report.client_scripts += [pscustomobject]@{name=$n; exists=(Exists-ErpDoc "Client Script" $n)} }

try {
    $Backfill = (Invoke-ErpRequest Get "/api/method/dispatch_task_queue_backfill?limit=5").message
    $Report.api_checks += [pscustomobject]@{name="dispatch_task_queue_backfill"; ok=$true; result=$Backfill}
} catch {
    $Report.api_checks += [pscustomobject]@{name="dispatch_task_queue_backfill"; ok=$false; error=$_.Exception.Message}
}

$Missing = @()
foreach($r in $Report.custom_fields){ if(-not $r.exists){ $Missing += $r.name } }
foreach($r in $Report.server_scripts){ if(-not $r.exists){ $Missing += $r.name } }
foreach($r in $Report.client_scripts){ if(-not $r.exists){ $Missing += $r.name } }
$Report.summary.total_missing = $Missing.Count
$Report.summary.missing = $Missing
$Report.summary.ready_for_manual_test = ($Missing.Count -eq 0)
$Report | ConvertTo-Json -Depth 40
