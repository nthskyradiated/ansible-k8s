#!/bin/bash

# Update and upgrade system packages
sudo apt update -y && sudo apt upgrade -y

# Disable swap and configure system parameters for Kubernetes
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo rm -f /swapfile
sudo systemctl daemon-reexec

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay && sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Install necessary packages for containerd and Kubernetes
DEBIAN_FRONTEND=noninteractive sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Install and configure containerd
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update -y

DEBIAN_FRONTEND=noninteractive sudo apt install -y containerd.io

containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo sed -i '/sandbox_image/s|registry.k8s.io/pause:3.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd

# Add Kubernetes repository and install the latest kubeadm, kubelet, and kubectl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -y

KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/tags | jq -r '.[0].name' | cut -c 2-)

# Check if the version was fetched successfully
if [ -z "$KUBESEAL_VERSION" ]; then
    echo "Failed to fetch the latest KUBESEAL_VERSION"
    exit 1
fi

curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

DEBIAN_FRONTEND=noninteractive sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Check hostname and proceed with kubeadm init only on the master node
if [[ "$(hostname)" == "controlplane01" ]]; then
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16 \
    --service-cidr=10.96.0.0/16 \
    --control-plane-endpoint=192.168.1.211 \
    --skip-phases=addon/kube-proxy \
    --upload-certs | tee ~/kubeadm-init-output.txt
    # Configure kubectl for the master node
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    # Install Ciliium CNI
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    helm install cilium cilium/cilium --version 1.17.0-rc.0 --namespace kube-system -f cilium-values.yaml
    
    # Add Aliases to .bashrc
BASHRC="$HOME/.bashrc"
echo_step "Adding Kubernetes aliases to $BASHRC..."
ALIASES=$(cat << 'EOF'

# Kubernetes Aliases
alias k='kubectl'
alias kgp='kubectl get pod'
alias kgs='kubectl get svc'
alias kgsec='kubectl get secret'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kga='kubectl get all -A'
alias kd='kubectl describe'
alias kgn='kubectl get namespace'
alias kl='kubectl logs'
alias kgnet='kubectl get networkpolicies'
alias kdel='kubectl delete'
alias kgpv='kubectl get pv'
alias kgpvc='kubectl get pvc'
alias kdm='kubectl get daemonset'

EOF
)

if ! grep -q "alias k='kubectl'" "$BASHRC"; then
    echo "$ALIASES" >> "$BASHRC"
    echo "Aliases added to $BASHRC."
else
    echo "Aliases already exist in $BASHRC. Skipping addition."
fi

# Reload .bashrc to apply changes
echo_step "Reloading $BASHRC..."
source "$BASHRC"
echo_success "Script execution completed!"

else
    echo "This is not the control plane node. Script execution ends here."
    exit 0
fi