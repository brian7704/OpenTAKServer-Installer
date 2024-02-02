#!/bin/bash

. /etc/os-release
. colors.sh

IP_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"

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

sudo apt update && sudo NEEDRESTART_MODE=a apt upgrade -y
sudo NEEDRESTART_MODE=a apt install curl python3 python3-pip rabbitmq-server git openssl nginx ffmpeg -y
sudo pip3 install poetry pyotp

if [ -d "/opt/OpenTAKServer" ]; then
  cd /opt/OpenTAKServer || exit
  sudo git pull
else
  sudo git clone https://github.com/brian7704/OpenTAKServer.git /opt/OpenTAKServer
  sudo chown "$USERNAME":"$USERNAME" /opt/OpenTAKServer -R
fi

poetry config virtualenvs.in-project true
poetry config virtualenvs.options.system-site-packages true
cd /opt/OpenTAKServer && poetry update && poetry install

cd "$INSTALLER_DIR" || exit

INSTALL_ZEROTIER=""
while :
do
  read -p "${GREEN}Would you like to install ZeroTier?${NC} [y/n]" INSTALL_ZEROTIER
  if [[ "$INSTALL_ZEROTIER" =~ [yY]|[yY][eE][sS] ]]; then
    INSTALL_ZEROTIER=1
    break
  elif [[ "$INSTALL_ZEROTIER" =~ [nN]|[nN][oO] ]]; then
    INSTALL_ZEROTIER=0
    break
  else
    echo "${RED}Invalid input"
  fi
done

if [ "$INSTALL_ZEROTIER" == 1 ];
then
  read -p "${GREEN}What is your ZeroTier network ID? ${NC}" ZT_NETWORK_ID
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
        read -p "${GREEN}Please re-enter your ZeroTier network ID: ${NC}" ZT_NETWORK_ID
      else
        break
      fi
  done
  read -p "${GREEN}ZeroTier has been installed. Please log into your ZeroTier admin account and authorize this server and then press enter to continue.${NC}"
fi

INSTALL_MUMBLE=""
while :
do
  read -p "${GREEN}Would you like to install Mumble Server?${NC} [y/n]" INSTALL_MUMBLE
  if [[ "$INSTALL_MUMBLE" =~ [yY]|[yY][eE][sS] ]]; then
    INSTALL_MUMBLE=1
    break
  elif [[ "$INSTALL_MUMBLE" =~ [nN]|[nN][oO] ]]; then
    INSTALL_MUMBLE=0
    sed -i 's/OTS_ENABLE_MUMBLE_AUTHENTICATION = True/OTS_ENABLE_MUMBLE_AUTHENTICATION = False/g' /opt/OpenTAKServer/opentakserver/config.py
    break
  else
    echo "${RED}Invalid input"
  fi
done

if [ "$INSTALL_MUMBLE" == 1 ]; then
  sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv B6391CB2CFBA643D
  sudo apt-add-repository -s "deb http://zeroc.com/download/Ice/3.7/ubuntu`lsb_release -rs` stable main"

  sudo add-apt-repository ppa:mumble/release
  sudo apt update

  sudo NEEDRESTART_MODE=a apt install mumble-server zeroc-ice-all-runtime zeroc-ice-all-dev -y

  sudo sed -i '/ice="tcp -h 127.0.0.1 -p 6502"/s/^#//g' /etc/mumble-server.ini
  sudo service mumble-server restart

  PASSWORD_LOG=$(sudo grep -m 1 SuperUser /var/log/mumble-server/mumble-server.log)
  PASSWORD=($PASSWORD_LOG)
  read -p "${GREEN}Mumble Server is now installed. The SuperUser password is ${YELLOW}${PASSWORD[-1]}${GREEN}. Press enter to continue.${NC}"
fi

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
    if [ "$ip" == "Other IP or domain" ]; then
        read -p "Please enter the domain or IP: " SERVER_ADDRESS
        break
    elif [[ "$ip" =~ $IP_REGEX ]]; then
        SERVER_ADDRESS=$ip
        break
    else
        echo "${RED}Invalid option ${ip}${NC}";
    fi
    echo "SERVER_ADDRESS = ${SERVER_ADDRESS}"
  done
done

LETS_ENCRYPT=""

if ! [[ $SERVER_ADDRESS =~ $IP_REGEX ]]
then
  while :
do
  read -p "${GREEN}Looks like you're using a domain for your server address. Would you like to get a free SSL certificate from Let's Encrypt?${NC} [y/n]" ENABLE_EMAIL
  if [[ "$LETS_ENCRYPT" =~ [yY]|[yY][eE][sS] ]]; then
    LETS_ENCRYPT=1
    break
  elif [[ "$LETS_ENCRYPT" =~ [nN]|[nN][oO] ]]; then
    LETS_ENCRYPT=0
    break
  else
    echo "${RED}Invalid input"
  fi
done
fi

if [ "$LETS_ENCRYPT" == 1 ];
then
  read -p "${YELLOW}Attempting to get a Let's Encrypt certificate for {$SERVER_ADDRESS}. Please make sure that ports 80 and 443 are forwarded from your firewall to this server. See https://certbot.eff.org/ for more details. Press enter to continue.${NC}"
  sudo NEEDRESTART_MODE=a apt install certbot -y
  CERTBOT_EXIT_CODE=$(sudo certbot certonly --nginx -d "$SERVER_ADDRESS")
  if [ "$CERTBOT_EXIT_CODE" == 0 ];
  then
    read -p "${GREEN}Successfully obtained a certificate for ${SERVER_ADDRESS}. Press enter to continue.${NC}"
  else
    read -p "${RED}Failed to get a Let's Encrypt certificate. The installer will proceed with a self signed certificate. Press enter to continue."
    LETS_ENCRYPT=0
  fi
