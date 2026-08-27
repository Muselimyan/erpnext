param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Deploy"
)

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

Write-Host "Granting Task and Customer permissions to Ops - Order Creating role..." -ForegroundColor Cyan

# Grant permissions via API
$permissions = @(
    @{
        doctype = "Task"
        role = "Ops - Order Creating"
        permlevel = 0
        read = 1
        write = 1
        create = 1
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
    },
    @{
        doctype = "Customer"
        role = "Ops - Order Creating"
        permlevel = 0
        read = 1
        write = 0
        create = 0
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
    },
    @{
        doctype = "Task"
        role = "Ops - Order Accepting"
        permlevel = 0
        read = 1
        write = 1
        create = 1
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
    },
    @{
        doctype = "Customer"
        role = "Ops - Order Accepting"
        permlevel = 0
        read = 1
        write = 0
        create = 0
        delete = 0
        submit = 0
        cancel = 0
        amend = 0
    }
)

foreach ($perm in $permissions) {
    Write-Host "Setting permission: $($perm.role) on $($perm.doctype)..." -ForegroundColor Yellow
    try {
        $result = Invoke-ErpRequest -Method Post -Path "/api/method/frappe.core.doctype.doctype.doctype.update_permission_property" -Body @{
            doctype = $perm.doctype
            role = $perm.role
            permlevel = $perm.permlevel
            ptype = "read"
            value = $perm.read
        }
        
        $result = Invoke-ErpRequest -Method Post -Path "/api/method/frappe.core.doctype.doctype.doctype.update_permission_property" -Body @{
            doctype = $perm.doctype
            role = $perm.role
            permlevel = $perm.permlevel
            ptype = "write"
            value = $perm.write
        }
        
        $result = Invoke-ErpRequest -Method Post -Path "/api/method/frappe.core.doctype.doctype.doctype.update_permission_property" -Body @{
            doctype = $perm.doctype
            role = $perm.role
            permlevel = $perm.permlevel
            ptype = "create"
            value = $perm.create
        }
        
        Write-Host "  ✓ Done" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Error: $_" -ForegroundColor Red
    }
}

Write-Host "`n✓ Permissions updated! Please refresh your browser (Ctrl+F5)" -ForegroundColor Green
