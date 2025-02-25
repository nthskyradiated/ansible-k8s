#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error and exit immediately

# Function to display progress
echo_step() {
  echo -e "\033[1;34m[STEP]\033[0m $1"
}
echo_success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}
echo_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Detect architecture if not set
echo_step "updating package lists..."
ARCH=${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}
echo_success "Architecture detected: $ARCH"

# Download kubectl
echo_step "Downloading kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" --silent --show-error
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
echo_success "kubectl installed successfully."

# Download cilium
echo_step "Downloading cilium..."
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
echo_success "cilium installed successfully."

# Download Hubble
echo_step "Downloading Hubble..."
HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)
HUBBLE_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then HUBBLE_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/$HUBBLE_VERSION/hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
sha256sum --check hubble-linux-${HUBBLE_ARCH}.tar.gz.sha256sum
sudo tar xzvfC hubble-linux-${HUBBLE_ARCH}.tar.gz /usr/local/bin
rm hubble-linux-${HUBBLE_ARCH}.tar.gz{,.sha256sum}
echo_success "Hubble installed successfully."

# Set Kubernetes version
echo_step "Fetching Kubernetes version..."
KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
echo_success "Kubernetes version: $KUBE_VERSION"

# Download Kubernetes binaries
echo_step "Downloading Kubernetes binaries..."
for binary in kube-apiserver kube-controller-manager kube-scheduler; do
  wget -q --https-only --timestamping "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/${binary}"
  chmod +x ${binary}
  sudo mv ${binary} /usr/local/bin/
  echo_success "$binary installed."
done

# Download and install etcd
echo_step "Installing etcd..."
ETCD_VERSION="v3.5.17"
wget -q --https-only --timestamping \
  "https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
tar -xvf etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz > /dev/null
sudo mv etcd-${ETCD_VERSION}-linux-${ARCH}/etcd* /usr/local/bin/
rm -rf etcd-${ETCD_VERSION}-linux-${ARCH} etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz
echo_success "etcd installed."

# Add Helm and HashiCorp repositories
echo_step "Adding Helm and HashiCorp repositories..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
wget -q -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo apt-get install -y apt-transport-https
echo_success "Repositories added."

echo_step "Updating package lists and installing packages..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
sudo apt-get update -q
sudo apt-get install -y terraform helm jq
echo_success "Packages installed: terraform, helm, jq."

# Verify installations
echo_step "Verifying installations..."
kubectl version --client --output=yaml && echo_success "kubectl verified."
calicoctl version && echo_success "calicoctl verified."
etcd --version && echo_success "etcd verified."
terraform -version && echo_success "terraform verified."
helm version --short && echo_success "helm verified."
jq --version && echo_success "jq verified."

echo_success "All tools installed successfully and are ready to use."

# Remaining steps...
echo_step "Configuring Kubernetes..."
CONTROL01=$(dig +short controlplane01 | head -n1)
LOADBALANCER=$(dig +short controlplane01 | head -n1)
NODE01=$(dig +short node01)
NODE02=$(dig +short node02)

SERVICE_CIDR=10.96.0.0/16
API_SERVICE=$(echo $SERVICE_CIDR | awk 'BEGIN {FS="."} ; { printf("%s.%s.%s.1", $1, $2, $3) }')
POD_CIDR=10.244.0.0/16

{
  # Create private key for CA
  openssl genrsa -out ca.key 2048

  # Create CSR using the private key
  openssl req -new -key ca.key -subj "/CN=KUBERNETES-CA/O=Kubernetes" -out ca.csr

  # Self sign the csr using its own private key
  openssl x509 -req -in ca.csr -signkey ca.key -CAcreateserial -out ca.crt -days 1000
}
{
  # Generate private key for admin user
  openssl genrsa -out admin.key 2048

  # Generate CSR for admin user. Note the OU.
  openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr

  # Sign certificate for admin user using CA servers private key
  openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out admin.crt -days 1000
}
{
  openssl genrsa -out kube-controller-manager.key 2048

  openssl req -new -key kube-controller-manager.key \
    -subj "/CN=system:kube-controller-manager/O=system:kube-controller-manager" -out kube-controller-manager.csr

  openssl x509 -req -in kube-controller-manager.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-controller-manager.crt -days 1000
}
{
  openssl genrsa -out kube-proxy.key 2048

  openssl req -new -key kube-proxy.key \
    -subj "/CN=system:kube-proxy/O=system:node-proxier" -out kube-proxy.csr

  openssl x509 -req -in kube-proxy.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-proxy.crt -days 1000
}
{
  openssl genrsa -out kube-scheduler.key 2048

  openssl req -new -key kube-scheduler.key \
    -subj "/CN=system:kube-scheduler/O=system:kube-scheduler" -out kube-scheduler.csr

  openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-scheduler.crt -days 1000
}
cat > openssl.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
IP.1 = ${API_SERVICE}
IP.2 = ${CONTROL01}
IP.3 = 127.0.0.1
EOF

