# Step-by-step plan

Every step is a checkbox. Each session starts with `make up` and ends with `make down` once Phase 1 exists.

## Phase 0 — Account and guardrails (week 1)

**Done when:** A pull request runs `terraform plan` in GitHub Actions with no stored secrets, and `apply` and `destroy` of the resource group and budget both succeed.

- [ ] Create the Azure account and upgrade it to pay-as-you-go (the free trial's 4-core cap blocks Databricks)
- [ ] Pick one region (for example East US 2) and confirm Azure Databricks and serverless SQL are offered there
- [ ] Request a vCPU quota increase for the VM family the clusters will use (for example 16 vCPUs of Standard DDSv5) plus total regional vCPUs
- [ ] Install locally: Azure CLI, Terraform, Databricks CLI, Astro CLI, Docker, Python 3.11
- [ ] Bootstrap state: a one-time script creates `rg-tfstate`, a storage account, and a `tfstate` container (record the bootstrap problem in ADR-003)
- [ ] Create the public GitHub repo with the layout from the spec, plus pre-commit for `terraform fmt`, `tflint`, and `ruff`
- [ ] Terraform: `rg-capstone` with tags `project=capstone`, `owner=paul`
- [ ] Terraform: subscription-scoped budgets (in a persistent \`foundation\` root that \`make down\` never touches) with email alerts at $50 a month (warning) and $100 a month (stop and look), plus forecast alerts. Use the subscription, not the resource group: Databricks VMs land in the workspace's managed resource group
- [ ] Entra app registration for CI with a federated credential for the repo (OIDC), and Contributor on `rg-capstone` only
- [ ] GitHub Actions: `terraform plan` on every PR, and `apply` only on manual dispatch
- [ ] Write ADR-002 (identity) and ADR-003 (state)

## Phase 1 — Landing zone and workspace (weeks 2–3)

**Done when:** Starting from nothing, `make up` produces a workspace where a notebook reads a test file in ADLS through a Unity Catalog external location, with no keys in code. Run `make down` then `make up` again, and record the rebuild time in minutes.

**Network module**

- [ ] VNet (for example 10.10.0.0/16) with a host subnet and a container subnet (/24 each), both delegated to `Microsoft.Databricks/workspaces`
- [ ] An NSG associated with both subnets
- [ ] A NAT gateway with a public IP attached to both subnets (cluster egress without public IPs)

**Storage and secrets module**

- [ ] ADLS Gen2 account (`is_hns_enabled = true`) with containers `landing`, `quarantine`, `uc-managed`
- [ ] Key Vault in RBAC mode, for the Airflow service principal's secret

**Workspace module**

- [ ] `azurerm_databricks_workspace`, Premium tier, VNet injection, `no_public_ip = true`
- [ ] Check whether the `trial` tier gives 14 free DBU days, and whether switching to Premium later keeps the workspace. If both hold, start on trial to time the free window
- [ ] `azurerm_databricks_access_connector` with a managed identity, plus Storage Blob Data Contributor on the ADLS account

**Unity Catalog module (Databricks provider)**

- [ ] Confirm the workspace is attached to the region's metastore; new workspaces usually are, otherwise add a `databricks_metastore_assignment`
- [ ] Storage credential for the access connector; external locations for `landing` and `quarantine`
- [ ] Catalog `sleep` with managed storage on `uc-managed`; schemas `bronze`, `silver`, `gold`, `semantic`, `ops`
- [ ] Groups `capstone_engineers` and `capstone_analysts`; `databricks_grants` for each schema
- [ ] Service principal `sp-airflow` with an OAuth secret stored in Key Vault
- [ ] Cluster policy: single node, auto-terminate at 15 minutes, an allow-list of small VM sizes

**Prove it**

- [ ] Smoke notebook reads a test file from `landing` through the external location
- [ ] Makefile with `make up` (all Terraform layers in order) and `make down`
- [ ] Destroy, rebuild, and record the time; write ADR-001 (network)

## Phase 2 — Ingestion (weeks 4–5)

**Done when:** Over three simulated days of releases, every good file reaches bronze exactly once. The late hypnogram attaches to its recording, and the corrupt EDF lands in `quarantine` with an email alert. Re-running a day's release adds no rows.

- [ ] Download Sleep-EDF Expanded once to a local `source/` folder (8.1 GB); it's never committed to git
- [ ] Write `release_manifest.csv`: file, release date, and flags for the late file and the deliberately truncated EDF
- [ ] `astro dev init`; add `apache-airflow-providers-databricks` and `apache-airflow-providers-microsoft-azure`
- [ ] Airflow connections for ADLS and Databricks, authenticated as `sp-airflow`
- [ ] `release_files` DAG: daily, uploads that day's manifest rows to `landing/edf/` and the subject spreadsheets to `landing/meta/`
- [ ] Pick the Auto Loader trigger: managed file events on the external location, or classic file-notification mode (ADR-004)
- [ ] Bronze stream in a Databricks Asset Bundle (`databricks.yml`): `binaryFile` metadata only (path, size, modified time), not file contents (ADR-005)
- [ ] Header-parse job: read each EDF header with MNE or pyedflib into `bronze.edf_header` (channels, sample rates, start time, duration)
- [ ] On a parse failure: move the file to `quarantine/`, write a row to `ops.quarantine_log`, fire the job's failure email
- [ ] Load `SC-subjects.xls` and `ST-subjects.xls` into `bronze.subject`; confirm whether lights-off times are present (this feeds ADR-009)
- [ ] Idempotency test: re-run day 2 and assert the row counts don't change
- [ ] CI: `databricks bundle validate` on every PR

## Phase 3 — Transform and orchestration (weeks 6–7)

**Done when:** One Airflow run takes a newly released file all the way to `gold.fct_sleep_night`, and the landing-to-gold time is recorded. A forced task failure retries twice, then alerts.

**Silver (Spark)**

- [ ] Parse the EDF+ hypnogram annotations into stage intervals, then expand them into one row per epoch in `silver.sleep_epoch` (subject, night, epoch index, start time, stage). Confirm the epoch length here
- [ ] Band-power job: a pandas UDF per recording reads Fpz-Cz, cuts it into epochs, runs a Welch PSD, and writes delta, theta, alpha, sigma, and beta power to `silver.epoch_band_power`
- [ ] Pin library versions (MNE, SciPy) in the bundle; run on a job cluster under the cluster policy

**Gold (dbt)**

- [ ] `dbt init` with `dbt-databricks`, targeting a serverless SQL warehouse
- [ ] Staging models over silver and bronze; `dim_subject`, `dim_night`, `fct_sleep_epoch`, `fct_sleep_night`
- [ ] Enforce model contracts on every gold model; add tests for accepted stages, relationships, and not-null keys
- [ ] dbt unit tests for total sleep time and sleep onset latency on a three-night fixture

**Orchestration (Airflow)**

- [ ] `pipeline` DAG: wait for the bronze update → `DatabricksRunNowOperator` (silver jobs) → dbt models as Airflow tasks via Astronomer Cosmos
- [ ] Retries (2, exponential backoff), an `on_failure_callback` email, and an SLA on the end-to-end run
- [ ] Log landing-to-gold time per file to `ops.pipeline_latency`
- [ ] Write ADR-006 (Airflow vs. Lakeflow Jobs vs. Data Factory) and ADR-007 (Spark/dbt boundary)

## Phase 4 — Semantic layer and governance (weeks 8–9)

**Done when:** The CI answer-key check passes, a test user in `capstone_analysts` sees masked subject IDs and can't read silver, and the dashboard and Genie space read only from metric views.

- [ ] Answer key: a separate notebook computes all 8 metrics for 3 nights straight from the raw hypnograms, without reusing silver code. Save the results as `semantic/answer_key.csv`
- [ ] Settle ADR-009 (time in bed) and stage mapping before writing any metric
- [ ] Metric view `semantic.sleep_night_metrics`: YAML over `fct_sleep_night` joined to `dim_subject`; dimensions for study, arm, night, age band, sex
- [ ] Measures: total sleep time, sleep efficiency, onset latency, wake after sleep onset, REM %, deep sleep %, scoreable epoch rate
- [ ] Metric view `semantic.pipeline_metrics` over `ops.pipeline_latency` for landing-to-gold time
- [ ] Keep both metric views in the repo and deploy them through the bundle or Terraform, never by hand in the UI
- [ ] CI check: query the metric views with `MEASURE()` for the 3 nights and fail on any difference over 0.01 from the answer key
- [ ] Governance: tag `subject_id` columns `pii`; a column mask that shows a hash to anyone outside `capstone_engineers`; analysts get grants on `semantic` only
- [ ] Create a second Entra user, add it to `capstone_analysts`, and screenshot what it can and can't see
- [ ] AI/BI dashboard: sleep efficiency by age band, temazepam vs. placebo per subject (paired), quality rate over release days
- [ ] Genie space over the metric views; save 5 test questions and their answers
- [ ] Write ADR-008 (semantic layer) and ADR-010 (PHI handling)

## Phase 5 — Write-up (weeks 10–11)

**Done when:** Someone who has never seen the repo can follow the README from `make up` to the dashboard, and every resume line has its real number filled in.

- [ ] Finish ADR-001 through ADR-010; each ends with "what would make me reverse this"
- [ ] `docs/runbook.md`: rebuild, teardown, re-running a release day, recovering a quarantined file, rotating the service principal secret
- [ ] Cost report: actual spend by tag and service from Cost Management, compared with the projection tab, with the gap explained
- [ ] Put the architecture diagram in the repo; README with prerequisites, `make up`/`make down`, and screenshots
- [ ] Stretch: the same 4 metrics in MetricFlow (`metricflow` package plus the Databricks adapter; confirm adapter support first), and compare the generated SQL in ADR-008
- [ ] One-page case study: the problem, the architecture, 3 decisions and their tradeoffs, the numbers, and what I'd change
- [ ] Fill the resume lines with real numbers (rebuild minutes, GB ingested, landing-to-gold minutes) and update the strategy doc's evidence table
- [ ] Pin the repo, and post the case study on LinkedIn
