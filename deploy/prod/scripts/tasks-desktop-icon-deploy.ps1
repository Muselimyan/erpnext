# Tasks Desktop Icon Deployment Script
# Adds a "Tasks" module icon to the ERPNext Desk page for easy access to Task list

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Deploy", "Check")]
    [string]$Mode = "Deploy"
)

# Load API configuration
. "$PSScriptRoot\export.ps1"

$Headers = @{
    Authorization = "token $($ApiKey):$($ApiSec)"
    "Content-Type" = "application/json"
}

function Invoke-ErpRequest {
    param($Uri, $Method = "GET", $Body = $null)
    try {
        $params = @{
            Uri = $Uri
            Headers = $Headers
            Method = $Method
        }
        if ($Body) { $params.Body = $Body }
        return Invoke-RestMethod @params
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        return $null
    }
}

function Get-ErpDoc {
    param($DocType, $Name)
    $encodedDocType = [System.Web.HttpUtility]::UrlEncode($DocType)
    $encodedName = [System.Web.HttpUtility]::UrlEncode($Name)
    $uri = "$BaseUrl/api/resource/$encodedDocType/$encodedName"
    $response = Invoke-ErpRequest -Uri $uri
    return $response.data
}

function Upsert-ErpDoc {
    param($DocType, $Doc)
    $encodedDocType = [System.Web.HttpUtility]::UrlEncode($DocType)
    $exists = Get-ErpDoc -DocType $DocType -Name $Doc.name
    
    if ($exists) {
        $encodedName = [System.Web.HttpUtility]::UrlEncode($Doc.name)
        $uri = "$BaseUrl/api/resource/$encodedDocType/$encodedName"
        $body = $Doc | ConvertTo-Json -Depth 10 -Compress
        Invoke-ErpRequest -Uri $uri -Method "PUT" -Body $body | Out-Null
        return @{action="updated"; name=$Doc.name}
    } else {
        $uri = "$BaseUrl/api/resource/$encodedDocType"
        $body = $Doc | ConvertTo-Json -Depth 10 -Compress
        Invoke-ErpRequest -Uri $uri -Method "POST" -Body $body | Out-Null
        return @{action="created"; name=$Doc.name}
    }
}

# ---------------------------------------------------------------------------
# DESKTOP ICON DEFINITION
# ---------------------------------------------------------------------------

$TasksDesktopIcon = @{
    doctype = "Desktop Icon"
    name = "Tasks"
    module_name = "Tasks"
    label = "Tasks"
    link = "List/Task"
    type = "link"
    icon = "fa fa-tasks"
    color = "#3498db"
    _doctype = "Desktop Icon"
    standard = 0
    custom = 1
    hidden = 0
    blocked = 0
    force = 0
}

# ---------------------------------------------------------------------------
# DEPLOYMENT
# ---------------------------------------------------------------------------

if ($Mode -eq "Deploy") {
    Write-Host "Deploying Tasks Desktop Icon..." -ForegroundColor Cyan
    
    $result = Upsert-ErpDoc -DocType "Desktop Icon" -Doc $TasksDesktopIcon
    
    $output = @{
        mode = "Deploy"
        desktop_icon = $result
        notes = @(
            "Tasks icon added to Desk page",
            "Clicking opens the Task list",
            "Visible to all users with Task permissions"
        )
    }
    
    $output | ConvertTo-Json -Depth 5
}

if ($Mode -eq "Check") {
    Write-Host "Checking Tasks Desktop Icon..." -ForegroundColor Cyan
    
    $icon = Get-ErpDoc -DocType "Desktop Icon" -Name "Tasks"
    
    $output = @{
        mode = "Check"
        desktop_icon = @{
            name = "Tasks"
            exists = ($null -ne $icon)
            link = $icon.link
            hidden = $icon.hidden
        }
    }
    
    $output | ConvertTo-Json -Depth 5
}
