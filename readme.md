# Ansible Kubernetes Local Cluster Provisioning

A lightweight and opinionated alternative to Kubespray for provisioning production-grade Kubernetes clusters locally using **kubeadm**. This simplifies cluster deployment with Ansible automation while maintaining production-ready configurations.

## Deployment Methods

Choose one of the following methods based on environment:

- **Vagrant on Hyper-V** (using WSL)
- **Vagrant on Libvirt** (RPM-based distros with older libvirt versions)
- **Pure Ansible** (Recommended for newer RPM-based distributions)

## Important Note for Newer RPM-Based Distributions

⚠️ **Vagrant with the Libvirt provider does NOT work on newer RPM-based distributions** (RHEL 10, AlmaLinux 10, Rocky Linux 10, etc.) due to the current vagrant-libvirt plugin being outdated and incompatible with newer libvirt versions.

- ✅ **Fully tested and working on RHEL 9, AlmaLinux 9, Rocky Linux 9** and similar distros
- **Recommended workaround for RHEL 10+ systems**: Use the **pure Ansible method** instead, which works on newer distros

## Prerequisites

### General Requirements
- Ansible installed on your system
- Vagrant installed (if using Vagrant methods)

### Linux-Specific Requirements
- **Libvirt** and **QEMU** installed (for libvirt-based deployments)
- **Vagrant Libvirt provider** installed (for Vagrant + Libvirt method)
  - Documentation: https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html

### Windows/WSL-Specific Requirements
- **Hyper-V** enabled
- Vagrant accessible from WSL environment

### Known Issues
- ⚠️ Vagrant versions **later than 2.4.5** have issues with the Hyper-V provider
- **Recommendation**: Stick to Vagrant **2.4.5** until resolved
- Reference: https://github.com/hashicorp/vagrant/issues/13676

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/nthskyradiated/ansible-k8s
cd ansible-k8s
```

### 2. Configure Your Deployment

#### For Hyper-V Deployment
- Ensure a bridge network is already created in Hyper-V
- Adjust variables in the Hyper-V `Vagrantfile`:
  - `RAM_SIZE` - Memory allocation per VM
  - `CPU_CORES` - CPU cores per VM
  - `NUM_CONTROL_NODES` - Number of control plane nodes
  - Other relevant configuration options

#### For Libvirt-Vagrant Deployment (RHEL 9-based systems)
- Adjust variables in the Libvirt `Vagrantfile`:
  - `RAM_SIZE` - Memory allocation per VM
  - `CPU_CORES` - CPU cores per VM
  - `NUM_CONTROL_NODES` - Number of control plane nodes
  - Other relevant configuration options

#### For Pure Ansible Deployment (Recommended for RHEL 10+ systems)
- Variables are stored in `./pure-ansible/group_vars/all.yaml`
- Generate SSH keys and store them in the `./pure-ansible` folder:
  ```bash
  ssh-keygen -t ed25519 -f ./pure-ansible/id_ed25519 -N ""
  ```

### 3. Update Hosts File

Add VM IP addresses to your `/etc/hosts` file before deployment:

```bash
# Add these entries to /etc/hosts
192.168.100.211 controlplane01
192.168.100.221 node01
192.168.100.222 node02
# Adjust IPs based on your configuration
```

### 4. Deploy the Cluster

Navigate to your chosen deployment method directory and run the appropriate command:

#### Hyper-V Deployment
```bash
cd hyperv-vagrant
export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
vagrant up --provider=hyperv
```

#### Libvirt-Vagrant Deployment (RHEL 9-based systems)
```bash
cd libvirt-vagrant
vagrant up --provider=libvirt
```

#### Pure Ansible Deployment (All platforms, recommended for RHEL 10+)
```bash
cd pure-ansible
ansible-playbook site.yaml --ask-become-pass
```

### 5. Access Your Cluster

Once provisioning finishes:

1. **Kubeconfig is automatically configured** on your local machine at `~/.kube/config`

2. **Verify cluster access**:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

3. **(Optional) Retrieve kubeadm join command** if needed later:
   ```bash
   ssh your-username@controlplane01
   cat ~/kubeadm-init-output.txt
   ```

4. **Join additional nodes** by SSHing to each node and running the kubeadm join command from the output file

## Deployment Defaults

### Infrastructure
- **OS**: Ubuntu 24.04 LTS
- **Container Runtime**: Containerd
- **CNI**: Cilium
- **Load Balancer**: HAProxy (auto-provisioned for multi-master setups)
- **Provisioning Tool**: kubeadm

### Networking
- **Libvirt**: Uses subnet `192.168.100.0/24`
- **Hyper-V**: Depends on your network configuration

### Tools Installed
- Terraform
- Helm
- jq
- kubeseal
- Hubble
- Cilium CLI

### Network Configuration Notes
- **Libvirt deployment**: Fully automated, no manual intervention required
- **Hyper-V deployment**: You must manually select a network interface for each VM*

  *See Hyper-V limitations: https://developer.hashicorp.com/vagrant/docs/providers/hyperv/limitations

## Customization

### Cilium Configuration
Cilium is provisioned via Helm. You can modify its values in:
```
./tools/ubuntu/cilium-values.yaml
```

Add, remove, or modify Cilium features according to your requirements.

## Troubleshooting

### Vagrant Libvirt Not Working on RHEL 10+
If you encounter issues with vagrant-libvirt on newer RPM-based distributions (RHEL 10, AlmaLinux 10, Rocky Linux 10, etc.), use the pure Ansible method instead. This is a known compatibility issue with newer libvirt versions.

### Network Connectivity Issues

#### Check NAT and iptables Configuration
If VMs cannot reach the internet or communicate with the host:

1. **Verify NAT rules**:
   ```bash
   sudo iptables -t nat -L -n -v
   ```

2. **Check if MASQUERADE rule exists** for your VM subnet:
   ```bash
   sudo iptables -t nat -L POSTROUTING -n -v | grep 192.168.100.0
   ```

3. **Add MASQUERADE rule if missing** (adjust interface name and subnet as needed):
   ```bash
   # Replace wlp0s20f3 with your actual network interface (use 'ip a' to find it)
   sudo iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o wlp0s20f3 -j MASQUERADE
   ```

4. **Enable IP forwarding**:
   ```bash
   echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
   # Make it persistent
   echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
   sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
   ```

5. **Verify libvirt network is active**:
   ```bash
   sudo virsh net-list --all
   sudo virsh net-start k8s-net  # If not active
   ```

#### Check Firewall Rules
```bash
# For firewalld (RHEL/Fedora)
sudo firewall-cmd --list-all
sudo firewall-cmd --zone=libvirt --add-masquerade --permanent
sudo firewall-cmd --reload

# For ufw (Ubuntu/Debian)
sudo ufw status
sudo ufw allow from 192.168.100.0/24
```

### Hyper-V Network Selection
If VMs fail to start on Hyper-V, ensure you've created a virtual switch in Hyper-V Manager before running `vagrant up`.

### SSH Connection Issues
Ensure:
- SSH keys are properly configured in `pure-ansible` directory
- Firewall rules allow SSH connections
- VM IP addresses are reachable from your host
- SELinux is not blocking connections (check with `sudo ausearch -m avc -ts recent`)

### Cluster Not Initializing
If kubeadm init fails:
```bash
# Check kubelet logs
sudo journalctl -xeu kubelet

# Verify container runtime is running
sudo systemctl status containerd

# Check if required ports are available
sudo ss -tulpn | grep -E ':(6443|2379|2380|10250|10251|10252)'
```

## Contributing

Issues and pull requests are welcome: https://github.com/nthskyradiated/ansible-k8s
