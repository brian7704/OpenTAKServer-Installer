#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh -qO "$INSTALLER_DIR"/colors.sh
. "$INSTALLER_DIR"/colors.sh

. /etc/os-release

if [ "$NAME" != "Raspbian GNU/Linux" ] && [ "$NAME" != "Debian GNU/Linux" ]
then
  read -p "${YELLOW} This installer is for Raspberry Pi OS but this system is $NAME. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
fi

USERNAME=$(whoami)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  exit 1
fi

mkdir -p ~/ots
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/iconsets.sqlite -qO ~/ots/ots.db

echo "${GREEN}Installing packages via apt. You may be prompted for your sudo password...${NC}"

sudo apt update && sudo NEEDRESTART_MODE=a apt upgrade -y
sudo NEEDRESTART_MODE=a apt install curl python3 python3-pip python3-venv rabbitmq-server openssl nginx ffmpeg openjdk-17-jre-headless -y

echo "${GREEN}Installing OpenTAKServer from PyPI...${NC}"
python3 -m venv ~/.opentakserver_venv
source "$HOME"/.opentakserver_venv/bin/activate
pip3 install opentakserver
echo "${GREEN}OpenTAKServer Installed!${NC}"

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
  sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv B6391CB2CFBA643D
  sudo echo "deb http://zeroc.com/download/Ice/3.7/ubuntu`lsb_release -rs` stable main" > root@atakpi:/etc/apt/sources.list.d/zeroc.list
  sudo apt update

  sudo NEEDRESTART_MODE=a apt install mumble-server zeroc-ice-all-runtime zeroc-ice-all-dev -y

  sudo sed -i '/ice="tcp -h 127.0.0.1 -p 6502"/s/^#//g' /etc/mumble-server.ini
  sudo sed -i 's/icesecretwrite/;icesecretwrite/g' /etc/mumble-server.ini
  sudo service mumble-server restart

  PASSWORD_LOG=$(sudo grep -m 1 SuperUser /var/log/mumble-server/mumble-server.log)
  PASSWORD=($PASSWORD_LOG)
  read -p "${GREEN}Mumble Server is now installed. The SuperUser password is ${YELLOW}${PASSWORD[-1]}${GREEN}. Press enter to continue.${NC}" < /dev/tty
fi

echo "${GREEN}Creating certificate authority...${NC}"

mkdir -p ~/ots/ca
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/config.cfg -qO "$INSTALLER_DIR"/config.cfg
cp "$INSTALLER_DIR"/config.cfg ~/ots/ca/ca_config.cfg

# Generate CA
cd "$INSTALLER_DIR"
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/makeRootCa.sh -qO "$INSTALLER_DIR"/makeRootCa.sh
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/makeCert.sh -qO "$INSTALLER_DIR"/makeCert.sh
bash ./makeRootCa.sh --ca-name OpenTAKServer-CA
bash ./makeCert.sh server opentakserver

echo "${GREEN}Installing mediamtx...${NC}"
mkdir -p ~/ots/mediamtx/recordings

cd ~/ots/mediamtx

KERNEL_BITS=$(getconf LONG_BIT)
if [ "$KERNEL_BITS" == 32 ]; then
  lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx -o ~/ots/mediamtx
elif [ "$KERNEL_BITS" == 64 ]; then
  lastversion --filter '~*linux_arm64v8' --assets download bluenviron/mediamtx -o ~/ots/mediamtx
fi

cd ~/ots/mediamtx
tar -xf ./*.tar.gz
cd "$INSTALLER_DIR"
wget https://github.com/brian7704/OpenTAKServer-Installer/raw/master/mediamtx.yml -qO ~/ots/mediamtx/mediamtx.yml

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
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/online_installer/nginx_configs/ots_certificate_enrollment -qO /etc/nginx/sites-available/ots_certificate_enrollment
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/online_installer/nginx_configs/ots_http -qO /etc/nginx/sites-available/ots_http
sudo wget https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/online_installer/nginx_configs/ots_https -qO /etc/nginx/sites-available/ots_https

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/sites-available/ots_certificate_enrollment
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/sites-available/ots_certificate_enrollment
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_https
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/sites-available/ots_certificate_enrollment

sudo ln -s /etc/nginx/sites-available/ots_* /etc/nginx/sites-enabled/

sudo systemctl enable nginx
sudo systemctl restart nginx

cd "$INSTALLER_DIR" || exit

sudo tee /etc/systemd/system/opentakserver.service >/dev/null << EOF
[Unit]
Wants=network.target
[Service]
User=$(whoami)
WorkingDirectory=${HOME}/ots
ExecStart=${HOME}/.opentakserver_venv/bin/python3 -m opentakserver.app
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opentakserver
sudo systemctl start opentakserver

rm -fr $INSTALLER_DIR
deactivate

echo "${GREEN}Setup is complete and OpenTAKServer is running. ${NC}"