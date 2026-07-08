*This project has been created as part of the 42 curriculum by andresmejiaro, samusanc.*

# Cloud-1 — Automated Deployment of Inception

## Description

**Cloud-1** automatically deploys a containerized WordPress site — the same set of
services as the *Inception* project — onto a remote cloud server, with **no manual
steps** after launch.

This repository is the **infrastructure & automation** layer. [Terraform](https://www.terraform.io/)
provisions an **Ubuntu 22.04 LTS** virtual machine on **Microsoft Azure**, and
[cloud-init](https://cloudinit.readthedocs.io/) bootstraps it on first boot:
installs Docker, clones the application repository
([`samusanc/cloud-1`](https://github.com/samusanc/cloud-1)), and brings its Docker
Compose stack up. Each service runs in its own container (**1 process = 1
container**): WordPress, MySQL, nginx (TLS), and phpMyAdmin.

Key properties (mandatory requirements of the subject):

- **Fully automated** end to end — one command from empty subscription to running site.
- **Auto-restart** — services come back automatically if the server reboots.
- **Persistent data** — articles, users, and uploads survive reboots and container recreation (Docker named volumes).
- **Parallel deployment** — deploy N servers at once via a single `vm_count` variable.
- **Secure networking** — only ports **22, 80, 443** are open; MySQL and phpMyAdmin are not reachable on their native ports.
- **TLS** — nginx serves HTTPS and redirects HTTP → HTTPS.
- **No hard-coded secrets** — credentials live in a git-ignored `.env`, injected at deploy time.
- **Idempotent** — re-running the deployment converges to the same state (Terraform).

### Architecture

```
deploy.sh
   │  1. clone/update github.com/samusanc/cloud-1   (application code)
   │  2. base64-encode ./.env  ->  Terraform variable `env`
   │  3. terraform init / validate / plan / apply
   ▼
Terraform (Deployment/, modular)  ── on Azure ──▶  Resource Group, VNet, Subnet,
   │                                               Public IP, NIC, NSG (22/80/443),
   │                                               Linux VM (Ubuntu 22.04)   × vm_count
   ▼
cloud-init (Deployment/user-data) on first boot:
   • enables key-based root SSH login
   • installs docker + docker-compose
   • clones samusanc/cloud-1 into /opt/repo
   • writes docker/.env from the injected secrets, sets WP_URL to the public IP
   • runs docker/setup.sh  ->  brings the Compose stack up
```

## Instructions

### Prerequisites

| Tool | Notes |
|------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 | pre-installed in Azure Cloud Shell |
| `git`, `bash` | |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | `az login` (not needed in Cloud Shell) |
| An **RSA** SSH key | Azure `admin_ssh_key` requires RSA: `ssh-keygen -t rsa -b 4096 -C "your-login@student.42.fr"` |

### Deploy (recommended: Azure Cloud Shell)

Cloud Shell is already authenticated and ships Terraform + git.

```bash
# 1. Clone
git clone https://github.com/samusanc/Cloud-1-deployment.git
cd Cloud-1-deployment

# 2. Subscription (azurerm v4 requires it explicitly)
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 3. Secrets — copy the template and fill in real values
cp .env.example .env
nano .env

# 4. Terraform variables (git-ignored, so not in the clone — create it)
cat > Deployment/terraform.tfvars <<'EOF'
location      = "spaincentral"
address_space = ["10.0.0.0/16"]
# vm_count    = 3      # optional: deploy N servers in parallel
EOF

# 5. RSA key (Cloud Shell may not have one)
test -f ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# 6. Deploy  (init -> validate -> plan -> apply)
bash deploy.sh                 # 'bash deploy.sh plan' stops after plan
```

When it finishes, Terraform prints the server IP(s):

```
Outputs:
public_ip_addresses = ["20.x.x.x"]
```

The Docker stack takes ~1–2 min after the VM boots (image pulls + DB init).

### Configuration reference

- **`.env`** (git-ignored) — WordPress/MySQL credentials + optional `EMERGENCY_USER`. Template: `.env.example`.
- **`Deployment/terraform.tfvars`** (git-ignored) — `location`, `address_space`, optional `vm_count`.

### Usage — access the deployed server

```bash
# Web (self-signed TLS — accept the warning)
https://<public_ip>              # WordPress
https://<public_ip>/phpmyadmin/  # phpMyAdmin (reverse-proxied, login with MySQL creds)

# SSH as root (key-based — required by the evaluation)
ssh -i ~/.ssh/id_rsa root@<public_ip>

# Optional emergency sudo user (only if EMERGENCY_USER set in .env; same key as root)
ssh -i ~/.ssh/id_rsa <EMERGENCY_USER>@<public_ip>
```

### Parallel deployment

Set `vm_count` (in `terraform.tfvars` or `-var vm_count=N`) to provision N servers in
one `apply`; Terraform creates them concurrently, each with its own public IP, NIC, and
firewall association and indexed names (`cloud-1-vm-<workspace>-<n>`). A separate
`terraform workspace` gives an independent resource group for fully isolated stacks.

### Tear down (stop billing)

```bash
cd Deployment && terraform destroy
```

### Repository structure

```
.
├── deploy.sh                 # one-shot deploy wrapper
├── .env.example              # secrets template (committed)
├── evaluations-commands.txt  # quick command cheatsheet
└── Deployment/
    ├── providers.tf          # azurerm ~> 4.0
    ├── variables.tf          # location, env, address_space, vm_count, tags
    ├── main.tf               # wires the modules together
    ├── outputs.tf            # public_ip_addresses
    ├── user-data             # cloud-init bootstrap
    └── modules/              # resource_group, virtual-network, subnet, public_ip,
                              # network-interface, virtual-machine, NSG, NSG_Asociation
```

### Troubleshooting

- **`plan` hangs on "ensuring Resource Providers are registered":** handled — `providers.tf`
  sets `resource_provider_registrations = "none"`. If `apply` says a provider is missing:
  `az provider register --namespace Microsoft.Network --wait`.
- **VM image generation error** on `Standard_B2als_v2`: change the VM module's `sku` to `22_04-lts-gen2`.
- **Restart / firewall / persistence checks:** see `evaluations-commands.txt`.

## Resources

Documentation and references used while building this project:

- [Terraform azurerm provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [cloud-init documentation](https://cloudinit.readthedocs.io/)
- [Azure Linux VM docs](https://learn.microsoft.com/azure/virtual-machines/linux/)
- [Docker Compose](https://docs.docker.com/compose/) · [nginx reverse proxy](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [WordPress](https://developer.wordpress.org/) · [phpMyAdmin](https://docs.phpmyadmin.net/)
- 42 *Inception* project (the containerized stack this deploys)

### Use of AI

AI (Claude / Claude Code) was used as a coding partner, with every change reviewed,
tested, and decided on by us:

- **Debugging:** diagnosing a Docker Compose v1/v2 mismatch that broke provisioning, and
  an nginx location-priority bug that 404'd phpMyAdmin's assets.
- **Terraform:** scaffolding and refactoring the modules, and adding `vm_count`-based
  parallel deployment.
- **cloud-init:** the root-login setup, public-IP → `WP_URL` injection, and the optional
  emergency user.
- **Documentation:** drafting this README and the command cheatsheet.

All architectural decisions — cloud provider (Azure), automation tool (Terraform +
cloud-init), the two-repo split, and the security model — were made and validated by us.
AI accelerated implementation and debugging; it did not make design decisions on our behalf.
