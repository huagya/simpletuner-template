#!/usr/bin/env bash
# Regenerate locks/cpu.txt and locks/cu128.txt. Requires uv.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UV="${UV:-uv}"
cd "${ROOT}"
common=(
  --python-version 3.12
  --python-platform x86_64-manylinux_2_28
  --index-strategy unsafe-best-match
  --generate-hashes
)
"${UV}" pip compile requirements/cpu.in -o locks/cpu.txt "${common[@]}"
"${UV}" pip compile requirements/cu128.in -o locks/cu128.txt "${common[@]}"
"${UV}" pip compile requirements/jupyter.in -o locks/jupyter.txt \
  --python-version 3.12 \
  --python-platform x86_64-manylinux_2_28 \
  --generate-hashes
echo "locks updated"
