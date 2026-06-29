# Tasks Workspace Deployment Script
# Creates a Tasks workspace that appears on the Desk page

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Deploy", "Check")]
    [string]$Mode = "Deploy"
)

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

# Tasks Workspace definition
$TasksWorkspace = @{
    doctype = "Workspace"
    name = "Tasks"
    title = "Tasks"
    icon = "list"
    indicator_color = "blue"
    module = "Projects"
    public = 1
    is_hidden = 0
    content = @'
[
  {
    "type": "Card Break"
  },
  {
    "type": "Link",
    "link_type": "DocType",
    "link_to": "Task",
    "label": "Task List",
    "icon": "list",
    "description": "View and manage all tasks"
  },
  {
    "type": "Link",
    "link_type": "DocType",
    "link_to": "Task",
    "label": "New Task",
    "icon": "add",
    "description": "Create a new task",
    "is_query_report": 0,
    "only_for": "",
    "onboard": 0
  }
]
'@
}

if ($Mode -eq "Deploy") {
    Write-Host "Deploying Tasks Workspace..." -ForegroundColor Cyan
    
    $result = Upsert-ErpDoc -DocType "Workspace" -Doc $TasksWorkspace
    
    $output = @{
        mode = "Deploy"
        workspace = $result
        notes = @(
            "Tasks workspace created",
            "Appears as a card on the Desk page",
            "Contains shortcuts to Task List and New Task",
            "Visible to all users"
        )
    }
    
    $output | ConvertTo-Json -Depth 5
}

if ($Mode -eq "Check") {
    Write-Host "Checking Tasks Workspace..." -ForegroundColor Cyan
    
    $workspace = Get-ErpDoc -DocType "Workspace" -Name "Tasks"
    
    $output = @{
        mode = "Check"
        workspace = @{
            name = "Tasks"
            exists = ($null -ne $workspace)
            public = $workspace.public
            is_hidden = $workspace.is_hidden
        }
    }
    
    $output | ConvertTo-Json -Depth 5
}
