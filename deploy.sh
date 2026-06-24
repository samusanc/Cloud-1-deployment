#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# deploy.sh — provision the cloud-1 infrastructure on Azure with Terraform.
#
# What it does:
#   1. Clones (or updates) the application repo: github.com/samusanc/cloud-1
#   2. Builds the base64 'env' Terraform variable from that repo's docker/.env
#      (the VM's cloud-init decodes it into /opt/repo/docker/.env at boot)
#   3. Runs the Terraform workflow in ./Deployment:
#         terraform init -> validate -> plan -> apply
#
# Requirements:
#   - git, terraform (>= 1.6)
#   - Azure auth:  az login   AND   export ARM_SUBSCRIPTION_ID=<your-subscription-id>
#   - An RSA SSH public key at ~/.ssh/id_rsa.pub (Azure admin_ssh_key requires RSA)
#
# Usage:
#   bash deploy.sh            # full workflow (plan + apply)
#   bash deploy.sh plan       # stop after plan (no apply)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/Deployment"

APP_REPO_URL="https://github.com/samusanc/cloud-1.git"
APP_REPO_DIR="$SCRIPT_DIR/cloud-1"
ENV_FILE="$APP_REPO_DIR/docker/.env"

MODE="${1:-apply}"   # "apply" (default) or "plan"

log()  { printf '\n\033[1;36m[deploy %s]\033[0m %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '\033[1;33m[deploy WARN]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m[deploy ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────────────────
command -v git       >/dev/null 2>&1 || die "git not found in PATH"
command -v terraform >/dev/null 2>&1 || die "terraform not found in PATH"
[ -n "${ARM_SUBSCRIPTION_ID:-}" ] || \
  die "ARM_SUBSCRIPTION_ID is not set. Run 'az login' then 'export ARM_SUBSCRIPTION_ID=<id>'."
[ -f "$HOME/.ssh/id_rsa.pub" ] || \
  warn "No RSA key at ~/.ssh/id_rsa.pub — Terraform will fail at the VM step. Create one: ssh-keygen -t rsa -b 4096"

# ── 1. Clone / update the application repo ───────────────────────────────────
if [ -d "$APP_REPO_DIR/.git" ]; then
  log "Updating existing app repo: $APP_REPO_DIR"
  git -C "$APP_REPO_DIR" pull --ff-only
else
  log "Cloning $APP_REPO_URL -> $APP_REPO_DIR"
  git clone "$APP_REPO_URL" "$APP_REPO_DIR"
fi

# ── 2. Encode docker/.env into the Terraform 'env' variable ──────────────────
if [ -f "$ENV_FILE" ]; then
  log "Encoding $ENV_FILE into TF_VAR_env"
  grep -q "CHANGE_ME" "$ENV_FILE" 2>/dev/null && \
    warn "$ENV_FILE still contains CHANGE_ME placeholder secrets — update before a real deploy."
  # Single-line base64 (portable across GNU/BSD base64)
  export TF_VAR_env="$(base64 < "$ENV_FILE" | tr -d '\n')"
else
  warn "$ENV_FILE not found. Terraform will require -var 'env=...' or a pre-set TF_VAR_env."
fi

# ── 3. Terraform workflow ────────────────────────────────────────────────────
cd "$TF_DIR"
log "terraform init";     terraform init -input=false
log "terraform validate"; terraform validate
log "terraform plan";     terraform plan -input=false -out=tfplan

if [ "$MODE" = "plan" ]; then
  log "Plan-only mode requested — stopping before apply."
  exit 0
fi

log "terraform apply"; terraform apply -input=false tfplan

log "Deployment complete. Outputs:"
terraform output
