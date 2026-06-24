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

## Access the deployed VM

```bash
# Web (self-signed TLS — accept the warning)
https://<public_ip>          # WordPress
https://<public_ip>/phpmyadmin/

# SSH (RSA key, admin user is "adminuser")
ssh -i ~/.ssh/id_rsa adminuser@<public_ip>
```

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

## Known limitations / hardening TODO

- **Secrets in state:** the `env` value lands in `terraform.tfstate` in plaintext.
  Use a remote backend with encryption (e.g. Azure Storage) and protect the state.
- **`terraform.tfvars` is git-ignored**, so `location`/`address_space` are not in
  the repo — keep your copy locally (a fresh clone will otherwise prompt).
- **VM image generation:** if Azure rejects `Standard_B2als_v2` with a Gen1 image,
  change the VM module's `sku` to `22_04-lts-gen2`.
- **Hardcoded resource names** (`example-machine`, `acceptanceTestPublicIp1`, …):
  fine for one VM per resource group; template them before scaling.
- `Deployment/example.wtf` is an unused scratch file and can be deleted.
