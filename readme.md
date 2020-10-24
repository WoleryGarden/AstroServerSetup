# A set of PowerShell scripts for maintaining Astorneer Dedicated Server installation

Based on [AstroInstaller](https://github.com/alex4108/AstroInstaller). These scripts are designed to be used as a part of a VM provisioning process, the help get Astroneer Dedicated Server up and running quickly. I'm using them as a part of an ansible/awx playbook.

## Features

* Sets up [AstroLauncher](https://github.com/ricky-davis/AstroLauncher)
* Configures it as a Windows Service with [nssm](https://nssm.cc/)
* Configures scheduled [restic](https://restic.net/) backups 
* Configures daily AstroLauncher and Astroneed Dedicated Server updates at 4am
* Support restoring from prior restic backups during setup for DR scenario

## Files

* `install-astroneer-server.ps1` - the main setup script
* `Launcher.ini` - for first time setup `Launcher.ini` disabled `AstroLauncher` built-in update, because they do not work under nssm
* `astroneer-update.ps1` - This is called from a Windows Task Schedular task to update AstroLauncher and Astroneed Dedicated Server
* `restic-backup.ps1`  - This is called from a Windows Task Schedular task to backup the Astroneed Dedicated Server
* `Misc\get-launcher-src.ps1` - this is a debug script to be able to run AstroLauncher pyhton code directly (not as an exe) and allow Fiddler inspection of AstroLauncher

## Usage

These parameters of the main script are for the Astroneed Dedicated Server configuration:

* ownerName
* serverName
* serverPort
* serverPassword
* maxFPS

Additional parameters:

* installPath - where to install astroneer
* restoreLocation - this is used during setup only. If specified the latest backup will be restored from the given location
* backupLocation - if specified a scheduled backup will be setup, to the location specified.

An example of backup location: `s3:server.domain.tld/bucket`

For `restic` authentication the following environment variables have to be supplied:

* AWS_ACCESS_KEY_ID
* AWS_SECRET_ACCESS_KEY
* RESTIC_PASSWORD

See [restic documentation](https://restic.readthedocs.io/en/stable/) for their meaning.

## Notes

* `restic` credentials are stored on the Astoneer Server in a file as plain text.
* By default restic backups to an s3 backet you specify, but a small script modification can support other targets, you just will need to add environment variables with appropriate credentials, see restic documentation for details
* Schedules are hard coded, but not difficult to located and change in the source code
* For general overview of Astroneer Dedicated Server setup see: <https://tinyurl.com/astroneer-server-setup>.

## Hairpin NAT configuration for Mikrotik

Given:

* 1.1.1.1 - Astroneer Dedicated Server External IP
* 10.2.1.1 - Astroneer Dedicated Server Internal IP
* 10.1.1.0/24 - Subnet to access Astroneer Dedicated Server from, by its external IP address
* 8777 - Astroneer Dedicated Server port

The following sample configuration for Mikrotik can be used:

```text
/ip firewall nat chain=srcnat action=masquerade protocol=udp src-address=10.1.1.0/24 dst-address=10.2.1.1 out-interface-list=LAN dst-port=8777
/ip firewall nat chain=dstnat action=dst-nat to-addresses=10.2.1.1 to-ports=8777 protocol=udp dst-address=1.1.1.1 dst-port=8777
```
