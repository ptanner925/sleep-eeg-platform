#!/usr/bin/env bash
# Downloads PhysioNet Sleep-EDF Expanded v1.0.0 (~8.1 GB) into data/sleep-edfx. Resumable.
# License: Open Data Commons Attribution v1.0 — cite Kemp et al. and PhysioNet in the README.
set -euo pipefail
DEST="$(cd "$(dirname "$0")/.." && pwd)/data/sleep-edfx"
mkdir -p "$DEST"
wget -r -N -c -np -nH --cut-dirs=3 -P "$DEST" https://physionet.org/files/sleep-edfx/1.0.0/
echo "Done. Files in $DEST"
