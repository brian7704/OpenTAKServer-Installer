# OpenTAKServer-Installer

This repo contains installer scripts for OpenTAKServer. Ubuntu, Raspberry Pi OS, and Windows are currently supported.
You can request support for different platforms by opening and issue on GitHub.

## Usage

### Ubuntu
```shell
curl https://i.opentakserver.io/ubuntu_installer -L | bash - | tee ~/ots_ubuntu_installer.log
```

### Raspberry Pi OS
```shell
curl https://i.opentakserver.io/raspberry_pi_installer -L | bash - | tee ~/ots_rpi_installer.log
```

### Windows

The script will install the [Chocolatey](https://chocolatey.org/) package manager which is used to install
the prerequisites (RabbitMQ, nginx, git, sed, python3, and openssl). It will also install services for MediaMTX
and OpenTAKServer. These services will run as the user you are logged in as and require a password. Make sure
your user account has a password enabled. OpenTAKServer and all its data will install to C:\users\your_username\ots.
Basic usage instructions follow. For detailed instructions, see the [documentation](https://docs.opentakserver.io/#installation/windows)

1. Open Powershell as an administrator
2. `Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://i.opentakserver.io/windows_installer'))`
3. You may be prompted about the script being untrusted. If so, enter R at the prompt and press Enter to run it anyway.
4. At this point the script will run with minimal user action required. You may see dialog boxes asking if you want to allow the installed software to access the network. Click allow on all of these dialogs
5. After everything is installed, the installer will make services for MediaMTX and OpenTAKServer so they can run automatically at boot. You will be prompted for your password. The password is only used to create the services.
6. If you didn't get any errors, installation should be complete and OpenTAKServer should be running. Try browsing to http://127.0.0.1 and you will see the login page.
7. If other devices on the network can't see the login page, you may need to configure Windows Firewall. The list of ports that OpenTAKServer uses is here.
8. When installation is finished, run `Set-ExecutionPolicy Restricted -Scope Process -Force`

## Upgrading

There are upgrade scripts for Ubuntu and Raspberry Pi OS that can be used to get the newest version of OpenTAKServer.
Please make a backup of your database so it can be restored if the upgrade fails.

### Ubuntu
```shell
curl -L https://i.opentakserver.io/ubuntu_updater | bash - | tee ~/ots_ubuntu_upgrade.log
```

### Raspberry Pi OS
```shell
curl -L https://i.opentakserver.io/raspberry_pi_installer | bash - | tee ~/ots_rpi_upgrade.log
```

## Bleeding Edge

Both the Ubuntu and Raspberry Pi upgrade scripts have an option to install the latest, unstable versions of
OpenTAKServer and OpenTAKServer-UI. This is for testing purposes only, **DO NOT USE THIS ON A PRODUCTION SERVER!** More than
likely things will break or there will be bugs.

### Ubuntu

```shell
curl -L https://i.opentakserver.io/ubuntu_updater | bash -s -- --bleeding-edge | tee ~/ots_ubuntu_upgrade.log
 ```

### Raspberry Pi

```shell
curl -L https://i.opentakserver.io/raspberry_pi_installer | bash -s -- --bleeding-edge | tee ~/ots_rpi_upgrade.log
```

## Notes

For better security, OpenTAKServer should not be run as root. This installer will exit when run as root.

## Features

### Certificates

This installer will generate a CA and all the keys you need to get the server started. It will also do all the
configuration automatically.

### ZeroTier

You can optionally install [ZeroTier](https://www.zerotier.com/) with this installer. If you plan to do so, make sure 
you already have an account and a network ID before running the installer. The installer will ask for your network ID 
so it can join the network automatically.

### MediaMTX

This installer will install static binaries for [MediaMTX](https://github.com/bluenviron/mediamtx) and make the 
appropriate configuration changes in order to work with OpenTAKServer
