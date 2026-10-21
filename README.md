# sleep-eeg-platform

An end-to-end clinical sleep-study data platform on **Azure + Databricks**, built from an empty
subscription to a governed semantic layer. Data: [PhysioNet Sleep-EDF Expanded](https://www.physionet.org/content/sleep-edfx/1.0.0/)
(197 overnight polysomnograms, EDF/EDF+, ODC-BY 1.0).

> Status: **Phase 0 (scaffold)**. Nothing below is claimed as built until its phase's
> done-when test passes (see `docs/PLAN.md`).

## Architecture

```
PhysioNet Sleep-EDF ──(Airflow release DAG)──▶ ADLS Gen2 landing
                                                   │  Auto Loader (file events)
                                                   ▼
            Databricks workspace · Unity Catalog · VNet-injected
            bronze (raw EDF + metadata) ─▶ silver (30-s epochs, band power)
                 ─▶ gold (dbt: subject-night facts) ─▶ semantic (UC metric views)
                 ─▶ consumers (AI/BI dashboard, Genie)
Everything Azure-side is Terraform. Airflow (Astro CLI) runs locally and orchestrates.
```

## Repo layout

| Path | What lives there |
| --- | --- |
| `infra/bootstrap/` | One-time script: Terraform remote-state storage (az CLI) |
| `infra/foundation/` | Persistent Terraform: subscription budgets and alerts. Applied once, never torn down |
| `infra/envs/dev/` | Ephemeral Terraform root: everything `make up` / `make down` creates and destroys |
| `infra/modules/` | network, storage, workspace, unity_catalog modules (Phase 1) |
| `airflow/` | Astro project: release + pipeline DAGs (Phase 2–3) |
| `databricks/` | Databricks Asset Bundle: Auto Loader + silver jobs (Phase 2–3) |
| `dbt/` | dbt-databricks gold models, contracts, tests (Phase 3) |
| `semantic/` | Metric view YAML, answer key, MetricFlow stretch (Phase 4) |
| `docs/adr/` | Architecture decision records 001–010 |
| `docs/runbook.md` | Rebuild, teardown, failure handling |
| `scripts/` | Data download and helpers |
| `data/` | Local-only source data (git-ignored) |

## Quick start

```bash
# prerequisites: az, terraform >= 1.6, databricks CLI, astro CLI, docker, uv
az login
make bootstrap          # once: creates rg-tfstate + storage for Terraform state
make foundation         # once: subscription budgets ($50 warn / $100 stop)
make init               # init the ephemeral dev root against remote state
make up                 # create the environment
make down               # destroy it at the end of EVERY session
```

## Cost

Projected ~$112 over 11 weeks at list price (~$80 with the Databricks 14-day trial timed to
weeks 8–9). Worst realistic case ~$245, almost all from resources left running. **Run `make down`
after every session.**

## Phases

| # | Phase | Weeks | Done when |
| --- | --- | --- | --- |
| 0 | Account and guardrails | 1 | PR runs `terraform plan` via OIDC; apply/destroy succeed |
| 1 | Landing zone + workspace | 2–3 | Empty subscription → notebook reads ADLS via UC, no keys; rebuild timed |
| 2 | Ingestion | 4–5 | Late file attaches, corrupt file quarantined, reruns idempotent |
| 3 | Transform + orchestration | 6–7 | One Airflow run: new file → gold; failure retries then alerts |
| 4 | Semantic layer + governance | 8–9 | Answer key passes in CI; analysts see masked IDs |
| 5 | Write-up | 10–11 | A stranger can go from `make up` to the dashboard |
