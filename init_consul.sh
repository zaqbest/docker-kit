#!/usr/bin/env bash
set -euo pipefail

mkdir -p consul/data
mkdir -p consul/config
chown -R 100:100 consul/data
chown -R 100:100 consul/config
