#!/bin/bash

# List of hostnames and IPs to remove from known_hosts
HOSTS=("controlplane01" "controlplane02" "node01" "node02" "loadbalancer")
IPS=("192.168.1.211" "192.168.1.212" "192.168.1.221" "192.168.1.222" "192.168.1.200")

# Remove hostnames
for HOST in "${HOSTS[@]}"; do
  ssh-keygen -R "$HOST" 2>/dev/null || true
done

# Remove IPs
for IP in "${IPS[@]}"; do
  ssh-keygen -R "$IP" 2>/dev/null || true
done

echo "Cleaned up SSH keys for: ${HOSTS[*]} and ${IPS[*]}"
