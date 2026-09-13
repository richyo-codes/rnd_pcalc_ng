#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8090
THEME=both
OUTPUT=
EXPRESSION=
LAYOUT=phone
MULTILINE=false
BUILD=true

usage() {
  cat <<'EOF'
Usage: tools/capture_web_screenshot.sh [--no-build] [--theme light|dark|both]
                                       [--output PATH] [--port PORT] [--expression TEXT]
                                       [--expression-file PATH] [--desktop] [--multiline]

Builds the WebAssembly release and captures phone screenshots with Chromium.
--desktop uses an exact 1280x1000 viewport; --multiline requires --desktop.
Unlike widget-test goldens, this uses the browser's real font rendering.
By default it writes both light and dark screenshots.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)
      BUILD=false
      shift
      ;;
    --theme)
      THEME="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --expression)
      EXPRESSION="$2"
      shift 2
      ;;
    --expression-file)
      EXPRESSION="$(< "$2")"
      shift 2
      ;;
    --desktop)
      LAYOUT=desktop
      shift
      ;;
    --multiline)
      MULTILINE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
  echo "--port must be a number." >&2
  exit 2
fi

if [[ "$THEME" != light && "$THEME" != dark && "$THEME" != both ]]; then
  echo "--theme must be light, dark, or both." >&2
  exit 2
fi

if [[ "$THEME" == both && -n "$OUTPUT" ]]; then
  echo "--output can only be used with --theme light or --theme dark." >&2
  exit 2
fi

if [[ "$MULTILINE" == true && "$LAYOUT" != desktop ]]; then
  echo "--multiline requires --desktop." >&2
  exit 2
fi

for browser in chromium-browser chromium google-chrome-stable; do
  if command -v "$browser" >/dev/null 2>&1; then
    BROWSER="$(command -v "$browser")"
    break
  fi
done

if [[ -z "${BROWSER:-}" ]]; then
  echo "No supported Chromium browser found." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required for the Chromium screenshot capture." >&2
  exit 1
fi

if [[ "$BUILD" == true ]]; then
  PATH="/usr/bin:/bin:$PATH" flutter build web --wasm --release --no-pub
fi

if [[ ! -f "$ROOT_DIR/build/web/index.html" ]]; then
  echo "No web build found. Run without --no-build first." >&2
  exit 1
fi

SERVER_LOG="$(mktemp)"
DEBUG_PORT=$((PORT + 1))
python3 -m http.server "$PORT" --directory "$ROOT_DIR/build/web" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  rm -f "$SERVER_LOG"
}
trap cleanup EXIT

capture_theme() {
  local theme="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  node "$ROOT_DIR/tools/capture_chromium_screenshot.mjs" \
    "$BROWSER" \
    "http://127.0.0.1:$PORT/?theme=$theme" \
    "$output" \
    "$DEBUG_PORT" \
    "$EXPRESSION" \
    "$LAYOUT" \
    "$MULTILINE"
  echo "Browser screenshot written to $output"
}

if [[ "$THEME" == both ]]; then
  capture_theme light "$ROOT_DIR/test/screenshots/calculator_${LAYOUT}_light.png"
  capture_theme dark "$ROOT_DIR/test/screenshots/calculator_${LAYOUT}_dark.png"
else
  capture_theme "$THEME" "${OUTPUT:-$ROOT_DIR/test/screenshots/calculator_${LAYOUT}_$THEME.png}"
fi
