# Development

Build and test instructions for PCalc Express. For features and examples, see
[the README](../README.md).

## Native development

```bash
flutter pub get
flutter run -d linux
```

Evaluator packages own their build hooks and bundled assets. Flutter invokes the
hooks automatically; there is no application-level `hook/build.dart` to run.
Linux Clang builds require CMake, Ninja, LLVM and Clang development libraries,
alongside Flutter's GTK development dependencies. Android uses the evaluator's
bundled native library; the web build includes its JavaScript loader and WASM.
Backend availability varies by platform.

For the optional GTK4 runner, engine selection, and native window sizing, see
[Linux GTK3 / GTK4 development](linux-gtk.md). GTK3 remains the default.
For widget semantics and real GTK4 AT-SPI validation, see
[Accessibility](accessibility.md).

## Flatpak

Flatpak packaging files live under `flatpak/`.

- Host build: `./tools/build_flatpak.sh`
- Container build: `./tools/build_flatpak_container.sh`

See `FLATPAK.md` for details.

## WebAssembly

To build and run the app without running tests:

```bash
./tools/run_wasm.sh
```

Open `http://127.0.0.1:8080` and press `Ctrl+C` to stop the server. Use
`--port 9000` to choose another port.

Build and run the web test suite with the Dart-to-Wasm target:

```bash
./tools/build_test_wasm.sh
```

The script enables Flutter web support, fetches dependencies, runs tests in
Chrome with `--wasm`, writes the release build to `build/web/`, then serves it
at `http://127.0.0.1:8080`. Press `Ctrl+C` to stop the server. Use
`--no-serve` for a build/test-only run, or `--port 9000` to choose a port.

To make a human-readable phone screenshot using Chromium's real font
rendering, run:

```bash
./tools/capture_web_screenshot.sh --expression '(0xFF << 8) | 0xA5'
```

It builds the Wasm release and writes
`test/screenshots/calculator_phone_light.png` and
`test/screenshots/calculator_phone_dark.png`. This is separate from the
widget-test goldens, which intentionally use Flutter's block-shaped test font
for deterministic layout checks. It requires Chromium and Node.js. Use
`--theme light` or `--theme dark` to capture one palette, `--output PATH` to
choose its destination, or `--port` to choose the temporary server port. Use
`--no-build` to capture an already-built `build/web/` directory.
The optional `--expression` argument enters and evaluates an expression before
capture, so the screenshot shows calculated results.

Recreate the desktop recursive-lambda screenshot from its regression fixture:

```bash
./tools/capture_web_screenshot.sh --desktop --multiline --theme light \
  --expression-file test/fixtures/recursive_factorial.cpp \
  --output test/screenshots/calculator_desktop_recursive_lambda.png
flutter test test/recursive_factorial_test.dart
```

Desktop capture uses a fixed 1280 × 1000 viewport. Multiline capture exercises a
single expand click, drags the editor taller, and evaluates with Ctrl+Enter.
The fixture is tested with the Clang backend in C++17, C++20, and C++23 modes.

## GitHub Pages

The `Deploy WebAssembly to GitHub Pages` workflow publishes the Wasm build
from the `main` or `publish` branch. Enable GitHub Pages for the repository
with **Source: GitHub Actions** under Settings → Pages; subsequent pushes
will deploy the calculator at the repository's Pages URL.
The deployment requires the browser smoke test and release build to pass.
Keypad rendering checks run separately with `continue-on-error`, so visual
golden differences do not block publication.
