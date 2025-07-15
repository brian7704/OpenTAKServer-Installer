#!/bin/bash

INSTALLER_DIR=/tmp/ots_installer
mkdir -p $INSTALLER_DIR
cd $INSTALLER_DIR

curl -L -s -o "$INSTALLER_DIR"/colors.sh https://github.com/brian7704/OpenTAKServer-Installer/raw/master/colors.sh
. "$INSTALLER_DIR"/colors.sh

echo "${GREEN}

   ___                        _____     _     _  __  ___
  / _ \   _ __   ___   _ _   |_   _|   /_\   | |/ / / __|  ___   _ _  __ __  ___   _ _
 | (_) | | '_ \ / -_) | ' \    | |    / _ \  | ' <  \__ \ / -_) | '_| \ V / / -_) | '_|
  \___/  | .__/ \___| |_||_|   |_|   /_/ \_\ |_|\_\ |___/ \___| |_|    \_/  \___| |_|
         |_|

${NC}"

. /etc/os-release

SUPPORTED_DISTRO=0

if [ "$NAME" == "Rocky Linux" ]
then
  IFS='.'
  read -ra VERSION_ARRAY <<< "$VERSION_ID"
  VERSION_MAJOR=${VERSION_ARRAY[0]}
  VERSION_MINOR=${VERSION_ARRAY[1]}

  if [ "$VERSION_MAJOR" -eq 9 ] && [ "$VERSION_MINOR" -ge 4 ]
  then
    SUPPORTED_DISTRO=1
  fi
fi

if [ "$SUPPORTED_DISTRO" -eq 0 ]
then
  read -p "${YELLOW} This installer is for Rocky Linux >= 9.4 but this system is $NAME $VERSION_ID. Do you want to run anyway? [y/N] ${NC}" confirm < /dev/tty && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
fi

USERNAME=$(whoami)

if [ "$USERNAME" == 'root' ]
then
  echo "${RED}Do no run this script as root. Instead run it as the same user that OTS will run as.${NC}"
  rm -fr $INSTALLER_DIR
  exit 1
fi

mkdir -p ~/ots

echo "${GREEN}Installing packages via dnf. You may be prompted for your sudo password...${NC}"

sudo dnf update -y
sudo dnf install python3.12 python3.12-pip-wheel python3.12-libs python3.12-devel epel-release openssl nginx nginx-mod-stream tar gcc policycoreutils-python-utils -y
sudo dnf config-manager --set-enabled crb
sudo dnf install --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm -y
sudo dnf install ffmpeg ffmpeg-devel -y

# Install signing keys for the RabbitMQ repos
sudo rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
sudo rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
sudo rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'


sudo tee /etc/yum.repos.d/rabbitmq.repo >/dev/null << EOF
##
## Zero dependency Erlang RPM
##

[modern-erlang]
name=modern-erlang-el9
# Use a set of mirrors maintained by the RabbitMQ core team.
# The mirrors have significantly higher bandwidth quotas.
baseurl=https://yum1.rabbitmq.com/erlang/el/9/\$basearch
        https://yum2.rabbitmq.com/erlang/el/9/\$basearch
repo_gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md

[modern-erlang-noarch]
name=modern-erlang-el9-noarch
# Use a set of mirrors maintained by the RabbitMQ core team.
# The mirrors have significantly higher bandwidth quotas.
baseurl=https://yum1.rabbitmq.com/erlang/el/9/noarch
        https://yum2.rabbitmq.com/erlang/el/9/noarch
repo_gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key
       https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md

[modern-erlang-source]
name=modern-erlang-el9-source
# Use a set of mirrors maintained by the RabbitMQ core team.
# The mirrors have significantly higher bandwidth quotas.
baseurl=https://yum1.rabbitmq.com/erlang/el/9/SRPMS
        https://yum2.rabbitmq.com/erlang/el/9/SRPMS
repo_gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key
       https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1


##
## RabbitMQ Server
##

[rabbitmq-el9]
name=rabbitmq-el9
baseurl=https://yum2.rabbitmq.com/rabbitmq/el/9/\$basearch
        https://yum1.rabbitmq.com/rabbitmq/el/9/\$basearch
