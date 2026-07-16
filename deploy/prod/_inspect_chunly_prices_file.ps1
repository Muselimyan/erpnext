$ErrorActionPreference = "Stop"
$ExcelPath = (Get-ChildItem "C:\Users\Levon\.windsurf" -Filter "Chunly*.xlsx" | Select-Object -First 1).FullName
Write-Host "Reading: $ExcelPath"
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($ExcelPath)
Write-Host "Sheets:"
for ($i=1; $i -le $wb.Worksheets.Count; $i++) {
    $ws = $wb.Worksheets.Item($i)
    Write-Host "[$i] $($ws.Name): $($ws.UsedRange.Rows.Count) rows x $($ws.UsedRange.Columns.Count) cols"
    for ($r=1; $r -le [Math]::Min(12,$ws.UsedRange.Rows.Count); $r++) {
        $vals = @()
        for ($c=1; $c -le [Math]::Min(12,$ws.UsedRange.Columns.Count); $c++) {
            $v = $ws.Cells.Item($r,$c).Text
            if ($v -ne "") { $vals += "$c=$v" }
        }
        if ($vals.Count -gt 0) { Write-Host ("Row $r : " + ($vals -join " | ")) }
    }
    Write-Host ""
}
$wb.Close($false)
$excel.Quit()
