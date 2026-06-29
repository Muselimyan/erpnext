param(
    [string]$DocType = "Task"
)

Set-StrictMode -Off

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json"; "User-Agent" = "Mozilla/5.0" }

function Enc ([string]$s) { [uri]::EscapeDataString($s) }

Write-Host "`n=== Checking Permissions for DocType: $DocType ===" -ForegroundColor Cyan

$roles = @(
    "Ops - Order Accepting",
    "Ops - Order Creating",
    "Ops - Inventory",
    "Delivery Driver",
    "Ops - Delivery",
    "Ops - Returns",
    "Ops - Accounting",
    "Ops - Finance",
    "Ops - Directors"
)

try {
    $uri = "$BaseUrl/api/resource/DocType/$($DocType)?fields=[`"name`",`"permissions`"]"
    $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get -TimeoutSec 30
    
    $permissions = $response.data.permissions
    
    Write-Host "`nCurrent Permissions:" -ForegroundColor Yellow
    Write-Host "Role                      | Read | Write | Create | Delete | Submit | Cancel" -ForegroundColor Gray
    Write-Host "--------------------------|------|-------|--------|--------|--------|-------" -ForegroundColor Gray
    
    foreach ($role in $roles) {
        $perm = $permissions | Where-Object { $_.role -eq $role -and $_.permlevel -eq 0 } | Select-Object -First 1
        
        if ($perm) {
            $read = if ($perm.read) { "Y" } else { "N" }
            $write = if ($perm.write) { "Y" } else { "N" }
            $create = if ($perm.create) { "Y" } else { "N" }
            $delete = if ($perm.delete) { "Y" } else { "N" }
            $submit = if ($perm.submit) { "Y" } else { "N" }
            $cancel = if ($perm.cancel) { "Y" } else { "N" }
            
            $line = "{0,-25} | {1,4} | {2,5} | {3,6} | {4,6} | {5,6} | {6,6}" -f $role, $read, $write, $create, $delete, $submit, $cancel
            
            # Highlight missing permissions
            if ($role -like "Ops - Order*" -or $role -eq "Ops - Inventory" -or $role -eq "Delivery Driver" -or $role -eq "Ops - Returns" -or $role -eq "Ops - Accounting" -or $role -eq "Ops - Finance") {
                if (-not $perm.read -or -not $perm.write -or -not $perm.create) {
                    Write-Host $line -ForegroundColor Red
                } else {
                    Write-Host $line -ForegroundColor Green
                }
            } elseif ($role -eq "Ops - Directors") {
                if (-not $perm.read -or -not $perm.write -or -not $perm.create -or -not $perm.delete) {
                    Write-Host $line -ForegroundColor Red
                } else {
                    Write-Host $line -ForegroundColor Green
                }
            } else {
                Write-Host $line
            }
        } else {
            $line = "{0,-25} | {1,4} | {2,5} | {3,6} | {4,6} | {5,6} | {6,6}" -f $role, "N", "N", "N", "N", "N", "N"
            Write-Host $line -ForegroundColor Red
        }
    }
    
    Write-Host "`n"
    
} catch {
    Write-Host "Error checking permissions: $_" -ForegroundColor Red
}
