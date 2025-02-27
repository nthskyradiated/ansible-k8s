#!/bin/bash
echo "Waiting for all VMs to be fully up..."
sleep 30
echo "Running Ansible playbook..."
ansible-playbook -i ../inventory ../site.yaml --extra-vars 'ansible_ssh_pass=vagrant ansible_become_pass=vagrant'