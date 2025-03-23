## Provision all VM's and the k8s cluster using only ansible.
* adjust the number of control planes and worker nodes in ./site.yaml
* run ansible
 ```bash
    ansible-playbook site.yml --ask-become-pass
```