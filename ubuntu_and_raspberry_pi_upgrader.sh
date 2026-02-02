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
BRANCH=""

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
  read -p "${YELLOW} This updater is for Ubuntu and Raspberry Pi OS but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
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
  GIT_URL=git+https://github.com/brian7704/OpenTAKServer.git
  read -p "${GREEN}What branch would you like to install from? [master]${NC} " BRANCH < /dev/tty
  if [ -n "$BRANCH" ]; then
    echo "Installing from the ${BRANCH} branch..."
    GIT_URL="${GIT_URL}@${BRANCH}"
  else
    echo "${GREEN}Installing OpenTAKServer from master branch...${NC}"
  fi
  ~/.opentakserver_venv/bin/pip install "$GIT_URL"

  echo "${GREEN}Backing up DB...${NC}"
  sudo su postgres -c "pg_dump ots" > ~/ots/ots_backup.db
  echo "${GREEN}Upgrading DB...${NC}"
  cd ~/.opentakserver_venv/lib/python3.1*/site-packages/opentakserver
  ~/.opentakserver_venv/bin/flask db upgrade
  cd $INSTALLER_DIR

  echo "${GREEN}Upgrading UI...${NC}"
  rm -fr /var/www/html/opentakserver/*
  cd /var/www/html/opentakserver/
  ~/.opentakserver_venv/bin/lastversion --pre --assets extract brian7704/OpenTAKServer-UI

  echo "${GREEN}Restarting the OpenTAKServer service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart opentakserver

elif [[ "$LATEST_MAJOR" -ne "$INSTALLED_MAJOR" || "$LATEST_MINOR" -ne "$INSTALLED_MINOR" || "$LATEST_PATCH" -ne "$INSTALLED_PATCH" ]]; then
  echo "${GREEN}Upgrading OpenTAKServer to version ${LATEST_OTS_VERSION}${NC}"
  ~/.opentakserver_venv/bin/pip install opentakserver -U

  if [ "$(grep postgresql ~/ots/config.yml)" -ne 0 ]; then
      echo "${GREEN}Migrating from SQLite to PostgreSQL...${NC}"
      sudo apt install postgresql-postgis pgloader

      # Check of Postgres user ots exists
      OTS_USER_EXISTS=$(sudo su postgres -c "psql -tXAc \"SELECT 1 from pg_roles WHERE rolname='ots'\"")

      if [ "$OTS_USER_EXISTS" != 1 ];
      then
        echo "${GREEN}Creating ots database and user in PostgreSQL${NC}"
        POSTGRESQL_PASSWORD=$(tr -dc 'A-Za-z0-9!?%=' < /dev/urandom | head -c 20)
        sudo su postgres -c "psql -c 'create database ots;'"
        sudo su postgres -c "psql -c \"create role ots with login password '${POSTGRESQL_PASSWORD}';\""
        sudo su postgres -c "psql -c 'GRANT ALL PRIVILEGES  ON DATABASE \"ots\" TO ots;'"
        sudo su postgres -c "psql -d ots -c 'GRANT ALL ON SCHEMA public TO ots;'"
      else
        POSTGRESQL_PASSWORD=$(cat ~/ots/config.yml | awk 'match($0, /\/\/.*:(.*)@/, a) {print a[1]}')
      fi

      sed -i "s/SQLALCHEMY_DATABASE_URI/\#SQLALCHEMY_DATABASE_URI/g" ~/ots/config.yml
      echo "SQLALCHEMY_DATABASE_URI: postgresql+psycopg://ots:${POSTGRESQL_PASSWORD}@127.0.0.1/ots" >> ~/ots/config.yml

      cd ~/.opentakserver_venv/lib/python3.1*/site-packages/opentakserver
      ~/.opentakserver_venv/bin/flask db upgrade

      # Use pgloader to import the old data
      tee ${INSTALLER_DIR}/db.load >/dev/null << EOF
