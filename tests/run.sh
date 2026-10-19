#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"
