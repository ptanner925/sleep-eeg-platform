# storage (Phase 1)

- [ ] ADLS Gen2 account (`is_hns_enabled = true`, shared-key access off, TLS 1.2)
- [ ] Containers: `landing`, `quarantine`, `uc-managed`
- [ ] Key Vault, RBAC authorization mode (holds the Airflow service principal secret)

Outputs: storage account ID/name, container names, Key Vault ID.