repo_gpgcheck=1
enabled=1
# Cloudsmith's repository key and RabbitMQ package signing key
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
       https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md

[rabbitmq-el9-noarch]
name=rabbitmq-el9-noarch
baseurl=https://yum2.rabbitmq.com/rabbitmq/el/9/noarch
        https://yum1.rabbitmq.com/rabbitmq/el/9/noarch
repo_gpgcheck=1
enabled=1
# Cloudsmith's repository key and RabbitMQ package signing key
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
       https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc
gpgcheck=1
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md

[rabbitmq-el9-source]
name=rabbitmq-el9-source
baseurl=https://yum2.rabbitmq.com/rabbitmq/el/9/SRPMS
        https://yum1.rabbitmq.com/rabbitmq/el/9/SRPMS
repo_gpgcheck=1
enabled=1
gpgkey=https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key
gpgcheck=0
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
pkg_gpgcheck=1
autorefresh=1
type=rpm-md
EOF

sudo dnf install rabbitmq-server -y
sudo systemctl enable rabbitmq-server
sudo systemctl start rabbitmq-server

echo "${GREEN} Installing OpenTAKServer from PyPI...${NC}"
python3.12 -m venv --system-site-packages ~/.opentakserver_venv
source "$HOME"/.opentakserver_venv/bin/activate
pip3.12 install opentakserver
# Configure SELinux to allow OpenTAKServer to be launched by systemd
sudo semanage fcontext -a -t bin_t "$HOME/.opentakserver_venv/bin(/.*)?"
restorecon -r -v "$HOME"/.opentakserver_venv/bin
echo "${GREEN}OpenTAKServer Installed!${NC}"

echo "${GREEN}Initializing Database...${NC}"
cd "$HOME"/.opentakserver_venv/lib/python3.12/site-packages/opentakserver
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

echo "${GREEN}Creating certificate authority...${NC}"

mkdir -p ~/ots/ca
curl -L -s -o "$INSTALLER_DIR"/config.cfg https://github.com/brian7704/OpenTAKServer-Installer/raw/master/config.cfg
cp "$INSTALLER_DIR"/config.cfg ~/ots/ca/ca_config.cfg

# Generate CA
cd ~/.opentakserver_venv/lib/python3.12/site-packages/opentakserver
~/.opentakserver_venv/bin/flask ots create-ca
cd "$INSTALLER_DIR"

echo "${GREEN}Installing mediamtx...${NC}"
mkdir -p ~/ots/mediamtx/recordings

cd ~/ots/mediamtx

ARCH=$(uname -m)
KERNEL_BITS=$(getconf LONG_BIT)
if [ "$ARCH" == "x86_64" ]; then
  lastversion --filter '~*linux_amd64' --assets download bluenviron/mediamtx --only 1.10.0
elif [ "$KERNEL_BITS" == 32 ]; then
  lastversion --filter '~*linux_armv7' --assets download bluenviron/mediamtx --only 1.10.0
elif [ "$KERNEL_BITS" == 64 ]; then
  lastversion --filter '~*linux_arm64v8' --assets download bluenviron/mediamtx --only 1.10.0
fi

