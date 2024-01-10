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

echo "${GREEN}Installing packages via apt. You may be prompted for your sudo password...${NC}"


sudo apt update && sudo apt upgrade -y
sudo apt install curl python3 python3-pip rabbitmq-server git openssl nginx -y
pip3 install poetry
sudo git clone https://github.com/brian7704/OpenTAKServer.git /opt/OpenTAKServer
sudo chown "$USERNAME":"$USERNAME" /opt/OpenTAKServer -R
poetry config virtualenvs.in-project true
cd /opt/OpenTAKServer && poetry update && poetry install
cd opentakserver && cp secret_key.example.py secret_key.py

cd "$INSTALLER_DIR" || exit

echo "${GREEN}Installing mediamtx...${NC}"
sudo mkdir -p /usr/local/bin/
sudo mkdir -p /usr/local/etc/

sudo cp mediamtx/linux_amd64/mediamtx /usr/local/bin/
sudo chmod a+x /usr/local/bin/mediamtx
sudo cp mediamtx/mediamtx.yml /usr/local/etc/
sudo chmod a+rw /usr/local/etc/mediamtx.yml

sudo tee /etc/systemd/system/mediamtx.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
ExecStart=/usr/local/bin/mediamtx /usr/local/etc/mediamtx.yml
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

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

bash ./makeRootCa.sh --ca-name OpenTAKServer-CA
bash ./makeCert.sh server "$SERVER_ADDRESS"

cd "$INSTALLER_DIR" || exit

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
ExecStart=cd /opt/OpenTAKServer && poetry run python opentakserver/app.py
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
sudo systemctl start opentakserver

echo "${GREEN}Setup is complete. You can start OpenTAKServer by running this command 'cd /opt/OpenTAKServer && poetry run python opentakserver/app.py${NC}"