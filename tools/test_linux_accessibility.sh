#!/usr/bin/env bash
set -euo pipefail

binary="${1:-build/linux-gtk4/x64/debug/bundle/pcalc_express}"
validator="${AT_SPI_VALIDATOR:-validate_atspi_export.py}"

if [[ ! -x "$binary" ]]; then
  echo "Accessibility test binary is missing or not executable: $binary" >&2
  exit 1
fi
if ! command -v "$validator" >/dev/null 2>&1; then
  echo "AT-SPI validator not found: $validator" >&2
  echo "Set AT_SPI_VALIDATOR=/path/to/validate_atspi_export.py" >&2
  exit 1
fi

gtk_variant="unknown"
if ldd "$binary" | grep -q 'libgtk-4'; then
  gtk_variant="GTK4"
elif ldd "$binary" | grep -q 'libgtk-3'; then
  gtk_variant="GTK3"
fi

echo "Testing $gtk_variant accessibility: $binary"

if [[ "$gtk_variant" == "GTK3" ]]; then
  export GTK_MODULES="${GTK_MODULES:+$GTK_MODULES:}gail:atk-bridge"
else
  export GTK_A11Y=atspi
fi

"$binary" &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true' EXIT

common_args=(--pid "$app_pid" --wait-seconds 20 --max-depth 30)
"$validator" "${common_args[@]}" --min-nodes 30 --min-depth 10 \
  --reject-state defunct
"$validator" "${common_args[@]}" --expect-role text \
  --expect-name 'Enter Expression' --expect-state focusable
"$validator" "${common_args[@]}" --expect-role button \
  --expect-name Calculate
"$validator" "${common_args[@]}" --expect-role text \
  --expect-name 'Decimal result'

echo "$gtk_variant AT-SPI accessibility checks passed."
