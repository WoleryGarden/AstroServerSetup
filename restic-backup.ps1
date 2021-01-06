$env:AWS_ACCESS_KEY_ID="%AWS_ACCESS_KEY_ID%"
$env:AWS_SECRET_ACCESS_KEY="%AWS_SECRET_ACCESS_KEY%"
$env:RESTIC_PASSWORD="%RESTIC_PASSWORD%"
$env:RESTIC_REPOSITORY="%backupLocation%"

$scheduledTasksFolder = "%scheduledTasksFolder%"
$installPath = "%installPath%"

"Backup started at $(Get-Date)" *>> "$scheduledTasksFolder\backup.log"
restic backup "$installPath\astroneer\Launcher.ini" "$installPath\astroneer\Astro\Saved\Config\WindowsServer" "$installPath\astroneer\Astro\Saved\SaveGames" *>> "$scheduledTasksFolder\backup.log"
restic forget --keep-last 10 --keep-hourly 48 --keep-daily 7 --keep-weekly 5 --keep-monthly 6 *>> "$scheduledTasksFolder\backup.log"
restic prune *>> "$scheduledTasksFolder\backup.log"
"Backup finished at $(Get-Date)" *>> "$scheduledTasksFolder\backup.log"
