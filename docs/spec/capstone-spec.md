# Capstone Spec — Sleep EEG Platform on Azure + Databricks

Oct 13, 2026 · @Paul Tanner

## Goal

This project designs, provisions, and runs a sleep-study data platform from an empty Azure subscription to governed metrics. It's the first platform where I make every foundational choice and write down why. Everything is defined in code, so the whole thing can be destroyed and rebuilt with one command.

**It closes these gaps:**

- **Architecture from zero:** Every layer is my decision, recorded as an ADR.
- **Cloud infrastructure:** Terraform for networking, identity, storage, and the Databricks workspace.
- **Databricks and Spark:** Unity Catalog, Auto Loader, Spark jobs on real signal files.
- **Orchestration:** Airflow triggering and monitoring Databricks jobs.
- **Semantic layer:** Designed by me, not inherited.
- **Health data domain:** EEG/EDF formats, clinical sleep scoring, de-identification thinking.

**Claims I can make once it ships (and not before):** "Designed and built an Azure + Databricks lakehouse from an empty subscription with Terraform." "Built event-driven ingestion of EEG recordings." "Orchestrated with Airflow." "Designed a semantic layer for clinical sleep metrics." Each claim links to the repo and an ADR.

## Architecture

Everything inside the Azure box comes from one Terraform apply. Airflow runs locally and drives the pipeline from outside.

&#91;embedded content: capstone architecture · Azure + Databricks, 5 data hops\]

Data moves left to right through bronze, silver, and gold, then down into the semantic layer. Consumers only ever query metric views, never the gold tables directly.

## Dataset

