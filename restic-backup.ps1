$env:AWS_ACCESS_KEY_ID="%AWS_ACCESS_KEY_ID%"
$env:AWS_SECRET_ACCESS_KEY="%AWS_SECRET_ACCESS_KEY%"
$env:RESTIC_PASSWORD="%RESTIC_PASSWORD%"

$scheduledTasksFolder = "%scheduledTasksFolder%"
$installPath = "%installPath%"
$backupLocation = "%backupLocation%"

"Backup started at $(Get-Date)" | Add-Content "$scheduledTasksFolder\backup.log"
restic -r $backupLocation backup "$installPath\astroneer\Launcher.ini" "$installPath\astroneer\Astro\Saved\Config\WindowsServer" "$installPath\astroneer\Astro\Saved\SaveGames" | Add-Content "$scheduledTasksFolder\backup.log"
restic -r $backupLocation forget --keep-last 10 --keep-hourly 48 --keep-daily 7 --keep-weekly 5 --keep-monthly 6 | Add-Content "$scheduledTasksFolder\backup.log"
"Backup finished at $(Get-Date)" | Add-Content "$scheduledTasksFolder\backup.log"
