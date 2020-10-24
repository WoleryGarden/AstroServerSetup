<#
.Synopsis
Install Astroneer Server
.Description
https://github.com/WoleryGarden/AstroServerSetup 
.Parameter ownerName
Astroneer server owner steam name
.Parameter serverName
Astroneer server name
.Parameter serverPort
Astroneer server UDP port. Default is 8777
.Parameter maxFPS
Maximum server FPS. Default is 30
.Parameter serverPassword
Server password. If ownerName, or sereverName or serverPasswords are not provided
on the command line, the script will ask for them interactively
.Parameter installPath
Path where to install steam applications. Defaults to "C:\Astroneer"
.Parameter restoreLocation
If specified latest restic backup from this location will be restored as a part of setup
.Parameter backupLocation
If specified a scheduled restic backup will be setip to this location
.Link
https://github.com/WoleryGarden/AstroServerSetup
#>
param(
  [string]$ownerName,
  [string]$serverName = "Astroneer Dedicated Server",
  [int]$serverPort = 8777,
  [string]$serverPassword,
  [string]$installPath = "C:\Astroneer",
  [int]$maxFPS = 30,
  [string]$backupLocation,
  [string]$restoreLocation
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$scheduledTasksFolder = "$installPath\ScheduledTasks"


# This function is taken from https://stackoverflow.com/a/53561052/284111
function Remove-FileSystemItem {
  <#
  .SYNOPSIS
    Removes files or directories reliably and synchronously.

  .DESCRIPTION
    Removes files and directories, ensuring reliable and synchronous
    behavior across all supported platforms.

    The syntax is a subset of what Remove-Item supports; notably,
    -Include / -Exclude and -Force are NOT supported; -Force is implied.

    As with Remove-Item, passing -Recurse is required to avoid a prompt when 
    deleting a non-empty directory.

    IMPORTANT:
      * On Unix platforms, this function is merely a wrapper for Remove-Item, 
        where the latter works reliably and synchronously, but on Windows a 
        custom implementation must be used to ensure reliable and synchronous 
        behavior. See https://github.com/PowerShell/PowerShell/issues/8211

    * On Windows:
      * The *parent directory* of a directory being removed must be 
        *writable* for the synchronous custom implementation to work.
      * The custom implementation is also applied when deleting 
         directories on *network drives*.

    * If an indefinitely *locked* file or directory is encountered, removal is aborted.
      By contrast, files opened with FILE_SHARE_DELETE / 
      [System.IO.FileShare]::Delete on Windows do NOT prevent removal, 
      though they do live on under a temporary name in the parent directory 
      until the last handle to them is closed.

    * Hidden files and files with the read-only attribute:
      * These are *quietly removed*; in other words: this function invariably
        behaves like `Remove-Item -Force`.
      * Note, however, that in order to target hidden files / directories
        as *input*, you must specify them as a *literal* path, because they
        won't be found via a wildcard expression.

    * The reliable custom implementation on Windows comes at the cost of
      decreased performance.

  .EXAMPLE
    Remove-FileSystemItem C:\tmp -Recurse

    Synchronously removes directory C:\tmp and all its content.
  #>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Path', PositionalBinding = $false)]
  param(
    [Parameter(ParameterSetName = 'Path', Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [string[]] $Path
    ,
    [Parameter(ParameterSetName = 'Literalpath', ValueFromPipelineByPropertyName)]
    [Alias('PSPath')]
    [string[]] $LiteralPath
    ,
    [switch] $Recurse
  )
  begin {
    # !! Workaround for https://github.com/PowerShell/PowerShell/issues/1759
    if ($ErrorActionPreference -eq [System.Management.Automation.ActionPreference]::Ignore) { $ErrorActionPreference = 'Ignore' }
    $targetPath = ''
    $yesToAll = $noToAll = $false
    function trimTrailingPathSep([string] $itemPath) {
      if ($itemPath[-1] -in '\', '/') {
        # Trim the trailing separator, unless the path is a root path such as '/' or 'c:\'
        if ($itemPath.Length -gt 1 -and $itemPath -notmatch '^[^:\\/]+:.$') {
          $itemPath = $itemPath.Substring(0, $itemPath.Length - 1)
        }
      }
      $itemPath
    }
    function getTempPathOnSameVolume([string] $itemPath, [string] $tempDir) {
      if (-not $tempDir) { $tempDir = [IO.Path]::GetDirectoryName($itemPath) }
      [IO.Path]::Combine($tempDir, [IO.Path]::GetRandomFileName())
    }
    function syncRemoveFile([string] $filePath, [string] $tempDir) {
      # Clear the ReadOnly attribute, if present.
      if (($attribs = [IO.File]::GetAttributes($filePath)) -band [System.IO.FileAttributes]::ReadOnly) {
        [IO.File]::SetAttributes($filePath, $attribs -band -bnot [System.IO.FileAttributes]::ReadOnly)
      }
      $tempPath = getTempPathOnSameVolume $filePath $tempDir
      [IO.File]::Move($filePath, $tempPath)
      [IO.File]::Delete($tempPath)
    }
    function syncRemoveDir([string] $dirPath, [switch] $recursing) {
      if (-not $recursing) { $dirPathParent = [IO.Path]::GetDirectoryName($dirPath) }
      # Clear the ReadOnly attribute, if present.
      # Note: [IO.File]::*Attributes() is also used for *directories*; [IO.Directory] doesn't have attribute-related methods.
      if (($attribs = [IO.File]::GetAttributes($dirPath)) -band [System.IO.FileAttributes]::ReadOnly) {
        [IO.File]::SetAttributes($dirPath, $attribs -band -bnot [System.IO.FileAttributes]::ReadOnly)
      }
      # Remove all children synchronously.
      $isFirstChild = $true
      foreach ($item in [IO.directory]::EnumerateFileSystemEntries($dirPath)) {
        if (-not $recursing -and -not $Recurse -and $isFirstChild) {
          # If -Recurse wasn't specified, prompt for nonempty dirs.
          $isFirstChild = $false
          # Note: If -Confirm was also passed, this prompt is displayed *in addition*, after the standard $PSCmdlet.ShouldProcess() prompt.
          #       While Remove-Item also prompts twice in this scenario, it shows the has-children prompt *first*.
          if (-not $PSCmdlet.ShouldContinue("The item at '$dirPath' has children and the -Recurse switch was not specified. If you continue, all children will be removed with the item. Are you sure you want to continue?", 'Confirm', ([ref] $yesToAll), ([ref] $noToAll))) { return }
        }
        $itemPath = [IO.Path]::Combine($dirPath, $item)
        ([ref] $targetPath).Value = $itemPath
        if ([IO.Directory]::Exists($itemPath)) {
          syncremoveDir $itemPath -recursing
        }
        else {
          syncremoveFile $itemPath $dirPathParent
        }
      }
      # Finally, remove the directory itself synchronously.
      ([ref] $targetPath).Value = $dirPath
      $tempPath = getTempPathOnSameVolume $dirPath $dirPathParent
      [IO.Directory]::Move($dirPath, $tempPath)
      [IO.Directory]::Delete($tempPath)
    }
  }

  process {
    $isLiteral = $PSCmdlet.ParameterSetName -eq 'LiteralPath'
    if ($env:OS -ne 'Windows_NT') {
      # Unix: simply pass through to Remove-Item, which on Unix works reliably and synchronously
      Remove-Item @PSBoundParameters
    }
    else {
      # Windows: use synchronous custom implementation
      foreach ($rawPath in ($Path, $LiteralPath)[$isLiteral]) {
        # Resolve the paths to full, filesystem-native paths.
        try {
          # !! Convert-Path does find hidden items via *literal* paths, but not via *wildcards* - and it has no -Force switch (yet)
          # !! See https://github.com/PowerShell/PowerShell/issues/6501
          $resolvedPaths = if ($isLiteral) { Convert-Path -ErrorAction Stop -LiteralPath $rawPath } else { Convert-Path -ErrorAction Stop -path $rawPath }
        }
        catch {
          Write-Error $_ # relay error, but in the name of this function
          continue
        }
        try {
          $isDir = $false
          foreach ($resolvedPath in $resolvedPaths) {
            # -WhatIf and -Confirm support.
            if (-not $PSCmdlet.ShouldProcess($resolvedPath)) { continue }
            if ($isDir = [IO.Directory]::Exists($resolvedPath)) {
              # dir.
              # !! A trailing '\' or '/' causes directory removal to fail ("in use"), so we trim it first.
              syncRemoveDir (trimTrailingPathSep $resolvedPath)
            }
            elseif ([IO.File]::Exists($resolvedPath)) {
              # file
              syncRemoveFile $resolvedPath
            }
            else {
              Throw "Not a file-system path or no longer extant: $resolvedPath"
            }
          }
        }
        catch {
          if ($isDir) {
            $exc = $_.Exception
            if ($exc.InnerException) { $exc = $exc.InnerException }
            if ($targetPath -eq $resolvedPath) {
              Write-Error "Removal of directory '$resolvedPath' failed: $exc"
            }
            else {
              Write-Error "Removal of directory '$resolvedPath' failed, because its content could not be (fully) removed: $targetPath`: $exc"
            }
          }
          else {
            Write-Error $_  # relay error, but in the name of this function
          }
          continue
        }
      }
    }
  }
}
function InstallScoop {
  if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..."
    Invoke-WebRequest -UseBasicParsing get.scoop.sh | Invoke-Expression
    scoop install git -g
    scoop bucket add extras
  }
}

function InstallDotnet {
  $edition = (Get-WindowsEdition -Online).Edition
  if ($edition -like "*Server*") { 
    $windowsServer = $true;
  }
  else {
    $windowsServer = $false;
  }

  Write-Host "Installing DotNet Framework..."
  if ( $windowsServer -eq $true ) { 
    Install-WindowsFeature Net-Framework-Core
  }
  else {
    # Windows 10
    Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3"
  }
}

function InstallWithScoop {
  Write-Host "Installing nescessary software with scoop..."
  scoop install steamcmd nssm restic fiddler -g
}

                    
function ConfigureFirewall {
  Write-Host "Configuring firewall..."
  netsh advfirewall firewall add rule name="AstroServer" dir=in action=allow program="$installPath\Astroneer\AstroServer.exe" | Out-Null
  netsh advfirewall firewall add rule name="AstroServer" dir=in action=allow program="$installPath\Astroneer\astro\binaries\win64\astroserver-win64-shipping.exe" | Out-Null
  netsh advfirewall firewall add rule name="AstroServer" dir=in action=allow protocol=UDP localport=$serverPort  | Out-Null
  netsh advfirewall firewall add rule name="AstroLauncher" dir=in action=allow program="$installPath\Astroneer\AstroLauncher.exe"  | Out-Null
  netsh advfirewall firewall add rule name="AstroLauncher" dir=in action=allow protocol=TCP localport=5000  | Out-Null 
}

function InstallAstroneer {
  Write-Host "Installing Astroneer Dedicated Server..."
  steamcmd +login anonymous +force_install_dir "$installPath\astroneer" +app_update 728470 validate +quit

  Write-Host "Running Unreal Engine 4 Prerequisite Setup"
  $proc = Start-Process -FilePath "$installPath\Astroneer\Engine\Extras\Redist\en-us\UE4PrereqSetup_x64.exe" -ArgumentList "/uninstall /passive" -WorkingDirectory $installPath -PassThru
  $proc | Wait-Process
  $proc = Start-Process -FilePath "$installPath\Astroneer\Engine\Extras\Redist\en-us\UE4PrereqSetup_x64.exe"  -ArgumentList "/install /passive" -WorkingDirectory $installPath -PassThru
  $proc | Wait-Process
}

function UpdateSettings([string]$fileName, $settings) {
  $data = @{}
  $currentGroup = "ungrouped"
  $r = [regex]"(?<key>[^=]*)=(?<value>.*)"

  Get-Content -Path $fileName | ForEach-Object {
    $current = $_.Trim()
    if ($current.Length -gt 0) {
      if ($current[0] -eq "[" -and $current[-1] -eq "]") {
        $newGroup = $current.Substring(1, $current.Length - 2)
        if ($newGroup.Length -le 0) {
          Write-Error "Failed parsing $fileName. Empty group '[]' is found"
        }
        $currentGroup = $newGroup
      }
      else {
        if (!$data[$currentGroup]) {
          $data[$currentGroup] = @()
        }
        $m = $r.Match($current)
        $key = $m.Groups["key"].Value
        $value = $m.Groups["value"].Value
        if (!$key) {
          Write-Error "Could not parse '$current' as 'key=value' in $fileName"
        }
        $data[$currentGroup] = @($data[$currentGroup]) + @([pscustomobject]@{Key = $key; Value = $value })
      }
    } 
  }

  $settings | ForEach-Object {
    $key = $_.Key
    $data[$_.Group] = $data[$_.Group] | Where-Object { $_.Key -ne $key }
    if (!$data[$_.Group]) {
      $data[$_.Group] = @()
    }
    $data[$_.Group] = @($data[$_.Group]) + @([pscustomobject]@{Key = $key; Value = $_.Value })
  }

  $result = $data.Keys | Sort-Object | ForEach-Object {
    if ($data[$_].Count -ge 0) {
      "[$_]"
      $data[$_] | Sort-Object | ForEach-Object {
        "$($_.Key)=$($_.Value)"
      }
    }
  }

  $result = $result -join "`r`n"
  [IO.File]::WriteAllBytes($fileName, [Text.Encoding]::UTF8.GetBytes($result))
}

function ConfigureAstroneer {
  $configFile = "$installPath\Astroneer\Astro\Saved\Config\WindowsServer\AstroServerSettings.ini"
  $engineFile = "$installPath\Astroneer\Astro\Saved\Config\WindowsServer\Engine.ini"

  # This one silences a popup for dependncies that are already installed
  Write-Host "Starting Astroneer..."
  $proc = Start-Process -filePath "$installPath\Astroneer\AstroServer.exe" -WorkingDirectory "$installPath\Astroneer\" -PassThru

  Write-Host "Waiting for config file to populate"
  $slept = $false
  $start = Get-Date
  while (($start.AddMinutes(2) -gt (Get-Date)) -and (!(Test-Path $configFile) -or (get-childitem $configFile).length -le 10)) {
    Start-Sleep 10
    Write-Host "." -NoNewLine
    $slept = $true
  }

  # Kill AstroServer.exe if it's not dead yet
  if ($slept) { Write-Host }
  if (!(Test-Path $configFile) -or (get-childitem $configFile).length -le 10) {
    Write-Error "Timed out waiting for config file to be populated"
  }

  Write-Host "Kill Astroneer..."
  Stop-Process $proc
  Get-Process AstroServer-Win64-Shipping -ErrorAction SilentlyContinue | Stop-Process

  $publicIP = Invoke-RestMethod -Uri 'http://ifconfig.me/ip'


  Write-Host "Modifying Config Files"

  UpdateSettings $configFile  @(
    @{Group = "/Script/Astro.AstroServerSettings"; Key = "PublicIP"; Value = "$publicIP" },
    @{Group = "/Script/Astro.AstroServerSettings"; Key = "MaxServerFramerate"; Value = "$maxFPS.000000" },
    @{Group = "/Script/Astro.AstroServerSettings"; Key = "ServerName"; Value = "$serverName" },
    @{Group = "/Script/Astro.AstroServerSettings"; Key = "OwnerName"; Value = "$ownerName" },
    @{Group = "/Script/Astro.AstroServerSettings"; Key = "ServerPassword"; Value = "$serverPassword" }
  )

  UpdateSettings $engineFile  @(
    @{Group = "URL"; Key = "Port"; Value = "$serverPort" }
  )
}

function InstallAstroLauncher {
  Write-Host "Downloading AstroLauncher"
  $repo = "ricky-davis/AstroLauncher"
  $filename = "AstroLauncher.exe"
  $releasesUri = "https://api.github.com/repos/$repo/releases/latest"
  $downloadUri = ((Invoke-RestMethod -Method GET -Uri $releasesUri).assets | Where-Object name -like $filename ).browser_download_url
  Invoke-WebRequest -Uri $downloadUri -OutFile "$installPath\Astroneer\AstroLauncher.exe" -UseBasicParsing
}

# If string does not match returns nothing
# If string matches returns an object with Suffix that matched and remaining Prefix
# If more than one target matched selects longest match
function utilSplit($string, $targets) {
  $result = $targets | ForEach-Object {
    if ($string.EndsWith($_)) {
      [pscustomobject]@{Prefix = $string.Substring(0, $string.length - $_.length); Suffix = $_ }
    }
  }
  $result | Sort-Object -Property @{Expression = { $_.Suffix.Length }; Descending = $True } | Select-Object -First 1
}

function RestoreBackup {
  Write-Host "Restoring backup..."

  $targets = "Astro\Saved\Config\WindowsServer",
  "Astro\Saved\SaveGames",
  "Launcher.ini"

  $tempRestore = "$installPath\restore"

  $data = restic -r $restoreLocation snapshots --last --json | ConvertFrom-Json

  # Adds Prefix/Suffix breakdown (as above) for each path
  $decorated = $data | ForEach-Object {
    [pscustomobject]@{Restic = $_; Parts = ($_.Paths | ForEach-Object { utilSplit $_ $targets }) }
  }

  # Select only those elements that match
  $result = $decorated | Where-Object {
    #  Compare-Object freaks out on $null
    $left = if ($null -eq $_.Parts.Suffix) { , @() } else { $_.Parts.Suffix }
    # If we have the same suffixes and targets
    !(Compare-Object $left $targets) -and 
    # And all prefixes are equal
    (($_.Parts.Prefix | Select-Object -Unique).Count -eq 1) -and
    # And there are as many Paths as targets
    $_.Restic.Paths.Count -eq $_.Parts.Count
  } | Select-Object -First 1

  restic -r $restoreLocation restore $result.Restic.id --target $tempRestore
  $prefix = $result.Parts.Prefix | Select-Object -First 1
  Push-Location
  Set-Location $tempRestore
  $prefix.Replace(":", "").Split([IO.Path]::DirectorySeparatorChar) | ForEach-Object {
    Set-Location $_
  }

  $fromPrefix = (Get-Location).Path
  $toPrefix = "C:\Astroneer\astroneer"

  Get-ChildItem -Recurse -File | ForEach-Object {
    $from = $_.FullName
    $to = $from.Replace($fromPrefix, $toPrefix);
    "$from => $to" | Write-host   
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($to)) -Force | Out-Null
    Copy-Item $from $to
  }

  Pop-Location
  
  Remove-FileSystemItem $tempRestore -Recurse

}

function InstallService {

  if (Get-Service astroneer -ErrorAction SilentlyContinue) {
    Write-Host "Service is already installed. removing..."  
    nssm remove astroneer confirm
  }
  Write-Host "Installing Service..."  
  nssm install astroneer "$installPath\astroneer\AstroLauncher.exe"
  nssm set astroneer start SERVICE_DELAYED_AUTO_START
  nssm set astroneer AppStopMethodConsole 10000
  nssm set astroneer AppStopMethodWindow 10000
  nssm set astroneer AppStopMethodThreads 10000
}

function SetupBackups {
  
  if (Get-ScheduledTask astroneer-backup -ErrorAction SilentlyContinue) {
    Write-Host "Task is already registered. Unregistering..."  
    Unregister-ScheduledTask astroneer-backup -Confirm:$false
  }

  Write-Host "Setting up backups..."

  New-Item -ItemType Directory -Force -Path $scheduledTasksFolder | Out-Null
  Copy-Item "$PSScriptRoot\restic-backup.ps1" "$scheduledTasksFolder\restic-backup.ps1" -Force
  
  $data = [IO.File]::ReadAllText("$scheduledTasksFolder\restic-backup.ps1")
  $data = $data.Replace("%AWS_ACCESS_KEY_ID%",$env:AWS_ACCESS_KEY_ID)
  $data = $data.Replace("%AWS_SECRET_ACCESS_KEY%",$env:AWS_SECRET_ACCESS_KEY)
  $data = $data.Replace("%RESTIC_PASSWORD%",$env:RESTIC_PASSWORD)
  $data = $data.Replace("%scheduledTasksFolder%",$scheduledTasksFolder)
  $data = $data.Replace("%installPath%",$installPath)
  $data = $data.Replace("%backupLocation%",$backupLocation)
  [IO.File]::WriteAllText("$scheduledTasksFolder\restic-backup.ps1", $data)
   
  $A = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $scheduledTasksFolder\restic-backup.ps1"
  $T = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
  $P = New-ScheduledTaskPrincipal ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U
  $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T 
  Register-ScheduledTask astroneer-backup -InputObject $D
}

function SetupUpdates {

  if (Get-ScheduledTask astroneer-update -ErrorAction SilentlyContinue) {
    Write-Host "Task is already registered. Unregistering..."  
    Unregister-ScheduledTask astroneer-update -Confirm:$false
  }

  Write-Host "Setting up updates..."

  New-Item -ItemType Directory -Force -Path $scheduledTasksFolder | Out-Null
  Copy-Item "$PSScriptRoot\astroneer-update.ps1" "$scheduledTasksFolder\astroneer-update.ps1" -Force

  $data = [IO.File]::ReadAllText("$scheduledTasksFolder\astroneer-update.ps1")
  $data = $data.Replace("%installPath%",$installPath)
  $data = $data.Replace("%scheduledTasksFolder%",$scheduledTasksFolder)
  [IO.File]::WriteAllText("$scheduledTasksFolder\astroneer-update.ps1", $data)

  $A = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File $scheduledTasksFolder\astroneer-update.ps1"
  $T = New-ScheduledTaskTrigger -Daily -At "4:00"
  $P = New-ScheduledTaskPrincipal ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U
  $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T 
  Register-ScheduledTask astroneer-update -InputObject $D
}

InstallScoop
InstallDotnet
InstallWithScoop
ConfigureFirewall
InstallAstroneer
ConfigureAstroneer
InstallAstroLauncher
InstallService

if ($restoreLocation) {
  if (!$env:RESTIC_PASSWORD) {
    Write-Error "RESTIC_PASSWORD environent variable is not set"
  }
  RestoreBackup
} else {
  Write-Host "Copying starting Launcher.ini..."
  Copy-Item "$PSScriptRoot\Launcher.ini" "$installPath\astroneer\Launcher.ini" -Force
}

if ($backupLocation) {
  if (!$env:RESTIC_PASSWORD) {
    Write-Error "RESTIC_PASSWORD environent variable is not set"
  }
  SetupBackups
}

SetupUpdates

Write-Host "Finished"
