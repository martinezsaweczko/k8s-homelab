# K8s Homelab - Kubernetes & Ceph Ansible Automation

Automated installation and configuration of Kubernetes and Ceph clusters using Ansible with GitHub Secrets integration for secure credential management.

**Supports**: Fedora 38+, Ubuntu 20.04 LTS+, RHEL 8+

## Quick Start

1. **Clone the repository and configure inventory:**
   ```bash
   cp inventories/hosts.example.yml inventories/hosts.yml
   # Edit with your target hosts
   ```

2. **Set up Ansible vault for secrets:**
   ```bash
   ansible-vault create group_vars/all/vault.yml
   # Add your sensitive data (passwords, keys, etc.)
   ```

3. **Run the main playbook:**
   ```bash
   ansible-playbook playbooks/site.yml --vault-password-file .vault-pass
   ```

## Features

- ✅ Modular role-based architecture
- ✅ GitHub Secrets integration for secure credential management
- ✅ Separate Kubernetes and Ceph installation playbooks
- ✅ Environment-specific variables (group_vars, host_vars)
- ✅ **Multi-OS support**: Fedora, Ubuntu, RHEL
- ✅ CI/CD ready with GitHub Actions workflow

## Documentation

See [SETUP.md](SETUP.md) for detailed setup and usage instructions.

## Directory Structure

- **playbooks/** - Main orchestration playbooks
- **roles/** - Reusable Ansible roles for different components
- **inventories/** - Host inventory configurations
- **group_vars/** - Group-level variables
- **host_vars/** - Host-specific variables

## GitHub Secrets Setup

For CI/CD pipelines, add these secrets in GitHub:

- `VAULT_PASSWORD` - Ansible vault password for encrypted variables
- `SSH_PRIVATE_KEY` - (Optional) SSH key for automation

See SETUP.md for detailed instructions.

## Requirements

- Ansible 2.9+
- Python 3.7+
- SSH access to target hosts
- **Fedora 38+, Ubuntu 20.04 LTS+, or RHEL 8+ on target hosts**

## License

See LICENSE file


*For testing with 1 OSD*

 ceph osd pool set kubernetes size 1
Error EPERM: configuring pool size as 1 is disabled by default.
ceph config set global mon_allow_pool_size_one true
ceph osd pool set kubernetes size 1
Error EPERM: WARNING: setting pool size 1 could lead to data loss without recovery. If you are *ABSOLUTELY CERTAIN* that is what you want, pass the flag --yes-i-really-mean-it.
ceph osd pool set kubernetes size 1 --yes-i-really-mean-it
