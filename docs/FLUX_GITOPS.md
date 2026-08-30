# Flux CD GitOps Setup & Troubleshooting

This guide covers the GitOps architecture, the manual workaround for the Flux bootstrap failure, and day-to-day operations.

## Architecture

```
Ansible (k8s-homelab)          GitOps (k8s-homelab-gitops)
├── OS / MicroK8s / Ceph  ──▶  ├── Apps (Deployments, Services)
├── Ceph CSI driver       ──▶  ├── Namespaces
└── Flux bootstrap        ──▶  └── Secrets (*.sops.yaml)
```

- **Infrastructure** (OS, MicroK8s snap, Ceph cluster, Ceph CSI) stays in Ansible
- **Workloads** (apps, namespaces, secrets) move to the GitOps repo
- Ceph CSI and StorageClass remain Ansible-managed

## Prerequisites

On your **admin machine** (the laptop/workstation where you run Ansible):

- `gh` CLI installed and authenticated (`gh auth login`)
- `age` installed automatically by the `k8s-master` role
- `sops` installed (from [releases](https://github.com/getsops/sops/releases))
- `kubectl` or `microk8s kubectl` configured for cluster access

## One-Time Setup (After Ansible Provisions the Cluster)

### Step 1: Verify the Age Key Exists

Ansible generates an Age keypair on your admin machine:

```bash
cat ~/.config/sops/age/keys.txt
```

You should see a public key (`age1...`) and a private key (`AGE-SECRET-KEY-1...`).

> **IMPORTANT:** Back up this file in your password manager (1Password, Bitwarden, etc.). If you lose it, all encrypted secrets in the GitOps repo are **unrecoverable**.

### Step 2: Handle Flux Bootstrap

The Ansible playbook attempts to run `flux bootstrap github`. If your GitHub organization has **Deploy Keys disabled**, this step will fail with:

```
POST https://api.github.com/repos/.../keys: 422 Validation Failed
  [{Resource:PublicKey Field: Code:custom Message:Deploy keys are disabled}]
```

This is expected and harmless. The playbook still creates:
- The `flux-system` namespace and controllers
- The `sops-age` Secret for SOPS decryption

You must complete the wiring manually:

#### 2a. Create the GitHub Token Secret in the Cluster

On the first master node:

```bash
export KUBECONFIG=/var/snap/microk8s/current/credentials/client.config
microk8s kubectl create secret generic github-token \
  --namespace=flux-system \
  --from-literal=username=git \
  --from-literal=password=<YOUR_GITHUB_PAT>
```

#### 2b. Create the GitRepository and Kustomization

```bash
cat <<EOF | microk8s kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k8s-homelab-gitops
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/martinezsaweczko/k8s-homelab-gitops
  ref:
    branch: main
  secretRef:
    name: github-token
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cluster
  namespace: flux-system
spec:
  interval: 1m
  path: ./cluster
  prune: true
  sourceRef:
    kind: GitRepository
    name: k8s-homelab-gitops
    namespace: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-age
EOF
```

#### 2c. Verify Flux is Reconciling

```bash
microk8s kubectl get kustomization -n flux-system cluster
# Should show READY=True
```

### Step 3: Clone the GitOps Repo and Add `.sops.yaml`

On your admin machine:

```bash
git clone https://github.com/martinezsaweczko/k8s-homelab-gitops.git
cd k8s-homelab-gitops
```

Extract the Age public key:

```bash
AGE_KEY=$(grep "Public key" ~/.config/sops/age/keys.txt | awk '{print $3}')
```

Create the SOPS config:

```bash
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: cluster/.*\.sops\.yaml$
    age: $AGE_KEY
EOF
```

Commit and push:

```bash
git add .sops.yaml
git commit -m "chore: add sops creation rules"
git push
```

## Day-to-Day Operations

### Adding a New Application

1. Create a directory: `cluster/apps/homelab/<app-name>/`
2. Add manifests (Deployment, Service, PVC, etc.)
3. If you have Secrets, encrypt them as `*.sops.yaml` (see below)
4. Add the directory to `cluster/apps/homelab/kustomization.yaml`
5. Commit and push — Flux deploys automatically within ~1 minute

### Encrypting a Secret with SOPS

```bash
# Create a plaintext Secret
cat > secret.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  password: my-secret-value
EOF

# Rename to .sops.yaml convention
mv secret.yaml secret.sops.yaml

# Encrypt (uses .sops.yaml in the repo root)
sops --encrypt --in-place secret.sops.yaml

# Verify only values are encrypted
cat secret.sops.yaml
```

### Editing an Encrypted Secret

```bash
sops secret.sops.yaml
```

This opens your `$EDITOR` with the decrypted contents. Save and exit to re-encrypt automatically.

### Force Reconciliation

If you need immediate deployment instead of waiting for the 1-minute poll:

```bash
# Force GitRepository to pull
microk8s kubectl annotate --overwrite gitrepository k8s-homelab-gitops \
  -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)"

# Force Kustomization to apply
microk8s kubectl annotate --overwrite kustomization cluster \
  -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)"
```

## How Decryption Works in the Cluster

The `sops-age` Secret in `flux-system` contains the Age private key. The Kustomization controller uses it to decrypt `*.sops.yaml` files during reconciliation. The private key **never** leaves the cluster and **never** enters Git.

## Disaster Recovery

If the cluster is completely rebuilt:

1. Run the Ansible playbooks (`playbooks/site.yml`)
2. Follow the manual Flux wiring steps above
3. The cluster pulls the GitOps repo and self-heals to the current desired state
