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
function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}
function Get-ErpDoc { param([string]$DocType,[string]$Name)
    try { return (Invoke-ErpRequest -Method Get -Path "/api/resource/$(Enc $DocType)/$(Enc $Name)").data } catch { return $null }
}

# Enable inline editing for Dispatch Case Item child table
$Report = [ordered]@{
    mode = $Mode
    property_setters = @()
    notes = @()
}

$DocType = "Dispatch Case Item"
$PropertyName = "Dispatch Case Item-editable_grid"

if ($Mode -eq "Deploy") {
    Write-Host "Enabling inline editing for Dispatch Case Item table..."
    
    # Get the DocType metadata
    $dt = Get-ErpDoc "DocType" $DocType
    if ($null -eq $dt) {
        Write-Host "ERROR: DocType '$DocType' not found" -ForegroundColor Red
        exit 1
    }
    
    # Set editable_grid to 1
    $dt.editable_grid = 1
    
    # Update the DocType
    try {
        Invoke-ErpRequest -Method Put -Path "/api/resource/DocType/$(Enc $DocType)" -Body $dt | Out-Null
        Write-Host "SUCCESS: Enabled inline editing for $DocType" -ForegroundColor Green
        $Report.property_setters += [pscustomobject]@{ 
            action = "updated"
            doctype = $DocType
            property = "editable_grid"
            value = 1
        }
    } catch {
        Write-Host "ERROR: Failed to update $DocType - $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    # Check mode
    $dt = Get-ErpDoc "DocType" $DocType
    if ($null -eq $dt) {
        $Report.property_setters += [pscustomobject]@{ 
            doctype = $DocType
            property = "editable_grid"
            exists = $false
        }
    } else {
        $Report.property_setters += [pscustomobject]@{ 
            doctype = $DocType
            property = "editable_grid"
            current_value = $dt.editable_grid
            desired_value = 1
            would_change = ($dt.editable_grid -ne 1)
        }
    }
}

$Report.notes += "Enables inline editing for Dispatch Case Item child table."
$Report.notes += "Workers can click directly in cells to edit values without opening popup dialogs."
$Report.notes += "Specifically useful for editing returned_qty, used_qty fields during returns inspection."

$Report | ConvertTo-Json -Depth 40
