#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP_ID="ca.richyoung.pcalcexpress"
MANIFEST="$ROOT_DIR/flatpak/$APP_ID.yml"
OUT_DIR="$ROOT_DIR/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --out-dir=*)
      OUT_DIR="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

BUILD_DIR="$OUT_DIR/flatpak"
REPO_DIR="$OUT_DIR/flatpak-repo"
BUNDLE_PATH="$OUT_DIR/$APP_ID.flatpak"
FLATPAK_BUILDER_ARGS=(--disable-rofiles-fuse --force-clean)

mkdir -p "$OUT_DIR"

if ! command -v flatpak-builder >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    echo "flatpak-builder not found. Install: sudo dnf install -y flatpak flatpak-builder" >&2
  else
    echo "flatpak-builder not found. Install: sudo apt-get install flatpak flatpak-builder" >&2
  fi
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

if [[ ! -f "$ROOT_DIR/build/linux/x64/release/bundle/pcalc_express" ]]; then
  echo "Expected binary missing: build/linux/x64/release/bundle/pcalc_express" >&2
  exit 1
fi

if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if flatpak-builder --help 2>/dev/null | grep -q -- '--disable-sandbox'; then
    FLATPAK_BUILDER_ARGS+=(--disable-sandbox)
  elif command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
    echo "flatpak-builder does not support --disable-sandbox; falling back to container build." >&2
    exec "$ROOT_DIR/tools/build_flatpak_container.sh"
  else
    echo "flatpak-builder lacks --disable-sandbox and no container engine found." >&2
    echo "Install podman/docker, or upgrade flatpak-builder." >&2
  fi
fi

flatpak-builder "${FLATPAK_BUILDER_ARGS[@]}" "$BUILD_DIR" "$MANIFEST"
flatpak-builder "${FLATPAK_BUILDER_ARGS[@]}" --repo="$REPO_DIR" "$BUILD_DIR" "$MANIFEST"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_PATH" "$APP_ID"

echo "Flatpak bundle created: $BUNDLE_PATH"
echo "Install with: flatpak install --user --reinstall $BUNDLE_PATH"
