#!/usr/bin/env bash
# One-time bootstrap of Terraform remote state (ADR-003: the state store can't manage itself).
# Creates rg-tfstate, a storage account with Entra-only auth, and a tfstate container,
# then writes infra/backend.hcl for `terraform init -backend-config`.
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
RG="${TFSTATE_RG:-rg-tfstate}"
SA="${TFSTATE_SA:-sttfstate$(openssl rand -hex 4)}"   # must be globally unique, 3-24 lowercase alnum
CONTAINER="tfstate"
HERE="$(cd "$(dirname "$0")" && pwd)"

SUB_ID="$(az account show --query id -o tsv)"
ME="$(az ad signed-in-user show --query id -o tsv)"
echo "Subscription: $SUB_ID  Location: $LOCATION  Storage account: $SA"

az group create -n "$RG" -l "$LOCATION" --tags project=capstone owner=paul lifecycle=persistent -o none
az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false -o none
az storage account blob-service-properties update -n "$SA" -g "$RG" --enable-versioning true -o none

SA_ID="$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)"
az role assignment create --assignee "$ME" --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none || true
echo "Waiting 30s for role assignment to propagate..."; sleep 30
az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none

cat > "$HERE/../backend.hcl" <<HCL
resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "$CONTAINER"
use_azuread_auth     = true
HCL
echo "Wrote infra/backend.hcl (git-ignored). Set GitHub repo variable TFSTATE_SA=$SA for CI."
