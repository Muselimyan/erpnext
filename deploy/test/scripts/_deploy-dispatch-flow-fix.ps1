Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$BaseUrl = "https://test.erpnext.am"
$ApiKey = "af78cbd691f0b2e"
$ApiSec = "b26698573b80f5e"
$AuthHeader = "token $($ApiKey):$($ApiSec)"
$Headers = @{ Authorization = $AuthHeader; "Content-Type" = "application/json" }

# Read server script and strip header (# --- separator)
$Raw = Get-Content "C:\Users\Vahe\CascadeProjects\erpnext\deploy\test\work\server\Task-after-save-dispatch-flow.py" -Raw -Encoding UTF8
if ($Raw -match '(?s)^.*?#\s*---\s*\r?\n') {
    $Script = $Raw.Substring($Matches[0].Length).TrimEnd()
} else {
    $Script = $Raw.TrimEnd()
}

Write-Host "Script length: $($Script.Length) chars"
Write-Host "First line: $($Script.Split("`n")[0])"

# Deploy
$Body = @{ script = $Script } | ConvertTo-Json -Depth 10 -Compress
$Name = [uri]::EscapeDataString("Task-after-save-dispatch-flow")
$Result = Invoke-RestMethod -Uri "$BaseUrl/api/resource/Server%20Script/$Name" -Headers $Headers -Method Put -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec 120
Write-Host "Updated: $($Result.data.name) modified=$($Result.data.modified)"
