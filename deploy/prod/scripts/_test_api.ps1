$Config = Get-Content (Join-Path $PSScriptRoot "export.ps1") -Raw
$BaseUrl = [regex]::Match($Config, '\$BaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
$ApiKey  = [regex]::Match($Config, '\$ApiKey\s*=\s*"([^"]+)"').Groups[1].Value
$ApiSec  = [regex]::Match($Config, '\$ApiSec\s*=\s*"([^"]+)"').Groups[1].Value
$Headers = @{ Authorization = "token $($ApiKey):$($ApiSec)"; "Content-Type" = "application/json" }

Write-Host "Testing task_list_filtered API (my_tasks=1, open_tasks=1, completed=0)..."
try {
    $r = Invoke-RestMethod -Uri "$BaseUrl/api/method/task_list_filtered?my_tasks=1&open_tasks=1&completed=0" -Headers $Headers -Method Get -TimeoutSec 30
    $names = $r.message
    Write-Host "Success! Got $($names.Count) task names." -ForegroundColor Green
    if ($names.Count -gt 0) {
        Write-Host "First 5: $($names[0..4] -join ', ')"
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    Write-Host $reader.ReadToEnd()
}
