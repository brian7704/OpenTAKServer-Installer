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
