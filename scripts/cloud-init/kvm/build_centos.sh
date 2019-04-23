#!/bin/bash

# Take one argument from the commandline: VM name
if ! [ $# -eq 1 ]; then
    echo "Usage: $0 <node-name>"
    exit 1
fi

# Check if domain already exists
virsh dominfo $1 > /dev/null 2>&1
if [ "$?" -eq 0 ]; then
    echo -n "[WARNING] $1 already exists.  "
    read -p "Do you want to overwrite $1 (y/[N])? " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        virsh destroy $1 > /dev/null
        virsh undefine $1 > /dev/null
    else
        echo -e "\nNot overwriting $1. Exiting..."
        exit 1
    fi
fi

# Directory to store images
DIR=/var/lib/libvirt/images

# Location of cloud image
IMAGE=$DIR/CentOS-7-x86_64-GenericCloud-1805.qcow2

# Amount of RAM in MB
MEM=1024

# Number of virtual CPUs
CPUS=1

# Cloud init files
USER_DATA=user-data
META_DATA=meta-data
CI_ISO=$1-cidata.iso
DISK=$1.qcow2

# Bridge for VMs (default on Fedora is virbr0)
BRIDGE=virbr0

NETWORK=""

# Start clean
rm -rf $DIR/$1
mkdir -p $DIR/$1

pushd $DIR/$1 > /dev/null

    # Create log file
    touch $1.log

    echo "$(date -R) Destroying the $1 domain (if it exists)..."

    # Remove domain with the same name
    virsh destroy $1 >> $1.log 2>&1
    virsh undefine $1 >> $1.log 2>&1

    # cloud-init config: set hostname, remove cloud-init package,
    # and add ssh-key
    cat > $USER_DATA << _EOF_
#cloud-config
preserve_hostname: False
hostname: $1
fqdn: $1.domain.tld
users:
  - default
  - name: test
    primary_group: wheel
    groups: users
    passwd: $6$SALTED_HASH_HERE
    ssh_authorized_keys:
      - ssh-rsa EXAMPLE_KEY blah@domain.tld
runcmd:
  - [ yum, -y, remove, cloud-init ]
  - [ mkdir, -p, -m, 700, /etc/salt/pki/minion ]
  - [ chmod, 700, /etc/salt/pki/minion ]
  - [ systemctl, enable, salt-minion.service ]
output:
  all: ">> /var/log/cloud-init.log"
ssh_svcname: ssh
ssh_deletekeys: True
ssh_genkeytypes: ['rsa', 'ecdsa']
ssh_authorized_keys:
  - ssh-rsa YOUR_SSH_PUB_KEY_HERE description@domain.tld
yum_repos:
  saltstack:
    baseurl: https://repo.saltstack.com/yum/redhat/7/\$basearch/latest/
    enabled: true
    gpgcheck: true
    gpgkey: https://repo.saltstack.com/yum/redhat/7/\$basearch/latest/SALTSTACK-GPG-KEY.pub
    name: SaltStack latest Release Channel for RHEL/CentOS \$releasever
packages:
  - epel-release
  - salt-minion
write_files:
  - path: /etc/salt/pki/minion/master_sign.pub
    encoding: b64
    content: MASTER_SIGNING_PUB_KEY_GOES_HERE
  - path: /etc/salt/grains
    permissions: 0640
    owner: root
    content: |
      cis:
        profile: xccdf_org.cisecurity.benchmarks_profile_Level_2_-_Server
    owner: root:root
    permissions: '0644'
  - path: /etc/sysctl.d/10-disable-ipv6.conf
    permissions: 0644
    owner: root
    content: |
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
  - path: /etc/yum.conf
    permissions: 0644
    owner: root
    content: |
      [main]
      cachedir=/var/cache/yum/\$basearch/\$releasever
      keepcache=0
      debuglevel=2
      logfile=/var/log/yum.log
      exactarch=1
      obsoletes=1
      gpgcheck=1
      plugins=1
      installonly_limit=5
      bugtracker_url=http://bugs.centos.org/set_project.php?project_id=23&ref=http://bugs.centos.org/bug_report_page.php?category=yum
      distroverpkg=centos-release
      ip_resolve=4
salt_minion:
  conf:
    master: "salt.domain.tld"
    master_type: "str"
    verify_master_pubkey_sign: true
    ipv6: false
    retry_dns: 30
    backup_mode: "minion"
    rejected_retry: true
    master_tries: -1
    ping_interval: 4
    mine_functions:
      public_ssh_host_keys: {'mine_function': 'cmd.run', 'cmd': 'cat /etc/ssh/ssh_host_*_key.pub 2>/dev/null', 'python_shell': True}
      public_ssh_hostname: {'mine_function': 'grains.get', 'key': 'id'}
    startup_states: "highstate"
    pillar_merge_lists: true
    log_level: "warning"
    tcp_keepalive: true
    tcp_keepalive_idle: 30
    tcp_keepalive_cnt: 3
    tcp_keepalive_intvl: 15
    restart_on_error: true
package_upgrade: true
_EOF_

    echo "instance-id: $1\nlocal-hostname: $1" > $META_DATA

    echo "$(date -R) Copying template image..."
    cp $IMAGE $DISK

    # Create CD-ROM ISO with cloud-init config
    echo "$(date -R) Generating ISO for cloud-init..."
    genisoimage -output $CI_ISO -volid cidata -joliet -r $USER_DATA $META_DATA &>> $1.log

    echo "$(date -R) Installing the domain and adjusting the configuration..."
    echo "[INFO] Installing with the following parameters:"
    echo "virt-install --import --name $1 --ram $MEM --vcpus $CPUS --disk
    $DISK,format=qcow2,bus=virtio --disk $CI_ISO,device=cdrom --network
    bridge=virbr0,model=virtio --os-type=linux --os-variant=rhel7 --noautoconsole"

    virt-install --import --name $1 --ram $MEM --vcpus $CPUS --disk \
    $DISK,format=qcow2,bus=virtio --disk $CI_ISO,device=cdrom --network \
    bridge=virbr0,model=virtio --os-type=linux --os-variant=rhel7 --noautoconsole

    MAC=$(virsh dumpxml $1 | awk -F\' '/mac address/ {print $2}')
    while true
    do
        IP=$(grep -B1 $MAC /var/lib/libvirt/dnsmasq/$BRIDGE.status | head \
             -n 1 | awk '{print $2}' | sed -e s/\"//g -e s/,//)
        if [ "$IP" = "" ]
        then
            sleep 1
        else
            break
        fi
    done

    # Eject cdrom
    echo "$(date -R) Cleaning up cloud-init..."
    virsh change-media $1 hda --eject --config >> $1.log

    # Remove the unnecessary cloud init files
    rm $USER_DATA $CI_ISO

    echo "$(date -R) DONE. SSH to $1 using $IP with  username 'centos'."

popd > /dev/null
