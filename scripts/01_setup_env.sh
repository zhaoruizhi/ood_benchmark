#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/01a_setup_evalplus_env.sh"
bash "$SCRIPT_DIR/01b_setup_lcb_env.sh"
bash "$SCRIPT_DIR/01c_setup_bfcl_v3_env.sh"
