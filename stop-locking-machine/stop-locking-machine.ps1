Clear-Host
Echo "### Testing ###"

$WShell = New-Object -com "Wscript.Shell"
$sleep = 30


while ($true)
{
  $WShell.sendkeys("{SCROLLLOCK}")
  Start-Sleep -Milliseconds 100
  Write-Host "Test in progress"
  $WShell.sendkeys("{SCROLLLOCK}")
  Write-Host "Waiting " $sleep " seconds" 
  Start-Sleep -Seconds $sleep
}
