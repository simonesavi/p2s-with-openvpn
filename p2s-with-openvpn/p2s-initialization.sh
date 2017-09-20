#!/bin/bash

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

LOG_FILE=/var/log/p2s-initialization.log
COUNTRY="export KEY_COUNTRY=\"US\""
PROVINCE="export KEY_PROVINCE=\"CA\""
CITY="export KEY_CITY=\"SanFrancisco\""
ORG="export KEY_ORG=\"Fort-Funston\""
EMAIL="export KEY_EMAIL=\"me@myhost.mydomain\""
OU="export KEY_OU=\"MyOrganizationalUnit\""
OPENVPN_PORT="443"
OPENVPN_SERVER_NET="10.6.0.0"
OPENVPN_MASK="255.255.255.0"
VNET="192.169.0.0"
VNET_MASK="255.255.0.0."
BLOB_ACCOUNT_NAME=""
BLOB_ACCOUNT_KEY=""
BLOB_CONTAINER_NAME=""

while getopts v:m:c:k:p:l:o:r:i:g:e:u:a:y:t: option
do
        case "${option}"
        in
        v) VNET=${OPTARG};;
        m) VNET_MASK=${OPTARG};;
		c) OPENVPN_SERVER_NET=${OPTARG};;
		k) OPENVPN_MASK=${OPTARG};;
		p) OPENVPN_PORT=${OPTARG};;
		l) LOG_FILE=${OPTARG};;
		o) COUNTRY=${OPTARG};;
		r) PROVINCE=${OPTARG};;
		i) CITY=${OPTARG};;
		g) ORG=${OPTARG};;
		e) EMAIL=${OPTARG};;
		u) OU=${OPTARG};;
		a) BLOB_ACCOUNT_NAME=${OPTARG};;
		y) BLOB_ACCOUNT_KEY=${OPTARG};;
		t) BLOB_CONTAINER_NAME=${OPTARG};;
        esac
done

echo "## Start EPEL Installation ##" >> ${LOG_FILE}
yum install -y epel-release >> ${LOG_FILE} 2>&1
echo "## EPEL Installed ##" >> ${LOG_FILE}

echo "## Start OpenVPN Installation ##" >> ${LOG_FILE}
yum install -y openvpn >> ${LOG_FILE} 2>&1
echo "## OpenVPN Installed ##" >> ${LOG_FILE}

echo "## Start Easy RSA Installation ##" >> ${LOG_FILE}
yum install -y easy-rsa >> ${LOG_FILE} 2>&1
echo "## Easy RSA Installed ##" >> ${LOG_FILE}

# echo "## System Update ##" >> ${LOG_FILE}
# yum -y upgrade --exclude=WALinuxAgent >> ${LOG_FILE} 2>&1
# echo "## End System Update ##" >> ${LOG_FILE}

echo "## Start enable Swap ##" >> ${LOG_FILE}
dd if=/dev/zero of=/swapfile bs=1024 count=1024000 >> ${LOG_FILE} 2>&1
mkswap /swapfile >> ${LOG_FILE} 2>&1
chmod 600 /swapfile
swapon /swapfile
echo "/swapfile   swap    swap    defaults        0       0" >> /etc/fstab
echo "## End enable Swap ##" >> ${LOG_FILE}

echo "## Start disable IPv6 ##" >> ${LOG_FILE}
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/ipv6.conf
sed -i '2s/^/#/' /etc/hosts
sed -i '18s/#//' /etc/ssh/sshd_config
sed -i '18s/any/inet/' /etc/ssh/sshd_config
echo "## End disable IPv6 - Reboot required ##" >> ${LOG_FILE}

echo "## Start Easy RSA Configuration ##" >> ${LOG_FILE}
mkdir /etc/openvpn/rsa
cp -rf /usr/share/easy-rsa/2.0/* /etc/openvpn/rsa
sed -i "s/export KEY_COUNTRY=\"US\"/$COUNTRY/" /etc/openvpn/rsa/vars
sed -i "s/export KEY_PROVINCE=\"CA\"/$PROVINCE/" /etc/openvpn/rsa/vars
sed -i "s/export KEY_CITY=\"SanFrancisco\"/$CITY/" /etc/openvpn/rsa/vars
sed -i "s/export KEY_ORG=\"Fort-Funston\"/$ORG/" /etc/openvpn/rsa/vars
sed -i "s/export KEY_EMAIL=\"me@myhost.mydomain\"/$EMAIL/" /etc/openvpn/rsa/vars
sed -i "s/export KEY_OU=\"MyOrganizationalUnit\"/$OU/" /etc/openvpn/rsa/vars
cd /etc/openvpn/rsa/
source ./vars >> ${LOG_FILE} 2>&1
./clean-all
./build-ca --batch >> ${LOG_FILE} 2>&1
./build-key-server --batch server >> ${LOG_FILE} 2>&1
cd /etc/openvpn/rsa/keys
touch .rnd
export RANDFILE="/etc/openvpn/rsa/keys/.rnd"
cd /etc/openvpn/rsa/
./build-dh >> ${LOG_FILE} 2>&1
cp /etc/openvpn/rsa/keys/ca.crt /etc/openvpn/
cp /etc/openvpn/rsa/keys/dh2048.pem /etc/openvpn/
cp /etc/openvpn/rsa/keys/server.* /etc/openvpn/
echo "## End Easy RSA Configuration ##" >> ${LOG_FILE}

echo "## Start OpenVPN Configuration ##" >> ${LOG_FILE}
cp /usr/share/doc/openvpn-*/sample/sample-config-files/server.conf /etc/openvpn/
sed -i "s/port 1194/port $OPENVPN_PORT/" /etc/openvpn/server.conf
sed -i '35s/;//' /etc/openvpn/server.conf
sed -i '36s/^/;/' /etc/openvpn/server.conf
sed -i "s/server 10.8.0.0 255.255.255.0/server $OPENVPN_SERVER_NET $OPENVPN_MASK/" /etc/openvpn/server.conf
sed -i "143 i\push \"route $VNET $VNET_MASK\"" /etc/openvpn/server.conf
sed -i '245s/^/;/' /etc/openvpn/server.conf
sed -i '253s/^/;/' /etc/openvpn/server.conf
## Enable Compression lzo for backward compatibility
sed -i '264s/;//' /etc/openvpn/server.conf
##
sed -i '275s/;//' /etc/openvpn/server.conf
sed -i '276s/;//' /etc/openvpn/server.conf
sed -i '316s/^/;/' /etc/openvpn/server.conf
systemctl enable openvpn@server >> ${LOG_FILE} 2>&1
echo "## End OpenVPN Configuration ##" >> ${LOG_FILE}

