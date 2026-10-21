# CLAUDE.md — sleep-eeg-platform

Capstone project: a clinical sleep-study data platform on **Azure + Databricks**, from an empty
subscription to a governed semantic layer, on PhysioNet Sleep-EDF Expanded (197 EEG recordings, EDF/EDF+).
Built by Paul as portfolio proof for health/neurotech data engineering roles.

## Read first
- `docs/spec/capstone-spec.md`: goals, architecture, dataset, semantic-layer design, ADR list, cost guardrails
- `docs/spec/step-by-step-plan.md`: phase checklists (0–5) with done-when tests
- `docs/spec/phase0-setup-guide.md`: exact Phase 0 commands
- `docs/PLAN.md`: evidence log (fill in as phases complete)
- `docs/adr/`: decision records (template + index)
The living originals are Claude docs (link in `docs/PLAN.md`); if they disagree, ask Paul which wins.

## Current status
Phase 0 scaffold only. Terraform has NOT yet been run or validated: run `terraform validate` on
`infra/foundation` and `infra/envs/dev` before trusting any HCL here. Modules under `infra/modules/`
are empty stubs with README checklists.

## Working agreements
- **Paul is learning this stack.** He is strong in dbt, Snowflake, and SQL modeling, and newer to Terraform, Azure
  networking/identity, Airflow, and Spark internals. Explain *why* before *what*; dbt analogies help.
- **Paul owns the design.** For each Phase 1+ component, lay out the options and tradeoffs and let him choose
  before writing the code. When a decision is made, draft or update the matching ADR (`docs/adr/`). Resume
  claims depend on him being able to defend every choice.
- **Accuracy over speculation.** Never mark a phase done, or write a resume line, without its done-when
  test passing and the real numbers recorded in `docs/PLAN.md`.
- **Verify before claiming.** Run `terraform fmt/validate/plan`, `dbt build`, `databricks bundle validate`,
  and tests; report actual output, not expected output.

## Architecture rules
- `infra/foundation/` = persistent (subscription budgets, $50 warn / $100 stop). Never destroyed.
- `infra/envs/dev/` = ephemeral; `make up` / `make down` every session. Budgets are subscription-scoped
  because Databricks VMs land in the workspace's managed resource group.
- **Orchestration split:** Airflow owns cross-system boundaries and schedule semantics (release files from
  outside → ADLS, trigger ONE Databricks job, dbt via Cosmos, answer-key check, alerts, backfills over
  release dates). Lakeflow Jobs owns the task graph inside Databricks (bronze → silver).
- **No production notebooks.** Databricks code = Python files in Asset Bundles, deployed from CI.
  Notebooks only for exploration and the independent answer key.
- **dbt owns relational modeling** (gold); Spark owns signal processing (silver). Metric logic lives once,
  in Unity Catalog metric views (`semantic/`), never re-derived in gold models.
- Everything through code and PRs: Terraform, bundles, metric-view YAML. No UI-only config.

## Cost guardrails (projection ~$112 over 11 weeks)
- Remind Paul to `make down` at the end of every session; check `az group list --query "[?tags.lifecycle=='ephemeral'].name"` returns `[]`.
- Single-node clusters, auto-terminate 15 min; serverless SQL warehouse 2X-Small (~$2.80/hr) with minimum auto-stop.
- Develop signal jobs on ~5 recordings; run all 197 only when code is final.
- Flag anything that bills hourly while idle (NAT gateway, warehouses, all-purpose clusters).

## Security
- No secrets in code or git. CI auth = GitHub OIDC → Entra (repo *variables*, not secrets).
- `*.tfvars`, `backend.hcl`, `.env`, and `data/` are git-ignored. Never commit EDF files.
- Treat `subject_id` as PHI-like (tags + column masks) even though the data is de-identified.

## Commands
```bash
make help        # list targets
make bootstrap   # once: Terraform state storage
make foundation  # once: budgets
make init / plan / up / down / fmt / validate / lint
make data        # download Sleep-EDF (8.1 GB) to data/sleep-edfx
```

## Open questions to resolve with data, not assumptions
- Hypnogram epoch length (expected 30 s under R&K; confirm from files, Phase 2–3)
- Whether SC/ST subject files include lights-off times (drives ADR-009 time-in-bed)
- Whether the `trial` workspace SKU can switch to Premium in place (timing the 14-day free DBUs)
- MetricFlow + Databricks adapter support (Phase 5 stretch)
- Several rate-card prices are approximate (VM, NAT gateway, public IP, storage): check in the Azure pricing calculator
