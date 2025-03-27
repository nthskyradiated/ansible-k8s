#!/usr/bin/env ruby

# Get project root directory (one level up from script location)
ROOT_DIR = File.expand_path('..', File.dirname(__FILE__))

# Read constants from Vagrantfile
vagrantfile = File.join(ROOT_DIR, "libvirt-vagrant", "Vagrantfile")
constants = {}
File.readlines(vagrantfile).each do |line|
  if line =~ /^(NUM_CONTROL_NODES|NUM_WORKER_NODE|MASTER_IP_START|NODE_IP_START|LB_IP_START)\s*=\s*(\d+)/
    constants[$1] = $2.to_i
  end
end

# Update inventory path to point to project root
inventory_path = File.join(ROOT_DIR, "inventory")
dir = File.dirname(inventory_path)
Dir.mkdir(dir) unless Dir.exist?(dir)

inventory = ""
inventory << "[controlplanes]\n"
(1..constants["NUM_CONTROL_NODES"]).each do |i|
  inventory << format("controlplane%02d ansible_host=192.168.100.%d\n", i, constants["MASTER_IP_START"] + i)
end
inventory << "\n"

if constants["NUM_CONTROL_NODES"] >= 2
  inventory << "[loadbalancers]\n"
  inventory << format("loadbalancer ansible_host=192.168.100.%d\n\n", constants["LB_IP_START"])
end

inventory << "[workernodes]\n"
(1..constants["NUM_WORKER_NODE"]).each do |i|
  inventory << format("node%02d ansible_host=192.168.100.%d\n", i, constants["NODE_IP_START"] + i)
end

inventory << "\n"
# Add k8s_cluster group
inventory << "[k8s_cluster:children]\n"
inventory << "controlplanes\n"
inventory << "workernodes\n"
if constants["NUM_CONTROL_NODES"] >= 2
  inventory << "loadbalancers\n"
end

File.write(inventory_path, inventory)
puts "Dynamic inventory updated at #{inventory_path}"
