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

function Get-TaskFieldMap {
    $Map = @{}
    try {
        $TaskMeta = (Invoke-ErpRequest -Method Get -Path "/api/resource/DocType/Task").data
        foreach ($Field in ($TaskMeta.fields | ForEach-Object { $_ })) {
            if ($Field.fieldname) { $Map[$Field.fieldname] = $Field }
        }
    } catch {
        Write-Warning "Could not fetch Task DocType metadata. Check mode will still show planned settings, but Deploy will not run safely. Error: $($_.Exception.Message)"
    }

    try {
        $CustomFields = (Invoke-ErpRequest -Method Get -Path "/api/resource/Custom%20Field?fields=%5B%22name%22,%22fieldname%22,%22label%22,%22hidden%22,%22depends_on%22,%22read_only%22%5D&filters=%5B%5B%22dt%22,%22%3D%22,%22Task%22%5D%5D&limit_page_length=500").data
        foreach ($Field in ($CustomFields | ForEach-Object { $_ })) {
            if ($Field.fieldname) { $Map[$Field.fieldname] = $Field }
        }
    } catch {
        Write-Warning "Could not fetch Task Custom Field metadata. Error: $($_.Exception.Message)"
    }

    return $Map
}

function Build-SetterName {
    param([string]$DocType, [string]$FieldName, [string]$Property)
    return "$DocType-$FieldName-$Property"
}

function Get-PropertySetter {
    param([string]$FieldName, [string]$Property)
    $Name = Build-SetterName -DocType "Task" -FieldName $FieldName -Property $Property
    return Get-ErpDoc -DocType "Property Setter" -Name $Name
}

function Upsert-PropertySetter {
    param([string]$FieldName, [string]$Property, [string]$PropertyType, [string]$Value)
    $Name = Build-SetterName -DocType "Task" -FieldName $FieldName -Property $Property
    $Body = [ordered]@{
        doctype_or_field = "DocField"
        doc_type         = "Task"
        field_name       = $FieldName
        property         = $Property
        property_type    = $PropertyType
        value            = $Value
    }

    $Existing = Get-ErpDoc -DocType "Property Setter" -Name $Name
    if ($null -eq $Existing) {
        $Body.name = $Name
        $Created = (Invoke-ErpRequest -Method Post -Path "/api/resource/Property%20Setter" -Body $Body).data
        return [pscustomobject]@{ action="created"; name=$Created.name; fieldname=$FieldName; property=$Property; value=$Value }
    }

    $Updated = (Invoke-ErpRequest -Method Put -Path "/api/resource/Property%20Setter/$(Enc $Name)" -Body $Body).data
    return [pscustomobject]@{ action="updated"; name=$Updated.name; fieldname=$FieldName; property=$Property; value=$Value }
}

