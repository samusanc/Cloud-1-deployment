# Cloud-1 — Azure Deployment

Infrastructure-as-code that provisions an Ubuntu VM on **Microsoft Azure** and
auto-deploys the [`cloud-1`](https://github.com/samusanc/cloud-1) WordPress stack
(WordPress + MySQL + nginx + phpMyAdmin, via Docker Compose) onto it — with no
manual steps after `apply`.

## How it works

```
deploy.sh
   │  1. clone/update github.com/samusanc/cloud-1   (app code)
   │  2. base64-encode ./.env  ->  TF_VAR_env
   │  3. terraform init / validate / plan / apply
   ▼
Terraform (Deployment/)  ── creates on Azure ──▶  Resource Group, VNet, Subnet,
   │                                              Public IP, NIC, NSG (22/80/443),
   │                                              Linux VM (Ubuntu 22.04)
   ▼
cloud-init (Deployment/user-data) runs on first boot:
   • installs docker + compose
   • clones samusanc/cloud-1 into /opt/repo
   • decodes TF_VAR_env into /opt/repo/docker/.env
   • runs docker/setup.sh  ->  brings up the stack
```

The site is then reachable at the VM's public IP.

## Prerequisites

| Tool | Notes |
|------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 | |
| `git` | |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | `az login` before deploying |
| `bash` | Git Bash or WSL on Windows |
| An **RSA** SSH key | Azure requires RSA. Create one if missing: `ssh-keygen -t rsa -b 4096` (produces `~/.ssh/id_rsa.pub`) |

Set your Azure subscription (required by the azurerm v4 provider):

```bash
az login
export ARM_SUBSCRIPTION_ID="<your-subscription-id>"
```

## Configuration

**1. Secrets — `.env`** (git-ignored)

```bash
cp .env.example .env
# edit .env and replace every CHANGE_ME value
```

`deploy.sh` base64-encodes this file into the Terraform `env` variable; the VM
decodes it into the stack's `docker/.env` at boot. For a real cloud deploy, set
`WP_URL` in `.env` to the VM's public IP or domain (not `localhost`).

**2. Terraform vars — `Deployment/terraform.tfvars`** (git-ignored, kept locally)

```hcl
location      = "spaincentral"
address_space = ["10.0.0.0/16"]
# Optional — deploy N servers in parallel in one apply (default 1):
# vm_count    = 3
```

## Deploy

From the repo root:

```bash
bash deploy.sh          # full workflow: init -> validate -> plan -> apply
bash deploy.sh plan     # stop after plan (review only, no changes)
```

When it finishes, Terraform prints the VM's public IP:

```
Outputs:
public_ip_address = "20.x.x.x"
```

## Deploying from Azure Cloud Shell

[Cloud Shell](https://portal.azure.com/#cloudshell/) is already authenticated
(no `az login`) and ships Terraform + git, so you only need to expose the
subscription id. Full sequence:

```bash
# 1. Get the deployment repo
git clone https://github.com/samusanc/Cloud-1-deployment.git
cd Cloud-1-deployment

# 2. Subscription (azurerm v4 needs it explicitly; ACC_USER_SUBSCRIPTION also works)
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 3. Secrets
cp .env.example .env
nano .env                      # replace the CHANGE_ME values

# 4. Terraform vars  (git-ignored, so NOT in the clone — create it)
cat > Deployment/terraform.tfvars <<'EOF'
location      = "spaincentral"
address_space = ["10.0.0.0/16"]
EOF

# 5. RSA SSH key (Cloud Shell may not have one)
test -f ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# 6. Deploy
bash deploy.sh
```

Notes:
- **`terraform.tfvars` is git-ignored**, so it isn't in the clone — step 4 recreates it,
  or Terraform will prompt for `location`/`address_space`.
- **Cloud Shell sessions are ephemeral**: exported vars and files outside `$HOME`
  (clouddrive) are lost on timeout. Re-run the `export` when you return, or add it
  to `~/.bashrc` to make it persist.

## Access the deployed VM

```bash
# Web (self-signed TLS — accept the warning)
https://<public_ip>          # WordPress
https://<public_ip>/phpmyadmin/

# SSH as root (key-based — required by the eval)
ssh -i ~/.ssh/id_rsa root@<public_ip>

# SSH as the provisioning user (also key-based)
ssh -i ~/.ssh/id_rsa adminuser@<public_ip>

# Emergency fallback (only if EMERGENCY_USER was set in .env):
# a named sudo user that uses the SAME key as root — a break-glass account
ssh -i ~/.ssh/id_rsa <EMERGENCY_USER>@<public_ip>
```

Give root the identity the eval expects by putting your 42 login/email in the
key's comment: `ssh-keygen -t rsa -b 4096 -C "your-login@student.42.fr"`.

The Docker stack can take ~1–2 min after the VM boots (image pulls + DB init).

## Tear down

```bash
cd Deployment
terraform destroy
```

## Switching the app repo (samusanc ⇄ andresmejiaro)

The deployed app repo is referenced in **two** places (both marked with a
`>>> APP REPO <<<` comment):

1. `Deployment/user-data` — what the **VM** clones at boot (this is the one that
   actually matters for what gets deployed).
2. `deploy.sh` (`APP_REPO_URL`) — the local clone the script makes.

Change both to keep them consistent.

## Repo structure

```
.
├── deploy.sh                 # one-shot deploy wrapper
├── .env.example              # template for secrets  (committed)
├── .env                      # real secrets          (git-ignored)
└── Deployment/
    ├── providers.tf          # azurerm ~> 4.0
    ├── variables.tf          # location, env, address_space, tags
    ├── terraform.tfvars      # values                (git-ignored)
    ├── main.tf               # wires the modules together
    ├── outputs.tf            # public_ip_address
    ├── user-data             # cloud-init bootstrap
    └── modules/
        ├── resource_group/  virtual-network/  subnet/
        ├── public_ip/  network-interface/  virtual-machine/
        └── NSG/  NSG_Asociation/
```

## Troubleshooting

- **`plan` hangs, then errors on "ensuring Resource Providers are registered"
  (`context canceled` after Ctrl+C):** the provider was trying to auto-register
  Azure resource providers, which is slow and often not permitted on Cloud Shell /
  restricted subscriptions. Already handled — `providers.tf` sets
  `resource_provider_registrations = "none"`. If `apply` later says a specific
  provider isn't registered, register it once: `az provider register --namespace Microsoft.Network --wait`.
- **`terraform plan` → "No configuration files":** run it from inside `Deployment/`
  (the `.tf` files live there). `deploy.sh` handles this for you.

## Known limitations / hardening TODO

- **Secrets in state:** the `env` value lands in `terraform.tfstate` in plaintext.
  Use a remote backend with encryption (e.g. Azure Storage) and protect the state.
- **`terraform.tfvars` is git-ignored**, so `location`/`address_space` are not in
  the repo — keep your copy locally (a fresh clone will otherwise prompt).
- **VM image generation:** if Azure rejects `Standard_B2als_v2` with a Gen1 image,
  change the VM module's `sku` to `22_04-lts-gen2`.
- `Deployment/example.wtf` is an unused scratch file and can be deleted.

## Parallel deployment

Set `vm_count` (in `terraform.tfvars` or `-var vm_count=N`) to provision N servers
in a single `apply`; Terraform creates them concurrently. Each gets its own
public IP, NIC, and NSG association, with indexed names
(`cloud-1-vm-<workspace>-<n>`). `terraform output public_ip_addresses` returns the
list of IPs. Deploying into a separate `terraform workspace` gives an independent
resource group, so you can also run fully isolated stacks side by side.
