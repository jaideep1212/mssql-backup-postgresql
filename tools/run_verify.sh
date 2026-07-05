#!/usr/bin/env bash
#
# run_verify.sh  -  set up the venv (once), install deps, and run the
# decryption verification tool. Safe to re-run: it only creates the venv the
# first time, and reuses it afterwards.
#
# Usage:
#   ./run_verify.sh --test     # TEST lane  (reads *_TEST env vars)
#   ./run_verify.sh            # PROD lane  (reads *_PROD env vars)
#
# The .env with the ENCRYPTION_KEY_* / PG_*_* vars must sit next to
# verify_decrypt_export.py.

set -euo pipefail

# ---- Parse the single optional flag: --test selects the TEST lane ----------
LANE_ARG="--lane PROD"          # default: prod
if [ "${1:-}" = "--test" ]; then
    LANE_ARG="--test"           # test lane
elif [ "$#" -gt 0 ]; then
    echo "usage: $0 [--test]   (no flag = PROD lane)" >&2
    exit 1
fi

# Always operate from the tools directory (where this script lives).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="venv"

# 1. Create the venv only if it doesn't already exist.
if [ ! -d "$VENV_DIR" ]; then
    echo ">> creating virtual environment in $SCRIPT_DIR/$VENV_DIR"
    python3 -m venv "$VENV_DIR"
else
    echo ">> reusing existing virtual environment"
fi

# 2. Activate it.
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# 3. Install/upgrade deps (quiet; quick no-op if already satisfied).
echo ">> installing dependencies from requirements-verify.txt"
pip install -q --upgrade pip
pip install -q -r requirements-verify.txt

# 4. Run the tool with the selected lane, output to ~/decrypted.
echo ">> running verify_decrypt_export.py $LANE_ARG --out ~/decrypted"
python verify_decrypt_export.py $LANE_ARG --out "$HOME/decrypted"

# 5. Deactivate the venv on the way out.
deactivate
echo ">> done. CSVs are in ~/decrypted"