echo "## Start Firewalld Configuration ##" >> ${LOG_FILE}
systemctl start firewalld.service >> ${LOG_FILE} 2>&1
sed -i "s/1194/443/" /usr/lib/firewalld/services/openvpn.xml
sed -i "s/udp/tcp/" /usr/lib/firewalld/services/openvpn.xml
firewall-cmd --zone=external --add-service=openvpn --permanent >> ${LOG_FILE} 2>&1
firewall-cmd --zone=external --change-interface=eth0 >> ${LOG_FILE} 2>&1
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
systemctl enable firewalld.service >> ${LOG_FILE} 2>&1
echo "## End Firewalld Configuration ##" >> ${LOG_FILE}

echo "## OpenVPN Client Certificate Generation ##" >> ${LOG_FILE}
cd /etc/openvpn/rsa/
source ./vars >> ${LOG_FILE} 2>&1
./build-key --batch client >> ${LOG_FILE} 2>&1
echo "## End OpenVPN Client Certificate Generation ##" >> ${LOG_FILE}

echo "## Install Azure CLI ##" >> ${LOG_FILE}
cd /root/
yum install -y gcc libffi-devel python-devel openssl-devel >> ${LOG_FILE} 2>&1
(curl -L https://aka.ms/InstallAzureCli > cli.sh) >> ${LOG_FILE} 2>&1
chmod 755 cli.sh 
sed -i '33s/^/#/' /root/cli.sh
echo 'echo -ne "\n\nn\n"  | $install_script' >> /root/cli.sh
./cli.sh >> ${LOG_FILE} 2>&1
echo "## Azure CLI Installed ##" >> ${LOG_FILE}

echo "## Upload Certificate to Blob ##" >> ${LOG_FILE}
/root/bin/az storage blob upload --file /etc/openvpn/rsa/keys/ca.crt --container-name $BLOB_CONTAINER_NAME --name ca.crt --account-name $BLOB_ACCOUNT_NAME --account-key $BLOB_ACCOUNT_KEY >> ${LOG_FILE} 2>&1
/root/bin/az storage blob upload --file /etc/openvpn/rsa/keys/client.crt --container-name $BLOB_CONTAINER_NAME --name client.crt --account-name $BLOB_ACCOUNT_NAME --account-key $BLOB_ACCOUNT_KEY >> ${LOG_FILE} 2>&1
/root/bin/az storage blob upload --file /etc/openvpn/rsa/keys/client.key --container-name $BLOB_CONTAINER_NAME --name client.key --account-name $BLOB_ACCOUNT_NAME --account-key $BLOB_ACCOUNT_KEY >> ${LOG_FILE} 2>&1
echo "## End Upload Certificate to Blob ##" >> ${LOG_FILE}

echo "## Create Client Config File and Upload to Blob ##" >> ${LOG_FILE}
cd /root/
echo "client" >> client.ovpn
echo "dev tun" >> client.ovpn
echo "proto tcp" >> client.ovpn
echo "## Change 0.0.0.0 IP with OpenVPN server public IP ##" >> client.ovpn
echo "remote 0.0.0.0 $OPENVPN_PORT" >> client.ovpn
echo "resolv-retry infinite" >> client.ovpn
echo "nobind" >> client.ovpn
echo "persist-key" >> client.ovpn
echo "persist-tun" >> client.ovpn
echo "ca ca.crt" >> client.ovpn
echo "cert client.crt" >> client.ovpn
echo "key client.key" >> client.ovpn
echo "comp-lzo" >> client.ovpn
echo "verb 3" >> client.ovpn
/root/bin/az storage blob upload --file /root/client.ovpn --container-name $BLOB_CONTAINER_NAME --name client.ovpn --account-name $BLOB_ACCOUNT_NAME --account-key $BLOB_ACCOUNT_KEY >> ${LOG_FILE} 2>&1
echo "## End Create Client Config File and Upload to Blob ##" >> ${LOG_FILE}

exit 0