# Phase 0 setup guide

Run these steps in order in your Mac terminal. Each one ends with a check. Don't move on until it passes.

## What Terraform is, and why we're using it

Terraform is an infrastructure-as-code tool. You describe cloud resources (a network, a storage account, a Databricks workspace) in `.tf` files. Terraform then compares that description with what actually exists in Azure and creates, changes, or deletes resources until they match. It's the same declare-then-reconcile idea as dbt: you write what the end state should be, and the tool works out the steps.

| Command | What it does | dbt analogy |
| --- | --- | --- |
| `terraform plan` | Shows exactly what would be created, changed, or destroyed, without touching anything | `dbt compile` plus a diff |
| `terraform apply` | Makes Azure match the code | `dbt run` |
| `terraform destroy` | Removes everything the code created | Dropping the schema |
| State file | Terraform's record of what it created, so the next plan knows the difference | The manifest |

**Why it's in this capstone:**

- **It's the skill gap.** "Standing up cloud infrastructure from scratch" in job postings mostly means infrastructure as code. The Beacon posting names Terraform outright. Clicking through the Azure portal doesn't count as evidence.
- **It makes the cost plan work.** `make down` destroys everything after each session and `make up` rebuilds it in minutes. Without code, you'd either leave things running (the \~$245 worst case) or rebuild by hand every time.
- **It turns architecture into something reviewable.** Every network rule, permission, and setting sits in git with a PR and a `plan` diff. That's the evidence behind "designed it from zero."
- **It's the standard in the Databricks world.** Databricks maintains its own Terraform provider for workspaces, Unity Catalog, grants, and cluster policies.

**Alternatives considered:** Bicep (Azure-only, no Databricks provider for Unity Catalog objects), Pulumi (infrastructure as code in Python, but a smaller footprint in job postings), and clicking through the portal (not repeatable). Record this choice in ADR-003.

## Step 1 — Install the tools

Use Homebrew. Install Docker Desktop separately from docker.com; Airflow needs it in Phase 2.

```bash
brew install azure-cli gh tflint uv pre-commit
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
brew tap databricks/tap && brew install databricks
brew install astro
```

**Check:** every command below prints a version.

```bash
az version && terraform -version && databricks -v && astro version && gh --version && uv --version
```

- [ ] Tools installed and versions print

## Step 2 — Second GitHub account and the repo

The GitHub CLI can hold several accounts and switch between them.

```bash
gh auth login        # GitHub.com → HTTPS → sign in with the other account in the browser
gh auth status       # both accounts listed; check the right one is active
gh auth switch       # only if the wrong one is active
gh auth setup-git    # git uses gh's credentials for HTTPS pushes
```

Set this repo's commit identity locally, so it doesn't use your global name and email:

```bash
cd ~/dev/sleep-eeg-platform
git init -b main
git config user.name  "Your Name"
git config user.email "you@other-account-email.com"   # or the account's noreply address
pre-commit install
git add . && git commit -m "Phase 0 scaffold"
gh repo create sleep-eeg-platform --public --source=. --remote=origin --push
```

**If you use SSH instead of HTTPS:** your SSH key decides the account, not gh. Add a host alias in `~/.ssh/config` (`Host github-alt`, `HostName github.com`, `IdentityFile ~/.ssh/<that account's key>`, `IdentitiesOnly yes`), then run `git remote set-url origin git@github-alt:<username>/sleep-eeg-platform.git`.

**Check:** `git log -1 --format='%an <%ae>'` shows the new account's identity, and the repo page on GitHub shows the commit.

- [ ] Repo pushed under the right account
- [ ] Switch back (`gh auth switch`) before working in your other repos

## Step 3 — Azure account and subscription

1. Sign up at azure.microsoft.com, then **upgrade to pay-as-you-go** in the portal. The free trial's 4-core cap blocks Databricks clusters.
2. Log in and pin the subscription:

```bash
az login
az account list -o table
az account set --subscription "<subscription id>"
```

3. Register the resource providers this project uses (each takes a minute or two):

```bash
for ns in Microsoft.Databricks Microsoft.Storage Microsoft.Network Microsoft.KeyVault Microsoft.Consumption Microsoft.ManagedIdentity; do
  az provider register --namespace $ns
done
az provider list --query "[?registrationState=='Registered'].namespace" -o tsv | grep -E 'Databricks|Storage|Network|KeyVault|Consumption|ManagedIdentity'
```

4. Request vCPU quota: in the portal go to **Quotas → Compute**, region **East US 2**, and request **16 vCPUs** for *Standard DDSv5 Family* and at least 16 for *Total Regional vCPUs*. Small requests are usually approved automatically.

