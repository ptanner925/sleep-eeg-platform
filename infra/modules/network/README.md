# network (Phase 1)

- [ ] VNet (e.g. 10.10.0.0/16)
- [ ] Host subnet + container subnet (/24 each), both delegated to `Microsoft.Databricks/workspaces`
- [ ] NSG associated with both subnets (Databricks manages its rules)
- [ ] NAT gateway + standard static public IP, associated with both subnets (egress with no public IPs on nodes)

Outputs the workspace module needs: VNet ID, both subnet names, both NSG-association IDs.
Decision record: ADR-001 (network posture).