The dataset is [Sleep-EDF Database Expanded](https://www.physionet.org/content/sleep-edfx/1.0.0/) on PhysioNet: 197 whole-night recordings, 8.1 GB, open access under the Open Data Commons Attribution license. It's real clinical EEG with expert sleep scoring, small enough to keep compute cheap.

| Property | Value |  |  |
| --- | --- | --- | --- |
| Studies | Sleep Cassette: 153 recordings of healthy adults aged 25–101, at home. Sleep Telemetry: 44 recordings of 22 subjects, temazepam vs. placebo nights in hospital |  |  |
| Signals | EEG (Fpz-Cz, Pz-Oz) at 100 Hz, EOG, chin EMG, event marker; some files add respiration and temperature |  |  |
| Formats | Signals in EDF; hypnograms in EDF+; subject age and sex in SC-subjects.xls and ST-subjects.xls |  |  |
| Labels | Sleep stages W, R, 1, 2, 3, 4, M (movement), ? (not scored), scored by technicians using the 1968 Rechtschaffen & Kales rules |  |  |

**Why it suits a semantic layer:** The hypnograms turn into standard clinical sleep metrics (total sleep time, sleep efficiency, sleep latency, REM %, wake after sleep onset). The telemetry study adds a real treatment arm: temazepam vs. placebo. That makes it a small clinical trial with a real endpoint comparison.

**Realism moves:**

- Release files into the landing zone in batches over days, so ingestion behaves like at-home devices uploading. Include one late file and one corrupt EDF.
- Treat subject IDs as if they were PHI: tag them, mask them in gold, and restrict access with Unity Catalog grants. The data is already de-identified, so this is practice, not a requirement.
- The page doesn't state the scoring epoch length. R&K scoring normally uses 30-second epochs; confirm it from the hypnogram files in Phase 2.

## Semantic layer design

I'll build the semantic layer as [Unity Catalog metric views](https://docs.databricks.com/aws/en/business-semantics/metric-views), the native option on the platform I picked. They support star and snowflake joins and pre-computed aggregations, and they're queryable from Power BI, Tableau, dashboards, and Genie. As a stretch, I'll define the same core metrics in [MetricFlow](https://www.getdbt.com/blog/dbt-labs-affirms-commitment-to-open-semantic-interchange-by-open-sourcing-metricflow) (open source under Apache 2.0 since October 2025) and write an ADR comparing the two.

**Grain and entities:** subject → recording night → 30-second epoch. The fact table is `fct_sleep_epoch`, and the gold summary is `fct_sleep_night`.

**Dimensions:** study (Cassette or Telemetry), treatment arm (temazepam or placebo, Telemetry only), night number, age band, sex, sleep stage.

| Metric | Definition | Kind |
| --- | --- | --- |
| Total sleep time (min) | Epochs in stages 1, 2, 3, 4, R × 0.5 | Clinical |
| Sleep efficiency (%) | Total sleep time ÷ time in bed | Clinical |
| Sleep onset latency (min) | Lights-off to first sleep epoch | Clinical |
| Wake after sleep onset (min) | Wake epochs between first sleep and final awakening × 0.5 | Clinical |
| REM (%) | R epochs ÷ sleep epochs | Clinical |
| Deep sleep (%) | Stage 3 + 4 epochs ÷ sleep epochs | Clinical |
| Scoreable epoch rate (%) | Epochs not marked M or ? ÷ all epochs | Data quality |
| Landing-to-gold latency (hours) | File arrival time to gold row availability | Platform |

**Design questions to settle (each one gets an ADR):**

- **Time in bed:** Use lights-off and lights-on times from the subject files if they're present, or fall back to first-to-last sleep epoch. Cassette recordings run about 20 hours, so this choice moves sleep efficiency a lot.
- **Stage mapping:** Keep the R&K stages, or map 3 + 4 to modern N3 as a dimension attribute?
- **Where metric logic lives:** Ratios defined once in the metric view, never recomputed inside dbt gold models.

**Proof it's right:** Hand-compute every metric for 3 nights in a notebook and save the results as an answer key, the same pattern as my e-commerce lab. CI fails if the metric view disagrees with the answer key.

## Build phases

The build takes six phases, about 11 weeks at 8–10 hours a week. Each phase ends with a test I can demonstrate and something a reviewer can open. Nothing moves forward until the done-when test passes.

| # | Phase | Weeks | Scope | Done when | Leaves behind |
| --- | --- | --- | --- | --- | --- |
| 0 | Account and guardrails | 1 | Pay-as-you-go subscription, Terraform remote state in its own storage account, budget alerts in Terraform, GitHub repo running `terraform plan` in Actions | `terraform apply` creates the resource group and budget; `destroy` removes it cleanly | Repo skeleton, CI badge |
| 1 | Landing zone | 2–3 | VNet with Databricks host and container subnets, NSGs, NAT gateway, ADLS Gen2, Key Vault, Entra service principal, Premium workspace with VNet injection and secure cluster connectivity, Unity Catalog access connector, catalog, schemas, external location, grants | From an empty subscription, one apply produces a workspace where a notebook reads ADLS through Unity Catalog with no keys in code. Destroy and rebuild, and time it | Terraform modules, rebuild time in README, ADR-001 to 003 |
| 2 | Ingestion | 4–5 | Airflow (Astro CLI, local) DAG releases Sleep-EDF files into landing in batches; Auto Loader in file-notification mode loads bronze; EDF parsing; quarantine for bad files | The late file lands correctly, the corrupt file goes to quarantine with an alert, and reruns don't create duplicates | Ingestion DAG, bronze tables, ADR on Auto Loader mode |
| 3 | Transform | 6–7 | Silver: 30-second epochs joined to stages, EEG band power computed in Spark. Gold: dbt-databricks models with contracts and tests. Airflow runs ingest, then the Databricks job, then `dbt build` | One DAG run takes a new file all the way to gold; a failed task alerts and retries | Lineage in Unity Catalog, dbt docs, ADR on Airflow vs. Lakeflow Jobs |
| 4 | Semantic layer and governance | 8–9 | Metric views; answer key for 3 nights; tags and column masks on subject IDs; group-based grants; one dashboard plus a Genie space | Answer key passes in CI; a non-admin group sees masked IDs; the dashboard reads only from metric views | Metric view YAML, governance ADR, dashboard screenshot |
| 5 | Write-up | 10–11 | ADRs finished, architecture diagram, cost report, runbook, MetricFlow comparison (stretch) | A stranger can clone the repo, run `make up`, and reach the dashboard by following the README | Public repo plus a 1-page case study |

Steps to tick off for each phase are in Step-by-step plan; spend by week and component is in Cost projection.

## Decisions to write up as ADRs

These ADRs are where the systems-thinking claim comes from. Each one is a page: the context, 2–3 options, the decision, and what would make me reverse it. I'll write each one when I make the choice, not afterward.

| ADR | Decision | Options to weigh |
| --- | --- | --- |
| 001 | Network posture | VNet injection with secure cluster connectivity and a NAT gateway, vs. the default managed VNet; private endpoints for storage now or later |
| 002 | Identity | Service principal with OIDC federation from GitHub Actions, vs. a client secret in Key Vault |
| 003 | Terraform state and layout | One root module vs. split layers (network, workspace, Unity Catalog); remote state locking |
| 004 | Ingestion trigger | Auto Loader file notification vs. directory listing; cost and latency at 197 files vs. 1M |
| 005 | EDF parsing | Parse whole files on the driver vs. distributed UDFs; where raw bytes live |
| 006 | Orchestration | Airflow calling Databricks jobs, vs. Lakeflow Jobs end to end, vs. Azure Data Factory |
| 007 | Transform split | Spark for signal processing and dbt for relational modeling; where the boundary sits |
| 008 | Semantic layer | Unity Catalog metric views vs. MetricFlow; the lock-in vs. portability tradeoff |
| 009 | Time in bed definition | Lights-off window vs. first-to-last sleep epoch |
| 010 | PHI handling | Tags plus column masks vs. separate restricted schemas; how this changes for real PHI under HIPAA |

## Cost guardrails

The projection is about $112 over 11 weeks at list price (about $80 with the trial timed to weeks 8–9), and peak weeks run about $19. Terraform-managed budget alerts sit at $50 (warning) and $100 (stop and look) a month. The full model is in Cost projection.

**Known constraints:**

- **The Azure free trial won't run Databricks.** It caps you at 4 cores, which is too few for a Spark cluster. The subscription has to be pay-as-you-go, with a vCPU quota increase requested for the region ([Microsoft Q&A](https://learn.microsoft.com/en-us/answers/a/923007)).
- **Databricks Premium trial:** Workspaces can use a 14-day trial tier with free DBUs. The Azure VMs underneath are probably still billed. Time Phases 3–4 to fall inside a trial window. That thread is from 2022, so confirm the current terms before relying on it.

**Habits that keep costs down:**

- **Clusters:** Single-node job clusters, auto-terminate after 10–15 minutes, smallest VM that fits the EDF parsing.
- **SQL warehouse:** Smallest serverless size, with the shortest auto-stop.
- **Destroy anything that bills by the hour** (the NAT gateway above all) at the end of each session. The Phase 1 rebuild test is what makes this cheap to do.
- **Keep Airflow local** (Astro CLI in Docker), not on a managed service.
- **Tag every resource** with `project=capstone` so the cost report in Phase 5 is one query.

## Repo layout and resume lines

The repo is one public monorepo, scaffolded locally at \`\~/dev/sleep-eeg-platform\`. Each resume line unlocks only when its phase's done-when test passes.

```
sleep-eeg-platform/
  infra/            # Terraform: network, workspace, unity-catalog modules
  airflow/          # Astro project: ingest + orchestration DAGs
  databricks/       # Asset bundle: Auto Loader + silver jobs
  dbt/              # dbt-databricks gold models, contracts, tests
  semantic/         # metric view YAML, answer key, MetricFlow stretch
  docs/adr/         # ADR-001 … ADR-010
  docs/runbook.md   # rebuild, teardown, failure handling
  .github/workflows # terraform plan, dbt build, answer-key check
  Makefile          # make up / make down
```

| Unlocks after | Resume line (fill in the real numbers) |
| --- | --- |
| Phase 1 | Designed and provisioned an Azure + Databricks lakehouse from an empty subscription in Terraform (VNet injection, Unity Catalog, Entra identity); full rebuild in \_\_ minutes |
| Phase 2 | Built event-driven ingestion of \_\_ GB of clinical EEG (EDF) with Auto Loader, including quarantine and idempotent reprocessing |
| Phase 3 | Orchestrated Spark signal processing and dbt modeling with Airflow, from file arrival to gold in \_\_ minutes |
| Phase 4 | Designed a governed semantic layer for clinical sleep endpoints, validated against a hand-computed answer key in CI |

## Sources

- [Sleep-EDF Database Expanded, PhysioNet](https://www.physionet.org/content/sleep-edfx/1.0.0/)
- [Unity Catalog metric views, Databricks docs](https://docs.databricks.com/aws/en/business-semantics/metric-views)
- [dbt Labs open-sources MetricFlow under Apache 2.0 (Oct 14, 2025)](https://www.getdbt.com/blog/dbt-labs-affirms-commitment-to-open-semantic-interchange-by-open-sourcing-metricflow)
- [MetricFlow commands, dbt docs](https://docs.getdbt.com/docs/build/metricflow-commands)
- [Azure free trial and Databricks, Microsoft Q&A (2022)](https://learn.microsoft.com/en-us/answers/a/923007)
