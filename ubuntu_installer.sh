#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

. /etc/os-release

if [ "$NAME" != "Ubuntu" ]
then
  read -p "${YELLOW} This installer is for Ubuntu but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
  rm -fr $INSTALLER_DIR
fi

USERNAME=$(whoami)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  rm -fr $INSTALLER_DIR
  exit 1
fi

mkdir -p ~/ots

echo "${GREEN}Installing packages via apt. You may be prompted for your sudo password...${NC}"

sudo apt update && sudo NEEDRESTART_MODE=a apt upgrade -y
sudo NEEDRESTART_MODE=a apt install curl python3 python3-pip python3-venv rabbitmq-server openssl nginx ffmpeg libnginx-mod-stream python3-dev postgresql-postgis pgloader -y

echo "${GREEN} Installing OpenTAKServer from PyPI...${NC}"
python3 -m venv --system-site-packages ~/.opentakserver_venv
source "$HOME"/.opentakserver_venv/bin/activate
python3 -m pip install --upgrade pip setuptools wheel
pip3 install opentakserver

cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
# This command won't overwrite config.yml if it exists
flask ots generate-config

echo "${GREEN}OpenTAKServer Installed!${NC}"

echo "${GREEN}Initializing Database...${NC}"

# Check if the ots user and DB exist
OTS_DB_EXISTS=$(sudo su postgres -c "psql -XtAc \"SELECT 1 FROM pg_database WHERE datname='ots'\"")
OTS_USER_EXISTS=$(sudo su postgres -c "psql -tXAc \"SELECT 1 from pg_roles WHERE rolname='ots'\"")

if [ "$OTS_USER_EXISTS" != 1 ];
then
  echo "${GREEN}Creating ots user in PostgreSQL${NC}"
  POSTGRESQL_PASSWORD=$(tr -dc 'A-Za-z0-9!?%=' < /dev/urandom | head -c 20)
  sudo su postgres -c "psql -c \"create role ots with login password '${POSTGRESQL_PASSWORD}';\""
  sed -i "s/POSTGRESQL_PASSWORD/${POSTGRESQL_PASSWORD}/g" ~/ots/config.yml
else
  read -p "${GREEN}PostgreSQL user 'ots' already exists. Please provide its password: ${NC}" POSTGRESQL_PASSWORD < /dev/tty
  sed -i "s/POSTGRESQL_PASSWORD/${POSTGRESQL_PASSWORD}/g" ~/ots/config.yml
fi

if [ "$OTS_DB_EXISTS" != 1 ];
then
  echo "${GREEN}Creating ots database${NC}"
  sudo su postgres -c "psql -c 'create database ots;'"
fi

sudo su postgres -c "psql -c 'GRANT ALL PRIVILEGES  ON DATABASE \"ots\" TO ots;'"
sudo su postgres -c "psql -d ots -c 'GRANT ALL ON SCHEMA public TO ots;'"

cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
flask db upgrade
cd "$INSTALLER_DIR"
echo "${GREEN}Finished initializing database!${NC}"

INSTALL_ZEROTIER=""
while :
do
  read -p "${GREEN}Would you like to install ZeroTier?${NC} [y/n]" INSTALL_ZEROTIER < /dev/tty
  if [[ "$INSTALL_ZEROTIER" =~ [yY]|[yY][eE][sS] ]]; then
    INSTALL_ZEROTIER=1
    break
  elif [[ "$INSTALL_ZEROTIER" =~ [nN]|[nN][oO] ]]; then
    INSTALL_ZEROTIER=0
    break
  else
    echo "${RED}Invalid input${NC}"
  fi
done

if [ "$INSTALL_ZEROTIER" == 1 ];
then
  read -p "${GREEN}What is your ZeroTier network ID? ${NC}" ZT_NETWORK_ID < /dev/tty
  curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --import && \
  curl -s 'https://install.zerotier.com/' -o /tmp/zerotier_installer.sh
  if gpg --verify /tmp/zerotier_installer.sh; then
    sudo NEEDRESTART_MODE=a bash /tmp/zerotier_installer.sh
  fi

  while :
  do
      ZT_JOIN=$(sudo zerotier-cli join "$ZT_NETWORK_ID")
      echo "$ZT_JOIN"
      if [ "$ZT_JOIN" != "200 join OK" ]; then
        echo "${RED}Failed to join network ${ZT_NETWORK_ID}."
        read -p "${GREEN}Please re-enter your ZeroTier network ID: ${NC}" ZT_NETWORK_ID < /dev/tty
      else
        break
      fi
  done
  read -p "${GREEN}ZeroTier has been installed. Please log into your ZeroTier admin account and authorize this server and then press enter to continue.${NC}" < /dev/tty
