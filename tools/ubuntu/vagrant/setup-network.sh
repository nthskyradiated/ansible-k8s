#!/bin/bash

# Arguments: interface, IP address, gateway
INTERFACE=$1
IP_ADDRESS=$2
GATEWAY=$3
NETMASK="255.255.255.0"

echo "INTERFACE: $INTERFACE"
echo "IP_ADDRESS: $IP_ADDRESS"
echo "GATEWAY: $GATEWAY"


# Calculate CIDR prefix from the subnet mask
CIDR=$(echo $NETMASK | awk -F. '{print ($1>0)*8 + ($2>0)*8 + ($3>0)*8 + ($4>0)*8}')

# Generate a network configuration using netplan
cat <<EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - $IP_ADDRESS/$CIDR
      routes:
        - to: default
          via: $GATEWAY

EOF

sudo chmod 644 /etc/netplan/01-netcfg.yaml
sudo chmod 644 /etc/netplan/50-cloud-init.yaml

# cat <<EOF > /etc/netplan/00-installer-config.yaml
# network:
#   ethernets:
#     $INTERFACE:
#       dhcp4: false
#       dhcp6: false
#   version: 2

# EOF

netplan apply
