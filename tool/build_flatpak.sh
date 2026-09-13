#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_ID="ca.richyoung.pcalcexpress"
MANIFEST="$ROOT_DIR/flatpak/$APP_ID.yml"
DEFAULT_OUT_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pcalc-express/flatpak"
TMP_OUT_DIR="/tmp/pcalc-express-flatpak"

usage() {
  cat <<'EOF'
Usage: ./tool/build_flatpak.sh [--tmp] [--out-dir PATH]

  --tmp           Store Flatpak builder artifacts under /tmp.
  --out-dir PATH   Store Flatpak builder artifacts under PATH.
EOF
}

OUT_DIR="$DEFAULT_OUT_DIR"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tmp)
      OUT_DIR="$TMP_OUT_DIR"
      shift
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "--out-dir requires a path." >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$OUT_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd)
BUILD_DIR="$OUT_DIR/flatpak"
REPO_DIR="$OUT_DIR/flatpak-repo"
BUNDLE_PATH="$OUT_DIR/$APP_ID.flatpak"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Flatpak manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v flatpak-builder >/dev/null 2>&1; then
  echo "flatpak-builder not found. Install flatpak and flatpak-builder first." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH." >&2
  exit 1
fi

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "pkg-config not found. Install Flutter Linux build dependencies first." >&2
  echo "Ubuntu/Debian: sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev" >&2
  echo "Fedora: sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel" >&2
  exit 1
fi

if ! pkg-config --exists gtk+-3.0; then
  echo "gtk+-3.0 development files not found." >&2
  echo "Ubuntu/Debian: sudo apt-get install -y libgtk-3-dev" >&2
  echo "Fedora: sudo dnf install -y gtk3-devel" >&2
  exit 1
fi

flutter build linux --release

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y --noninteractive flathub \
  org.freedesktop.Sdk/x86_64/25.08 \
  org.freedesktop.Platform/x86_64/25.08

flatpak-builder --force-clean --install-deps-from=flathub "$BUILD_DIR" "$MANIFEST"
flatpak-builder --force-clean --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_PATH" "$APP_ID"

echo "Flatpak bundle created: $BUNDLE_PATH"