fi

ENABLE_EMAIL=""
while :
do
  read -p "${GREEN}Require users to register with an email address?${NC} [y/n]" ENABLE_EMAIL
  if [[ "$ENABLE_EMAIL" =~ [yY]|[yY][eE][sS] ]]; then
    ENABLE_EMAIL=1
    break
  elif [[ "$ENABLE_EMAIL" =~ [nN]|[nN][oO] ]]; then
    ENABLE_EMAIL=0
    break
  else
    echo "${RED}Invalid input"
  fi
done

if [ "$ENABLE_EMAIL" == 1 ];
then
  sed -i 's/OTS_ENABLE_EMAIL = False/OTS_ENABLE_EMAIL = True/g' /opt/OpenTAKServer/opentakserver/config.py

  read -p "${GREEN}What is your email address? This address will be used to send messages to users and be associated with the admin account: ${NC}" ADMIN_EMAIL
  read -p "${GREEN}What is your email address password or Google app password? ${NC}" EMAIL_PASS
  read -p "${GREEN}What is your SMTP server address [smtp.gmail.com]? ${NC}" SMTP_SERVER
  SMTP_SERVER=${SMTP_SERVER:-smtp.gmail.com}
  read -p "${GREEN}What port does your SMTP server use? [465]? ${NC}" SMTP_PORT
  SMTP_PORT=${SMTP_PORT:-465}
  read -p "${GREEN}Does your SMTP server use SSL? [Y/n]? ${NC}" SMTP_SSL
  SMTP_SSL=${SMTP_SSL:-Y}

  sed -i "s/MAIL_SERVER = 'smtp.gmail.com'/MAIL_SERVER = '${MAIL_SERVER}'/g" /opt/OpenTAKServer/opentakserver/config.py
  sed -i "s/MAIL_PORT = 'smtp.gmail.com'/MAIL_PORT = '${MAIL_PORT}'/g" /opt/OpenTAKServer/opentakserver/config.py
  if [[ $SMTP_SSL =~ ^[nN] ]];
  then
    sed -i "s/MAIL_USE_SSL = True/MAIL_USE_SSL = False/g" /opt/OpenTAKServer/opentakserver/config.py
  fi
fi

echo "${GREEN}Creating certificate authority...${NC}"

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

if [ "$LETS_ENCRYPT" == 1 ];
then
  sudo sed -i "s~SERVER_CERT_FILE~/etc/letsencrypt/live/${SERVER_ADDRESS}/fullchain.pem~g" ~/ots/mediamtx/mediamtx.yml
  sudo sed -i "s~SERVER_KEY_FILE~/etc/letsencrypt/live/${SERVER_ADDRESS}/privkey.pem~g" ~/ots/mediamtx/mediamtx.yml
  sudo sed -i "s~OTS_FOLDER~${HOME}/ots~g" ~/ots/mediamtx/mediamtx.yml
else
  sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.pem~g" ~/ots/mediamtx/mediamtx.yml
  sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.nopass.key~g" ~/ots/mediamtx/mediamtx.yml
  sudo sed -i "s~OTS_FOLDER~${HOME}/ots~g" ~/ots/mediamtx/mediamtx.yml
fi

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

echo "${GREEN}Setting up nginx...${NC}"
sudo rm -f /etc/nginx/sites-enabled/*
sudo cp ots_proxy /etc/nginx/sites-available/

if [ "$LETS_ENCRYPT" == 1 ];
then
  sudo sed -i "s~SERVER_CERT_FILE~/etc/letsencrypt/live/${SERVER_ADDRESS}/fullchain.pem~g" /etc/nginx/sites-available/ots_proxy
  sudo sed -i "s~SERVER_KEY_FILE~/etc/letsencrypt/live/${SERVER_ADDRESS}/privkey.pem~g" /etc/nginx/sites-available/ots_proxy
  sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_proxy
else
  sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.pem~g" /etc/nginx/sites-available/ots_proxy
  sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/${SERVER_ADDRESS}/${SERVER_ADDRESS}.nopass.key~g" /etc/nginx/sites-available/ots_proxy
  sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_proxy
fi
sudo ln -s /etc/nginx/sites-available/ots_proxy /etc/nginx/sites-enabled/ots_proxy

sudo systemctl enable nginx
sudo systemctl restart nginx

cd "$INSTALLER_DIR" || exit

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
if [ "$ENABLE_EMAIL" == 1 ];
then
  echo "mail_username = '${ADMIN_EMAIL}'" >> /opt/OpenTAKServer/opentakserver/secret_key.py
  echo "mail_password = '${EMAIL_PASS}'" >> /opt/OpenTAKServer/opentakserver/secret_key.py
else
  echo "mail_username = ''" >> /opt/OpenTAKServer/opentakserver/secret_key.py
  echo "mail_password = ''" >> /opt/OpenTAKServer/opentakserver/secret_key.py
fi
echo "totp_secrets = {1: '$(python3 -c "import pyotp; print(pyotp.random_base32())")'}" >> /opt/OpenTAKServer/opentakserver/secret_key.py

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
sudo systemctl start opentakserver

echo "${GREEN}Setup is complete and OpenTAKServer is running. ${NC}"