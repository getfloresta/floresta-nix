#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Import all trusted GPG keys into the local keyring.
#
# Usage: ./contrib/import-keys.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/trusted-keys"

if ! ls "${KEYS_DIR}"/*.asc &>/dev/null; then
    echo "No keys found in ${KEYS_DIR}"
    exit 0
fi

echo "Importing trusted keys..."
for key in "${KEYS_DIR}"/*.asc; do
    NAME=$(basename "${key}" .asc)
    if gpg --import "${key}" 2>/dev/null; then
        echo "  OK   ${NAME}"
    else
        echo "  FAIL ${NAME}"
    fi
done
echo "Done."
