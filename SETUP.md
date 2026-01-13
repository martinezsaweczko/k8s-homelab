# Kubernetes & Ceph Homelab Setup

This repository contains Ansible playbooks for automating the installation and configuration of Kubernetes and Ceph in a homelab environment.

## Project Structure

```
.
├── ansible.cfg              # Ansible configuration
├── inventories/             # Inventory files
│   └── hosts.example.yml    # Example inventory (copy to hosts.yml)
├── group_vars/              # Group-level variables
├── host_vars/               # Host-level variables
├── roles/                   # Ansible roles
│   ├── common/              # Common configurations for all hosts
│   ├── k8s-master/          # Kubernetes master setup
│   ├── k8s-worker/          # Kubernetes worker setup
│   ├── ceph-monitor/        # Ceph monitor setup
│   └── ceph-osd/            # Ceph OSD setup
└── playbooks/               # Main playbooks
    ├── site.yml             # Main orchestration playbook
    ├── kubernetes.yml       # Kubernetes setup
    └── ceph.yml             # Ceph setup
```

## Prerequisites

- Ansible 2.9+ installed on your control machine
- SSH access to all target hosts (key-based auth recommended)
- **Fedora 38+ or Ubuntu 20.04 LTS+ on target hosts**
- SSH key authentication configured (recommended)

### Supported Operating Systems

- ✅ Fedora 38, 39, 40+
- ✅ Ubuntu 20.04 LTS, 22.04 LTS
- ✅ RHEL 8, 9 (with dnf support)
- ✅ CentOS Stream 9+

**Note**: This project uses `dnf` for Fedora/RHEL and `apt` for Ubuntu/Debian. Ensure your target OS is one of the above.

### SSH Setup (Recommended)

If you haven't set up SSH key authentication yet:

```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copy key to your host
ssh-copy-id -i ~/.ssh/id_ed25519 david@172.26.32.240

# Verify SSH key auth works
ssh -i ~/.ssh/id_ed25519 david@172.26.32.240 "hostname"
```

Then add to your inventory or use SSH agent:
```bash
# Add key to SSH agent
ssh-add ~/.ssh/id_ed25519

# Verify key is loaded
ssh-add -l
```

## Initial Setup

### 1. Clone and Configure

```bash
git clone <repo-url> k8s-homelab
cd k8s-homelab
```

### 2. Create Inventory

```bash
cp inventories/hosts.example.yml inventories/hosts.yml
# Edit inventories/hosts.yml with your target hosts
```

### 3. Install Ansible

```bash
pip install ansible
# or on Fedora:
sudo dnf install ansible
# or on Ubuntu/Debian:
sudo apt install ansible
```

## Using GitHub Secrets for Sensitive Data

### 1. Create Vault Password

Store your Ansible vault password as a GitHub Secret:

```bash
# Generate a random password
openssl rand -base64 32 > .vault-pass

# Add to GitHub Secrets as 'VAULT_PASSWORD'
```

### 2. Encrypt Sensitive Variables

```bash
# Create encrypted vault files
ansible-vault create group_vars/all/vault.yml --vault-password-file .vault-pass

# Add your secrets (passwords, API keys, etc.):
# vault_ssh_password: your_password
# vault_ceph_admin_key: your_key
```

### 3. Configure GitHub Actions (CI/CD)

Add this to your GitHub Actions workflow to use the vault password:

```yaml
env:
  VAULT_PASSWORD: ${{ secrets.VAULT_PASSWORD }}

script: |
  echo "$VAULT_PASSWORD" > /tmp/.vault-pass
  ansible-playbook playbooks/site.yml --vault-password-file /tmp/.vault-pass
  rm /tmp/.vault-pass
```

### 4. Reference Encrypted Variables

In your playbooks, reference vault variables:

```yaml
- name: Example task
  command: sudo -u user whoami
  vars:
    ansible_become_pass: "{{ vault_ssh_password }}"
  when: vault_ssh_password is defined
```

## Running Playbooks

### Syntax Check

```bash
ansible-playbook playbooks/site.yml --syntax-check
```

### Dry Run

```bash
ansible-playbook playbooks/site.yml --check
```

### Full Run (with vault)

```bash
ansible-playbook playbooks/site.yml --vault-password-file .vault-pass
# or interactively:
ansible-playbook playbooks/site.yml --ask-vault-pass
```

### Run Specific Tags

```bash
ansible-playbook playbooks/site.yml --tags "kubernetes" --vault-password-file .vault-pass
```

## Best Practices

1. **Never commit secrets** - Use `.gitignore` to exclude:
   - `.vault-pass`
   - `vault.yml` files
   - `.env` files

2. **Use GitHub Secrets** - Store:
   - Vault password
   - SSH keys (as base64 in secrets)
   - API credentials

3. **Version Control**
   - Commit `.example` files as templates
   - Include encrypted vault files (safe to commit)
   - Exclude plaintext secrets

4. **Testing**
   - Use `--check` mode before running
   - Test on non-production first
   - Use version tags for releases

## Troubleshooting

### SSH Connection Issues

**Permission denied (publickey):**
```bash
# Option 1: Use SSH key (recommended)
ansible all -i inventories/hosts.yml -m ping --vault-password-file .vault-pass \
  -e ansible_ssh_private_key_file=~/.ssh/id_ed25519

# Option 2: Add key to SSH agent
ssh-add ~/.ssh/id_ed25519
ansible all -i inventories/hosts.yml -m ping --vault-password-file .vault-pass

# Option 3: Use password + sudo password
ansible all -i inventories/hosts.yml -m ping --vault-password-file .vault-pass -k -K
# -k = SSH password prompt
# -K = sudo password prompt
```

**With specific user:**
```bash
ansible all -i inventories/hosts.yml -u david -m ping --vault-password-file .vault-pass
```

### Vault Password Issues
```bash
# If you get "Attempting to decrypt but no vault secrets found":
# You need to provide the vault password with --vault-password-file or --ask-vault-pass

# With vault password file
ansible all -i inventories/hosts.yml -m ping --vault-password-file .vault-pass

# Or prompt for password interactively
ansible all -i inventories/hosts.yml -m ping --ask-vault-pass

# If vault errors occur, verify password is correct:
ansible all --vault-password-file .vault-pass -i inventories/hosts.yml -m ping
```

### "Missing sudo password" Error
```bash
# You need to provide sudo password with -K flag
ansible all -i inventories/hosts.yml -m ping --vault-password-file .vault-pass -k -K

# Or better: setup SSH key and add to sudoers NOPASSWD
# On target host:
# sudo visudo
# Add line: david ALL=(ALL) NOPASSWD:ALL
```

### Debug Mode
```bash
ansible-playbook playbooks/site.yml -vvv --vault-password-file .vault-pass
```

## CI/CD with GitHub Actions

Example workflow for automated deployment:

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - run: pip install ansible

      - name: Run playbooks
        env:
          VAULT_PASSWORD: ${{ secrets.VAULT_PASSWORD }}
        run: |
          echo "$VAULT_PASSWORD" > /tmp/.vault-pass
          ansible-playbook playbooks/site.yml --vault-password-file /tmp/.vault-pass
          rm /tmp/.vault-pass
```

## Contributing

1. Create a feature branch
2. Test changes with `--check` mode
3. Submit PR with description
4. Ensure ansible-lint passes

## License

See LICENSE file
