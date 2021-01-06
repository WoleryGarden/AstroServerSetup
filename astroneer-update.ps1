$installPath = "%installPath%"
$scheduledTasksFolder = "%scheduledTasksFolder%"

"Update started at $(Get-Date)" *>> "$scheduledTasksFolder\update.log"
Stop-Service astroneer

$repo = "ricky-davis/AstroLauncher"
$filename = "AstroLauncher.exe"
$releasesUri = "https://api.github.com/repos/$repo/releases/latest"
$downloadUri = ((Invoke-RestMethod -Method GET -Uri $releasesUri).assets | Where-Object name -like $filename ).browser_download_url
Invoke-WebRequest -Uri $downloadUri -OutFile "$installPath\astroneer\AstroLauncher.exe" -UseBasicParsing *>> "$scheduledTasksFolder\update.log"

steamcmd +login anonymous +force_install_dir "$installPath\astroneer" +app_update 728470 validate +quit  *>> "$scheduledTasksFolder\update.log"

Start-Service astroneer
"Update finished at $(Get-Date)" *>> "$scheduledTasksFolder\update.log"
