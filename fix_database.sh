#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

source "$HOME"/.opentakserver_venv/bin/activate

sudo systemctl stop opentakserver eud_handler eud_handler_ssl cot_parser

sudo su postgres -c "dropdb 'ots'"
sudo su postgres -c "psql -c 'create database ots;'"
sudo su postgres -c "psql -c 'GRANT ALL PRIVILEGES  ON DATABASE \"ots\" TO ots;'"
sudo su postgres -c "psql -d ots -c 'GRANT ALL ON SCHEMA public TO ots;'"

cp ~/ots/ots.db $INSTALLER_DIR
chmod a+r ${INSTALLER_DIR}/ots.db

cd "$HOME"/.opentakserver_venv/lib/python3.*/site-packages/opentakserver
flask db upgrade

POSTGRESQL_PASSWORD=$(cat ~/ots/config.yml | awk 'match($0, /\/\/.*:(.*)@/, a) {print a[1]}')
echo "${GREEN}Postgres password is ${YELLOW}${POSTGRESQL_PASSWORD}${NC}"

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