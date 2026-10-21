# Architecture decision records

| ADR | Decision | Phase | Status |
| --- | --- | --- | --- |
| 001 | Network posture: VNet injection + NAT vs. managed VNet; private endpoints now or later | 1 | open |
| 002 | Identity: OIDC federation from GitHub Actions vs. client secret in Key Vault | 0 | open |
| 003 | Terraform state and layout: bootstrap, foundation vs. ephemeral roots, module split | 0 | open |
| 004 | Ingestion trigger: Auto Loader file events vs. directory listing | 2 | open |
| 005 | EDF parsing: driver vs. distributed UDF; where raw bytes live | 2 | open |
| 006 | Orchestration: Airflow → Databricks jobs vs. Lakeflow Jobs vs. Data Factory | 3 | open |
| 007 | Transform split: Spark for signals, dbt for relational; where the boundary sits | 3 | open |
| 008 | Semantic layer: UC metric views vs. MetricFlow | 4 | open |
| 009 | Time in bed: lights-off window vs. first-to-last sleep epoch | 4 | open |
| 010 | PHI handling: tags + column masks vs. restricted schemas; what changes under HIPAA | 4 | open |

Copy `0000-template.md` to `NNN-short-title.md` for each.
