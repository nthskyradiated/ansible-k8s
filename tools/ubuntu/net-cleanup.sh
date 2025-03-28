#!/bin/bash


resolved_conf_path="/etc/systemd/resolved.conf"

netplan_file="/etc/netplan/50-cloud-init.yaml"

new_dns="4.2.2.2 8.8.8.8"

# Update /etc/systemd/resolved.conf
if grep -q "\[Resolve\]" "$resolved_conf_path"; then
    sed -i "/\[Resolve\]/,/^$/ s/^DNS=.*/DNS=$new_dns/" "$resolved_conf_path"
else
    echo -e "[Resolve]\nDNS=$new_dns" >> "$resolved_conf_path"
fi

systemctl restart systemd-resolved

# Update the specific Netplan configuration file
if [ -f "$netplan_file" ]; then
    sed -i "s/dhcp4:.*/dhcp4: false/" "$netplan_file"
    sed -i "s/dhcp6:.*/dhcp6: false/" "$netplan_file"
else
    echo "Netplan configuration file not found: $netplan_file"
    exit 1
fi

netplan apply

echo "Changes applied successfully!"
