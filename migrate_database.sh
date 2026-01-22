#!/bin/bash

# Load .env file if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set default values for environment variables
OTS_GITHUB_USER="${OTS_GITHUB_USER:-brian7704}"

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/${OTS_GITHUB_USER}/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

. /etc/os-release

if [ "$NAME" != "Ubuntu" ]
then
  read -p "${YELLOW} This installer is for Ubuntu but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
  rm -fr $INSTALLER_DIR
fi

source "$HOME"/.opentakserver_venv/bin/activate

echo "${GREEN}Installing PostGIS...${NC}"
sudo NEEDRESTART_MODE=a apt install postgresql-postgis pgloader -y
pip3 install psycopg

# Check of Postgres user ots exists
OTS_USER_EXISTS=$(sudo su postgres -c "psql -tXAc \"SELECT 1 from pg_roles WHERE rolname='ots'\"")
if [ "$OTS_USER_EXISTS" != 1 ];
then
  echo "${GREEN}Creating ots database and user in PostgreSQL${NC}"
  POSTGRESQL_PASSWORD=$(tr -dc 'A-Za-z0-9!?%=' < /dev/urandom | head -c 20)
  sudo su postgres -c "psql -c \"create role ots with login password '${POSTGRESQL_PASSWORD}';\""
  sudo su postgres -c "psql -c 'create database ots;'"
  sudo su postgres -c "psql -c 'GRANT ALL PRIVILEGES  ON DATABASE \"ots\" TO ots;'"
  sudo su postgres -c "psql -d ots -c 'GRANT ALL ON SCHEMA public TO ots;'"

  cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
  # This command won't overwrite config.yml if it exists
  flask ots generate-config
  cd "$INSTALLER_DIR"

  sed -i "s/SQLALCHEMY_DATABASE_URI/\#SQLALCHEMY_DATABASE_URI/g" ~/ots/config.yml
  echo "SQLALCHEMY_DATABASE_URI: postgresql+psycopg://ots:${POSTGRESQL_PASSWORD}@127.0.0.1/ots" >> ~/ots/config.yml
else
  POSTGRESQL_PASSWORD=$(cat ~/ots/config.yml | awk 'match($0, /\/\/.*:(.*)@/, a) {print a[1]}')
fi

cp ~/ots/ots.db $INSTALLER_DIR
chmod a+r ${INSTALLER_DIR}/ots.db

# Use Flask-Migrate to make a new blank DB
cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
flask db upgrade

# Use pgloader to import the old data
tee ${INSTALLER_DIR}/db.load >/dev/null << EOF
load database
     from sqlite:///${INSTALLER_DIR}/ots.db
     into pgsql://ots:${POSTGRESQL_PASSWORD}@127.0.0.1/ots

 with include drop, create tables, create indexes, reset sequences, quote identifiers, data only
 excluding table names like 'alembic_version';
EOF

sudo su postgres -c "pgloader ${INSTALLER_DIR}/db.load"

sudo systemctl restart opentakserver eud_handler eud_handler_ssl cot_parser

deactivate

rm -fr $INSTALLER_DIR
