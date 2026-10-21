# Runbook

## Start a session
1. `az login` (and `databricks auth login` once Phase 1 exists)
2. `make up`; note the time it prints

## End a session (every time)
1. `make down`
2. Check that `az group list --query "[?tags.lifecycle=='ephemeral']"` returns `[]`

## Rebuild from scratch
_Phase 1: fill in, with the timed result._

## Re-run a release day
_Phase 2._

## Recover a quarantined file
_Phase 2._

## Rotate the sp-airflow secret
_Phase 1/2._

## Cost check
Cost Management → filter tag `project=capstone` → compare with the projection tab.