{
  openssl genrsa -out kube-apiserver.key 2048

  openssl req -new -key kube-apiserver.key \
    -subj "/CN=kube-apiserver/O=Kubernetes" -out kube-apiserver.csr -config openssl.cnf

  openssl x509 -req -in kube-apiserver.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-apiserver.crt -extensions v3_req -extfile openssl.cnf -days 1000
}

cat > openssl-kubelet.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

{
  openssl genrsa -out apiserver-kubelet-client.key 2048

  openssl req -new -key apiserver-kubelet-client.key \
    -subj "/CN=kube-apiserver-kubelet-client/O=system:masters" -out apiserver-kubelet-client.csr -config openssl-kubelet.cnf

  openssl x509 -req -in apiserver-kubelet-client.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out apiserver-kubelet-client.crt -extensions v3_req -extfile openssl-kubelet.cnf -days 1000
}

cat > openssl-etcd.cnf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = ${CONTROL01}
IP.2 = 127.0.0.1
EOF

{
  openssl genrsa -out etcd-server.key 2048

  openssl req -new -key etcd-server.key \
    -subj "/CN=etcd-server/O=Kubernetes" -out etcd-server.csr -config openssl-etcd.cnf

  openssl x509 -req -in etcd-server.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out etcd-server.crt -extensions v3_req -extfile openssl-etcd.cnf -days 1000
}

