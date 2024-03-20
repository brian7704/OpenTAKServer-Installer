#!/bin/bash

. /etc/os-release
. colors.sh

if [ "$NAME" != "Raspbian GNU/Linux" ] && [ "$NAME" != "Debian GNU/Linux" ]
then
  read -p "${YELLOW} This installer is for Raspberry Pi OS but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
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
sudo NEEDRESTART_MODE=a apt install curl python3 python3-pip rabbitmq-server git openssl nginx ffmpeg python3-pyotp python3-poetry -y

#curl -sSL https://install.python-poetry.org | python3 -
#pip3 install --user poetry-plugin-expo

if [ -d "/opt/OpenTAKServer" ]; then
  cd /opt/OpenTAKServer || exit
  sudo git pull
else
  sudo git clone https://github.com/brian7704/OpenTAKServer.git /opt/OpenTAKServer
  sudo chown "$USERNAME":"$USERNAME" /opt/OpenTAKServer -R
fi

~/.local/bin/poetry config virtualenvs.in-project true
~/.local/bin/poetry config virtualenvs.options.system-site-packages false

cd /opt/OpenTAKServer || exit
.venv/bin/pip3 install cryptography==41.0.7
#echo "${GREEN} Locking${NC}"
#~/.local/bin/poetry lock --no-update
#echo "${GREEN} Exporting${NC}"
#~/.local/bin/poetry export > requirements.txt
#echo "${GREEN} Installing ${NC}"
#.venv/bin/pip3 install -r requirements.txt
#.venv/bin/pip3 install .
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
cd /opt/OpenTAKServer && poetry update && poetry install && poetry run pip3 install lastversion

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
  sudo sed -i 's/icesecretwrite/;icesecretwrite/g' /etc/mumble-server.ini
  sudo service mumble-server restart

  PASSWORD_LOG=$(sudo grep -m 1 SuperUser /var/log/mumble-server/mumble-server.log)
  PASSWORD=($PASSWORD_LOG)
  read -p "${GREEN}Mumble Server is now installed. The SuperUser password is ${YELLOW}${PASSWORD[-1]}${GREEN}. Press enter to continue.${NC}"
fi

echo "${GREEN}Creating certificate authority...${NC}"

mkdir -p ~/ots/ca
cp "$INSTALLER_DIR"/config.cfg ~/ots/ca/ca_config.cfg

bash ./makeRootCa.sh --ca-name OpenTAKServer-CA
bash ./makeCert.sh server opentakserver

cd "$INSTALLER_DIR" || exit

echo "${GREEN}Installing mediamtx...${NC}"
mkdir -p ~/ots/mediamtx/recordings

cd /opt/OpenTAKServer

KERNEL_BITS=$(getconf LONG_BIT)
if [ "$KERNEL_BITS" == 32 ]; then
  poetry run lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx -o ~/ots/mediamtx
elif [ "$KERNEL_BITS" == 64 ]; then
  poetry run lastversion --filter '~*linux_arm64v8' --assets download bluenviron/mediamtx -o ~/ots/mediamtx
fi

cd ~/ots/mediamtx
tar -xf ./*.tar.gz
cd "$INSTALLER_DIR"
cp mediamtx.yml ~/ots/mediamtx/

sudo tee /etc/systemd/system/mediamtx.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
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

echo "${GREEN}Setting up nginx...${NC}"
sudo rm -f /etc/nginx/sites-enabled/*
sudo cp ots_proxy /etc/nginx/sites-available/

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/sites-available/ots_proxy
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/sites-available/ots_proxy
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_proxy

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
ExecStart=/opt/OpenTAKServer/.venv/bin/python /opt/OpenTAKServer/opentakserver/app.py
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
sudo systemctl start opentakserver

echo "${GREEN}Setup is complete and OpenTAKServer is running. ${NC}"