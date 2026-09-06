#!/usr/bin/env bash
# Adopt the three existing Neon projects into state instead of creating duplicates.
# Run once, then `tofu plan` should show no destroys and no creates for neon_project.
set -euo pipefail
cd "$(dirname "$0")"
tofu init
tofu import 'neon_project.this["canonical"]' crimson-cell-39815049
tofu import 'neon_project.this["auth"]'      fancy-brook-94928157
tofu import 'neon_project.this["admin"]'     round-butterfly-64996380
echo "imported; now: tofu plan  (expect: no destroy, no neon_project create)"