tar -xf ./*.tar.gz
curl -L -s -o ~/ots/mediamtx/mediamtx.yml https://github.com/brian7704/OpenTAKServer-Installer/raw/master/mediamtx.yml

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

# Configure SELinux to allow MediaMTX to start via systemd
sudo semanage fcontext -a -t bin_t "$HOME"/ots/mediamtx/mediamtx
restorecon -r -v "$HOME"/ots/mediamtx/mediamtx

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

# Configure SELinux to allow nginx to act as a proxy
sudo setsebool httpd_can_network_connect 1 -P

sudo grep "stream {" /etc/nginx/nginx.conf &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "${GREEN}Setting up nginx...${NC}"
  sudo echo "
stream {
        include /etc/nginx/streams-enabled/*;
}" | sudo tee -a /etc/nginx/nginx.conf
fi

sudo tee /etc/nginx/proxy_params >/dev/null << EOF
proxy_set_header Host \$http_host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
EOF

# Configure firewalld
echo "${GREEN}Configuring firewalld...${NC}"
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --add-port=8443/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8446/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8080/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8088/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8089/tcp
sudo firewall-cmd --permanent --zone=public --add-port=1935/tcp
sudo firewall-cmd --permanent --zone=public --add-port=1936/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8000/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8001/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8189/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8322/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8554/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8888/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8889/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8890/tcp
sudo firewall-cmd --permanent --zone=public --add-port=1883/tcp
sudo firewall-cmd --permanent --zone=public --add-port=8883/tcp
sudo firewall-cmd --reload

sudo rm -f /etc/nginx/sites-enabled/*
sudo mkdir -p /etc/nginx/streams-available
sudo mkdir -p /etc/nginx/streams-enabled

sudo curl -L -s -o /etc/nginx/streams-available/rabbitmq https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/nginx_configs/rabbitmq
sudo curl -L -s -o /etc/nginx/streams-available/mediamtx https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/mediamtx
sudo curl -L -s -o /etc/nginx/conf.d/ots_certificate_enrollment.conf https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_certificate_enrollment
sudo curl -L -s -o /etc/nginx/conf.d/ots_http.conf https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_http
sudo curl -L -s -o /etc/nginx/conf.d/ots_https.conf https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/refs/heads/master/nginx_configs/ots_https

sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/conf.d/ots_https.conf
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/conf.d/ots_certificate_enrollment.conf
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/streams-available/rabbitmq
sudo sed -i "s~SERVER_CERT_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.pem~g" /etc/nginx/streams-available/mediamtx
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/conf.d/ots_https.conf
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/conf.d/ots_certificate_enrollment.conf
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/streams-available/rabbitmq
sudo sed -i "s~SERVER_KEY_FILE~${HOME}/ots/ca/certs/opentakserver/opentakserver.nopass.key~g" /etc/nginx/streams-available/mediamtx
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/conf.d/ots_https.conf
sudo sed -i "s~CA_CERT_FILE~${HOME}/ots/ca/ca.pem~g" /etc/nginx/conf.d/ots_certificate_enrollment.conf

sudo ln -s /etc/nginx/streams-available/rabbitmq /etc/nginx/streams-enabled/
sudo ln -s /etc/nginx/streams-available/mediamtx /etc/nginx/streams-enabled/

# Configure SELinux so nginx can start
sudo semanage fcontext -a -t httpd_sys_content_t "$HOME/ots(/.*)?"
sudo restorecon -Rv "$HOME"/ots
sudo semanage port -a -t http_port_t -p tcp 8446
sudo semanage port -a -t http_port_t -p tcp 8883
sudo setsebool -P httpd_can_network_connect 1

sudo systemctl enable nginx
sudo systemctl restart nginx

sudo mkdir -p /var/www/html/opentakserver
sudo chmod a+rw /var/www/html/opentakserver
cd /var/www/html/opentakserver
lastversion --assets extract brian7704/OpenTAKServer-UI

# Configure SELinux to allow nginx to access /var/www/html
sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/html/(/.*)?"
sudo restorecon -Rv /var/www/html

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
sudo curl -L -s -o /etc/rabbitmq/rabbitmq.conf https://raw.githubusercontent.com/brian7704/OpenTAKServer-Installer/master/rabbitmq.conf

# The following lines all end in "; \" because rabbitmq-plugins stops the script, even when it's successful
# Adding "; \" is a janky fix to make the rest of the script work
sudo rabbitmq-plugins enable rabbitmq_mqtt rabbitmq_auth_backend_http ; \
sudo systemctl restart rabbitmq-server ; \
echo "${GREEN}Finished configuring RabbitMQ${NC}" ; \
rm -fr $INSTALLER_DIR ; \
deactivate ; \
sudo systemctl restart opentakserver
echo "${GREEN}Setup is complete and OpenTAKServer is running. You can access the Web UI at https://$(hostname -I)${NC}"