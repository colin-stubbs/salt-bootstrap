#!/bin/bash

CURL_ARGS=''

SALT_VERSION='2017.7.4'
SALT_VERSION_PY='py2'

ROOT=''
CONFIG_DIR="${ROOT}/etc/salt"
MINION_PKI_DIR="${CONFIG_DIR}/pki/minion"

BOOTSTRAP_HOST='files.routedlogic.net'

MINION_CONFIG_URL="https://${BOOTSTRAP_HOST}/salt/bootstrap/minion"
MASTER_SIGN_URL="https://${BOOTSTRAP_HOST}/salt/bootstrap/master_sign.pub"
SALT_PKG_URL="https://repo.saltstack.com/osx/salt-${SALT_VERSION}-${SALT_VERSION_PY}-x86_64.pkg"

# download and install base salt package
curl -L ${SALT_PKG_URL} -o /tmp/salt.pkg
installer -pkg /tmp/salt.pkg -target "${ROOT}/"
rm -fv /tmp/salt.pkg

# validate package has actually installed
test -d ${CONFIG_DIR} || exit 1

# stop minion as we need to reconfigure
launchctl stop com.saltstack.salt.minion

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

# start salt minion
launchctl start com.saltstack.salt.minion

# EOF
