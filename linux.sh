#!/bin/bash

CURL_ARGS='-L'

ROOT=''
CONFIG_DIR="${ROOT}/etc/salt"
MINION_PKI_DIR="${CONFIG_DIR}/pki/minion"

BOOTSTRAP_HOST='files.routedlogic.net'

MINION_CONFIG_URL="https://${BOOTSTRAP_HOST}/salt/bootstrap/minion"
MASTER_SIGN_URL="https://${BOOTSTRAP_HOST}/salt/bootstrap/master_sign.pub"

SALT_BOOTSTRAP_URL="https://bootstrap.saltstack.com"

curl ${CURL_ARGS} ${SALT_BOOTSTRAP_URL} -o /tmp/install_salt.sh
sh /tmp/install_salt.sh -P
rm -fv /tmp/install_salt.sh

# validate package has actually installed
test -d ${CONFIG_DIR} || exit 1

# ensure the service is stopped while we reconfigure it
systemctl stop salt-minion.service

# install custom minion config if desired
if [ "${MINION_CONFIG}x" == "x" ] && [ "${MINION_CONFIG_URL}x" != "x" ] ; then
  curl ${CURL_ARGS} ${MINION_CONFIG_URL} -o ${CONFIG_DIR}/minion
elif [ "${MINION_CONFIG}x" != "x" ] ; then
  echo "${MINION_CONFIG}" > ${CONFIG_DIR}/minion
fi

# install master signing public key component if desired
if [ "${MASTER_SIGN}x" == "x" ] && [ "${MASTER_SIGN_URL}x" != "x" ] ; then
  curl ${CURL_ARGS} ${MASTER_SIGN_URL} -o ${MINION_PKI_DIR}/master_sign.pub
elif [ "${MASTER_SIGN}x" == "x" ]
  echo "${MASTER_SIGN}x" > ${MINION_PKI_DIR}/master_sign.pub
fi

# configure minion ID
hostname > /etc/salt/minion_id

# configure grains
if [ "${GRAINS}x" != "x" ] ; then
  echo "${GRAINS}" > ${CONFIG_DIR}/grains
else
  touch ${CONFIG_DIR}/grains
fi

# start salt minion and ensure start on boot
systemctl enable salt-minion.service
systemctl restart salt-minion.service

# EOF
