param([int]$BrowserProcessId)
$peak = 0L
while (Get-Process -Id $BrowserProcessId -ErrorAction SilentlyContinue) {
  $rows = @(Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'")
  $ids = [System.Collections.Generic.HashSet[int]]::new()
  [void]$ids.Add($BrowserProcessId)
  do {
    $changed = $false
    foreach ($row in $rows) {
      if ($ids.Contains([int]$row.ParentProcessId) -and $ids.Add([int]$row.ProcessId)) { $changed = $true }
    }
  } while ($changed)
  $working = 0L
  $private = 0L
  foreach ($id in $ids) {
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($process) { $working += $process.WorkingSet64; $private += $process.PrivateMemorySize64 }
  }
  Write-Output "$working,$private"
  Start-Sleep -Milliseconds 500
}
