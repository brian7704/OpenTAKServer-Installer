#!/bin/bash

SOPT='h'
LOPT='bleeding-edge,help'
OPTS=$(getopt -q -a \
    --options ${SOPT} \
    --longoptions ${LOPT} \
    --name "$(basename "$0")" \
    -- "$@"
)

if [[ $? -gt 0 ]]; then
    exit 2
fi

show_help () {
    echo "usage:  $BASH_SOURCE"
    echo "                     -h --help - Print help and exit"
    echo "                     --bleeding-edge - Upgrade to the non-production ready bleeding edge version"
}

BLEEDING_EDGE=0

eval set -- "$OPTS"

while [[ $# -gt 0 ]]; do
    case ${1} in
        -h)
                show_help
                exit 0
                ;;
        --help)
                show_help
                exit 0
                ;;
        --bleeding-edge)
                BLEEDING_EDGE=1
                ;;
        --)
                ;;
        -)
                ;;
        *)
                ;;
    esac
    shift
done

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

if [[ "$BLEEDING_EDGE" -gt 0 ]]; then
  echo "${YELLOW}------------------------------------------!!! WARNING !!!---------------------------------------------"
  echo "This will upgrade to the bleeding edge version of OpenTAKServer. DO NOT DO THIS ON PRODUCTION SERVERS!"
  read -p "Do you want to upgrade anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
fi

. /etc/os-release

if [ "$NAME" != "Ubuntu" ] && [ "$NAME" != "Raspbian GNU/Linux" ] && [ "$NAME" != "Debian GNU/Linux" ]
then
  read -p "${YELLOW} This updater is for Ubuntu and Rapsberry Pi but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
  rm -fr $INSTALLER_DIR
fi

USERNAME=$(whoami)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  rm -fr $INSTALLER_DIR
  exit 1
fi

read -p "${YELLOW}This script will make changes to your database. Please back it up in case anything goes wrong. Would you like to continue? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

LATEST_OTS_VERSION="$(curl -s https://pypi.org/rss/project/opentakserver/releases.xml | sed -n 's/\s*<title>\([0-9.]*\).*/\1/p' | head -2 | tail -1)"
INSTALLED_OTS_VERSION="$(~/.opentakserver_venv/bin/python -c 'import opentakserver; print(opentakserver.__version__)')"
echo "${GREEN}OpenTAKServer version ${INSTALLED_OTS_VERSION} is currently installed and ${LATEST_OTS_VERSION} is available${NC}"

# Compare versions by their individual major, minor, and patch numbers because bash throws an error on strings like "1.1.10"
IFS='.'
read -ra VERSION_ARRAY <<< "$INSTALLED_OTS_VERSION"
INSTALLED_MAJOR=${VERSION_ARRAY[0]}
INSTALLED_MINOR=${VERSION_ARRAY[1]}
INSTALLED_PATCH=${VERSION_ARRAY[2]}

read -ra VERSION_ARRAY <<< "$LATEST_OTS_VERSION"
LATEST_MAJOR=${VERSION_ARRAY[0]}
LATEST_MINOR=${VERSION_ARRAY[1]}
LATEST_PATCH=${VERSION_ARRAY[2]}

