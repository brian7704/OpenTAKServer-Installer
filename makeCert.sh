#!/bin/bash
# EDIT cert-metadata.sh before running this script! 
#  Optionally, you may also edit config.cfg, although unless you know what
#  you are doing, you probably shouldn't.

INSTALLER_DIR=/tmp/ots_installer

. "$INSTALLER_DIR"/cert-metadata.sh
. "$INSTALLER_DIR"/colors.sh

mkdir -p "$DIR"
cd "$DIR"
mkdir -p certs

usage() {
  echo "Usage: ./makeCert.sh [server|client|ca|dbclient] <common name>"
  echo "  If you do not provide a common name on the command line, you will be prompted for one"
  exit -1
}

if [ ! -e ca.pem ]; then
  echo "${RED}ca.pem does not exist!  Please make a CA before trying to make server certficiates${NC}"
  exit -1
fi

if [ "$1" ]; then
  if [ "$1" == "server" ]; then
    EXT=server
  elif [ "$1" == "client" ]; then
    EXT=client
  elif [ "$1" == "ca" ]; then
    EXT=v3_ca
  elif [ "$1" == "dbclient" ]; then
    EXT=client
  else
    usage
  fi
else
  usage
fi 


if [ "$2" ]; then
  SNAME=$2
  mkdir -p certs/"$SNAME"
  if [ -e certs/"$SNAME"/"$SNAME".key ]; then
    echo "A key already exists for $SNAME"
    exit 1
  fi
