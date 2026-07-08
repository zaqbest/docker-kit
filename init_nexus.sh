#!/usr/bin/env bash
set -euo pipefail

# ── Nexus (UID 200) ───────────────────────────────────────────────────────────
mkdir -p nexus/data
chown -R 200:200 nexus/data