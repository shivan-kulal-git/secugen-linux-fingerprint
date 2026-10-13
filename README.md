# SecuGen Fingerprint Reader on Linux

A community guide for getting a **SecuGen Hamster Pro 20 / USB U20** fingerprint reader working with Linux `fprintd` by building upstream [`libfprint`](https://gitlab.freedesktop.org/libfprint/libfprint) with the SecuGen driver enabled.

> **Tested hardware:** SecuGen USB U20 / Hamster Pro 20 (FDU05), USB ID `1162:2200`.
>
> **Tested environment:** Ubuntu-based system using `apt`, `systemd`, and `fprintd`. The successful build in the original test used GLib 2.88 and GUsb 0.4.9. Your distribution and upstream source revision may differ.

This repository documents a successful setup on one system. It is **not a guarantee for every SecuGen model or Linux distribution**.

## What this project does

- Checks for the SecuGen USB reader.
- Installs build dependencies on Ubuntu/Debian-style systems.
- Clones current upstream `libfprint` source into a new directory.
- Checks that the `secugen` driver and USB vendor ID are present.
- Configures and compiles `libfprint` with the driver enabled.
- Checks the compiled library for missing dependencies/unresolved symbols and confirms SecuGen driver strings exist.
- Asks for explicit confirmation before installing the library under `/usr/local`.
- Refreshes the dynamic linker cache, restarts `fprintd`, and checks device detection.

It does **not** automatically enroll fingerprints or configure PAM/login/`sudo` authentication.

## Before you begin

- Ubuntu/Debian-style system with `apt`, `systemd`, and `fprintd`.
- Internet access.
- Administrator access (`sudo`).
- SecuGen USB U20 / Hamster Pro 20 reader connected.
- Read the script before running it.

If `fprintd-list "$USER"` already detects your reader, you do not need this build process.

## Quick start

Download the repository, then from its directory run:

```bash
chmod +x scripts/install-secugen.sh
./scripts/install-secugen.sh
```

The script asks before installing the compiled library. Review its prompts and output. Do not run it on a production machine without reviewing the script and understanding that `/usr/local` may take precedence over the distribution library.

## Manual installation

### 1. Check the reader

```bash
lsusb | grep -i -E 'secugen|1162:2200'
```

The tested device reported USB ID `1162:2200`.

### 2. Install dependencies

```bash
sudo apt update
sudo apt install git build-essential meson ninja-build pkg-config libgusb-dev libgudev-1.0-dev
```

### 3. Clone upstream source

```bash
git clone --depth 1 https://gitlab.freedesktop.org/libfprint/libfprint.git ~/libfprint-secugen-src
cd ~/libfprint-secugen-src
```

Confirm the driver is present before proceeding:

```bash
grep -n -E 'secugen|0x1162|0x2200|Hamster Pro 20' libfprint/drivers/secugen.c
grep -n "'secugen'" meson.build
```

If the source file or USB ID is absent, stop. Upstream source may have changed.

### 4. Configure and compile

```bash
meson setup build --prefix=/usr/local -Ddrivers=all -Dintrospection=false
ninja -C build
```

`-Ddrivers=all` enabled the SecuGen driver in the verified setup. It also enables other drivers.

### 5. Validate before installing

```bash
ldd -r build/libfprint/libfprint-2.so.2.0.0
strings build/libfprint/libfprint-2.so.2.0.0 | grep -i -E 'secugen|hamster pro 20'
```

Do **not** install if `ldd -r` reports `undefined symbol` or `not found`, or if the driver strings are missing.

### 6. Install and test

```bash
sudo ninja -C build install
sudo ldconfig
ldconfig -p | grep libfprint
sudo systemctl restart fprintd
fprintd-list "$USER"
```

To verify an already-enrolled finger:

```bash
fprintd-verify "$USER"
```

To enroll a finger only if needed:

```bash
fprintd-enroll "$USER"
```

Follow the prompts. Do not erase existing fingerprint enrollment unless you intend to replace it.

## Troubleshooting

### `No devices available`

```bash
lsusb -d 1162:2200
systemctl status fprintd --no-pager
journalctl -u fprintd -b --no-pager -n 100
ldconfig -p | grep libfprint
systemctl cat fprintd
```

Check that the active library is the one built with SecuGen support. Library paths differ between distributions; use the actual path shown by `ldconfig -p`.

### Missing `gobject-introspection-1.0`

The tested build worked with:

```bash
-Dintrospection=false
```

### Missing `gudev-1.0` or “udev is required”

```bash
sudo apt install libgudev-1.0-dev
```

Then rerun the Meson setup command.

### GUsb undefined symbols

Do not restore an old `.so` backup built against a different GUsb ABI. Build against the current development headers/libraries and verify the output with `ldd -r` before installing.

### Reader works but login authentication does not

Device detection, enrollment, and PAM authentication are separate. First test `fprintd-list` and `fprintd-verify`. PAM integration varies by distribution. Do not replace PAM configuration blindly; keep a password-based recovery method.

## Rollback / safety

The build installs under `/usr/local`, while distribution-managed libraries normally live under `/usr/lib`. Inspect paths before changing anything:

```bash
ldconfig -p | grep libfprint
ls -l /usr/local/lib/x86_64-linux-gnu/libfprint-2.so*
```

If you choose to remove this local build, confirm the exact files belong to this project before removing only the local library and its symlinks. Then run `sudo ldconfig` and restart `fprintd`. Keep distribution files under `/usr/lib` intact. Paths may differ on other systems.

Do **not** run `sudo apt autoremove` as part of this guide.

## Known successful result

After installing the compiled library, refreshing the linker cache, and restarting `fprintd`, the test system reported:

```text
found 1 devices
Using device /net/reactivated/Fprint/Device/0
Fingerprints for user <username> on SecuGen Hamster Pro 20 (press):
 - #0: right-index-finger
```

The existing enrollment was still present.

## Contributing

Please open an issue or pull request with:
- Linux distribution and version.
- SecuGen model and `lsusb` USB ID.
- `libfprint` source revision.
- Build error or relevant `fprintd` logs (remove personal information first).

## License

This repository's guide and helper script are provided under the MIT License. The upstream `libfprint` project retains its own license and copyright notices. See [upstream libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) for its licensing details.
