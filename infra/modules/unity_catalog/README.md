# unity_catalog (Phase 1, databricks provider)

- [ ] Confirm the workspace is attached to the region's metastore (else `databricks_metastore_assignment`)
- [ ] Storage credential backed by the access connector
- [ ] External locations: `landing`, `quarantine`
- [ ] Catalog `sleep` (managed storage on `uc-managed`); schemas `bronze`, `silver`, `gold`, `semantic`, `ops`
- [ ] Groups `capstone_engineers`, `capstone_analysts`; `databricks_grants` per schema
- [ ] Service principal `sp-airflow` + OAuth secret written to Key Vault
- [ ] Cluster policy: single node, auto-terminate 15 min, small-VM allow-list
- [ ] SQL warehouse: serverless 2X-Small, minimum auto-stop

Decision records: ADR-002 (identity), ADR-010 (PHI handling).