load database
     from sqlite:///${HOME}/ots/ots.db
     into pgsql://ots:${POSTGRESQL_PASSWORD}@127.0.0.1/ots

 with include drop, create tables, create indexes, reset sequences, quote identifiers, data only
 excluding table names like 'alembic_version';
EOF

      sudo su postgres -c "pgloader ${INSTALLER_DIR}/db.load"
  else
    echo "${GREEN}Backing up DB...${NC}"
    sudo su postgres -c "pg_dump ots" > ~/ots/ots_backup.db
    echo "${GREEN}Upgrading DB...${NC}"
    cd ~/.opentakserver_venv/lib/python3.1*/site-packages/opentakserver
    ~/.opentakserver_venv/bin/flask db upgrade
    cd $INSTALLER_DIR
  fi

  echo "${GREEN}Upgrading UI...${NC}"
  rm -fr /var/www/html/opentakserver/*
  cd /var/www/html/opentakserver/
  ~/.opentakserver_venv/bin/lastversion --assets extract brian7704/OpenTAKServer-UI

  echo "${GREEN}Restarting the OpenTAKServer service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart opentakserver
fi

if [ ! -f /etc/systemd/system/cot_parser.service ]; then
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

sudo systemctl daemon-reload
sudo systemctl enable cot_parser
sudo systemctl start cot_parser
fi

if [ ! -f /etc/systemd/system/eud_handler.service ]; then
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

sudo systemctl daemon-reload
sudo systemctl enable eud_handler
sudo systemctl start eud_handler
fi

if [ ! -f /etc/systemd/system/eud_handler_ssl.service ]; then
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
sudo systemctl enable eud_handler_ssl
sudo systemctl start eud_handler_ssl
fi

# Add "Requires=eud_handler eud_handler_ssl cot_parser" to the systemd unit file
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

sudo systemctl daemon-reload

# Upgrade MediaMTX
MEDIAMTX_VERSION=$(~/ots/mediamtx/mediamtx --version)
MEDIAMTX_VERSION="${MEDIAMTX_VERSION//v}"
#NEWEST_MEDIAMTX_VERSION=$(~/.opentakserver_venv/bin/lastversion bluenviron/mediamtx)
NEWEST_MEDIAMTX_VERSION="1.13.0"

if [ "$MEDIAMTX_VERSION" != "$NEWEST_MEDIAMTX_VERSION" ]; then
  echo "${GREEN}Upgrading MediaMTX from version ${MEDIAMTX_VERSION} to ${NEWEST_MEDIAMTX_VERSION}...${NC}"
  cd ~/ots/mediamtx
  mv mediamtx.yml mediamtx.yml.bak
  mv mediamtx mediamtx_"$MEDIAMTX_VERSION"
  rm mediamtx*.tar.gz

  ARCH=$(uname -m)
  KERNEL_BITS=$(getconf LONG_BIT)
  if [ "$ARCH" == "x86_64" ]; then
    ~/.opentakserver_venv/bin/lastversion --filter '~*linux_amd64' --assets download bluenviron/mediamtx --only 1.13.0
  elif [ "$KERNEL_BITS" == 32 ]; then
    ~/.opentakserver_venv/bin/lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx --only 1.13.0
  elif [ "$KERNEL_BITS" == 64 ]; then
    ~/.opentakserver_venv/bin/lastversion --filter '~*linux_arm64v8' --assets download bluenviron/mediamtx --only 1.13.0
  fi

  tar -xf ./*.tar.gz
  cp mediamtx.yml.bak mediamtx.yml
  echo "${GREEN}Restarting the MediaMTX service. Please enter your sudo password if prompted${NC}"
  sudo systemctl restart mediamtx
  cd "$INSTALLER_DIR"
fi

# Make the server's public key if it doesn't exist
if [ ! -f ~/ots/ca/certs/opentakserver/opentakserver.pub ]; then
  echo "${GREEN}Generating server's public key...${NC}"
  openssl x509 -pubkey -in ~/ots/ca/certs/opentakserver/opentakserver.pem -out ~/ots/ca/certs/opentakserver/opentakserver.pub
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