fi

INSTALL_MUMBLE=""
while :
do
  read -p "${GREEN}Would you like to install Mumble Server?${NC} [y/n]" INSTALL_MUMBLE < /dev/tty
  if [[ "$INSTALL_MUMBLE" =~ [yY]|[yY][eE][sS] ]]; then
    INSTALL_MUMBLE=1
    break
  elif [[ "$INSTALL_MUMBLE" =~ [nN]|[nN][oO] ]]; then
    INSTALL_MUMBLE=0
    break
  else
    echo "${RED}Invalid input${NC}"
  fi
done

if [ "$INSTALL_MUMBLE" == 1 ]; then
  sudo NEEDRESTART_MODE=a apt install mumble-server zeroc-ice-all-runtime zeroc-ice-all-dev -y

  sudo sed -i '/ice="tcp -h 127.0.0.1 -p 6502"/s/^;//g' /etc/mumble/mumble-server.ini
  sudo sed -i 's/icesecretwrite/;icesecretwrite/g' /etc/mumble/mumble-server.ini

  sudo systemctl restart mumble-server

  PASSWORD_LOG=$(sudo grep -m 1 SuperUser /var/log/syslog)
  PASSWORD=($PASSWORD_LOG)
  read -p "${GREEN}Mumble Server is now installed. The SuperUser password is ${YELLOW}${PASSWORD[-1]}${GREEN}. Press enter to continue.${NC}" < /dev/tty
fi

echo "${GREEN}Creating certificate authority...${NC}"

mkdir -p ~/ots/ca

# Generate CA
cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
flask ots create-ca

echo "${GREEN}Installing mediamtx...${NC}"
mkdir -p ~/ots/mediamtx/recordings

cd ~/ots/mediamtx

# Install youtube streaming support 
pip3 install yt-dlp

ARCH=$(uname -m)
KERNEL_BITS=$(getconf LONG_BIT)
if [ "$ARCH" == "x86_64" ]; then
  lastversion --filter '~*linux_amd64' --assets download bluenviron/mediamtx --only 1.13.0
elif [ "$KERNEL_BITS" == 32 ]; then
  lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx --only 1.13.0
elif [ "$KERNEL_BITS" == 64 ]; then
  lastversion --filter '~*linux_arm64' --assets download bluenviron/mediamtx --only 1.13.0
fi

