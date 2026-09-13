# Linux GTK3 / GTK4 runners

The Linux runner supports both GTK versions using one C++ implementation and
shared CMake rules, adapted from the dual-runner setup in rnd-bambu-gtk4.
GTK3 remains the default for the standard Flutter SDK and release builds.
GTK4 requires the GTK4-enabled Flutter SDK and matching engine artifacts
(precompiled or locally built).
Selecting GTK4 does not make an official GTK3 engine compatible with GTK4.

## Build and run

With the standard Flutter SDK on PATH:

```sh
bash tool/flutter_linux.sh gtk3 run
bash tool/flutter_linux.sh gtk3 build --release
```

For the custom GTK4 SDK, supply your own checkout locations:

```sh
export FLUTTER_BIN=/path/to/flutter-gtk4/bin/flutter
export LOCAL_ENGINE_SRC=/path/to/flutter-gtk4/engine/src
bash tool/flutter_linux.sh gtk4 run
bash tool/flutter_linux.sh gtk4 build --debug
```

The default local engine is `host_debug_unopt`. For profile/release builds,
set `LOCAL_ENGINE` and, if different, `LOCAL_ENGINE_HOST` to matching compiled
engine configurations. A debug engine cannot produce a release build.
The wrapper checks for the selected engine library before invoking Flutter.

`tool/gtk3_build.sh` and `tool/gtk4_build.sh` are development-run shortcuts,
matching the reference project's naming. The wrapper passes arguments through.
Do not supply a conflicting `--linux-gtk` argument.

## Selection and build isolation

CMake resolves the variant from `FLUTTER_LINUX_GTK`, then an explicit
`-DLINUX_GTK_VARIANT`, then the ignored `linux/.gtk_variant.cmake` file,
and otherwise defaults to GTK3. The wrapper selects one build without changing
the saved preference. `bash tool/configure_linux_variant.sh gtk3` (or `gtk4`)
writes that local CMake preference; it does not select or install a Flutter engine.
Prefer the wrapper to keep Flutter and CMake aligned.

The custom Flutter SDK separates GTK build directories. Flutter's generated
`linux/flutter/ephemeral` files are still shared, so do not build both variants
concurrently in the same checkout. Use separate worktrees for parallel builds.
If switching between SDKs leaves incompatible generated files, run
`flutter clean` with the selected SDK, then resolve dependencies and rebuild.
Do not copy runner files or engine libraries between bundles.

## Windows and window sizing

Window initialization now lives in the native runners, not `window_manager`.
Both Linux variants and Windows request the existing 620 × 800 startup size.
Windows uses its existing DPI scaling and centers the window in the monitor's
work area; GTK3 requests centered placement. GTK4 placement is compositor-owned,
particularly on Wayland, so forced centering is not guaranteed.

Custom titlebar drag, minimize, maximize/restore, close, and edge/corner resize
continue through `app/window_drag`. The optional Linux system decorations use
`app/window_style`. GTK4 uses GdkSurface/GdkToplevel APIs; GTK3 uses GdkWindow.
This does not add persistence of user-resized dimensions across app restarts.

## Plugins and packaging

The URL launcher is pinned to the reference project's GTK3/GTK4-compatible
implementation at `1291cce9b9c86c48015e1f95a1875252a6e0d375`.
It retains GTK3 URI launching and uses GIO on GTK4. No local pub-cache patch is
needed. Reassess the fork when the upstream package supports GTK4.
`window_manager` and its screen-retriever dependency are no longer needed.

Existing Linux and Flatpak jobs remain GTK3 and need their existing GTK3
runtime libraries. The additional GTK4 CI
bundle is separate from the normal Linux and Flatpak artifacts.

## Precompiled GTK4 CI

The `linux_gtk4` job follows the reference project's FVM setup: FVM 4.2.0,
a registered `richyo-codes` fork, and a pinned SDK revision. It does not compile
the Flutter engine or modify the repository's default `.fvmrc` outside the job.

- Branch: `3.48.0-gtk4.issue94804.20260911`
- Framework revision: `c54f543d1d9a121cf359f2dbcf30ebebde8ff1d1`
- Prebuilt engine ID: `61dae0cb8f6752dae2404a6c142737f04df2592e`

