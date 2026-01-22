# OpenTAKServer-Installer

This repo contains installer scripts for OpenTAKServer. Ubuntu, Raspberry Pi OS, Rocky Linux, macOS, and Windows are currently supported.
You can request support for different platforms by opening an issue on GitHub.

## Quick Start

### Ubuntu
```shell
curl https://i.opentakserver.io/ubuntu_installer -L | bash - | tee ~/ots_ubuntu_installer.log
```

### Raspberry Pi OS
```shell
curl https://i.opentakserver.io/raspberry_pi_installer -L | bash - | tee ~/ots_rpi_installer.log
```

### Rocky Linux
```shell
curl https://i.opentakserver.io/rocky_installer -L | bash - | tee ~/ots_rocky_installer.log
```

### macOS
```shell
curl https://i.opentakserver.io/macos_installer -L | bash - | tee ~/ots_macos_installer.log
```

### Windows

The script will install the [Chocolatey](https://chocolatey.org/) package manager which is used to install
the prerequisites (RabbitMQ, nginx, git, sed, python3, and openssl). It will also install services for MediaMTX
and OpenTAKServer. These services will run as the user you are logged in as and require a password. Make sure
your user account has a password enabled. OpenTAKServer and all its data will install to `C:\users\your_username\ots` by default.
Basic usage instructions follow. For detailed instructions, see the [documentation](https://docs.opentakserver.io/#installation/windows)

1. Open Powershell as an administrator
2. `Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://i.opentakserver.io/windows_installer'))`
3. You may be prompted about the script being untrusted. If so, enter R at the prompt and press Enter to run it anyway.
4. At this point the script will run with minimal user action required. You may see dialog boxes asking if you want to allow the installed software to access the network. Click allow on all of these dialogs
5. After everything is installed, the installer will make services for MediaMTX and OpenTAKServer so they can run automatically at boot. You will be prompted for your password. The password is only used to create the services.
6. If you didn't get any errors, installation should be complete and OpenTAKServer should be running. Try browsing to http://127.0.0.1 and you will see the login page.
7. If other devices on the network can't see the login page, you may need to configure Windows Firewall. The list of ports that OpenTAKServer uses is here.
8. When installation is finished, run `Set-ExecutionPolicy Restricted -Scope Process -Force`

## Configuration

All installer scripts support customization through environment variables. You can create a `.env` file in the same directory as the installer script to configure various options.

### Creating a .env file

Copy the `.env.example` file to `.env` and customize as needed:

```shell
cp .env.example .env
# Edit .env with your preferred text editor
```

### Available Environment Variables

#### GitHub Repository
```shell
OTS_GITHUB_USER=brian7704  # Default: brian7704
```
Specify the GitHub user to download installer resources from. Useful when using a forked version of the installer.

#### Development Mode
```shell
OTS_DEV_MODE=0             # Default: 0 (production mode)
OTS_DEV_PATH=../OpenTAKServer  # Default: ../OpenTAKServer
```
Set `OTS_DEV_MODE=1` to install from local source code instead of PyPI. `OTS_DEV_PATH` specifies the path to your local OpenTAKServer source code. This is useful for development and testing local changes.

#### Installation Path
```shell
OTS_HOME=~/ots             # Default: ~/ots (or %USERPROFILE%\ots on Windows)
```
Customize the installation directory for OpenTAKServer and all its data files.

#### API Base Path
```shell
OTS_BASE=                  # Default: empty (API at root)
```
Set a base path for API endpoints. For example, set `OTS_BASE=opentakserver/` to have APIs available at `http://localhost:8081/opentakserver/api/...` instead of `http://localhost:8081/api/...`. Include trailing slash if not empty.

#### PostgreSQL Password
```shell
POSTGRESQL_PASSWORD=       # Default: randomly generated
```
Pre-configure the PostgreSQL password instead of having it randomly generated during installation.

#### Optional Features
```shell
INSTALL_ZEROTIER=0         # Default: 0
ZT_NETWORK_ID=             # Your ZeroTier network ID
INSTALL_MUMBLE=0           # Default: 0
```

### Using Environment Variables

After creating your `.env` file, the installer will automatically load it. You can also set environment variables directly:

**Linux/macOS:**
```shell
export OTS_GITHUB_USER=your_github_username
export OTS_DEV_MODE=1
./ubuntu_installer.sh
```

**Windows (PowerShell):**
```powershell
$env:OTS_GITHUB_USER="your_github_username"
$env:OTS_DEV_MODE="1"
.\windows_installer.ps1
```

## Upgrading

There are upgrade scripts for Ubuntu and Raspberry Pi OS that can be used to get the newest version of OpenTAKServer.
**Please make a backup of your database before upgrading** so it can be restored if the upgrade fails.

### Ubuntu
```shell
curl -L https://i.opentakserver.io/ubuntu_updater | bash - | tee ~/ots_ubuntu_upgrade.log
```

### Raspberry Pi OS
```shell
curl -L https://i.opentakserver.io/raspberry_pi_installer | bash - | tee ~/ots_rpi_upgrade.log
```

### Bleeding Edge Upgrades

Both the Ubuntu and Raspberry Pi upgrade scripts have an option to install the latest, unstable versions of
OpenTAKServer and OpenTAKServer-UI. This is for testing purposes only. **DO NOT USE THIS ON A PRODUCTION SERVER!** 
Expect bugs and potential breaking changes.

**Ubuntu:**
```shell
curl -L https://i.opentakserver.io/ubuntu_updater | bash -s -- --bleeding-edge | tee ~/ots_ubuntu_upgrade.log
```

**Raspberry Pi:**
```shell
curl -L https://i.opentakserver.io/raspberry_pi_installer | bash -s -- --bleeding-edge | tee ~/ots_rpi_upgrade.log
```

## Notes

ForAdvanced Usage

### Local Development

To install from local source code for development:

1. Clone both repositories:
```shell
git clone https://github.com/brian7704/OpenTAKServer.git
git clone https://github.com/brian7704/OpenTAKServer-Installer.git
cd OpenTAKServer-Installer
```

2. Create a `.env` file:
```shell
OTS_DEV_MODE=1
OTS_DEV_PATH=../OpenTAKServer
```

3. Run the installer:
```shell
./ubuntu_installer.sh
```

The installer will use `pip install -e` to install OpenTAKServer in editable mode, allowing you to test local changes.

### Using Forked Repositories

If you're using a forked version of the installer:

```shell
OTS_GITHUB_USER=your_github_username
```

This will download installer resources from your fork instead of the default repository.

### Custom Installation Paths

To install OpenTAKServer in a custom location:

```shell
OTS_HOME=/opt/opentakserver
```

All data, configurations, and certificates will be stored in this directory.

## Important Notes

- **Security:** OpenTAKServer should not be run as root. The installer will exit if run as root.
- **Backups:** Always backup your database before upgrading.
- **Firewall:** Ensure necessary ports are open in your firewall for network access.

## Features

### Automatic Certificate Generation

The installer automatically generates:
- Certificate Authority (CA)
- Server certificates and keys
- All necessary configuration for TLS/SSL

### PostgreSQL Database

The installer configures PostgreSQL with:
- Automatic database creation
- User and role setup
- Configurable passwords via `POSTGRESQL_PASSWORD` environment variable

### ZeroTier Integration (Optional)

Install [ZeroTier](https://www.zerotier.com/) during setup:
1. Set `INSTALL_ZEROTIER=1` in `.env`
2. Provide your `ZT_NETWORK_ID`
3. The installer will join the network automatically

### MediaMTX Video Streaming

The installer includes [MediaMTX](https://github.com/bluenviron/mediamtx):
- Pre-configured for OpenTAKServer integration
- Supports RTSP, RTMP, HLS, and WebRTC
- Automatic webhook configuration

### Mumble Voice Server (Optional)

Install Mumble server for voice communication:
```shell
INSTALL_MUMBLE=1
```

## Troubleshooting

### Check Service Status

**Linux/macOS:**
```shell
sudo systemctl status opentakserver
sudo systemctl status mediamtx
```

**Windows:**
```powershell
Get-Service OpenTAKServer
Get-Service MediaMTX
```

### View Logs

Logs are typically located at:
- Linux/macOS: `journalctl -u opentakserver -f`
- Windows: Check service logs in the installation directory

### Common Issues

1. **Port Conflicts:** Ensure ports 8080, 8081, 8443, 8444, 8446 are available
2. **Database Connection:** Verify PostgreSQL is running and credentials are correct
3. **Certificate Issues:** Check that CA and server certificates were generated correctly

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

## License

See LICENSE file for details.