tar -xf ./*.tar.gz
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/mediamtx.yml -qO ~/ots/mediamtx/mediamtx.yml

sudo tee /etc/systemd/system/mediamtx.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
User=$(whoami)
ExecStart=$HOME/ots/mediamtx/mediamtx $HOME/ots/mediamtx/mediamtx.yml
[Install]
WantedBy=multi-user.target
EOF

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" ~/ots/mediamtx/mediamtx.yml
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" ~/ots/mediamtx/mediamtx.yml
sudo sed -i "s~OTS_FOLDER~${HOME}/ots~g" ~/ots/mediamtx/mediamtx.yml

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

sudo grep "stream {" /etc/nginx/nginx.conf &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "${GREEN}Setting up nginx...${NC}"
  sudo echo "
stream {
        include /etc/nginx/streams-enabled/*;
}" | sudo tee -a /etc/nginx/nginx.conf
fi

sudo rm -f /etc/nginx/sites-enabled/*
sudo mkdir -p /etc/nginx/streams-available
sudo mkdir -p /etc/nginx/streams-enabled

sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/nginx_configs/rabbitmq -qO /etc/nginx/streams-available/rabbitmq
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/mediamtx -qO /etc/nginx/streams-available/mediamtx
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_certificate_enrollment -qO /etc/nginx/sites-available/ots_certificate_enrollment
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_http -qO /etc/nginx/sites-available/ots_http
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_https -qO /etc/nginx/sites-available/ots_https

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/sites-available/ots_certificate_enrollment
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/streams-available/rabbitmq
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/streams-available/mediamtx
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/sites-available/ots_certificate_enrollment
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/streams-available/rabbitmq
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/streams-available/mediamtx
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_certificate_enrollment

sudo ln -s /etc/nginx/sites-available/ots_* /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/streams-available/rabbitmq /etc/nginx/streams-enabled/
sudo ln -s /etc/nginx/streams-available/mediamtx /etc/nginx/streams-enabled/

sudo systemctl enable nginx
sudo systemctl restart nginx

sudo mkdir -p /var/www/html/opentakserver
sudo chmod a+rw /var/www/html/opentakserver
cd /var/www/html/opentakserver
lastversion --assets extract brian7704/OpenTAKServer-UI

sudo tee /etc/systemd/system/opentakserver.service >/dev/null << EOF
[Unit]
Wants=network.target rabbitmq-server.service
After=network.target rabbitmq-server.service
Requires=eud_handler eud_handler_ssl cot_parser
[Service]
User=$(whoami)
WorkingDirectory=${HOME}/ots
ExecStart=${HOME}/.opentakserver_venv/bin/opentakserver
Restart=on-failure
RestartSec=5s
StandardOutput=append:${HOME}/ots/logs/opentakserver.log
StandardError=append:${HOME}/ots/logs/opentakserver.log
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/cot_parser.service >/dev/null << EOF
[Unit]
Wants=network.target rabbitmq-server.service
After=network.target rabbitmq-server.service
PartOf=opentakserver.service
[Service]
User=$(whoami)
WorkingDirectory=${HOME}/ots
ExecStart=${HOME}/.opentakserver_venv/bin/cot_parser
Restart=on-failure
RestartSec=5s
StandardOutput=append:${HOME}/ots/logs/opentakserver.log
StandardError=append:${HOME}/ots/logs/opentakserver.log
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/eud_handler.service >/dev/null << EOF
[Unit]
Wants=network.target rabbitmq-server.service
After=network.target rabbitmq-server.service
PartOf=opentakserver.service
[Service]
User=$(whoami)
WorkingDirectory=${HOME}/ots
ExecStart=${HOME}/.opentakserver_venv/bin/eud_handler
Restart=on-failure
RestartSec=5s
StandardOutput=append:${HOME}/ots/logs/opentakserver.log
StandardError=append:${HOME}/ots/logs/opentakserver.log
[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/eud_handler_ssl.service >/dev/null << EOF
[Unit]
Wants=network.target rabbitmq-server.service
After=network.target rabbitmq-server.service
PartOf=opentakserver.service
[Service]
User=$(whoami)
WorkingDirectory=${HOME}/ots
ExecStart=${HOME}/.opentakserver_venv/bin/eud_handler --ssl
Restart=on-failure
RestartSec=5s
StandardOutput=append:${HOME}/ots/logs/opentakserver.log
StandardError=append:${HOME}/ots/logs/opentakserver.log
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
sudo systemctl start opentakserver

sudo systemctl enable cot_parser
sudo systemctl start cot_parser

sudo systemctl enable eud_handler
sudo systemctl start eud_handler

sudo systemctl enable eud_handler_ssl
sudo systemctl start eud_handler_ssl

echo "${GREEN}Configuring RabbitMQ...${NC}"
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/rabbitmq.conf -qO /etc/rabbitmq/rabbitmq.conf

# On Ubuntu 25.04 and up the PLUGINS_DIR variable needs to be set in order to enable plugins
IFS=" "
RABBITMQ_VERSION="$(sudo rabbitmqadmin --version)"
read -ra VERSION_ARRAY <<< "$RABBITMQ_VERSION"
VERSION=${VERSION_ARRAY[1]}
sudo echo "PLUGINS_DIR=\"/usr/lib/rabbitmq/plugins:/usr/lib/rabbitmq/lib/rabbitmq_server-${VERSION}/plugins\"" | sudo tee -a /etc/rabbitmq/rabbitmq-env.conf
sudo systemctl restart rabbitmq-server

# The following lines all end in "; \" because rabbitmq-plugins stops the script, even when it's successful
# Adding "; \" is a janky fix to make the rest of the script work
sudo rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_auth_backend_http ; \
sudo systemctl restart rabbitmq-server ; \
echo "${GREEN}Finished configuring RabbitMQ${NC}" ; \
rm -fr $INSTALLER_DIR ; \
deactivate ; \
echo "${GREEN}Setup is complete and OpenTAKServer is running. You can access the Web UI at https://$(hostname -I)${NC}"
