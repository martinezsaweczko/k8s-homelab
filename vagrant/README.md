Vagrant test environment for k8s-homelab

Overview
--------
This folder contains a simple Vagrant setup to create 3 Fedora VMs for testing the playbooks locally.
- Default box: generic/fedora38 (override with VAGRANT_BOX)
- Default private subnet: 192.168.56.0 (override with VAGRANT_SUBNET)
- Default addresses: 192.168.56.101, .102, .103
- Default user/password on each VM: david / PWD

Files
-----
- Vagrantfile: creates 3 VMs (node1,node2,node3) and sets private IPs
- provision.sh: extra provisioning helper (optional)
- hosts.ini: Ansible inventory for the 3 VMs (for quick testing)

Commands
--------
1) Start VMs

# Start all vagrant VMs using VirtualBox (default provider)
vagrant up --provider=virtualbox

# If you want to change box or subnet, set env vars before up:
# VAGRANT_BOX=generic/fedora38 VAGRANT_SUBNET=192.168.50 vagrant up

2) Inspect VMs and get SSH config

vagrant status
vagrant ssh node1
vagrant ssh-config > ssh-config  # optional: creates an SSH config you can reuse

3) Use the provided Ansible inventory to run the playbook

# Example: run the main site playbook against the Vagrant hosts
ansible-playbook -i vagrant/hosts.ini playbooks/site.yml --private-key ~/.vagrant.d/insecure_private_key

# If you prefer to pass the user explicitly:
ansible-playbook -i vagrant/hosts.ini -u david --private-key ~/.vagrant.d/insecure_private_key playbooks/site.yml

Notes & tips
------------
- The provision step copies the vagrant user's authorized_keys into david's home, so the default Vagrant insecure private key (~/.vagrant.d/insecure_private_key) can be used to SSH as david.
- If you want to SSH with password (david/PWD), we enabled PasswordAuthentication in sshd (not required if using private key).
- The `hosts.ini` maps groups used by the playbooks (ceph_monitors, ceph_osds, k8s_masters, k8s_workers). Edit as needed.
- Each VM has an extra 20GB virtual disk attached as `/dev/sdb` (created in `vagrant/vagrant_disks`), which you can use for OSD testing. The playbook's OSD preparation tasks will detect and can use `/dev/sdb`.
- The Vagrant environment uses the default `vagrant` user and the insecure private key for initial SSH access; the `david` user (password `PWD`) is created during provisioning and receives the `vagrant` authorized key so you can later SSH as `david` using the same key.
- Default box is now `bento/fedora-38`, which is Vagrant-ready and includes the `vagrant` user and insecure key to avoid SSH authentication failures. You can override via: `VAGRANT_BOX=generic/fedora38 vagrant up` if desired.

Cleaning up
-----------
vagrant destroy -f

Feedback
--------
If you want additional customization (CPU/memory per VM, different Fedora version, different IP addressing, or creation of additional host_vars/group_vars tailored to the Vagrant nodes), tell me and I can add it.