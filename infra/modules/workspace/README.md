# workspace (Phase 1)

- [ ] `azurerm_databricks_workspace`: Premium (check whether the `trial` SKU fits the timing), VNet injection,
      `no_public_ip = true`, custom parameters from the network module
- [ ] `azurerm_databricks_access_connector` with a system-assigned managed identity
- [ ] Role assignment: Storage Blob Data Contributor for the access connector on the ADLS account

Outputs: workspace URL and ID, access connector ID.
