## Provision all VM's and the k8s cluster using only ansible.

* Adjust the number of control planes and worker nodes in ./site.yaml:
```yaml
vars:
  control_planes: 2
  worker_nodes: 2
```

* Run ansible with your sudo password:
```bash
ansible-playbook site.yml --ask-become-pass
```

The playbook will:
1. Create required VMs using libvirt
2. Configure networking and user access
3. Provision kubernetes cluster