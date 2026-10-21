# data/ (local only, git-ignored)

`make data` downloads Sleep-EDF Expanded into `data/sleep-edfx/`. Never commit recordings.

`release_manifest.csv` (committed) drives the Phase 2 release DAG: which file lands on which simulated
day, plus the deliberate late hypnogram and the deliberately truncated EDF.
