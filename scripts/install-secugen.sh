#!/usr/bin/env bash
# Guided build/install of upstream libfprint with SecuGen support.
# Ubuntu/Debian apt-based systems only. Read README.md before running.
set -Eeuo pipefail

SOURCE_DIR="${HOME}/libfprint-secugen-src"
BUILD_DIR="${SOURCE_DIR}/build"
LIBRARY="${BUILD_DIR}/libfprint/libfprint-2.so.2.0.0"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }

[[ -r /etc/os-release ]] || die "Cannot identify this operating system."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]] ||
  die "This script is intended for Ubuntu/Debian-style systems only."
command -v apt-get >/dev/null || die "apt-get not found."
command -v systemctl >/dev/null || die "systemctl not found."
command -v fprintd-list >/dev/null || die "Install fprintd first."

note "USB device check"
if command -v lsusb >/dev/null; then
  lsusb | grep -i -E 'secugen|1162:2200' || {
    printf 'WARNING: SecuGen 1162:2200 was not found in lsusb.\n'
    read -r -p "Connect/check the reader. Continue anyway? Type YES: " answer
    [[ "$answer" == "YES" ]] || exit 1
  }
else
  printf "WARNING: lsusb unavailable; install usbutils if needed.\n"
fi

note "Check whether fprintd already detects a reader"
if fprintd-list "$USER"; then
  printf '\nIf the SecuGen reader is already listed, you may stop here.\n'
  read -r -p "Continue building anyway? Type YES: " answer
  [[ "$answer" == "YES" ]] || exit 0
fi

note "Install build dependencies"
sudo apt-get update
sudo apt-get install git build-essential meson ninja-build pkg-config libgusb-dev libgudev-1.0-dev

note "Fetch upstream libfprint source"
[[ ! -e "$SOURCE_DIR" ]] ||
  die "$SOURCE_DIR already exists. Inspect it; this script will not overwrite or reuse it. Rename it or edit SOURCE_DIR."
git clone --depth 1 https://gitlab.freedesktop.org/libfprint/libfprint.git "$SOURCE_DIR"

[[ -f "$SOURCE_DIR/libfprint/drivers/secugen.c" ]] ||
  die "Source checkout lacks libfprint/drivers/secugen.c."
grep -q "0x1162" "$SOURCE_DIR/libfprint/drivers/secugen.c" ||
  die "Source does not appear to contain USB vendor ID 0x1162."
grep -q "'secugen'" "$SOURCE_DIR/meson.build" ||
  die "Meson configuration does not register secugen."

note "Configure build (does not install system files)"
meson setup "$BUILD_DIR" --prefix=/usr/local -Ddrivers=all -Dintrospection=false

note "Compile"
ninja -C "$BUILD_DIR"
[[ -f "$LIBRARY" ]] || die "Expected shared library not found at $LIBRARY."

note "Check dynamic linking"
LINK_REPORT="$(ldd -r "$LIBRARY" 2>&1)" || {
  printf '%s\n' "$LINK_REPORT"
  die "ldd check failed."
}
printf '%s\n' "$LINK_REPORT"
if printf '%s\n' "$LINK_REPORT" | grep -E 'undefined symbol|not found'; then
  die "Unresolved symbols or missing dependencies; refusing to install."
fi

note "Confirm SecuGen driver is compiled in"
strings "$LIBRARY" | grep -i -E 'FpiDeviceSecugen|SecuGen Hamster Pro 20' ||
  die "SecuGen driver strings not found; refusing to install."

printf '\nThe build passed basic checks. Installing under /usr/local may change which library fprintd loads.\n'
read -r -p "Install now? Type INSTALL to continue: " answer
[[ "$answer" == "INSTALL" ]] || {
  printf "Build retained at %s; this script did not install it.\n" "$BUILD_DIR"
  exit 0
}

note "Install library"
sudo ninja -C "$BUILD_DIR" install
sudo ldconfig

note "Restart fprintd"
sudo systemctl restart fprintd

note "Library paths"
ldconfig -p | grep libfprint || true

note "Detected devices"
fprintd-list "$USER" || {
  printf '\nBuild installed but fprintd did not list a device. See README.md troubleshooting.\n' >&2
  exit 2
}
printf '\nDone. If SecuGen is listed, test an existing enrollment with: fprintd-verify "$USER"\n'
printf 'This script does not enroll fingers or configure PAM/login authentication.\n'
