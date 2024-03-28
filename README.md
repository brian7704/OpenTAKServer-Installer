# OpenTAKServer-Installer

This repo contains installer scripts for OpenTAKServer. So far the only script is for Ubuntu but before the first release 
there will also be an installer for Raspberry Pi. If you would like an installer for a different platform, please feel 
free to open an issue and request it.

## Usage

### Ubuntu
```
$ bash ubuntu_installer.sh
```

### Raspberry Pi
```
$ bash raspberry_pi_installer.sh
```

### Windows

The script will install the [Chocolatey](https://chocolatey.org/) package manager which is used to install
the prerequisites (RabbitMQ, nginx, git, sed, python3, and openssl). It will also install services for MediaMTX
and OpenTAKServer. These services will run as the user you are logged in as and require a password. Make sure
your user account has a password enabled. OpenTAKServer and all its data will install to C:\users\your_username\ots.
Basic usage instructions follow. For detailed instructions, see the [documentation](https://docs.opentakserver.io/#installation/windows)

1. Open Powershell as an administrator
2. Run `Set-ExecutionPolicy Unrestricted` and type `Y` at the prompt
3. Run `OpenTAKServer-Installer\windows_installer.ps1`
4. When installation is finished, run `Set-ExecutionPolicy Restricted -Scope Process -Force`

## Notes

For better security, OpenTAKServer should not be run as root. This installer will exit when run as root.

## Features

### Certificates

This installer will generate a CA and all the keys you need to get the server started. It will also do all the
configuration automatically.

### Let's Encrypt

The installer will prompt you for your server address. If you're using a domain name, the installer will ask if you
would like to get a certificate from Let's Encrypt. This certificate will be used for OpenTAKServer's web GUI,
MediaMTX video encryption, etc. Pretty much everything except the CoT SSL streaming port (8089).

Please note that in order for this to work, the domain name should be pointed at your server's public IP address and 
ports 80 and 443 should be forwarded to your server. See
[Let's Encrypt](https://letsencrypt.org/getting-started/) and 
[Certbot](https://certbot.eff.org/instructions?ws=nginx&os=ubuntufocal) for more details.

### ZeroTier

You can optionally install [ZeroTier](https://www.zerotier.com/) with this installer. If you plan to do so, make sure 
you already have an account and a network ID before running the installer. The installer will ask for your network ID 
so it can join the network automatically.

### MediaMTX

This installer will install static binaries for [MediaMTX](https://github.com/bluenviron/mediamtx) and make the 
appropriate configuration changes in order to work with OpenTAKServer

### Email support

OpenTAKServer can be optionally configured to require users to register using an email account. Users will be emailed to
confirm their registration, reset their passwords, and optionally for two-factor authentication codes. If this option is
enabled, you will need your mail server's address, port, username, and password. When using Gmail you will need to
log into your Gmail account and enable an app password. Your normal password will not work. Other providers probably
require you to take similar steps.