**Check:** `az account show --query "{name:name, id:id, state:state}"` shows your pay-as-you-go subscription as Enabled, all six providers are Registered, and the quota page shows the new limits.

- [ ] Pay-as-you-go subscription active
- [ ] Providers registered
- [ ] Quota approved

## Step 4 — Terraform state and budgets

**4a. Bootstrap state (once).** Terraform needs somewhere to keep its state file, and that storage can't be created by the same Terraform that uses it. So a small script creates it with the Azure CLI.

```bash
cd ~/dev/sleep-eeg-platform
make bootstrap
```

This creates `rg-tfstate`, a storage account with key-based access turned off, and a `tfstate` container. It also writes `infra/backend.hcl`, which git ignores. **Note the storage account name it prints**; GitHub needs it in Step 6.

**4b. Budgets (once, never destroyed).**

```bash
cp infra/foundation/terraform.tfvars.example infra/foundation/terraform.tfvars
# edit: subscription_id, alert_email, budget_start_date = first day of the current month, e.g. 2026-10-01T00:00:00Z
make foundation        # runs init, then apply; read the plan and type yes
```

**Check:** in the portal, **Cost Management → Budgets** lists `budget-capstone-warn` ($50) and `budget-capstone-stop` ($100), each with an actual and a forecast alert to your email.

- [ ] `infra/backend.hcl` exists; storage account name noted
- [ ] Both budgets visible in the portal

## Step 5 — Validate, then the first up and down

I couldn't run Terraform when I wrote the scaffold, so validating it is the first real test.

```bash
cp infra/envs/dev/terraform.tfvars.example infra/envs/dev/terraform.tfvars   # set subscription_id
make init
make validate
make fmt
make plan      # expect: 1 to add (rg-capstone-dev)
make up        # prints how long it took
make down
```

Fix any validation errors first, then commit (`git commit -am "Phase 0: validated roots"`).

**Check:** after `make down`, this returns `[]`:

```bash
az group list --query "[?tags.lifecycle=='ephemeral'].name"
```

- [ ] Both roots validate
- [ ] `make up` and `make down` both succeed

## Step 6 — CI identity and a test PR

GitHub Actions signs in to Azure with OIDC: Azure trusts tokens GitHub issues for this repo, so there's no password or secret to store or rotate. Do this by hand now and write ADR-002 about it; you can move it into Terraform later.

```bash
GH_USER=<your github username>
REPO=sleep-eeg-platform
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
TFSTATE_SA=<storage account name from Step 4a>

# app registration + service principal
APP_ID=$(az ad app create --display-name gh-$REPO --query appId -o tsv)
az ad sp create --id $APP_ID

# trust GitHub tokens for PRs and for the main branch
az ad app federated-credential create --id $APP_ID --parameters "{\"name\":\"gh-pr\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:$GH_USER/$REPO:pull_request\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
az ad app federated-credential create --id $APP_ID --parameters "{\"name\":\"gh-main\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:$GH_USER/$REPO:ref:refs/heads/main\",\"audiences\":[\"api://AzureADTokenExchange\"]}"

# least privilege for plan: read the subscription, read/write state (lock lease)
az role assignment create --assignee $APP_ID --role Reader --scope /subscriptions/$SUB_ID
az role assignment create --assignee $APP_ID --role "Storage Blob Data Contributor" \
  --scope $(az storage account show -n $TFSTATE_SA -g rg-tfstate --query id -o tsv)

# repo variables the workflow reads (identifiers, not secrets)
gh variable set AZURE_CLIENT_ID       --body $APP_ID     -R $GH_USER/$REPO
gh variable set AZURE_TENANT_ID       --body $TENANT_ID  -R $GH_USER/$REPO
gh variable set AZURE_SUBSCRIPTION_ID --body $SUB_ID     -R $GH_USER/$REPO
gh variable set TFSTATE_SA            --body $TFSTATE_SA -R $GH_USER/$REPO
```

**Test it:** make a small change under `infra/` (for example, add a tag), push it on a branch, and open a PR.

```bash
git switch -c test/ci-plan
# edit infra/envs/dev/main.tf, e.g. add  purpose = "capstone"  to local.tags
git commit -am "test: CI plan" && git push -u origin test/ci-plan
gh pr create --fill
gh pr checks --watch
```

**Check (Phase 0 done-when):** the `terraform-plan` check passes on the PR, and the repo has no stored secrets.

- [ ] OIDC app, federated credentials, and roles created
- [ ] Four repo variables set
- [ ] PR plan check is green
- [ ] ADR-002 (identity) and ADR-003 (state and layout) written
- [ ] Phase 0 row filled in `docs/PLAN.md`
