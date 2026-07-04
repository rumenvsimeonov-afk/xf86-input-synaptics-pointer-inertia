#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="$PROJECT_DIR/.build-pointer-inertia"
STATE_DIR="/var/lib/xf86-input-synaptics-pointer-inertia"
CONFIG_DIR="/etc/X11/xorg.conf.d"
CONFIG_NAME="99-synaptics-pointer-inertia.conf"
CONFIG_SOURCE="$PROJECT_DIR/conf/$CONFIG_NAME"
CONFIG_TARGET="$CONFIG_DIR/$CONFIG_NAME"
INSTALL_DEPS=1
BUILD_ONLY=0
UNINSTALL=0

usage()
{
    cat <<'EOF'
Usage:
  ./install-pointer-inertia.sh                 Build and install the driver
  ./install-pointer-inertia.sh --no-deps       Skip package installation
  ./install-pointer-inertia.sh --build-only    Build without system changes
  ./install-pointer-inertia.sh --uninstall     Restore the previous driver
  ./install-pointer-inertia.sh --help          Show this help
EOF
}

for argument in "$@"; do
    case "$argument" in
    --no-deps)
        INSTALL_DEPS=0
        ;;
    --build-only)
        BUILD_ONLY=1
        ;;
    --uninstall)
        UNINSTALL=1
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\n' "$argument" >&2
        usage >&2
        exit 2
        ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
else
    printf 'sudo is required when the script is not run as root.\n' >&2
    exit 1
fi

if [ "$UNINSTALL" -eq 1 ]; then
    if [ ! -f "$STATE_DIR/synaptics_drv.so.before-pointer-inertia" ]; then
        printf 'No saved driver module was found in %s.\n' "$STATE_DIR" >&2
        printf 'Reinstall the distribution package as a fallback.\n' >&2
        exit 1
    fi

    if ! command -v pkg-config >/dev/null 2>&1; then
        printf 'pkg-config is required to locate the X.Org module directory.\n' >&2
        exit 1
    fi

    MODULE_DIR=$(pkg-config --variable=moduledir xorg-server)
    if [ -z "$MODULE_DIR" ]; then
        printf 'Could not determine the X.Org module directory.\n' >&2
        exit 1
    fi

    "${SUDO[@]}" install -o root -g root -m 0644 \
        "$STATE_DIR/synaptics_drv.so.before-pointer-inertia" \
        "$MODULE_DIR/input/synaptics_drv.so"

    if [ -f "$STATE_DIR/$CONFIG_NAME.before-pointer-inertia" ]; then
        "${SUDO[@]}" install -o root -g root -m 0644 \
            "$STATE_DIR/$CONFIG_NAME.before-pointer-inertia" \
            "$CONFIG_TARGET"
    else
        "${SUDO[@]}" rm -f "$CONFIG_TARGET"
    fi

    printf '\nThe previous driver module was restored.\n'
    printf 'Restart the X.Org session or reboot to apply the change.\n'
    exit 0
fi

if [ "$INSTALL_DEPS" -eq 1 ]; then
    if command -v apt-get >/dev/null 2>&1; then
        printf 'Installing build dependencies...\n'
        "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            build-essential autoconf automake libtool pkgconf xutils-dev \
            xserver-xorg-dev libevdev-dev libxi-dev libxtst-dev \
            xserver-xorg-input-synaptics
    else
        printf 'No apt-get was found. Install the X.Org development headers,\n'
        printf 'libevdev, libXi, libXtst, Autoconf, Automake, and Libtool.\n'
    fi
fi

for command_name in autoreconf make pkg-config gcc; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Required command not found: %s\n' "$command_name" >&2
        exit 1
    fi
done

MODULE_DIR=$(pkg-config --variable=moduledir xorg-server)
if [ -z "$MODULE_DIR" ]; then
    printf 'Could not determine the X.Org module directory.\n' >&2
    exit 1
fi

printf 'Generating the build system...\n'
(
    cd "$PROJECT_DIR"
    NOCONFIGURE=1 ./autogen.sh
)

mkdir -p "$BUILD_DIR"
printf 'Configuring in %s...\n' "$BUILD_DIR"
(
    cd "$BUILD_DIR"
    "$PROJECT_DIR/configure" \
        --prefix=/usr \
        --with-xorg-module-dir="$MODULE_DIR" \
        --with-xorg-conf-dir=/usr/share/X11/xorg.conf.d
)

JOBS=1
if command -v nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
fi

printf 'Building with %s job(s)...\n' "$JOBS"
make -C "$BUILD_DIR" -j"$JOBS"

BUILT_MODULE="$BUILD_DIR/src/.libs/synaptics_drv.so"
if [ ! -f "$BUILT_MODULE" ]; then
    printf 'The expected driver module was not produced: %s\n' \
        "$BUILT_MODULE" >&2
    exit 1
fi

if [ "$BUILD_ONLY" -eq 1 ]; then
    printf '\nBuild completed successfully:\n%s\n' "$BUILT_MODULE"
    exit 0
fi

TARGET_MODULE="$MODULE_DIR/input/synaptics_drv.so"
"${SUDO[@]}" mkdir -p "$STATE_DIR" "$CONFIG_DIR"

if [ -f "$TARGET_MODULE" ] &&
   [ ! -f "$STATE_DIR/synaptics_drv.so.before-pointer-inertia" ]; then
    printf 'Saving the current driver module...\n'
    "${SUDO[@]}" cp -a "$TARGET_MODULE" \
        "$STATE_DIR/synaptics_drv.so.before-pointer-inertia"
fi

if [ -f "$CONFIG_TARGET" ] &&
   [ ! -f "$STATE_DIR/$CONFIG_NAME.before-pointer-inertia" ]; then
    "${SUDO[@]}" cp -a "$CONFIG_TARGET" \
        "$STATE_DIR/$CONFIG_NAME.before-pointer-inertia"
fi

printf 'Installing the pointer inertia driver...\n'
"${SUDO[@]}" install -o root -g root -m 0644 \
    "$BUILT_MODULE" "$TARGET_MODULE"

if [ ! -f "$CONFIG_TARGET" ]; then
    "${SUDO[@]}" install -o root -g root -m 0644 \
        "$CONFIG_SOURCE" "$CONFIG_TARGET"
else
    printf 'Keeping the existing configuration: %s\n' "$CONFIG_TARGET"
fi

printf '\nInstallation completed successfully.\n'
printf 'Restart the X.Org session or reboot to load the new driver.\n'
    printf 'To restore the previous module, run:\n'
    printf './install-pointer-inertia.sh --uninstall\n'
printf 'This driver is for X.Org sessions; native Wayland does not use it.\n'