else
  if [ "$1" == "dbclient" ]; then
    echo "Use default name martiuser for database client certificate"
    SNAME=martiuser
  else
    echo "Please give the common name for your certificate (no spaces).  It should be unique.  If you don't enter anything, or try something under 5 characters, I will make one for you"
    read SNAME
    canamelen=${#SNAME}
    if [[ "$canamelen" -lt 5 ]]; then
      SNAME=`date +%N`
    fi
  fi
fi

if [ "$1" == "server" ]; then
  if [[ $SNAME =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
     ALTNAMEFIELD="IP.1" 
  else
     ALTNAMEFIELD="DNS.1"
  fi

  cp "$INSTALLER_DIR"/config.cfg "$DIR"/config-"$SNAME".cfg
  echo "
subjectAltName = @alt_names

[alt_names]
$ALTNAMEFIELD = $SNAME
" >> config-"$SNAME".cfg
  CONFIG=config-$SNAME.cfg
else
  CONFIG="$INSTALLER_DIR"/config.cfg
fi

openssl list -providers 2>&1 | grep "\(invalid command\|unknown option\)" >/dev/null
if [ $? -ne 0 ] ; then
  echo "Using legacy provider"
  LEGACY_PROVIDER="-legacy"
fi

SUBJ=$SUBJBASE"CN=$SNAME"
echo "${GREEN}Making a $1 cert for $SUBJ ${NC}"
if [[ "$1" == "ca" ]]; then
  # Have to use the password {CAPASS} instead of {PASS} since the original CA can be replaced by this new CA at the end
  openssl req -new -newkey rsa:2048 -sha256 -keyout certs/"${SNAME}"/"${SNAME}".key -passout pass:${CAPASS} -out certs/"${SNAME}"/"${SNAME}".csr -subj "$SUBJ"
else
  openssl req -new -newkey rsa:2048 -sha256 -keyout certs/"${SNAME}"/"${SNAME}".key -passout pass:${PASS} -out certs/"${SNAME}"/"${SNAME}".csr -subj "$SUBJ"
fi
openssl x509 -sha256 -req -days 730 -in certs/"${SNAME}"/"${SNAME}".csr -CA ca.pem -CAkey ca-do-not-share.key -out certs/"${SNAME}"/"${SNAME}".pem -set_serial ${RANDOM} -passin pass:${CAPASS} -extensions $EXT -extfile $CONFIG

if [[ "$1" == "ca" ]]; then
  openssl x509 -in certs/"${SNAME}"/"${SNAME}".pem  -addtrust clientAuth -addtrust serverAuth -setalias "${SNAME}" -out certs/"${SNAME}"/"${SNAME}"-trusted.pem
fi

# Convert the database client private key to PKCS#8 format to use in TAK Server configuration file
if [[ "$1" == "dbclient" ]]; then
  openssl pkcs8 -topk8 -outform DER -in certs/"${SNAME}"/"${SNAME}".key -passin pass:$PASS -out "${SNAME}".key.pk8 -nocrypt
fi

# now add the chain
cat ca.pem >> certs/"${SNAME}"/"${SNAME}".pem
cat ca-trusted.pem >> certs/"${SNAME}"/"${SNAME}"-trusted.pem

# now make pkcs12 and jks keystore files
if [[ "$1" == "server" ||  "$1" == "client" || "$1" == "dbclient" ]]; then
  openssl pkcs12 ${LEGACY_PROVIDER} -export -in certs/"${SNAME}"/"${SNAME}".pem -inkey certs/"${SNAME}"/"${SNAME}".key -out certs/"${SNAME}"/"${SNAME}".p12 -name "${SNAME}" -CAfile ca.pem -passin pass:${PASS} -passout pass:${PASS}
  keytool -importkeystore -deststorepass "${PASS}" -destkeypass "${PASS}" -destkeystore certs/"${SNAME}"/"${SNAME}".jks -srckeystore certs/"${SNAME}"/"${SNAME}".p12 -srcstoretype PKCS12 -srcstorepass "${PASS}" -alias "${SNAME}"
  openssl rsa -in certs/"${SNAME}"/"${SNAME}".key -passin pass:"${PASS}" -out certs/"${SNAME}"/"${SNAME}".nopass.key
else # a CA

  openssl pkcs12 ${LEGACY_PROVIDER} -export -in "${SNAME}"-trusted.pem -out truststore-"${SNAME}".p12 -nokeys -passout pass:${CAPASS}
  keytool -import -trustcacerts -file "${SNAME}".pem -keystore truststore-"${SNAME}".jks -storepass "${CAPASS}" -noprompt

  # include a CA signing keystore; NOT FOR DISTRIBUTION TO CLIENTS
  openssl pkcs12 ${LEGACY_PROVIDER} -export -in "${SNAME}".pem -inkey "${SNAME}".key -out "${SNAME}"-signing.p12 -name "${SNAME}" -passin pass:${CAPASS} -passout pass:${CAPASS}
  keytool -importkeystore -deststorepass "${CAPASS}" -destkeypass "${CAPASS}" -destkeystore "${SNAME}"-signing.jks -srckeystore "${SNAME}"-signing.p12 -srcstoretype PKCS12 -srcstorepass "${CAPASS}" -alias "${SNAME}"

  ## create empty crl 
  openssl ca -config "$INSTALLER_DIR"/config.cfg -gencrl -keyfile "${SNAME}".key -key ${CAPASS} -cert "${SNAME}".pem -out "${SNAME}".crl


  echo "Do you want me to move files around so that future server and client certificates are signed by this new CA? [y/n]"
  read MVREQ
  if [[ "$MVREQ" == "y" || "$MVREQ" == "Y" ]]; then
    cp $SNAME.pem ca.pem
    cp $SNAME.key ca-do-not-share.key
    cp $SNAME-trusted.pem ca-trusted.pem
  else
    echo "Ok, not overwriting existing keys.  To manually change the CA later, execute these commands from the 'files' directory:"
    echo "  cp $SNAME.pem ca.pem"
    echo "  cp $SNAME.key ca-do-not-share.key"
    echo "  cp $SNAME-trusted.pem ca-trusted.pem"
  fi

fi

chmod og-rwx certs/"${SNAME}"/"${SNAME}".key

