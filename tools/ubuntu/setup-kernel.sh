#!/bin/bash
#
# Sets up the kernel with the requirements for running Kubernetes
set -e

# Add required kernel modules if not already loaded
MODULES=(ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh br_netfilter nf_conntrack)

for module in "${MODULES[@]}"; do
    if ! lsmod | grep -q "^$module"; then
        modprobe $module
        echo "$module" >> /etc/modules
    fi
done

cat <<EOF > /etc/sysctl.d/10-kubernetes.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system