The job sets these before FVM installs or runs Flutter:

```sh
export FLUTTER_PREBUILT_ENGINE_VERSION=61dae0cb8f6752dae2404a6c142737f04df2592e
export FLUTTER_ENGINE_STORAGE_BASE_URL=https://pub-79a02b1963fb4da6b5e4e4816e8b7146.r2.dev
```

The installer downloads and validates the three standard Linux engine archives
from R2 with [`tool/install_gtk4_prebuilt_engine.sh`](../tool/install_gtk4_prebuilt_engine.sh).
It intentionally does not globally set `FLUTTER_STORAGE_BASE_URL`: the bucket
holds custom engine artifacts, while Flutter's default storage continues to
provide common assets such as Material fonts.

Each archive must retain the regular Linux engine contract: `gen_snapshot`,
the public `flutter_linux` headers, `LICENSE.flutter_gtk.md`, and the GTK3
`libflutter_linux_gtk.so`. The fork additionally publishes
`libflutter_linux_gtk4.so`; CI verifies that the former links GTK3 and the
latter links GTK4 in debug, profile, and release archives. A partial or
mislabelled upload fails before the application build begins.

It builds release mode with `--linux-gtk=gtk4`, checks the ELF dependency tree
for GTK4 (rejecting GTK3 or missing libraries), and uploads
`build/linux-gtk4/x64/release/bundle/` as `pcalc-express-linux-x64-gtk4`.
Versioning and the uploader match the other platform jobs. LICENSE and
BUILD_INFO.txt accompany the bundle. Pull requests build but do not publish.

The published release ZIP for this artifact ID contains both GTK engines. CI
requires `libflutter_linux_gtk4.so` specifically, and verifies it links GTK4;
it will fail rather than fall back to GTK3. If a replacement artifact ID is
issued, update the job's engine ID too; do not rename a GTK3 binary to
masquerade as GTK4.

With corrected prebuilt artifacts, local builds can use the same two environment
variables plus `FLUTTER_BIN` pointing to the matching fork, without
`LOCAL_ENGINE_SRC`. Run the installer once after the SDK is initialized:

```sh
bash tool/install_gtk4_prebuilt_engine.sh "$(dirname "$(dirname "$FLUTTER_BIN")")"
bash tool/flutter_linux.sh gtk4 build --release
```

## Validation

Build each variant and inspect the bundle's ELF dependencies with `ldd`:
GTK3 should load `libgtk-3.so` and GTK4 `libgtk-4.so`, never both.
Smoke-test startup size, expression editing, window controls, edge resizing,
system decoration switching, and Help/source links. Test actual compositor
interaction on both X11 and Wayland before treating GTK4 as release-ready.

For a debug bundle, the optional X11 smoke test checks startup dimensions,
resizing, GTK linkage and native close without screenshot comparisons:

```sh
xvfb-run -a -s '-screen 0 1280x1024x24' python3 tools/test_linux_window.py \
  build/linux/x64/debug/bundle/rnd_pcalc_ng --gtk gtk3
```

It requires Xvfb and python-xlib. Pass the GTK4 bundle path and `--gtk gtk4`
to test the other variant. It is not wired into release CI.

## Flutter window API test bed

The custom Flutter checkout already has experimental window controllers in
`packages/flutter/lib/src/widgets/_window.dart` with `setSize`,
`setConstraints`, activation and window state operations.
On Linux, `fl_linux_windowing.cc` handles window creation and preferred
dimensions; `fl_window_state_monitor.cc` reports state changes.

Use pcalc to exercise those APIs before inventing a parallel public API.
The current app still uses its ordinary runner-created primary window, so
controller ownership/adoption of that window needs investigation first.
Useful acceptance cases are 620 × 800 startup, restore after maximizing,
programmatic resize, observed user resize, and constraints at fractional
display scale. GTK4's current `set_geometry_hints` only applies minimum size;
maximum constraints deserve an explicit test. Position/centering must report
compositor limitations rather than promise behavior Wayland cannot guarantee.

No engine API changes are needed for this runner port. Any follow-up engine
work should be independently tested in the Flutter fork, with pcalc as the
integration consumer; keep the GTK3 stable-SDK path working throughout.
