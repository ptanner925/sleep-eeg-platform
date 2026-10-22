# Phase 0 walkthrough: what we built and why

A plain-language record of Phase 0, written to be re-read before interviews. The exact
commands are in `docs/spec/phase0-setup-guide.md`; this explains the reasoning behind them.

Status as of Oct 21, 2026: Steps 1–5 done. Step 6 (CI identity and test PR), ADR-002, ADR-003,
and the Phase 0 row in `docs/PLAN.md` are still open.

---

## Big picture

### What this project is

A data platform that turns 197 raw sleep EEG recordings (PhysioNet Sleep-EDF Expanded) into
trustworthy, governed metrics. The portfolio point is not the metrics. It is showing that the whole
platform can be stood up **from an empty cloud account, in code, securely, and on a budget**.

### Where things live

```
 LAPTOP                        GITHUB                           AZURE (dedicated subscription)
 ──────                        ──────                           ──────────────────────────────
 code being edited    push →   the repo (source of truth)       what the code describes
 terraform, az, ...            CI checks every PR       ──────→  state storage   (persistent)
 git-ignored local             (Step 6: terraform plan)          budgets         (persistent)
 config (tfvars,                                                 dev environment (built and torn
 backend.hcl)                                                     down every session; Phase 1+:
                                                                  network, data lake, Databricks)
```

### The rules everything follows

1. **Everything is code, in git.** No clicking in the portal to build things. Every setting can be
   reviewed, reproduced, and defended. That is the difference between "used Azure" and "designed
   and built a platform on Azure."
2. **Persistent vs. ephemeral.** A small set of things lives forever (state storage, budgets).
   Everything that costs real money is created at the start of a session (`make up`) and destroyed
   at the end (`make down`). That is what makes an ~$112 total budget realistic.
3. **No secrets anywhere.** No passwords in code, git, or GitHub. Identities prove who they are with
   short-lived tokens instead (see Step 6).
4. **Layered cost protection.** Quota is a hard cap, budgets alert, `make down` is the routine, and
   cluster policies come in Phase 1.

---

## Little picture: each step and why

### Step 1: install the tools

| Tool | Purpose | dbt analogy |
| --- | --- | --- |
| `terraform` | Creates, changes, and deletes Azure resources to match `.tf` files | `dbt run` |
| `az` | Azure CLI for one-off setup and inspection | the warehouse console |
| `databricks` | Deploys Databricks Asset Bundles (Phase 1+) | |
| `astro` | Runs Airflow locally on Docker (Phase 2) | |
| `gh` | GitHub from the command line | |
| `uv` | Python versions, packages, and the `.venv`; `uv run` needs no activation | `dbt deps` + `packages.yml` |
| `tflint` | Linter for Terraform code | sqlfluff |
| `pre-commit` | Runs fmt, tflint, ruff, and file checks on every `git commit` | CI checks, but local |

Terraform is **not** a linter. Terraform builds things; tflint checks Terraform code.

**Local setup notes (this Mac).** Homebrew lives in `/usr/local/homebrew` rather than the standard
`/opt/homebrew`, so packages compile from source and some tools need help:
- A few libraries (`xz`, `sqlite`, `mpdecimal`) were built for Intel and had to be reinstalled as arm64.
- The azure-cli launcher cannot find Homebrew's Python in a non-standard prefix, so `~/.zshrc` sets
  `AZ_PYTHON`. The `SyntaxWarning` noise from `az` is a harmless CLI bug on Python 3.14.
- An old Ruby gem also called `pre-commit` shadowed the real one, so `~/.zlogin` puts Homebrew's
  `bin` ahead of RVM's gem path.
- `tflint` is not in Homebrew; it was installed from its GitHub release with a checksum check.

### Linting setup

- `.tflint.hcl` (repo root) enables the azurerm ruleset (catches invalid VM sizes, SKUs, and resource
  names before anything runs) plus stricter rules: documented variables and outputs, snake_case names.
  `make lint` and the pre-commit hook both point at this one file so they cannot disagree.
- Each module stub got a `versions.tf` with `required_version`, and every variable and output got a
  description.

**Why:** catching mistakes in seconds on a laptop is far cheaper than failing midway through creating
real cloud resources, which can leave half-built (and billing) infrastructure behind.

### Step 2: the GitHub repo

- Public repo, so it works as portfolio evidence. GitHub is also where CI runs from Step 6.
- Commits use the GitHub noreply email so a personal address is not published in history.
- The repo's own `.gitignore` was kept (no GitHub template) because it already covers this stack.
- Audited: no secrets, real IDs, emails, tfvars, state, or data files in any commit.

### Step 3: the Azure subscription

- **Pay-as-you-go**, because the free trial's 4-vCPU cap blocks Databricks clusters. Support plan:
  Basic (free); the paid Developer plan would eat a large share of the project budget.
- **Pay-as-you-go has no spending cap.** Nothing stops spend automatically, which is why the cost
  layers matter.
- **Resource providers.** A new subscription has most Azure services switched off. Registering a
  provider switches one on: Databricks, Storage, Network, KeyVault, Consumption (budgets), and
  ManagedIdentity, plus Compute and Quota, which the setup guide's list was missing.
- **vCPU quota.** Quota is permission to run VMs, not a VM. The automatic request for the DDSv5
  family was refused (common on new subscriptions), but the subscription already has 10 vCPUs in
  many families, including DDSv4. `Standard_D4ds_v4` (4 vCPU, 16 GB, local SSD) fits a single-node
  cluster; choosing the VM family is a Phase 1 decision for the compute/cost ADR. The 10-vCPU
  regional limit is also a hard cost ceiling.

