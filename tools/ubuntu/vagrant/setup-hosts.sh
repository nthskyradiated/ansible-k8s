#!/bin/bash
# Set up /etc/hosts so we can resolve all the machines in the VirtualBox/Hyper-V network
set -e

THISHOST=$2
IFNAME=$1
NETWORK=$3

# Debugging starts here
echo "DEBUG: THISHOST=${THISHOST}"
echo "DEBUG: IFNAME=${IFNAME}"

if [ -z "$IFNAME" ]; then
    echo "Error: Could not determine the network interface. Exiting."
    exit 1
fi

# Get the primary IP associated with the interface
PRIMARY_IP=$(ip -4 addr show "$IFNAME" | grep "inet" | awk '{print $2}' | cut -d/ -f1)
echo "DEBUG: PRIMARY_IP=${PRIMARY_IP}"

if [ -z "$PRIMARY_IP" ]; then
    echo "Error: Could not determine the IP address for interface $IFNAME. Exiting."
    exit 1
fi

# Export PRIMARY IP as an environment variable
echo "PRIMARY_IP=${PRIMARY_IP}" >> /etc/environment

# Export architecture as environment variable to download correct versions of software
echo "ARCH=amd64" | sudo tee -a /etc/environment > /dev/null

# Remove any existing entries related to this host
sed -i "/^.*$THISHOST.*/d" /etc/hosts

cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ubuntu2204.localdomain

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters

${NETWORK}211 controlplane01
${NETWORK}212 controlplane02
${NETWORK}221 node01
${NETWORK}222 node02
${NETWORK}200 loadbalancer
EOF
