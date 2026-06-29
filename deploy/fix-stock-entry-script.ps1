param(
    [ValidateSet("Check", "Deploy")]
    [string]$Mode = "Check"
)

$ConfigPath = Join-Path $PSScriptRoot "export.ps1"
$Config     = Get-Content $ConfigPath -Raw
$BaseUrl    = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiKey     = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$ApiSec     = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"\r\n]+)"').Groups[1].Value
$Headers    = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

function Invoke-ErpRequest { param([string]$Method, [string]$Path, $Body=$null)
    $Uri = "$BaseUrl$Path"
    if ($null -eq $Body) { return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 120 }
    $Json = $Body | ConvertTo-Json -Depth 40
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 120
}

$ScriptsToDisable = @(
    "Stock Entry-before-submit-dispatch-gate",
    "StockEntry-before-submit-fefo"
)

if ($Mode -eq "Deploy") {
    Write-Host "Disabling Stock Entry validation scripts temporarily for launch..."
    foreach ($ScriptName in $ScriptsToDisable) {
        try {
            $script = (Invoke-ErpRequest -Method Get -Path "/api/resource/Server Script/$([uri]::EscapeDataString($ScriptName))").data
            $script.disabled = 1
            Invoke-ErpRequest -Method Put -Path "/api/resource/Server Script/$([uri]::EscapeDataString($ScriptName))" -Body $script | Out-Null
            Write-Host "  [OK] Disabled: $ScriptName" -ForegroundColor Green
        } catch {
            Write-Host "  [SKIP] $ScriptName (not found or already disabled)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "SUCCESS! All scripts processed." -ForegroundColor Green
} else {
    Write-Host "Would disable:"
    $ScriptsToDisable | ForEach-Object { Write-Host "  - $($_)" }
}