$NoKind = '!doc.task_kind'
$ApprovalKinds = "$NoKind || doc.task_kind==`"Purchase Approval`" || doc.task_kind==`"Discount Approval`" || doc.task_kind==`"Write-off Approval`""
$DispatchKinds = "$NoKind || doc.task_kind==`"Pack / prepare items`" || doc.task_kind==`"Dispatch picking / hand-off`" || doc.task_kind==`"Delivery`" || doc.task_kind==`"Pickup Returns`" || doc.task_kind==`"Return drop-off at warehouse`" || doc.task_kind==`"Returns processing / verification`" || doc.task_kind==`"Returns restocking`" || doc.task_kind==`"Invoice preparation / create invoice`" || doc.task_kind==`"Discount Approval`""
$ReturnKinds = "$NoKind || doc.task_kind==`"Pickup Returns`" || doc.task_kind==`"Return drop-off at warehouse`""
$PaymentDebtKinds = "$NoKind || doc.task_kind==`"Payment Received`" || doc.task_kind==`"Debt Collection`""
$PaymentLinkKinds = "$NoKind || doc.task_kind==`"Payment Received`" || doc.task_kind==`"Distribute Payment`" || doc.task_kind==`"Debt Collection`""
$InvoiceKinds = "$NoKind || doc.task_kind==`"Invoice preparation / create invoice`" || doc.task_kind==`"Debt Collection`" || doc.task_kind==`"Payment Received`" || doc.task_kind==`"Distribute Payment`""

$Rules = @(
    [pscustomobject]@{ fieldname="weight"; hidden="1"; depends_on=""; note="Hide standard project progress weight" },
    [pscustomobject]@{ fieldname="project"; hidden="1"; depends_on=""; note="Hide standard Project link" },
    [pscustomobject]@{ fieldname="issue"; hidden="1"; depends_on=""; note="Hide standard Issue link" },
    [pscustomobject]@{ fieldname="type"; hidden="1"; depends_on=""; note="Hide standard Task Type; use Task Kind instead" },
    [pscustomobject]@{ fieldname="color"; hidden="1"; depends_on=""; note="Hide visual color field" },
    [pscustomobject]@{ fieldname="is_group"; hidden="1"; depends_on=""; note="Hide standard project group task field" },
    [pscustomobject]@{ fieldname="is_template"; hidden="1"; depends_on=""; note="Hide standard template field" },
    [pscustomobject]@{ fieldname="parent_task"; hidden="1"; depends_on=""; note="Hide standard parent task field" },
    [pscustomobject]@{ fieldname="dispatch_group_id"; hidden="1"; depends_on=""; note="Hide legacy technical dispatch group" },
    [pscustomobject]@{ fieldname="surgery_case"; hidden="1"; depends_on=""; note="Hide legacy Surgery Case link" },
    [pscustomobject]@{ fieldname="sales_order"; hidden="1"; depends_on=""; note="Hide legacy Sales Order link" },
    [pscustomobject]@{ fieldname="task_access_policy"; hidden="1"; depends_on=""; note="Hide internal policy field from normal users" },

    [pscustomobject]@{ fieldname="dispatch_case"; hidden="0"; depends_on="eval:$DispatchKinds"; note="Show for Dispatch Case operational tasks" },
    [pscustomobject]@{ fieldname="dispatch_case_status"; hidden="0"; depends_on="eval:$DispatchKinds"; note="Show Dispatch Case status for dispatch-related tasks" },
    [pscustomobject]@{ fieldname="delivery_status"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Delivery"'; note="Show while choosing task kind and for Delivery tasks" },
    [pscustomobject]@{ fieldname="pickup_status"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Pickup Returns"'; note="Show while choosing task kind and for Pickup Returns tasks" },
    [pscustomobject]@{ fieldname="return_pickup_driver"; hidden="0"; depends_on="eval:$ReturnKinds"; note="Show for return pickup/drop-off tasks" },
    [pscustomobject]@{ fieldname="scheduled_return_date"; hidden="0"; depends_on="eval:$ReturnKinds"; note="Show for return-related tasks" },
    [pscustomobject]@{ fieldname="driver_handover_note"; hidden="0"; depends_on=""; note="Always show handover note because drivers may need it on operational tasks" },
    [pscustomobject]@{ fieldname="warehouse_pickup_photo"; hidden="0"; depends_on=""; note="Always show required delivery/pickup photo attachment field" },
    [pscustomobject]@{ fieldname="warehouse_dropoff_photo"; hidden="0"; depends_on=""; note="Always show required return/drop-off photo attachment field" },

    [pscustomobject]@{ fieldname="purchase_order"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Purchase Approval"'; note="Show while choosing task kind and for Purchase Approval" },
    [pscustomobject]@{ fieldname="approval_outcome"; hidden="0"; depends_on="eval:$ApprovalKinds"; note="Show only for approval tasks" },
    [pscustomobject]@{ fieldname="approval_note"; hidden="0"; depends_on="eval:$ApprovalKinds"; note="Show only for approval tasks" },

    [pscustomobject]@{ fieldname="sales_invoice"; hidden="0"; depends_on="eval:$InvoiceKinds"; note="Show for invoice/payment/debt tasks" },
    [pscustomobject]@{ fieldname="payment_entry"; hidden="0"; depends_on="eval:$PaymentLinkKinds"; note="Show for payment/debt tasks" },
    [pscustomobject]@{ fieldname="new_payment_amount"; hidden="0"; depends_on="eval:$PaymentDebtKinds"; note="Show for recording payment/debt collection" },
    [pscustomobject]@{ fieldname="payment_method_dc"; hidden="0"; depends_on="eval:$PaymentDebtKinds"; note="Show for recording payment/debt collection" },
    [pscustomobject]@{ fieldname="payment_reference_dc"; hidden="0"; depends_on="eval:$PaymentDebtKinds"; note="Show for recording payment/debt collection" },
    [pscustomobject]@{ fieldname="current_debt_amd"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection"'; note="Show while choosing task kind and for Debt Collection" },
    [pscustomobject]@{ fieldname="debt_threshold_amd"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection"'; note="Show while choosing task kind and for Debt Collection" },
    [pscustomobject]@{ fieldname="total_outstanding"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"'; note="Show while choosing task kind and for debt/payment distribution" },
    [pscustomobject]@{ fieldname="available_advance_credit"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"'; note="Show while choosing task kind and for debt/payment distribution" },
    [pscustomobject]@{ fieldname="open_invoices"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"'; note="Show while choosing task kind and for debt/payment distribution" },
    [pscustomobject]@{ fieldname="payment_history"; hidden="0"; depends_on='eval:!doc.task_kind || doc.task_kind=="Debt Collection" || doc.task_kind=="Distribute Payment"'; note="Show while choosing task kind and for debt/payment distribution" }
)

$FieldMap = Get-TaskFieldMap
$Report = [ordered]@{ mode=$Mode; total_rules=$Rules.Count; existing_fields=0; missing_fields=@(); settings=@(); applied=@(); skipped=@() }

foreach ($Rule in $Rules) {
    $Exists = $FieldMap.ContainsKey($Rule.fieldname)
    if ($Exists) { $Report.existing_fields += 1 } else { $Report.missing_fields += $Rule.fieldname }

    $HiddenSetter = Get-PropertySetter -FieldName $Rule.fieldname -Property "hidden"
    $DependsSetter = Get-PropertySetter -FieldName $Rule.fieldname -Property "depends_on"

    $CurrentHidden = if ($null -ne $HiddenSetter) { $HiddenSetter.value } elseif ($Exists -and $null -ne $FieldMap[$Rule.fieldname].hidden) { [string]$FieldMap[$Rule.fieldname].hidden } else { $null }
    $CurrentDepends = if ($null -ne $DependsSetter) { $DependsSetter.value } elseif ($Exists -and $null -ne $FieldMap[$Rule.fieldname].depends_on) { [string]$FieldMap[$Rule.fieldname].depends_on } else { $null }

    $NeedsHidden = ($Exists -and $CurrentHidden -ne $Rule.hidden)
    $NeedsDepends = ($Exists -and (($CurrentDepends -replace "`r", "") -ne $Rule.depends_on))

    $Report.settings += [pscustomobject]@{
        fieldname=$Rule.fieldname
        exists=$Exists
        current_hidden=$CurrentHidden
        desired_hidden=$Rule.hidden
        current_depends_on=$CurrentDepends
        desired_depends_on=$Rule.depends_on
        would_change=($NeedsHidden -or $NeedsDepends)
        note=$Rule.note
    }

    if (-not $Exists) {
        $Report.skipped += [pscustomobject]@{ fieldname=$Rule.fieldname; reason="Field does not exist on Task metadata" }
        continue
    }

    if ($Mode -eq "Deploy") {
        if ($NeedsHidden) { $Report.applied += Upsert-PropertySetter -FieldName $Rule.fieldname -Property "hidden" -PropertyType "Check" -Value $Rule.hidden }
        if ($NeedsDepends) { $Report.applied += Upsert-PropertySetter -FieldName $Rule.fieldname -Property "depends_on" -PropertyType "Code" -Value $Rule.depends_on }
    }
}

$Report.summary = [ordered]@{
    would_change_count = @($Report.settings | Where-Object { $_.would_change }).Count
    applied_count      = @($Report.applied).Count
    skipped_count      = @($Report.skipped).Count
}

$Report | ConvertTo-Json -Depth 20
