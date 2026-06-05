#!/usr/bin/env bash
set -euo pipefail

# Create volume directories and fix ownership for services that run as non-root users.
# Run this once on a fresh host before: docker compose up

# ── Consul (UID 100) ──────────────────────────────────────────────────────────
mkdir -p data/consul_standalone/data
mkdir -p data/consul_standalone/config
chown -R 100:100 data/consul_standalone/data
chown -R 100:100 data/consul_standalone/config

# ── Kafka / ZooKeeper (run as root, no chown needed) ─────────────────────────
mkdir -p kafka/kafka_data
mkdir -p data/kafka/zk_data

# ── MySQL (UID 999) ───────────────────────────────────────────────────────────
mkdir -p data/mysql/data
chown -R 999:999 data/mysql/data

# ── Nexus (UID 200) ───────────────────────────────────────────────────────────
mkdir -p data/nexus/data
chown -R 200:200 data/nexus/data

# ── RabbitMQ (UID 999) ────────────────────────────────────────────────────────
mkdir -p data/rabbitmq/data
chown -R 999:999 data/rabbitmq/data

# ── Vaultwarden (runs as root, no chown needed) ───────────────────────────────
mkdir -p data/vault/data

echo "Done. All data directories created and ownership set."
