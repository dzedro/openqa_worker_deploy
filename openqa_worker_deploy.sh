#!/bin/bash
# Author: Jozef Pupava
# https://github.com/os-autoinst/openQA/blob/master/docs/Networking.asciidoc

function ~cancel {
    # it's expected that this files will be overweiten, delete what could be created anyway
    #rm -f /etc/sysconfig/network/ifcfg-$BRIDGE /etc/sysconfig/network/tap* /etc/wicked/scripts/gre_tunnel_preup.sh >/dev/null 2>&1
    #rm -rf /var/run/openvswitch /etc/openvswitch >/dev/null 2>&1
    #zypper -n rm openQA-worker os-autoinst-openvswitch libcap-progs >/dev/null 2>&1
    #zypper rr devel_openQA devel_openQA_SLE-12 >/dev/null 2>&1
    exit 1
}
trap ~cancel SIGINT SIGTERM

# variables and user input
DATE=$(date +%Y%m%d%H%M)
echo -e "\n\e[31mScript will add repos for SLE 12 SP3, modify the part if you run script on
different SLE,openSUSE version\e[39m\n"
echo -e "Set the bridge device name [br1]:"
read BRIDGE
if [ -z $BRIDGE ]; then
    BRIDGE='br1'
fi
echo -e "Set the HOST name [dzedro.suse.cz]:"
read HOST
if [ -z $HOST ]; then
    HOST='dzedro.suse.cz'
fi
echo -e "Enter key for $HOST (generate or find in webui http://$HOST/api_keys):"
read KEY
echo -e "Enter secret for $HOST:"
read SECRET
while [ -z $REMOTE_COUNT ]; do
    echo -e "Enter count (integer) of multimachine workers this worker node will connect to:"
    read REMOTE_COUNT
    if ! [[ $REMOTE_COUNT =~ ^[0-9]+$ ]]; then
        unset REMOTE_COUNT
        echo -e "\n\e[31mInteger only!\e[39m\n"
        continue
    fi
    continue
done
COUNT="1"
REMOTE_COUNT_DOWN=$REMOTE_COUNT
while [ "$REMOTE_COUNT_DOWN" -gt "0" ]; do
    echo -e "GRE tunnel to remote worker node No.${COUNT} of $REMOTE_COUNT:"
    read REMOTE_WORKER_$COUNT
    if ! [[ $(eval echo \$REMOTE_WORKER_$COUNT) =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
        unset REMOTE_WORKER_$COUNT
        echo -e "\n\e[31mDoes not look like valid IP!\e[39m\n"
        continue
    fi
    COUNT=$((COUNT+1))
    REMOTE_COUNT_DOWN=$((REMOTE_COUNT_DOWN-1))
    continue
done
echo -e "Enter number of workers which will be created and started on this machine (worker) [5]:"
read WORKER_COUNT_FROM1
if [ -z $WORKER_COUNT_FROM1 ]; then
    WORKER_COUNT_FROM1=5
fi
WORKER_COUNT_FROM0=$((WORKER_COUNT_FROM1-1))
echo -e "\n\e[31mScript will delete existing openvswitch configuration, install openqa-worker
and overwrite some files (/etc/sysconfig/network/ifcfg-*,
/etc/sysconfig/os-autoinst-openvswitch, /etc/wicked/scripts/gre_tunnel_preup.sh)
Configuration will be created based on your input and $WORKER_COUNT_FROM1 openQA
openQA workers will be started and enabled\e[39m\n"
read -p "Press any key ..." -n 1 -r

#==============================================================================
# remove existing openvswitch configuration and remove openQA packages to install them with clean configs
zypper -n rm openQA-worker os-autoinst-openvswitch libcap-progs >/dev/null 2>&1
zypper rr devel_openQA devel_openQA_SLE-12 >/dev/null 2>&1
rm -rf /var/run/openvswitch /etc/openvswitch >/dev/null 2>&1

# add openQA repos
zypper ar -G -f http://download.opensuse.org/repositories/devel:/openQA/SLE_12_SP3/devel:openQA.repo > /dev/null 2>&1
zypper ar -G -f http://download.opensuse.org/repositories/devel:/openQA:/SLE-12/SLE_12_SP3/devel:openQA:SLE-12.repo > /dev/null 2>&1
zypper ar -G -f http://download.suse.de/install/SLP/SLE-12-SP3-SDK-GM/x86_64/DVD1 SLE-12-SP3-SDK > /dev/null 2>&1
zypper ref -f

# install openqa worker, openvswitch and libcap-progs
zypper -n in openQA-worker os-autoinst-openvswitch libcap-progs
setcap CAP_NET_ADMIN=ep /usr/bin/qemu-system-x86_64

# add firewall rules
sed -i "s/^FW_DEV_INT=\"\"/FW_DEV_INT=\"$BRIDGE ovs-system\"/" /etc/sysconfig/SuSEfirewall2
sed -i 's/^FW_ROUTE="no"/FW_ROUTE="yes"/' /etc/sysconfig/SuSEfirewall2
sed -i 's/^FW_MASQUERADE="no"/FW_MASQUERADE="yes"/' /etc/sysconfig/SuSEfirewall2
sed -i 's/^FW_SERVICES_EXT_IP=""/FW_SERVICES_EXT_IP="GRE"/' /etc/sysconfig/SuSEfirewall2
sed -i 's/^FW_SERVICES_EXT_TCP=""/FW_SERVICES_EXT_TCP="20000:22000 5990:6020 1723"/' /etc/sysconfig/SuSEfirewall2
sed -i 's/^FW_SERVICES_EXT_TCP="1723"/FW_SERVICES_EXT_TCP="20000:22000 5990:6020 1723"/' /etc/sysconfig/SuSEfirewall2

# SES specififc rules
sed -i 's/FW_CONFIGURATIONS_EXT=""/FW_CONFIGURATIONS_EXT="ceph-mon ceph-osd-mds sshd vnc-httpd vnc-server"/' /etc/sysconfig/SuSEfirewall2
echo -e "\nChanged firewall rules:"
egrep "^FW_ROUTE|^FW_MASQUERADE|^FW_DEV_INT|^FW_SERVICES_EXT_IP|^FW_SERVICES_EXT_TCP" /etc/sysconfig/SuSEfirewall2
systemctl restart SuSEfirewall2.service
systemctl enable SuSEfirewall2.service

# start openvswitch
systemctl enable openvswitch.service os-autoinst-openvswitch.service
systemctl restart openvswitch.service os-autoinst-openvswitch.service
echo -e "\nCreating $WORKER_COUNT_FROM1 tap devices ..."
echo "BOOTPROTO='static'
IPADDR='10.0.2.2/15'
STARTMODE='auto'
PRE_UP_SCRIPT='wicked:gre_tunnel_preup.sh'
OVS_BRIDGE='yes'" >/etc/sysconfig/network/ifcfg-$BRIDGE
for i in $(seq 0 $WORKER_COUNT_FROM0); do echo "OVS_BRIDGE_PORT_DEVICE_$i='tap$i'" >>/etc/sysconfig/network/ifcfg-$BRIDGE; done
for i in $(seq 0 $WORKER_COUNT_FROM0); do
    echo "BOOTPROTO='none'
IPADDR=''
NETMASK=''
PREFIXLEN=''
STARTMODE='auto'
TUNNEL='tap'
TUNNEL_SET_GROUP='kvm'
TUNNEL_SET_OWNER='_openqa-worker'" >/etc/sysconfig/network/ifcfg-tap$i
done
echo "OS_AUTOINST_USE_BRIDGE=$BRIDGE" >/etc/sysconfig/os-autoinst-openvswitch
mkdir -p /etc/wicked/scripts
echo "#!/bin/sh
action=\"\$1\"
bridge=\"\$2\"
# enable STP for the multihost bridges
ovs-vsctl set bridge \$bridge stp_enable=true" >/etc/wicked/scripts/gre_tunnel_preup.sh

# don't setup GRE tunel if other multimachine workers are NOT defined
if [ $REMOTE_COUNT -ne "0" ]; then
    for i in $(seq 1 $REMOTE_COUNT); do
        echo "ovs-vsctl --may-exist add-port \$bridge gre$i -- set interface gre$i type=gre options:remote_ip=$(eval echo \$REMOTE_WORKER_$i)" >>/etc/wicked/scripts/gre_tunnel_preup.sh
    done
else
    # delete line PRE_UP_SCRIPT='wicked:gre_tunnel_preup.sh'
    sed -i '4d' /etc/sysconfig/network/ifcfg-$BRIDGE
fi
chmod +x /etc/wicked/scripts/gre_tunnel_preup.sh

# restart wickedd to create the devices defined in /etc/sysconfig/netwotk/ifcfg-
systemctl restart wickedd.service
sleep 2

# add bridge and tap devices
ovs-vsctl add-br $BRIDGE >/dev/null 2>&1
for i in $(seq 0 $WORKER_COUNT_FROM0); do ovs-vsctl add-port $BRIDGE tap$i tag=999 >/dev/null 2>&1; done

# restart network and openvswtich
echo -e "\nRestarting network ..."
systemctl restart openvswitch.service os-autoinst-openvswitch.service
systemctl restart network.service

# create geekotest user
if ! grep geekotest /etc/passwd > /dev/null; then
    echo "geekotest:x:475:65534:openQA user:/var/lib/openqa:/bin/bash" >>/etc/passwd
fi
chown _openqa-worker /var/lib/openqa/cache

# stop and disable apparmor
systemctl disable --now apparmor.service > /dev/null 2>&1

# prepare mounts
echo -e "\nMounting $HOST:/var/lib/openqa/share to /var/lib/openqa/share and adding fstab entry"
mkdir -p /var/lib/openqa/share
if ! mount|grep /var/lib/openqa/share > /dev/null; then
    mount -o ro -t nfs $HOST:/var/lib/openqa/share /var/lib/openqa/share
    # add openQA mounts into fstab
    echo "$HOST:/var/lib/openqa/share     /var/lib/openqa/share   nfs     defaults                0 0" >>/etc/fstab
fi

# add openQA keys & configuration for HOST
mv /etc/openqa/client.conf /etc/openqa/client.conf.$DATE
echo "[${HOST}]
key = $KEY
secret = $SECRET" >/etc/openqa/client.conf
mv /etc/openqa/workers.ini /etc/openqa/workers.ini.$DATE
echo "[global]
HOST=${HOST}
WORKER_HOSTNAME=$(ip a show dev $(ip route show|grep default|awk '{print$5}')|grep 'inet '|awk '{print$2}'|cut -f1 -d/)
CACHEDIRECTORY=/var/lib/openqa/cache
WORKER_CLASS=qemu_x86_64,tap

[${HOST}]
TESTPOOLSERVER = rsync://${HOST}/tests" >/etc/openqa/workers.ini

# start and enable 15 openqa workers
for i in $(seq 1 $WORKER_COUNT_FROM1); do systemctl enable openqa-worker@$i; done
for i in $(seq 1 $WORKER_COUNT_FROM1); do systemctl restart openqa-worker@$i; done
# try to finish with gre interfaces in STP_FORWARD state
COUNT=3
while ovs-ofctl show $BRIDGE|egrep -q "STP_LEARN$|STP_BLOCK$"; do
    # wait if gre interface has STP_LEARN state and hope for STP_FORWARD state
    while ovs-ofctl show $BRIDGE|grep -q STP_LEARN$; do
        sleep 2 && continue
    done
    # if any gre interface has STP_BLOCK state then try to restart network and continue with first loop
    while ovs-ofctl show $BRIDGE|grep -q STP_BLOCK$; do
        systemctl restart network.service
        # end whole loop after $COUNT tries
        if [ $COUNT -eq 0 ]; then
            echo -e "\n\e[31mWorkers should be connected and work, if not then reboot the machine
not all gre interfaces are in STP_FORWARD state and network restart did not help\e[39m\n"
            break 2
        fi
        COUNT=$(($COUNT-1)) && continue 2
    done
done