if [[ "$BLEEDING_EDGE" -eq 1 ]]; then
  echo "${GREEN}Installing OpenTAKServer from git HEAD...${NC}"
  ~/.opentakserver_venv/bin/pip install git+https://github.com/brian7704/OpenTAKServer.git

  echo "${GREEN}Upgrading database schema...${NC}"
  cd ~/.opentakserver_venv/lib/python3.1*/site-packages/opentakserver
  ~/.opentakserver_venv/bin/flask db upgrade

  echo "${GREEN}Upgrading UI...${NC}"
  rm -fr /var/www/html/opentakserver/*
  cd /var/www/html/opentakserver/
  ~/.opentakserver_venv/bin/lastversion --pre --assets extract brian7704/OpenTAKServer-UI

  echo "${GREEN}Restarting the OpenTAKServer service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart opentakserver

elif [[ "$LATEST_MAJOR" -ne "$INSTALLED_MAJOR" || "$LATEST_MINOR" -ne "$INSTALLED_MINOR" || "$LATEST_PATCH" -ne "$INSTALLED_PATCH" ]]; then
  echo "${GREEN}Upgrading OpenTAKServer to version ${LATEST_OTS_VERSION}${NC}"
  ~/.opentakserver_venv/bin/pip install opentakserver -U

  echo "${GREEN}Upgrading database schema...${NC}"
  ~/.opentakserver_venv/bin/flask db upgrade

  echo "${GREEN}Upgrading UI...${NC}"
  rm -fr /var/www/html/opentakserver/*
  cd /var/www/html/opentakserver/
  ~/.opentakserver_venv/bin/lastversion --assets extract brian7704/OpenTAKServer-UI

  echo "${GREEN}Restarting the OpenTAKServer service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart opentakserver
fi

# Upgrade MediaMTX
MEDIAMTX_VERSION=$(~/ots/mediamtx/mediamtx --version)
MEDIAMTX_VERSION="${MEDIAMTX_VERSION//v}"
NEWEST_MEDIAMTX_VERSION=$(~/.opentakserver_venv/bin/lastversion bluenviron/mediamtx)

if [[ MEDIAMTX_VERSION -ne NEWEST_MEDIAMTX_VERSION ]]; then
  echo "${GREEN}Upgrading MediaMTX from version ${MEDIAMTX_VERSION} to ${NEWEST_MEDIAMTX_VERSION}...${NC}"
  cd ~/ots/mediamtx
  mv mediamtx.yml mediamtx.yml.bak
  mv mediamtx mediamtx_"$MEDIAMTX_VERSION"
  rm mediamtx*.tar.gz

  ARCH=$(uname -m)
  KERNEL_BITS=$(getconf LONG_BIT)
  if [ "$ARCH" == "x86_64" ]; then
    lastversion --filter '~*linux_amd64' --assets download bluenviron/mediamtx
  elif [ "$KERNEL_BITS" == 32 ]; then
    lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx
  elif [ "$KERNEL_BITS" == 64 ]; then
    lastversion --filter '~*linux_arm64v8' --assets download bluenviron/mediamtx
  fi

  tar -xf ./*.tar.gz
  cp mediamtx.yml.bak mediamtx.yml
  echo "${GREEN}Restarting the MediaMTX service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart mediamtx
fi

# Check if nginx's stream module is enabled
echo "${GREEN}Checking nginx config. Please enter your sudo password if prompted${NC}"
sudo grep "stream {" /etc/nginx/nginx.conf &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "${GREEN}Configuring nginx...${NC}"
  sudo apt install libnginx-mod-stream
  sudo mkdir -p /etc/nginx/streams-available
  sudo mkdir -p /etc/nginx/streams-enabled
  cd /etc/nginx/streams-available
  sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/nginx_configs/rabbitmq
  sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" rabbitmq
  sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" rabbitmq
  sudo ln -s /etc/nginx/streams-available/rabbitmq /etc/nginx/streams-enabled/rabbitmq
  echo "
stream {
  include /etc/nginx/streams-enabled/*;
}
  " | sudo tee -a /etc/nginx/nginx.conf
  sudo systemctl restart nginx
  cd "$INSTALLER_DIR"
fi

# Check if "location /api" is in the server block for port 8443
# This is required for the plugin update server functionality to work
API=$(sudo grep "location /api" /etc/nginx/sites-enabled/ots_https | wc -l)
if [[ $API -eq 1 ]]; then
  echo "${GREEN}Configuring Nginx. Please enter your sudo password if prompted${NC}"
  sudo sed -i "s~\# listen \[::\]:8443 ssl ipv6only=on;~location /api { \n\
        proxy_pass http://127.0.0.1:8081; \n\
        proxy_http_version 1.1; \n\
        proxy_set_header Host \$host:8443; \n\
        proxy_set_header X-Forwarded-For \$remote_addr; \n\
        proxy_set_header X-Forwarded-Proto \$scheme; \n\
}~g" /etc/nginx/sites-enabled/ots_https
  sudo systemctl restart nginx
fi

# Check if MQTT is enabled in RabbitMQ
sudo ls /etc/rabbitmq/rabbitmq.conf &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "${GREEN}Enabling MQTT support in RabbitMQ${NC}"
  sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/rabbitmq.conf -O /etc/rabbitmq/rabbitmq.conf
  # The following lines all end in "; \" because rabbitmq-plugins stops the script, even when it's successful
  # Adding "; \" is a janky fix to make the rest of the script work
  sudo rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_auth_backend_http ; \
  sudo systemctl restart rabbitmq-server ; \
fi ; \
rm -fr "$INSTALLER_DIR" ; \
echo "${GREEN}The update is complete!${NC}"