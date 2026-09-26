#!/usr/bin/env bash
# Compatibility entry point; usable from Git checkouts and jj workspaces.
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/release_dispatch.py" "$@"
