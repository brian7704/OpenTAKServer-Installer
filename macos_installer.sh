#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

curl -sL https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -o "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

echo "${GREEN}

   ___                        _____     _     _  __  ___
  / _ \   _ __   ___   _ _   |_   _|   /_\   | |/ / / __|  ___   _ _  __ __  ___   _ _
 | (_) | | '_ \ / -_) | ' \    | |    / _ \  | ' <  \__ \ / -_) | '_| \ V / / -_) | '_|
  \___/  | .__/ \___| |_||_|   |_|   /_/ \_\ |_|\_\ |___/ \___| |_|    \_/  \___| |_|
         |_|

${NC}"

MACOS_VERSION=$(sw_vers --productVersion)
# Compare versions by their individual major, minor, and patch numbers because bash throws an error on strings like "1.1.10"
IFS='.'
read -ra VERSION_ARRAY <<< "$MACOS_VERSION"
INSTALLED_MAJOR=${VERSION_ARRAY[0]}

if [ "$INSTALLED_MAJOR" -lt 14 ]
then
  read -p "${YELLOW} This installer is for macOS 14 and up. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
  rm -fr $INSTALLER_DIR
fi

USERNAME=$(whoami)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  rm -fr $INSTALLER_DIR
  exit 1
fi

# Check if homebrew is installed
brew &> /dev/null
if [ "$?" -eq 127 ]
then
  echo "${GREEN}Installing homebrew...${NC}"
  INTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add the brew command to $PATH
  echo >> ~/.zprofile
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

mkdir -p ~/ots

echo "${GREEN}Installing prerequisites via brew...${NC}"

# Without the echo "", brew install causes the rest of the script to fail https://github.com/Homebrew/homebrew-core/issues/141712
echo "" | brew install rabbitmq python@3.12 nginx ffmpeg mediamtx

sudo curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/macos_configs/launchd.opentakserver.plist -o /Library/LaunchDaemons/launchd.opentakserver.plist
sudo curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/macos_configs/homebrew.mxcl.mediamtx.plist -o /Library/LaunchDaemons/homebrew.mxcl.mediamtx.plist
sudo curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/macos_configs/homebrew.mxcl.nginx.plist -o /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
sudo curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/macos_configs/homebrew.mxcl.rabbitmq.plist -o /Library/LaunchDaemons/homebrew.mxcl.rabbitmq.plist

sudo sed -i '' "s/USERNAME/${USERNAME}/g" /Library/LaunchDaemons/homebrew.mxcl.rabbitmq.plist
sudo sed -i '' "s/USERNAME/${USERNAME}/g" /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
sudo sed -i '' "s/USERNAME/${USERNAME}/g" /Library/LaunchDaemons/homebrew.mxcl.mediamtx.plist
sudo sed -i '' "s/USERNAME/${USERNAME}/g" /Library/LaunchDaemons/launchd.opentakserver.plist
sudo sed -i '' "s~HOME_FOLDER~${HOME}~g" /Library/LaunchDaemons/launchd.opentakserver.plist

sudo chown root /Library/LaunchDaemons/homebrew.mxcl.rabbitmq.plist
sudo chown root /Library/LaunchDaemons/homebrew.mxcl.nginx.plist
sudo chown root /Library/LaunchDaemons/homebrew.mxcl.mediamtx.plist
sudo chown root /Library/LaunchDaemons/launchd.opentakserver.plist

echo "${GREEN}Configuring MediaMTX...${NC}"
mkdir -p ~/ots/mediamtx/recordings
ln -s /opt/homebrew/etc/mediamtx/mediamtx.yml ~/ots/mediamtx/mediamtx.yml

cd ~/ots/mediamtx
curl -sL https://github.com/brian7704/OpenTAKServer-Installer/raw/master/mediamtx.yml -o /opt/homebrew/etc/mediamtx/mediamtx.yml
sed -i '' "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /opt/homebrew/etc/mediamtx/mediamtx.yml
sed -i '' "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /opt/homebrew/etc/mediamtx/mediamtx.yml
sed -i '' "s~OTS_FOLDER~${HOME}/ots~g" /opt/homebrew/etc/mediamtx/mediamtx.yml

sudo launchctl load -w /Library/LaunchDaemons/homebrew.mxcl.mediamtx.plist