### Step 4: Terraform state storage and budgets

**State storage** (`make bootstrap`, `infra/bootstrap/bootstrap.sh`).
Terraform keeps a record of what it built (the state file, like dbt's manifest). That record has to
live somewhere shared so CI and the laptop see the same thing, and Terraform cannot create its own
home, so a one-time `az` script creates it:

| Setting | Why |
| --- | --- |
| Own resource group `rg-tfstate`, tagged `lifecycle=persistent` | `make down` can never touch it |
| Account keys disabled | no master password exists to leak; only signed-in identities get in |
| Public blob access off, TLS 1.2 minimum | no anonymous access, modern encryption in transit |
| Versioning | an overwritten state file can be restored |
| Soft delete, 14 days (blobs and container) | a deleted state file or container can be restored |
| `CanNotDelete` lock on the resource group | nothing in it can be deleted until the lock is removed |
| `infra/backend.hcl` (git-ignored) | tells `terraform init` where state lives |

The script is safe to rerun: it reuses the existing storage account, skips steps already done, and
retries while a new role assignment propagates instead of sleeping a fixed 30 seconds.

**Budgets** (`make foundation`, `infra/foundation/`). The first real Terraform run. Two monthly
budgets, $50 (warn) and $100 (stop), each emailing on actual and forecasted spend. They are scoped
to the whole subscription because Databricks puts its VMs in a managed resource group that a
resource-group budget would miss. Budgets only alert, and Azure cost data lags 8–24 hours.

### Step 5: prove the routine works

`make init` connected the dev root to remote state. `make plan` showed one resource to add (an
empty resource group with four tags). `make up` created it in about 11 seconds, `make down`
destroyed it, and the ephemeral resource-group query returned `[]`.

**Why:** this proves Terraform can authenticate, read and write remote state, create, and clean up,
all before anything costly exists. It is a rehearsal of the routine every Phase 1+ session uses.

---

## Step 6: why an app registration, and why trust GitHub's tokens

### The problem

Every pull request should automatically run `terraform plan` and show what the change would do in
Azure, like a dbt CI job that builds a PR's models before merge. But `terraform plan` must log in to
Azure, and a GitHub Actions runner cannot open a browser for `az login`. **The CI robot needs its
own identity in Azure.**

### The app registration is that identity

An app registration (with its service principal) is an Entra ID account for software instead of a
person, like a dedicated dbt service user in Snowflake instead of CI logging in as you. It gets the
least permission plan needs:

- **Reader** on the subscription: can see what exists, cannot create or delete anything.
- **Storage Blob Data Contributor** on the state storage account: can read state and take the state
  lock during a plan.

Even if CI misbehaved, this identity cannot build or destroy resources, so it cannot run up cost.

### Why trust GitHub's tokens instead of using a password

The old way is a client secret (a password for the robot) stored in GitHub secrets. It is a
long-lived credential that can leak through logs or mistakes, must be rotated, and breaks the
"no secrets" rule.

**OIDC federation** replaces it:

1. When a GitHub Actions job runs, GitHub issues it a short-lived signed token that says, in effect,
   "this job runs in repo `<owner>/sleep-eeg-platform`, for a pull request" (or for `main`).
2. Azure is told in advance to trust GitHub tokens **only** when they name exactly that repo and that
   PR or branch. That rule is the federated credential.
3. The job hands its token to Azure. Azure verifies GitHub's signature and the repo and branch claims,
   then issues an Azure access token that expires in about an hour.
4. The job runs `terraform plan`; the token expires.

No password exists anywhere: nothing stored, nothing to leak, nothing to rotate. A token from another
repo or a fork does not match the rule and is rejected.

Analogy: instead of giving a contractor a permanent office key, the front desk is told "let in anyone
with a same-day badge from Acme, 3rd floor only." Acme prints fresh badges each morning; a lost badge
is useless by evening.

### Repo variables, not secrets

The workflow still needs to know which tenant, subscription, app, and state storage account to use.
Those are identifiers, not credentials (knowing them grants nothing), so they are stored as GitHub
repo **variables**. The repo has zero stored secrets.

### Why it matters

- It is the Phase 0 done-when test: a PR shows a passing `terraform-plan` check with no stored secrets.
- "CI authenticates to Azure via GitHub OIDC federation with least-privilege roles and no long-lived
  credentials" is exactly what regulated, health-data teams look for.
- ADR-002 records the choice (OIDC federation vs. a client secret in Key Vault) so it can be defended.

---

## Cost protection, in one place

| Layer | Type | Status |
| --- | --- | --- |
| vCPU quota (10 regional) | hard cap: Azure refuses more VMs | in place |
| Budgets $50 / $100 | email alerts, 8–24 h lag | in place |
| `make down` every session | routine | in place |
| Cluster policies (single node, auto-terminate, allowed VM sizes) | hard limits in Databricks | Phase 1 |
| Nightly cleanup of `lifecycle=ephemeral` resource groups | automation | optional, to decide |
| Azure Policy (allowed regions and VM sizes, deny NAT gateways) | blocks at creation | optional, to decide |

What actually causes runaway spend in this design: a cluster without auto-terminate, a SQL warehouse
that never stops, hourly-billed network pieces (NAT gateway, public IP), and a forgotten `make down`.
An idle Databricks workspace and the storage at this data size cost little.

## What exists right now

- **Azure:** `rg-tfstate` with the state storage account and `tfstate` container (cents per month),
  two budgets (free), the delete lock, and 10 vCPUs of quota. No compute.
- **GitHub:** the public repo, audited clean.
- **Laptop:** the tools, plus git-ignored `terraform.tfvars` files and `infra/backend.hcl`.
