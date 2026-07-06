#!/usr/bin/env bash
set -euo pipefail

# ── Kafka / ZooKeeper (run as root, no chown needed) ─────────────────────────
mkdir -p kafka/data
mkdir -p kafka/zk_data