## Ansible Kubernetes Local Cluster Provisioning
### Provision a local kubernetes cluster with Ansible using one of the following methods:

- Vagrant on HyperV (*using WSL*)
- Vagrant on Libvirt (Linux)
- Using pure Ansible

### Prerequisites
 - Make sure Ansible and Vagrant is installed.
 - Libvirt and Qemu should be installed if running on Linux.
 - Using Libvirt with Vagrant requires the Libvirt Vagrant provider to be installed. *Find the documentation here: https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html*
  
### Clone the repo
```bash
git clone https://github.com/nthskyradiated/ansible-k8s
```

### Make necessary adjustments
 - For HyperV, make sure that a bridge network has already been created to be used by the deployment.

 - Adjust the variables in the corresponding Vagrantfile (*RAM_SIZE, CPU_CORES, NUM_CONTROL_NODES, etc.*) 
 - For pure Ansible deployment, the variables are stored in `./pure-ansible/group_vars/all.yaml`.
  
 - Just cd into one of the 3 folders and run command:
```bash
# for hyperV
export VAGRANT_WSL_ENABLE_WINDOWS_ACCESS="1"
vagrant up --provider=hyperv

# for libvirt-vagrant
vagrant up --provider=libvirt

# for pure Ansible
ansible-playbook site.yaml --ask-become-pass
```

- Once the provision finishes, you can SSH to controlplane01 to get the kubeadm values from the home folder. (*Don't forget to add the VMs' IP addresses to your hosts file.*)
  ```bash
    ssh your-username@controlplane01

    cat ~/kubeadm-init-output.txt
  ```
- SSH to the rest of the nodes and use the command from the kubeadm-init-output.txt

### Some Defaults
 - Ubuntu VMs are used on all deployments.
 - Uses Cilium as Container Network Interface.
 - Uses Containerd as Container runtime.
 - Installs Terraform, Helm, jq, kubeseal, Hubble, Cilium cli.
 - By default, the libvirt deployment would use the subnet 192.168.100.0/24 while hyperV would depend entirely on your network configuration.
 - Deploying on libvirt requires no intervention. **With hyperV, you would need to manually choose a network interface for each VM.*
 - A load balancer would be provisioned if you have more than one master node. It uses HAProxy for load balancing.
- Cilium is provisioned by Helm. You can add/remove/modify some of its values. The yaml is found in `./tools/ubuntu/cilium-values.yaml`.

**https://developer.hashicorp.com/vagrant/docs/providers/hyperv/limitations*
