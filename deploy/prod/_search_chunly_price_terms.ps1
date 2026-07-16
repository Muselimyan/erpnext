$ErrorActionPreference = "Stop"
$PricePath = (Get-ChildItem "C:\Users\Levon\.windsurf" -Filter "Chunly*.xlsx" | Select-Object -First 1).FullName
$Terms = @("Ceramic", "Head 36", "36XL", "36L", "36M", "36S")
Write-Host "Price file: $PricePath"
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Open($PricePath)
for ($i=1; $i -le $wb.Worksheets.Count; $i++) {
    $ws = $wb.Worksheets.Item($i)
    $rows = $ws.UsedRange.Rows.Count
    $cols = $ws.UsedRange.Columns.Count
    $lastGroup = ""
    for ($r=1; $r -le $rows; $r++) {
        $vals = @()
        for ($c=1; $c -le $cols; $c++) { $vals += ($ws.Cells.Item($r,$c).Text).Trim() }
        if ($vals[2]) { $lastGroup = $vals[2] }
        $line = ($vals -join " | ")
        foreach ($term in $Terms) {
            if ($line -like "*$term*") {
                Write-Host "Sheet=$($ws.Name) Row=$r Group=$lastGroup :: $line"
                break
            }
        }
    }
}
$wb.Close($false)
$excel.Quit()