{
  openssl genrsa -out service-account.key 2048

  openssl req -new -key service-account.key \
    -subj "/CN=service-accounts/O=Kubernetes" -out service-account.csr

  openssl x509 -req -in service-account.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial -out service-account.crt -days 1000
}
{
  kubectl config set-cluster k8s-cluster01 \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://${LOADBALANCER}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=/var/lib/kubernetes/pki/kube-proxy.crt \
    --client-key=/var/lib/kubernetes/pki/kube-proxy.key \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=k8s-cluster01 \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}
{
  kubectl config set-cluster k8s-cluster01 \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=/var/lib/kubernetes/pki/kube-controller-manager.crt \
    --client-key=/var/lib/kubernetes/pki/kube-controller-manager.key \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=k8s-cluster01 \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
{
  kubectl config set-cluster k8s-cluster01 \
    --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=/var/lib/kubernetes/pki/kube-scheduler.crt \
    --client-key=/var/lib/kubernetes/pki/kube-scheduler.key \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=k8s-cluster01 \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
{
  kubectl config set-cluster k8s-cluster01 \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=k8s-cluster01 \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

{
  sudo mkdir -p /var/lib/kubernetes/
  sudo mv encryption-config.yaml /var/lib/kubernetes/
} 

# Node array for iteration
declare -A NODES
NODES["node01"]="${NODE01}"
NODES["node02"]="${NODE02}"

# Loop over each node to generate the necessary files and copy them
for node in "${!NODES[@]}"; do
  ip="${NODES[$node]}"

  # Create the OpenSSL configuration file
  cat > "openssl-${node}.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${node}
IP.1 = ${ip}
EOF

  # Generate key, CSR, and certificate for the current node
  openssl genrsa -out "${node}.key" 2048
  openssl req -new -key "${node}.key" -subj "/CN=system:node:${node}/O=system:nodes" -out "${node}.csr" -config "openssl-${node}.cnf"
  openssl x509 -req -in "${node}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${node}.crt" -extensions v3_req -extfile "openssl-${node}.cnf" -days 1000

  # Create the kubeconfig file for the current node
  kubeconfig_file="${node}.kubeconfig"
  {
    kubectl config set-cluster k8s-cluster01 \
      --certificate-authority=/var/lib/kubernetes/pki/ca.crt \
      --server=https://${LOADBALANCER}:6443 \
      --kubeconfig=${kubeconfig_file}

    kubectl config set-credentials system:node:${node} \
      --client-certificate=/var/lib/kubernetes/pki/${node}.crt \
      --client-key=/var/lib/kubernetes/pki/${node}.key \
      --kubeconfig=${kubeconfig_file}

    kubectl config set-context default \
      --cluster=k8s-cluster01 \
      --user=system:node:${node} \
      --kubeconfig=${kubeconfig_file}

    kubectl config use-context default --kubeconfig=${kubeconfig_file}
  }

  # Copy files to the node
  scp -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa "${node}.key" "${node}.crt" "${node}.csr" "${node}.kubeconfig" "kube-proxy.kubeconfig" "ca.crt" "kube-proxy.crt" "kube-proxy.key" vagrant@"${ip}":~/
done

{
  sudo mkdir -p /etc/etcd /var/lib/etcd /var/lib/kubernetes/pki
  sudo cp etcd-server.key etcd-server.crt /etc/etcd/
  sudo cp ca.crt /var/lib/kubernetes/pki/
  sudo chown root:root /etc/etcd/*
  sudo chmod 600 /etc/etcd/*
  sudo chown root:root /var/lib/kubernetes/pki/*
  sudo chmod 600 /var/lib/kubernetes/pki/*
  sudo ln -s /var/lib/kubernetes/pki/ca.crt /etc/etcd/ca.crt
}

ETCD_NAME=$(hostname -s)

cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/etcd-server.crt \\
  --key-file=/etc/etcd/etcd-server.key \\
  --peer-cert-file=/etc/etcd/etcd-server.crt \\
  --peer-key-file=/etc/etcd/etcd-server.key \\
  --trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-trusted-ca-file=/etc/etcd/ca.crt \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${PRIMARY_IP}:2380 \\
  --listen-peer-urls https://${PRIMARY_IP}:2380 \\
  --listen-client-urls https://${PRIMARY_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${PRIMARY_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controlplane01=https://${CONTROL01}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

{
  sudo systemctl daemon-reload
  sudo systemctl enable etcd
  sudo systemctl start etcd
}

{
  sudo mkdir -p /var/lib/kubernetes/pki

  # Only copy CA keys as we'll need them again for workers.
  sudo cp ca.crt ca.key /var/lib/kubernetes/pki
  for c in kube-apiserver service-account apiserver-kubelet-client etcd-server kube-scheduler kube-controller-manager
  do
    sudo mv "$c.crt" "$c.key" /var/lib/kubernetes/pki/
  done
  sudo chown root:root /var/lib/kubernetes/pki/*
  sudo chmod 600 /var/lib/kubernetes/pki/*
}

cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${PRIMARY_IP} \\
  --allow-privileged=true \\
  --apiserver-count=2 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --enable-admission-plugins=NodeRestriction,ServiceAccount \\
  --enable-bootstrap-token-auth=true \\
  --etcd-cafile=/var/lib/kubernetes/pki/ca.crt \\
  --etcd-certfile=/var/lib/kubernetes/pki/etcd-server.crt \\
  --etcd-keyfile=/var/lib/kubernetes/pki/etcd-server.key \\
  --etcd-servers=https://${CONTROL01}:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/pki/ca.crt \\
  --kubelet-client-certificate=/var/lib/kubernetes/pki/apiserver-kubelet-client.crt \\
  --kubelet-client-key=/var/lib/kubernetes/pki/apiserver-kubelet-client.key \\
  --runtime-config=api/all=true \\
  --service-account-key-file=/var/lib/kubernetes/pki/service-account.crt \\
  --service-account-signing-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-account-issuer=https://${LOADBALANCER}:6443 \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/pki/kube-apiserver.crt \\
  --tls-private-key-file=/var/lib/kubernetes/pki/kube-apiserver.key \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --allocate-node-cidrs=true \\
  --authentication-kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --authorization-kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --bind-address=127.0.0.1 \\
  --client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --cluster-cidr=${POD_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/var/lib/kubernetes/pki/ca.key \\
  --controllers=*,bootstrapsigner,tokencleaner \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --node-cidr-mask-size=24 \\
  --requestheader-client-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --root-ca-file=/var/lib/kubernetes/pki/ca.crt \\
  --service-account-private-key-file=/var/lib/kubernetes/pki/service-account.key \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/

cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/var/lib/kubernetes/kube-scheduler.kubeconfig \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 600 /var/lib/kubernetes/*.kubeconfig

{
  sudo systemctl daemon-reload
  sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
}

{

  kubectl config set-cluster k8s-cluster01 \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://${LOADBALANCER}:6443

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key

  kubectl config set-context k8s-cluster01 \
    --cluster=k8s-cluster01 \
    --user=admin

  kubectl config use-context k8s-cluster01
}

echo_success "Kubernetes controlplane configured successfully."

# # Variables
# WORKER_NODES=("192.168.1.221" "192.168.1.222")  # Replace with actual worker node IPs

# # Add ECMP Routes to Service CIDR
# echo_step "Configuring ECMP routes for service CIDR..."
# EXISTING_ROUTE=$(ip route show $SERVICE_CIDR)

# if [[ -z "$EXISTING_ROUTE" ]]; then
#     echo "Adding ECMP route at runtime..."
#     sudo ip route add $SERVICE_CIDR \
#         nexthop via ${WORKER_NODES[0]} \
#         nexthop via ${WORKER_NODES[1]}
# else
#     echo "Route already exists: $EXISTING_ROUTE"
# fi

# # Persist ECMP Routes in /etc/network/interfaces.d/route-k8s (Debian/Ubuntu specific)
# ROUTE_CONFIG="/etc/network/interfaces.d/route-k8s"
# if [[ ! -f "$ROUTE_CONFIG" ]]; then
#     echo "Creating persistent route configuration at $ROUTE_CONFIG..."
#     sudo bash -c "cat > $ROUTE_CONFIG" <<EOL
# post-up ip route add $SERVICE_CIDR nexthop via ${WORKER_NODES[0]} nexthop via ${WORKER_NODES[1]}
# EOL
#     echo "Persistent route configuration created."
# else
#     echo "Persistent route configuration already exists at $ROUTE_CONFIG. Skipping creation."
# fi

# echo_success "ECMP route configuration complete."

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