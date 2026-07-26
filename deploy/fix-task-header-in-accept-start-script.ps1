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

$Name = "Task-Accept Start"
Write-Host "=== Fix Task Header In Accept Start Script ===" -ForegroundColor Cyan
Write-Host "Target: $Target ($BaseUrl)" -ForegroundColor Yellow

$data = (Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)?fields=[`"script`"]" -Headers $Headers -Method Get -TimeoutSec 20).data
$script = $data.script

$hasOldWeak = $script -match "Global: fix page title overflow"
$hasStrong = $script -match "taskHeaderFixedActions"

Write-Host "Has old header block: $(if($hasOldWeak){'Yes'}else{'No'})"
Write-Host "Has strong fixed-actions block: $(if($hasStrong){'Yes'}else{'No'})"

if ($Mode -eq "Check") {
    if ($hasStrong) { Write-Host "Status: fixed" -ForegroundColor Green } else { Write-Host "Status: needs deploy" -ForegroundColor Yellow }
    return
}

$old = @'
        // Global: fix page title overflow â title row 1, buttons row 2
        (function() {
            var phc = $(frm.page.wrapper).find('.page-head-content');
            var ta = $(frm.page.wrapper).find('.title-area');
            var tt = $(frm.page.wrapper).find('.title-text');
            var pa = $(frm.page.wrapper).find('.page-actions');
            if (phc.length) phc.css({'flex-wrap': 'wrap', 'gap': '6px 0'});
            if (ta.length) ta.css({'flex': '1 1 100%', 'min-width': '0', 'overflow': 'hidden'});
            if (tt.length) tt.css({'overflow': 'hidden', 'text-overflow': 'ellipsis', 'white-space': 'nowrap', 'display': 'block'});
            if (pa.length) pa.css({'flex': '0 0 auto', 'gap': '6px', 'flex-wrap': 'wrap', 'justify-content': 'flex-end'});
        })();
'@

$new = @'
        (function() {
            function taskHeaderFixedActions() {
                var page = $(frm.page.wrapper);
                var head = page.find('.page-head').first();
                var phc = page.find('.page-head-content').first();
                var ta = page.find('.title-area').first();
                var tt = page.find('.title-text').first();
                var pa = page.find('.page-actions').first();
                if (!head.length || !phc.length || !ta.length || !pa.length) return;

                head.css({'position':'relative','overflow':'visible'});
                phc.css({'display':'flex','align-items':'flex-start','gap':'8px','min-width':'0','max-width':'100%','overflow':'visible','flex-wrap':'nowrap'});
                ta.css({'flex':'1 1 auto','min-width':'0','max-width':'calc(100% - 430px)','overflow':'hidden'});
                tt.css({'display':'block','overflow':'hidden','text-overflow':'ellipsis','white-space':'nowrap','max-width':'100%'});
                pa.css({'flex':'0 0 420px','width':'420px','max-width':'420px','min-width':'420px','display':'flex','flex-wrap':'wrap','justify-content':'flex-end','align-items':'flex-start','gap':'4px','overflow':'visible','z-index':'50','background':'var(--bg-color, #fff)'});
                pa.find('.btn').css({'max-width':'175px','overflow':'hidden','text-overflow':'ellipsis','white-space':'nowrap','flex':'0 0 auto'});

                if (window.innerWidth < 1250) {
                    phc.css({'display':'block'});
                    ta.css({'max-width':'100%'});
                    pa.css({'width':'100%','max-width':'100%','min-width':'0','justify-content':'flex-start','margin-top':'6px'});
                }
            }
            taskHeaderFixedActions();
            setTimeout(taskHeaderFixedActions, 100);
            setTimeout(taskHeaderFixedActions, 400);
            setTimeout(taskHeaderFixedActions, 1000);
        })();
'@

if (-not $script.Contains($old)) {
    Write-Host "Expected old block not found. Trying insertion after refresh start." -ForegroundColor Yellow
    if ($hasStrong) {
        Write-Host "Already has strong block." -ForegroundColor Green
        return
    }
    $marker = '    refresh(frm) {'
    $idx = $script.IndexOf($marker)
    if ($idx -lt 0) { throw "Could not find refresh(frm) block" }
    $insertAt = $idx + $marker.Length
    $script = $script.Substring(0, $insertAt) + "`n" + $new + $script.Substring($insertAt)
} else {
    $script = $script.Replace($old, $new)
}

$backupPath = Join-Path $PSScriptRoot ("_backup_Task_Accept_Start_header_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".js")
$data.script | Set-Content -Path $backupPath -Encoding UTF8
Write-Host "Backup: $backupPath" -ForegroundColor Green

$body = @{ script = $script } | ConvertTo-Json -Depth 10 -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/resource/Client%20Script/$(Enc $Name)" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 20 | Out-Null
Write-Host "Task-Accept Start header layout patched" -ForegroundColor Green
