#!/usr/bin/env bash
# Backward-compatible wrapper. Prefer: ./scripts/build_dist.sh release
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/build_dist.sh" release
