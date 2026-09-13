# Flatpak Build & Run

## App ID

- `ca.richyoung.pcalcexpress`

## Files

- Manifest: `flatpak/ca.richyoung.pcalcexpress.yml`
- Desktop entry: `flatpak/ca.richyoung.pcalcexpress.desktop`
- Metainfo: `flatpak/ca.richyoung.pcalcexpress.metainfo.xml`
- Host build script: `tools/build_flatpak.sh`
- Container build script: `tools/build_flatpak_container.sh`

## Build on host

Install the Flutter Linux and Flatpak build dependencies first:

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev lld git unzip xz-utils zip libglu1-mesa libsecret-1-dev libssl-dev flatpak flatpak-builder dbus-user-session
```

On Fedora:

```bash
sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel lld flatpak flatpak-builder
```

```bash
cd /path/to/pcalc-express
./tools/build_flatpak.sh --out-dir ./build/flatpak-release
```

The script:

1. Builds Flutter Linux release bundle
2. Runs `flatpak-builder`
3. Creates bundle at `build/flatpak-release/ca.richyoung.pcalcexpress.flatpak`

## Build in container

```bash
cd /path/to/pcalc-express
flutter build linux --release
./tools/build_flatpak_container.sh
```

Container build uses `ghcr.io/flathub-infra/flatpak-builder-lint:latest` with
Podman or Docker.

## Install & run

```bash
flatpak install --user --reinstall ./build/flatpak-release/ca.richyoung.pcalcexpress.flatpak
flatpak run ca.richyoung.pcalcexpress
```

## Notes

- The manifest packages the existing Flutter Linux release bundle rather than
  rebuilding inside the Flatpak manifest.
- The host script uses `flatpak-builder --disable-rofiles-fuse` to avoid FUSE
  issues commonly seen in CI.
- In CI, the host script attempts `--disable-sandbox` when supported. If the
  installed `flatpak-builder` is older and Podman or Docker is available, it
  falls back to the container build script.
