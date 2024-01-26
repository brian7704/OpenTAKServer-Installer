#!/bin/bash

. /etc/os-release
. colors.sh

if [ "$NAME" != "Ubuntu" ]
then
  read -p "${YELLOW} This installer is for Ubuntu but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
fi

USERNAME=$(whoami)
INSTALLER_DIR=$(pwd)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  exit 1
fi

mkdir -p ~/ots
cp iconsets.sqlite ~/ots/ots.db

echo "${GREEN}Installing packages via apt. You may be prompted for your sudo password...${NC}"


sudo apt update && sudo apt upgrade -y
sudo apt install curl python3 python3-pip rabbitmq-server git openssl nginx -y
pip3 install poetry
sudo git clone https://github.com/brian7704/OpenTAKServer.git /opt/OpenTAKServer
sudo chown "$USERNAME":"$USERNAME" /opt/OpenTAKServer -R
poetry config virtualenvs.in-project true
cd /opt/OpenTAKServer && poetry update && poetry install

cd "$INSTALLER_DIR" || exit

IP_ADDRESSES=()

PUBLIC_IP=$(curl https://ipinfo.io/ip) || ""
IP_ADDRESSES+=("$PUBLIC_IP")
echo "${GREEN}Got public IP: $PUBLIC_IP${NC}"

export IFS=" "
for ip in $(hostname --all-ip-addresses); do
  IP_ADDRESSES+=("$ip")
done

IP_ADDRESSES+=("Other IP or domain")
SERVER_ADDRESS=""

PS3="${GREEN}Which address will users connect to? ${NC}"
while [ "$SERVER_ADDRESS" == "" ]; do
  select ip in "${IP_ADDRESSES[@]}"
  do
    case $ip in
      "Other IP or domain")
        read -p "Please enter the domain or IP: " SERVER_ADDRESS
        break
        ;;
      "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$")
        SERVER_ADDRESS=$ip
        echo "got regex shit"
        break
        ;;
      *)
        echo "Invalid option";;
      esac
    echo "$ip"
    SERVER_ADDRESS=$ip
    break
  done
done

echo "${GREEN}Creating certificate authority...${NC}}"

mkdir -p ~/ots/ca
cp "$INSTALLER_DIR"/config.cfg ~/ots/ca/ca_config.cfg

bash ./makeRootCa.sh --ca-name OpenTAKServer-CA
bash ./makeCert.sh server "$SERVER_ADDRESS"

cd "$INSTALLER_DIR" || exit

echo "${GREEN}Installing mediamtx...${NC}"
mkdir -p ~/ots/mediamtx/recordings

MTX_TOKEN=$(python3 -c "import secrets; print(secrets.SystemRandom().getrandbits(128))")

cp mediamtx/linux_amd64/mediamtx ~/ots/mediamtx
chmod +x ~/ots/mediamtx/mediamtx
cp mediamtx/mediamtx.yml ~/ots/mediamtx

sudo sed -i "s/MTX_TOKEN/${MTX_TOKEN}/g" ~/ots/mediamtx/mediamtx.yml

sudo tee /etc/systemd/system/mediamtx.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
ExecStart=$HOME/ots/mediamtx/mediamtx $HOME/ots/mediamtx/mediamtx.yml
[Install]
WantedBy=multi-user.target
EOF

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.pem~g" ~/ots/mediamtx/mediamtx.yml
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.nopass.key~g" ~ots/mediamtx/mediamtx.yml
sudo sed -i "s~OTS_FOLDER~${HOME}/ots~g" ~ots/mediamtx/mediamtx.yml

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

echo "${GREEN}Setting up nginx...${NC}"
sudo rm -f /etc/nginx/sites-enabled/*
sudo cp ots_proxy /etc/nginx/sites-available/

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.pem~g" /etc/nginx/sites-available/ots_proxy
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.nopass.key~g" /etc/nginx/sites-available/ots_proxy
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_proxy

sudo ln -s /etc/nginx/sites-available/ots_proxy /etc/nginx/sites-enabled/ots_proxy

sudo systemctl enable nginx
sudo systemctl restart nginx

sudo tee /etc/systemd/system/opentakserver.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
User=$(whoami)
WorkingDirectory=/opt/OpenTAKServer
ExecStart=/usr/local/bin/poetry run python /opt/OpenTAKServer/opentakserver/app.py
[Install]
WantedBy=multi-user.target
EOF

echo "secret_key = '$(python3 -c 'import secrets; print(secrets.token_hex())')'" > /opt/OpenTAKServer/opentakserver/secret_key.py
echo "node_id = '$(python3 -c "import random; import string; print(''.join(random.choices(string.ascii_lowercase + string.digits, k=64)))")'" >> /opt/OpenTAKServer/opentakserver/secret_key.py
echo "security_password_salt = '$(python3 -c "import secrets; print(secrets.SystemRandom().getrandbits(128))")'" >> /opt/OpenTAKServer/opentakserver/secret_key.py
echo "mediamtx_token = '${MTX_TOKEN}'" >> /opt/OpenTAKServer/opentakserver/secret_key.py
echo "server_address = '${SERVER_ADDRESS}'" >> /opt/OpenTAKServer/opentakserver/secret_key.py

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
systemctl start opentakserver

echo "${GREEN}Setup is complete and OpenTAKServer is running. ${NC}"