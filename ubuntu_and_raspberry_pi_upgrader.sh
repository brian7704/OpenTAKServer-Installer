#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

. /etc/os-release

if [ "$NAME" != "Ubuntu" ] && [ "$NAME" != "Raspbian GNU/Linux" ] && [ "$NAME" != "Debian GNU/Linux" ]
then
  read -p "${YELLOW} This updater is for Ubuntu but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
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

if [[ "$LATEST_MAJOR" -ne "$INSTALLED_MAJOR" || "$LATEST_MINOR" -ne "$INSTALLED_MINOR" || "$LATEST_PATCH" -ne "$INSTALLED_PATCH" ]]; then
  echo "${GREEN}Upgrading OpenTAKServer to version ${LATEST_OTS_VERSION}${NC}"
  ~/.opentakserver_venv/bin/pip install opentakserver -U

  echo "${GREEN}Upgrading database schema...${NC}"
  ~/.opentakserver_venv/bin/opentakserver --upgrade-db

  echo "${GREEN}Upgrading UI...${NC}"
  rm -fr /var/www/html/opentakserver/*
  cd /var/www/html/opentakserver/
  ~/.opentakserver_venv/bin/lastversion --assets extract brian7704/OpenTAKServer-UI

  echo "${GREEN}Restarting the OpenTAKServer service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart opentakserver
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

# Check if MQTT is enabled in RabbitMQ
sudo ls /etc/rabbitmq/rabbitmq.conf &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "${GREEN}Enabling MQTT support in RabbitMQ${NC}"
  sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/rabbitmq.conf -O /etc/rabbitmq/rabbitmq.conf
  sudo rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_auth_backend_http
  sudo systemctl restart rabbitmq-server
fi

rm -fr "$INSTALLER_DIR"
echo "${GREEN}The update is complete!${NC}"