echo "${GREEN}Configuring nginx...${NC}"
mkdir -p /opt/homebrew/etc/nginx/streams
rm /opt/homebrew/etc/nginx/nginx.conf
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/macos_configs/nginx.conf -o /opt/homebrew/etc/nginx/nginx.conf
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/nginx_configs/rabbitmq -o /opt/homebrew/etc/nginx/streams/rabbitmq
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/mediamtx -o /opt/homebrew/etc/nginx/streams/mediamtx
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_certificate_enrollment -o /opt/homebrew/etc/nginx/servers/ots_certificate_enrollment
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_http -o /opt/homebrew/etc/nginx/servers/ots_http
curl -sL https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_https -o /opt/homebrew/etc/nginx/servers/ots_https

sed -i '' "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /opt/homebrew/etc/nginx/servers/ots_https
sed -i '' "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /opt/homebrew/etc/nginx/servers/ots_certificate_enrollment
sed -i '' "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /opt/homebrew/etc/nginx/streams/rabbitmq
sed -i '' "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /opt/homebrew/etc/nginx/streams/mediamtx
sed -i '' "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /opt/homebrew/etc/nginx/servers/ots_https
sed -i '' "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /opt/homebrew/etc/nginx/servers/ots_certificate_enrollment
sed -i '' "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /opt/homebrew/etc/nginx/streams/rabbitmq
sed -i '' "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /opt/homebrew/etc/nginx/streams/mediamtx
sed -i '' "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /opt/homebrew/etc/nginx/servers/ots_https
sed -i '' "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /opt/homebrew/etc/nginx/servers/ots_certificate_enrollment
sed -i '' "s~/var/www/html~/opt/homebrew/var/www~g" /opt/homebrew/etc/nginx/servers/ots_http
sed -i '' "s~/var/www/html~/opt/homebrew/var/www~g" /opt/homebrew/etc/nginx/servers/ots_https
sed -i '' "s~/var/www/html~/opt/homebrew/var/www~g" /opt/homebrew/etc/nginx/servers/ots_certificate_enrollment

tee /opt/homebrew/etc/nginx/proxy_params >/dev/null << EOF
proxy_set_header Host \$http_host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
EOF

NGINX_CELLAR=`readlink -f $(brew --prefix nginx)`
mkdir -p "$NGINX_CELLAR"/logs

echo "${GREEN}Configuring RabbitMQ...${NC}"
echo "
mqtt.listeners.tcp.default = 1883

auth_backends.1 = internal
auth_backends.2 = http
auth_http.http_method   = post
auth_http.user_path     = http://127.0.0.1:8081/api/rabbitmq/auth
auth_http.vhost_path    = http://127.0.0.1:8081/api/rabbitmq/vhost
auth_http.resource_path = http://127.0.0.1:8081/api/rabbitmq/resource
auth_http.topic_path    = http://127.0.0.1:8081/api/rabbitmq/topic" >> /opt/homebrew/etc/rabbitmq/rabbitmq.conf

sudo launchctl load -w /Library/LaunchDaemons/homebrew.mxcl.rabbitmq.plist

echo "${GREEN} Installing OpenTAKServer from PyPI...${NC}"
python3.12 -m venv --system-site-packages ~/.opentakserver_venv
source "$HOME"/.opentakserver_venv/bin/activate
pip3.12 install opentakserver
mkdir -p /opt/homebrew/var/www/opentakserver
cd /opt/homebrew/var/www/opentakserver
lastversion --assets extract brian7704/OpenTAKServer-UI
echo "${GREEN}OpenTAKServer Installed!${NC}"

echo "${GREEN}Initializing Database...${NC}"
cd "$HOME"/.opentakserver_venv/lib/python3.12/site-packages/opentakserver
flask db upgrade
cd "$INSTALLER_DIR"
echo "${GREEN}Finished initializing database!${NC}"

echo "${GREEN}Creating certificate authority...${NC}"

mkdir -p ~/ots/ca
cd "$HOME"/.opentakserver_venv/lib/python3.12/site-packages/opentakserver
flask ots create-ca

deactivate

sudo launchctl load -w /Library/LaunchDaemons/launchd.opentakserver.plist
sudo launchctl load -w /Library/LaunchDaemons/homebrew.mxcl.nginx.plist

echo "${GREEN}Finished installing OpenTAKServer${NC}"
