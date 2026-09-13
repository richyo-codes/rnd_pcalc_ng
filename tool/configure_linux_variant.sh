#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-gtk3}"
case "$variant" in
  gtk3|gtk4) ;;
  *) echo "Expected gtk3 or gtk4, got: $variant" >&2; exit 2 ;;
esac

# Local preference only; no runner source files are copied or overwritten.
printf 'set(LINUX_GTK_VARIANT "%s")\n' "$variant" > "$project_dir/linux/.gtk_variant.cmake"
echo "Configured Linux runner for $variant."
echo "Use tool/flutter_linux.sh to keep the Flutter engine and runner selection aligned."
