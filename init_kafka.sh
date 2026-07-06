#!/usr/bin/env bash
set -euo pipefail

# ── Kafka / ZooKeeper (run as root, no chown needed) ─────────────────────────
mkdir -p kafka/kafka_data
mkdir -p kafka/zk_data