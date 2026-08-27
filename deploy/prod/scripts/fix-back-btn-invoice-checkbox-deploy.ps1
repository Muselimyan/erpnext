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

$Report = [ordered]@{ mode=$Mode; back_button=@(); sales_invoice_field=@(); checkbox_dirty=@(); notes=@() }

# ===========================================================================
# FIX 1: Back button — mobile only
# ===========================================================================
Write-Host "`n=== Fix 1: Back Button (mobile only) ===" -ForegroundColor Cyan

$AllCS = @()
try {
    $r = Invoke-ErpRequest -Method Get -Path "/api/resource/Client%20Script?filters=%5B%5B%22enabled%22%2C%22%3D%22%2C1%5D%5D&fields=%5B%22name%22%2C%22dt%22%2C%22view%22%2C%22script%22%5D&limit_page_length=100"
    $AllCS = $r.data
} catch {
    Write-Warning "Could not fetch Client Scripts: $($_.Exception.Message)"
}

$BackBtnScripts = $AllCS | Where-Object { $_.script -and $_.script.Contains('mobile-back-btn') }
Write-Host "Found $(@($BackBtnScripts).Count) Client Script(s) containing back button code"

foreach ($cs in $BackBtnScripts) {
    Write-Host "  - $($cs.name) (dt=$($cs.dt), view=$($cs.view))"

    $AlreadyFixed = $cs.script -match 'function ensureBackBtn\(\)\s*\{\s*var btn\s*=\s*document\.getElementById'
    $HasOldOuterGuard = $cs.script.Contains('if (window.innerWidth > 768) return;')
    $HasOldInnerGuard = $cs.script.Contains('if (window.innerWidth <= 768 && !window._mobileBackInterval)')
    $NeedsFix = (-not $AlreadyFixed) -and ($HasOldOuterGuard -or $HasOldInnerGuard)

    if (-not $NeedsFix) {
        Write-Host "    -> Already fixed or no old pattern" -ForegroundColor Green
        $Report.back_button += [pscustomobject]@{ name=$cs.name; needs_fix=$false; dt=$cs.dt }
        continue
    }

    Write-Host "    -> Needs fix" -ForegroundColor Yellow

    if ($Mode -ne "Deploy") {
        $Report.back_button += [pscustomobject]@{ name=$cs.name; needs_fix=$true; dt=$cs.dt }
        continue
    }

    $fixed = $cs.script
    $fixed = $fixed.Replace('if (window.innerWidth > 768) return;', '')
    $fixed = $fixed.Replace('if (window.innerWidth <= 768 && !window._mobileBackInterval)', 'if (!window._mobileBackInterval)')

    # Inject width check inside ensureBackBtn
    if ($fixed -match 'function ensureBackBtn\(\)\s*\{\s*\r?\n\s*var url') {
        $fixed = $fixed -replace '(function ensureBackBtn\(\)\s*\{)\s*\r?\n(\s*)var url', ('$1' + "`n" + '$2var btn = document.getElementById(' + "'" + 'mobile-back-btn' + "'" + ');' + "`n" + '$2if (window.innerWidth > 768) { if (btn) btn.style.display = ' + "'" + 'none' + "'" + '; return; }' + "`n" + '$2var url')
        $fixed = $fixed -replace '\r?\n\s*var btn = document\.getElementById\(' + "'" + 'mobile-back-btn' + "'" + '\);\s*\r?\n(\s*if \(isHome\))', ("`n" + '$1')
    }

    try {
        $Path = '/api/resource/Client%20Script/' + (Enc $cs.name)
        Invoke-ErpRequest -Method Put -Path $Path -Body @{ script = $fixed } | Out-Null
        $Report.back_button += [pscustomobject]@{ name=$cs.name; action='updated'; dt=$cs.dt }
        Write-Host "    -> Fixed!" -ForegroundColor Green
    } catch {
        Write-Host "    -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $Report.back_button += [pscustomobject]@{ name=$cs.name; action='error'; error=$_.Exception.Message }
    }
}

# ===========================================================================
# FIX 2: Sales Invoice field visible for "Returns processing / verification"
# ===========================================================================
Write-Host "`n=== Fix 2: Sales Invoice field on Returns processing task ===" -ForegroundColor Cyan

