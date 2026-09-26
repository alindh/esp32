# ESP32-C6 OpenThread RCP for Home Assistant

Turns a **Waveshare ESP32-C6-DEV-KIT-N8** into an OpenThread **radio co-processor (RCP)**.
Home Assistant's **OpenThread Border Router** app drives it over USB, which makes HA a Thread
border router for Matter-over-Thread devices. The first device is an IKEA TIMMERFLOTTE.

The firmware is ESP-IDF's own `examples/openthread/ot_rcp`, unmodified. This repo pins the
toolchain, adds a small config overlay, and scripts the build, flash and verify steps.

## Quick start

Prerequisites: [INSTALL.md](INSTALL.md) (Colima, the pinned ESP-IDF image, Homebrew `esptool`).

```sh
scripts/build.sh            # build in the pinned container -> dist/
scripts/flash.sh --erase    # first flash: wipe the factory demo, write the RCP, then probe it
scripts/flash.sh            # later flashes
scripts/rcp-probe.sh        # ask the RCP for its Spinel/firmware versions
```

Expected probe output for the current pin, verified on the board on 2026-09-26:

```
>> Spinel probe on /dev/cu.usbmodemXXXXXXXXXX1 @ 460800 baud (8N1, no flow control)
Spinel protocol version : 4.3
RCP firmware version    : openthread-esp32/fff9895c82d-b678a4f63; esp32c6;  2026-08-25 03:21:08 UTC
802.15.4 EUI-64         : 10:51:db:ff:fe:xx:xx:xx
RCP API version         : 11
Min host RCP API version: 4
```

The board must be plugged into the **Mac** while flashing. If UTM has captured it for the
Home Assistant VM, release it in UTM first. Only one side can own a serial port.

## How it works

| Step | Where | What |
|---|---|---|
| Build | Colima container `espressif/idf:v6.1@sha256:8189…` | Copies `ot_rcp` from ESP-IDF, applies [`firmware/sdkconfig.defaults.project`](firmware/sdkconfig.defaults.project), builds for `esp32c6`, and writes a merged image plus checksums to `dist/`. |
| Flash | macOS, Homebrew `esptool` | Finds the CH343 port by USB ID `1a86:55d3` and writes `dist/ot_rcp-esp32c6-merged.bin` at `0x0`. |
| Verify | macOS, `scripts/rcp_probe.py` | Sends Spinel `PROP_VALUE_GET` frames at 460800 8N1 and prints the protocol version, firmware version, EUI-64 and RCP API versions. |

Pins live in one place, [`firmware/config.env`](firmware/config.env): the ESP-IDF version,
its commit, the image digest and the target. The build refuses to run if the container's
ESP-IDF commit differs from the pin.

**Reproducible:** two builds from an empty cache produce byte-identical images, verified
2026-09-26. Two settings make that true:

- `CONFIG_APP_REPRODUCIBLE_BUILD=y` removes absolute paths and build dates from the app.
- `SOURCE_DATE_EPOCH` is set to the ESP-IDF commit time. ESP-IDF's OpenThread component
  stamps a CMake timestamp into the RCP version string, and CMake honours this variable.
  The RCP therefore reports `2026-08-25 03:21:08 UTC`, not the time you built it.

Expected `dist/SHA256SUMS` for the current pin:

```
cedbcb66d51b065dc44ae8c7ae6ece98a50a9324ec2c6f5d8595282a5438da33  bootloader.bin
00aeb428c1b9bbacb9729fa19a84e48ae8e4f09fd600194ec384b006fbb6bc77  esp_ot_rcp.bin
ae15413036e029e9cad505118b1586c0c415cb93fcdf9640bec14a640aad8568  ot_rcp-esp32c6-merged.bin
7f00b6c042a89b15b0cac534f82ed988caf29278ff5700b0c511eb1b5bb7c820  partition-table.bin
```

**Build speed:** a full build takes about 35 seconds. `BUILD_JOBS` (default 8) caps
parallelism. Uncapped, the build took over 25 minutes on this Mac, because Colima's 16
vCPUs overcommit the 10 physical cores, which the HA VM also uses. A compiler cache lives in
the Docker volume `ot-rcp-ccache`; delete it with `docker volume rm ot-rcp-ccache`.

### `dist/` contents

| File | Purpose |
|---|---|
| `ot_rcp-esp32c6-merged.bin` | Bootloader, partition table and app in one image, flashed at `0x0` |
| `bootloader.bin`, `partition-table.bin`, `esp_ot_rcp.bin`, `flash_args`, `flasher_args.json` | Individual images and offsets, for other flashing tools |
| `sdkconfig.used` | The full resolved configuration |
| `build-info.txt` | ESP-IDF and OpenThread commits, target, transport |
| `SHA256SUMS` | Checksums; `flash.sh` verifies them before writing |

## Board facts

One USB-C port feeds a CH334 hub. The hub exposes two serial devices to the host:

| Device | USB ID | Role here |
|---|---|---|
| CH343 USB-UART bridge to C6 UART0 | `1a86:55d3` | **RCP host link and flashing** |
| C6 native USB Serial/JTAG | `303a:1001` | Not used yet; see CLAUDE.md open issues |

## Docs

- [INSTALL.md](INSTALL.md): prerequisites for the Mac, Home Assistant and the iPhone
- [CLAUDE.md](CLAUDE.md): decisions, pinned versions, open issues
- Home Assistant setup checklist: phase 4, to come
- Troubleshooting: phase 5, to come
