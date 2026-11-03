#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Wrapper for the YAML-aware workflow contract checker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to inspect workflow contracts" >&2
  exit 2
fi
exec python3 "$SCRIPT_DIR/check_workflow_contracts.py" "$@"
