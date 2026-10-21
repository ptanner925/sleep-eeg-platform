#!/usr/bin/env bash
# One-time bootstrap of Terraform remote state (ADR-003: the state store can't manage itself).
# Creates rg-tfstate, a storage account with Entra-only auth, and a tfstate container,
# then writes infra/backend.hcl for `terraform init -backend-config`.
# Safe to rerun: reuses the existing storage account and skips steps already done.
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
RG="${TFSTATE_RG:-rg-tfstate}"
CONTAINER="tfstate"
ROLE="Storage Blob Data Contributor"
HERE="$(cd "$(dirname "$0")" && pwd)"

SUB_ID="$(az account show --query id -o tsv)"
ME="$(az ad signed-in-user show --query id -o tsv)"

az group create -n "$RG" -l "$LOCATION" --tags project=capstone owner=paul lifecycle=persistent -o none

# Reuse the account from an earlier run; a new random name on every run would orphan the old one.
EXISTING_SA="$(az storage account list -g "$RG" --query "[?starts_with(name, 'sttfstate')].name | [0]" -o tsv)"
SA="${TFSTATE_SA:-${EXISTING_SA:-sttfstate$(openssl rand -hex 4)}}"   # globally unique, 3-24 lowercase alnum
echo "Subscription: $SUB_ID  Location: $LOCATION  Storage account: $SA"

az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false -o none
az storage account blob-service-properties update -n "$SA" -g "$RG" --enable-versioning true -o none

SA_ID="$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)"
if [[ -z "$(az role assignment list --assignee "$ME" --role "$ROLE" --scope "$SA_ID" --query '[0].id' -o tsv)" ]]; then
  az role assignment create --assignee "$ME" --role "$ROLE" --scope "$SA_ID" -o none
fi

# Role assignments can take minutes to propagate; retry instead of guessing a fixed wait.
for attempt in $(seq 1 20); do
  if az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none 2>/dev/null; then
    break
  fi
  if (( attempt == 20 )); then
    echo "Container create still failing after 5 min; last error:" >&2
    az storage container create -n "$CONTAINER" --account-name "$SA" --auth-mode login -o none
  fi
  echo "Waiting for role assignment to propagate (attempt $attempt/20)..."; sleep 15
done

cat > "$HERE/../backend.hcl" <<HCL
resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "$CONTAINER"
use_azuread_auth     = true
HCL
echo "Wrote infra/backend.hcl (git-ignored). Set GitHub repo variable TFSTATE_SA=$SA for CI."