$DesiredDependsOn = 'eval:!doc.task_kind || doc.task_kind=="Invoice preparation / create invoice" || doc.task_kind=="Debt Collection" || doc.task_kind=="Payment Received" || doc.task_kind=="Distribute Payment" || doc.task_kind=="Returns processing / verification"'
$SetterName = "Task-sales_invoice-depends_on"
$Existing = Get-ErpDoc "Property Setter" $SetterName

$HasReturnsFix = $false
if ($null -ne $Existing) {
    $HasReturnsFix = $Existing.value -and $Existing.value.Contains('Returns processing / verification')
    Write-Host "Property Setter exists. Has Returns fix: $HasReturnsFix"
} else {
    Write-Host "Property Setter does not exist yet"
}

if ($Mode -eq "Deploy" -and (-not $HasReturnsFix)) {
    $Body = [ordered]@{
        doctype_or_field = "DocField"
        doc_type         = "Task"
        field_name       = "sales_invoice"
        property         = "depends_on"
        property_type    = "Code"
        value            = $DesiredDependsOn
    }
    try {
        if ($null -eq $Existing) {
            $Body.name = $SetterName
            $C = (Invoke-ErpRequest -Method Post -Path "/api/resource/Property%20Setter" -Body $Body).data
            $Report.sales_invoice_field += [pscustomobject]@{ action='created'; name=$C.name }
        } else {
            $U = (Invoke-ErpRequest -Method Put -Path "/api/resource/Property%20Setter/$(Enc $SetterName)" -Body $Body).data
            $Report.sales_invoice_field += [pscustomobject]@{ action='updated'; name=$U.name }
        }
        Write-Host "  -> Done!" -ForegroundColor Green
    } catch {
        Write-Host "  -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    $Report.sales_invoice_field += [pscustomobject]@{ setter=$SetterName; exists=($null -ne $Existing); needs_fix=(-not $HasReturnsFix) }
}

# ===========================================================================
# FIX 3: Checkbox toggle marks form dirty so Save works
# ===========================================================================
Write-Host "`n=== Fix 3: Checkbox toggle marks form dirty ===" -ForegroundColor Cyan

$CsName = "Task-Packing Checkboxes"
$CsDoc = Get-ErpDoc "Client Script" $CsName

if ($null -eq $CsDoc) {
    Write-Host "Client Script not found!" -ForegroundColor Red
    $Report.checkbox_dirty += [pscustomobject]@{ name=$CsName; exists=$false }
} else {
    $NeedsDirtyFix = -not ($CsDoc.script.Contains('__unsaved'))
    Write-Host "Found. Needs dirty fix: $NeedsDirtyFix"

    if ($Mode -eq "Deploy" -and $NeedsDirtyFix) {
        $fixed = $CsDoc.script
        $search = 'task_product_work_area_refresh(frm, false);'
        $replace = 'frm.doc.__unsaved = 1; frm.page.set_indicator(__("Not Saved"), "orange"); task_product_work_area_refresh(frm, false);'

        # Replace only the first occurrence (inside the toggle callback)
        $idx = $fixed.IndexOf($search)
        if ($idx -ge 0) {
            $fixed = $fixed.Substring(0, $idx) + $replace + $fixed.Substring($idx + $search.Length)
        }

        try {
            $Path = '/api/resource/Client%20Script/' + (Enc $CsName)
            Invoke-ErpRequest -Method Put -Path $Path -Body @{ script = $fixed } | Out-Null
            $Report.checkbox_dirty += [pscustomobject]@{ name=$CsName; action='updated' }
            Write-Host "  -> Fixed!" -ForegroundColor Green
        } catch {
            Write-Host "  -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
            $Report.checkbox_dirty += [pscustomobject]@{ name=$CsName; action='error'; error=$_.Exception.Message }
        }
    } else {
        $Report.checkbox_dirty += [pscustomobject]@{ name=$CsName; exists=$true; needs_fix=$NeedsDirtyFix }
    }
}

# ===========================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$Report.notes += 'Fix 1: Back button hidden on desktop via width check inside ensureBackBtn'
$Report.notes += 'Fix 2: sales_invoice field visible on Returns processing / verification tasks'
$Report.notes += 'Fix 3: Checkbox toggle marks form dirty so Save works'
$Report | ConvertTo-Json -Depth 20
