#!/bin/bash

MASTER_USER="salt"
MASTER_GROUP="salt"
MASTER_CONFIG_URL=""
MASTER_KEY_SIGN="1"
MASTER_KEY_SIGN_ARGS="--auto-create"
MASTER_CONFIG='# /etc/salt/master_sign

interface: "::"
ipv6: true

user: salt

pidfile: /var/run/salt/master/salt-master.pid

master_sign_pubkey: true
master_use_pubkey_signature: true

cli_summary: true
state_verbose: false
state_aggregate: true

file_roots:
  base:
    - /srv/salt/file_root

gitfs_remotes:
  - https://github.com/saltstack-formulas/salt-formula.git

file_ignore_regex:
  - /\.svn($|/)
  - /\.git($|/)

fileserver_backend:
  - roots
  - git

pillar_roots:
  base:
    - /srv/salt/pillar_root

pillar_safe_render_error: true
pillar_source_merging_strategy: smart
pillar_merge_lists: true
pillar_raise_on_missing: true

top_file_merging_strategy: merge

env_order:
  - base

default_top: base

hash_type: sha256

log_level: info
log_level_logfile: info

# EOF

'

MINION_USER=""
MINION_GROUP=""
MINION_CONFIG_URL=""
MINION_CONFIG='# /etc/salt/minion

master: 127.0.0.1
master_type: str
rejected_retry: true
master_tries: -1
master_alive_interval: 30
verify_master_pubkey_sign: true

log_level: info

tcp_keepalive: true
tcp_keepalive_idle: 300
tcp_keepalive_cnt: -1
tcp_keepalive_intvl: -1

restart_on_error: true

# EOF

'

MINION_ID="`hostname`"

MASTER_SIGN=""
MASTER_SIGN_URL=""

GRAINS=""

CURL_ARGS='-L'

ROOT=''
CONFIG_DIR="${ROOT}/etc/salt"
MINION_CONFIG_FILE="${CONFIG_DIR}/minion"
MASTER_CONFIG_FILE="${CONFIG_DIR}/master"
MINION_CONFIG_D="${CONFIG_DIR}/minion.d"
MASTER_CONFIG_D="${CONFIG_DIR}/master.d"
MINION_PKI_DIR="${CONFIG_DIR}/pki/minion"
MASTER_PKI_DIR="${CONFIG_DIR}/pki/master"
MASTER_PKI_MINIONS_DIR="${CONFIG_DIR}/pki/master/minions"
MINION_CACHE="/var/cache/salt/minion"
MASTER_CACHE="/var/cache/salt/master"

EXTENSIONS_DIR="/srv/salt/modules/extensions"
FILE_ROOT="/srv/salt/file_root"
PILLAR_ROOT="/srv/salt/pillar_root"

SALT_BOOTSTRAP_URL="https://bootstrap.saltstack.com"

curl ${CURL_ARGS} ${SALT_BOOTSTRAP_URL} -o /tmp/install_salt.sh
sh /tmp/install_salt.sh -P
rm -fv /tmp/install_salt.sh

# validate minion package has actually installed
test -d ${CONFIG_DIR} || exit 1

# install master package
yum -y install salt-master git python-pygit2

cp ${MINION_CONFIG_FILE} ${MINION_CONFIG_FILE}.orig
cp ${MASTER_CONFIG_FILE} ${MASTER_CONFIG_FILE}.orig

mkdir -p ${EXTENSIONS_DIR}
mkdir -p ${FILE_ROOT}
mkdir -p ${PILLAR_ROOT}
mkdir -p ${MINION_CACHE}
mkdir -p ${MASTER_CACHE}
mkdir -p ${MASTER_PKI_MINIONS_DIR}

# ensure the service is stopped while we reconfigure it
systemctl stop salt-minion.service
systemctl stop salt-master.service

# install custom minion config if desired
if [ "${MINION_CONFIG}x" == "x" ] && [ "${MINION_CONFIG_URL}x" != "x" ] ; then
  curl ${CURL_ARGS} ${MINION_CONFIG_URL} -o ${MINION_CONFIG_FILE} || exit 1
elif [ "${MINION_CONFIG}x" != "x" ] ; then
  echo "${MINION_CONFIG}" > ${MINION_CONFIG_FILE}
fi

# configure minion ID
echo "${MINION_ID}" > ${CONFIG_DIR}/minion_id

# configure grains
if [ "${GRAINS}x" != "x" ] ; then
  echo "${GRAINS}" > ${CONFIG_DIR}/grains
else
  touch ${CONFIG_DIR}/grains
fi

# install custom master config if desired
if [ "${MASTER_CONFIG}x" == "x" ] && [ "${MASTER_CONFIG_URL}x" != "x" ] ; then
  curl ${CURL_ARGS} ${MASTER_CONFIG_URL} -o ${MASTER_CONFIG_FILE} || exit 1
elif [ "${MASTER_CONFIG}x" != "x" ] ; then
  echo "${MASTER_CONFIG}" > ${MASTER_CONFIG_FILE}
fi

# install master signing public key component if desired
if [ "${MASTER_SIGN}x" == "x" ] && [ "${MASTER_SIGN_URL}x" != "x" ] ; then
  curl ${CURL_ARGS} ${MASTER_SIGN_URL} -o ${MINION_PKI_DIR}/master_sign.pub
elif [ "${MASTER_SIGN}x" == "x" ] ; then
  echo "${MASTER_SIGN}x" > ${MINION_PKI_DIR}/master_sign.pub
fi

# fix permissions if running master as non-default user
if [ "${MASTER_USER}x" != "x" ] ; then
  adduser --home-dir /srv/salt -c 'Salt Stack' -m -r -s /bin/bash salt

  CHOWN="${MASTER_USER}"
  if [ "${MASTER_GROUP}x" != "x" ] ; then
    CHOWN="${CHOWN}:${MASTER_GROUP}"
  fi

  chown -Rv ${CHOWN} ${MASTER_CONFIG_FILE} ${MASTER_PKI_DIR} ${MASTER_CONFIG_D} /var/log/salt/master /var/cache/salt/master /var/run/salt/master
fi

# fix permissions if running minion as non-default user
if [ "${MINION_USER}x" != "x" ] ; then
  CHOWN="${MINION_USER}"
  if [ "${MINION_GROUP}x" != "x" ] ; then
    CHOWN="${CHOWN}:${MINION_GROUP}"
  fi

  chown -Rv ${CHOWN} ${CONFIG_DIR}/minion_id ${CONFIG_DIR}/grains ${MINION_CONFIG_FILE} ${MINION_PKI_DIR} ${MINION_CONFIG_D} /var/log/salt/minion /var/cache/salt/minion /var/run/salt/minion
fi

# generate the salt master key
salt-key --gen-keys-dir=${MASTER_PKI_DIR} --gen-keys=master

# if master key signing is required auto-gen a signing key and sign the master key
if [ "${MASTER_KEY_SIGN}x" != "x" ] ; then
  salt-key --gen-keys-dir=${MASTER_PKI_DIR} --gen-signature ${MASTER_KEY_SIGN_ARGS}

  cp -v ${MASTER_PKI_DIR}/master_sign.pub ${MINION_PKI_DIR}/master_sign.pub
fi

# start salt master and ensure start on boot
systemctl enable salt-master.service
systemctl restart salt-master.service

# start salt minion and ensure start on boot
systemctl enable salt-minion.service
systemctl restart salt-minion.service

# accept the minion key
sleep 30
salt-key --yes --accept-all
sleep 30

# test connectivity to minion
salt '*' test.ping

# EOF
