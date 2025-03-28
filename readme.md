## Ansible Kubernetes Cluster Provisioning
### Provision a local kubernetes cluster with Ansible using one of the following methods:

- Vagrant on HyperV (*using WSL*)
- Vagrant on Libvirt (Linux)
- Using pure Ansible


### Clone the repo
```bash
git clone https://github.com/nthskyradiated/ansible-k8s
```

### Make necessary adjustments
 - For HyperV, make sure that a bridge network has already been created to used by the deployment.

 - Adjust the variables in the corresponding Vagrantfile (*RAM_SIZE, CPU_CORES, NUM_CONTROL_NODES, etc.*) 
- 
Just cd into one of the 3 folders and run command:
```bash
# for hyperV
vagrant up --provider=hyperv

# for libvirt-vagrant
vagrant up --provider=libvirt

# for pure Ansible
ansible-playbook site.yaml --ask-become-pass
```

### Some Defaults
 - Uses Cilium as Container Network Interface
 - Uses Containerd as Container runtime.
 - Installs Terraform, Helm, jq, and kubeseal, Hubble, Cilium cli.
 - By default, the libvirt deployment would use the network address 192.168.100.0/24 while hyperV would depend on your subnet.
 - Deploying on libvirt requires no intervention. **With hyperV, you would need to manually choose a network interface for each VM.*
 - A load balancer would be provisioned if you have more than one master node. It uses HAProxy for load balancing.


**https://developer.hashicorp.com/vagrant/docs/providers/hyperv/limitations*
