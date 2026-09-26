# CLAUDE.md — ESP32-C6 OpenThread RCP for Home Assistant

Project log: decisions, pinned versions, open issues. Keep it current with every change.

## Goal

Waveshare ESP32-C6-DEV-KIT-N8 flashed with ESP-IDF `examples/openthread/ot_rcp`, plugged
into the Home Assistant host by USB. HA's OpenThread Border Router app drives it. The
first Matter-over-Thread device is an IKEA TIMMERFLOTTE temp/humidity sensor.

## Working rules (from the user)

- Ask, then propose a plan before writing code. Stop at the phase boundaries the user sets.
- Verify facts against current Espressif and Home Assistant docs, not memory. Record the
  source and check date.
- Small commits with clear messages.
- Phases: 1 INSTALL.md → 2 repo, build and flash → 3 UART vs USB Serial/JTAG and
  sdkconfig → 4 HA checklist → 5 troubleshooting doc.

## Public repo rule

This repo is **public** at https://github.com/alindh/esp32 (pushed 2026-09-26). Personal
identifiers are placeholders: `<home SSID>`, `<ha-lan-ip>`, `<vm-mac>`, `XXXXXXXXXX` (CH343
serial), `10:51:db:xx:xx:xx`, `ha-thread-XXXX`, `<ext-pan-id>`, `<border-agent-id>`, `<room>`.
**Never commit** Thread dataset TLVs or network keys, Wi-Fi SSIDs, LAN IPs, MAC/serial numbers,
or room/address names. A pre-scrub backup bundle is kept locally only
(`/Volumes/Work/Projects/esp32-before-scrub.bundle`).

## Environment facts

- Dev machine: macOS 26.3, Apple Silicon (arm64), Homebrew 7.x, Python 3.14 (Homebrew).
- Container runtime: **Colima**, profile `default`, aarch64 with the vz VM type.
  **It only shares `/Volumes/Work`.** `~/Projects/esp32` resolves to the same folder on
  macOS, but a container sees it as an empty directory. Scripts must mount the real path:
  `cd "$(dirname "$0")" && pwd -P`, which is under `/Volumes/Work/...`.
- Docker Desktop and Colima on macOS cannot pass USB into containers. Build in the
  container, flash with host `esptool`.

## Decisions

| Date | Decision | Why |
|---|---|---|
| 2026-09-26 | Build in `espressif/idf` container pinned by digest. Flash with host esptool (Homebrew). | Reproducible toolchain, native arm64, and no USB passthrough on macOS. |
| 2026-09-26 | ESP-IDF **v6.1** (fallback v6.0.3) | v6.1 is the current stable release, marked Latest. It has the newest OpenThread for a host running OTBR POSIX v2026.08. |
| 2026-09-26 | HA = HAOS 18.3 stable, Core 2026.9.3, aarch64, in a UTM (QEMU) VM on this Mac, bridged to `en0` (VM MAC <vm-mac>, <ha-lan-ip>) | Confirmed by the user and the running VM. The RCP reaches it by UTM USB redirection. |
| 2026-09-26 | ZBT-2 stays on Zigbee; the C6 is the only Thread radio | User decision. Radios must be separated and channels coordinated. |
| 2026-09-26 | iPhone uses untagged Wi-Fi "<home 2.4 GHz SSID>" / "<home SSID>", the same LAN as HA on `en0`; not IoT_Network | User. Needed for mDNS `_meshcop._udp` discovery during commissioning. |
| 2026-09-26 | **Start a fresh HA-owned Thread network; target channel 15.** In phase 4, before adding the OTBR integration, delete the orphaned preferred dataset "MyHomeNNNNNNNNNN" (ch 25, PAN 0xNNNN), so `_set_dataset` creates a new network on `DEFAULT_CHANNEL = 15`. | The user says the dataset's only likely source, the Aqara Hub M100, is broken. There is no Apple hub. HA has 0 Matter devices, so nothing depends on MyHome. Deleting is recoverable: the iPhone keychain still holds MyHome and can resend it. Ch 15 = 2425 MHz is 20 MHz above Zigbee ch 11. Recheck against the Hue Bridge's Zigbee channel; HA can move the Thread channel later. |
| 2026-09-26 | **RCP transport = CH343 UART, 460800 8N1, no HW flow control. HA OTBR: `baudrate: 460800`, `flow_control: false`.** | Bench tests in docs/rcp-transport.md: init-deassert 20/20; flow control 0/5 (RTS drives the auto-reset circuit); the CH343 survives C6 resets, while native USB re-enumerates, which is bad for UTM passthrough. |
| 2026-09-26 | Phone = iPhone; no other Thread BRs | User. Credential sync uses "Send credentials to phone". |

## Pinned versions (checked 2026-09-26)

| Component | Version / pin |
|---|---|
| ESP-IDF | `v6.1`, tag commit `fff9895c82d744c7237be8847347bdd1b07c6643` |
| Docker image | `espressif/idf:v6.1@sha256:81893c71bb5e570088901f21def8684c25cd2a9020281bd01b843a7655edb18c` (amd64+arm64 index) |
| esptool (host) | 5.4.0 (Homebrew). CLI: `esptool`, hyphenated subcommands (`write-flash`) |
| HA OTBR app | 3.2.0 (OTBR POSIX `v2026.08.0`). Requires HA Core ≥ 2025.7.0 |
| HA Matter Server app | 9.2.0 (matter.js server 1.4.0) |

## Build & firmware facts (verified 2026-09-26)

- `scripts/build.sh` → `dist/`. It copies `$IDF_PATH/examples/openthread/ot_rcp` unmodified and
  applies `firmware/sdkconfig.defaults.project` via `SDKCONFIG_DEFAULTS`, which is a list.
- **Reproducible**: the SHA-256 of 2 clean builds (ccache volume removed) and 1 cached build
  match. It needs `CONFIG_APP_REPRODUCIBLE_BUILD=y` **and** `SOURCE_DATE_EPOCH` = IDF commit
  time (1787628068). ESP-IDF's `components/openthread/CMakeLists.txt:57` uses
  `string(TIMESTAMP … UTC)` for the RCP version string, and without it the app hash changed on
  every build.
- Merged image SHA-256 `ae15413036e029e9cad505118b1586c0c415cb93fcdf9640bec14a640aad8568`
  (app `00aeb428…bb6bc77`). App size 0x459c0, 73% of the 1 MB factory partition free.
- `CONFIG_ESPTOOLPY_FLASHSIZE="2MB"` (example default) on an 8 MB chip: harmless, left as is.
- **Flashed and verified on the board**: Spinel protocol 4.3; RCP version
  `openthread-esp32/fff9895c82d-b678a4f63; esp32c6;  2026-08-25 03:21:08 UTC`;
  EUI-64 10:51:db:ff:fe:xx:xx:xx; RCP API version 11; min host RCP API version 4.
- **Build performance**: Colima `default` has 16 vCPUs on a 10-core Mac that also runs the HA VM.
  An uncapped ninja (18 jobs) spent more than 25 min at ~55% guest sys time; capped at
  `-j 8 --cpus 8` it builds in ~35 s. The user restarted Colima with **8 CPUs** on 2026-09-26. The rebuild after that matched the
  pinned hashes. After the restart the `colima` Docker context was briefly missing; Colima
  re-registered it itself.
- macOS ships bash 3.2: an empty array under `set -u` is "unbound". Use `${a[@]+"${a[@]}"}`.
- The user's shell aliases `cat` to `bat`. Use `command cat` / `od` in scripts and checks.

## Hardware facts

- Board has **one USB-C** → **CH334 USB hub** → (a) **CH343** USB-UART bridge to C6 UART0
  and (b) C6 native **USB Serial/JTAG**. One cable exposes two serial ports. Source: Waveshare wiki.
- Waveshare says the board is pin-compatible with ESP32-C6-DevKitC-1. That implies UART0
  TX=GPIO16, RX=GPIO17 and an RGB LED on GPIO8. ⚠️ Not verified from a Waveshare schematic.
- Confirmed on the Mac: CH334 hub `1a86:8091`; CH343 `1a86:55d3` = `/dev/cu.usbmodemXXXXXXXXXX1`;
  USB Serial/JTAG `303a:1001` = `/dev/cu.usbmodem831401`. No driver needed.
  Both run at USB full speed (12 Mb/s). The board and the ZBT-2 sit on the same Apple hub.
- Probed 2026-09-26 with esptool 5.4.0: chip ESP32-C6 (QFN40) rev v0.2, 8 MB flash, base MAC
  10:51:db:xx:xx:xx. Factory firmware: Waveshare "blink" test app (ESP-IDF v5.1-dirty). Its ROM log
  shows a bootloader "SHA-256 comparison failed … Attempting to boot anyway"; harmless, and
  replaced by our flash.
- **CH343 port works for flashing**; DTR/RTS auto-reset works (RTS pulse = rst:0x1 POWERON;
  RTS then DTR = DOWNLOAD mode).
- **Native USB Serial/JTAG (`/dev/cu.usbmodem831401`) never answers esptool**, not even with the
  ROM confirmed in "waiting for download" (strapped via the CH343 lines, no UART sync, 1.5 s
  settle, `--before no-reset --no-stub`). eFuses are clean (DIS_USB_SERIAL_JTAG=0,
  DIS_USB_JTAG=0, DIS_DOWNLOAD_MODE=0). Cause unknown. It enumerates fine as 303a:1001.
  Retested with the RCP firmware flashed: still no response. A failed attempt can leave the chip
  in the ROM bootloader; `esptool --port <CH343> chip-id` (hard reset) recovers it.
  **Update 2026-09-26 12:08: after the user rebooted/replugged the board, `esptool chip-id` over
  native USB (`/dev/cu.usbmodem831401`) connects fine.** The earlier failures were a stuck
  USB Serial/JTAG state that survived EN resets and cleared only with a power cycle. Both ports
  are usable. Phase 3 should test whether that stuck state recurs (RCP resets, OTBR restarts).
- Unknown: whether CH343 RTS/CTS are wired to C6 GPIOs. Probably not, since only DTR/RTS
  auto-reset is typical. Matters for flow control.

## Key compatibility facts

- `ot_rcp` UART config in v6.1 `main/esp_ot_config.h`: **460800 baud, 8N1,
  `UART_HW_FLOWCTRL_DISABLE`**. The transport is chosen by Kconfig: `OPENTHREAD_RCP_UART`,
  `OPENTHREAD_RCP_SPI` or `OPENTHREAD_RCP_USB_SERIAL_JTAG`.
- HA OTBR app defaults: `baudrate: "460800"`, **`flow_control: true`**. The allowed
  baudrates are 57600, 115200, 230400, 460800, 921600 and 1000000. ⇒ **must set
  `flow_control: false`** for stock ot_rcp over UART.
- TIMMERFLOTTE: Matter Server 9.0.x PASE-timeout bug (home-assistant/addons#4677, closed
  as not planned). Static IPv6 on HA broke IKEA Matter pairing for at least one user, so
  use IPv6 Automatic.

## HA state (read via the HA MCP, 2026-09-26)

- Apps: Matter Server 9.2.0 (started), Zigbee2MQTT 2.14.1 (ZBT-2, Zigbee ch 11), Mosquitto. No OTBR yet.
- Integrations: `matter` loaded; `thread` loaded (zeroconf); `homeassistant_connect_zbt2`; `hue`
  (the Hue Bridge has its own Zigbee channel, unknown); `homekit_controller` Aqara-Hub-M100
  in setup_retry (the M100 can be a Thread BR; the user says it is broken); `unifi` in setup_retry, so no Wi-Fi channel data.
- Network: `enp0s1` IPv4 <ha-lan-ip>/24, IPv6 method auto, link-local only (no IPv6 RA on
  the LAN). `enp0s1.20` VLAN 20 exists (IPv6 disabled).
- `dns-sd -B _meshcop._udp` from the Mac: no Thread BRs advertising.
- iPhone: iPhone18,4, iOS 27.0, HA app 2026.9.1, location Always.

## Open issues

1. ~~Colima VM disk full~~ **Resolved 2026-09-26.** The legacy `/var/lib/docker/overlay2`
   (~89 GB) was deleted with user approval. Docker 29 uses the containerd snapshotter,
   so it was unreferenced. Image v6.1 is pulled and `idf.py --version` = ESP-IDF v6.1.
2. Open questions for the user: the Hue Bridge's Zigbee channel (avoid it for Thread); the 2.4 GHz Wi-Fi channel of "<home 2.4 GHz SSID>"; and whether UTM
   autostarts the VM.
3. Phase 3 input: in a VM, a USB device that re-enumerates can drop out of UTM's USB
   redirection. Find out whether an RCP reset (spinel reset → `esp_restart`)
   re-enumerates USB Serial/JTAG. The CH343 stays enumerated across C6 resets. Also check
   whether the OTBR opening the port toggles DTR/RTS and triggers the auto-reset circuit.
4. ~~Phase 3 transport decision~~ Done: CH343 UART (docs/rcp-transport.md).
5. ~~Board on the native-USB variant~~ **Resolved:** the earlier abort was an accidental keypress
   (user, 2026-09-26). The native-USB variant was then tested: 0/20 plus silent probe, the port
   present but mute, as in the earlier stuck state (no power cycle possible remotely). The board
   was reflashed with the UART build and the probe OK: Spinel 4.3, RCP API 11.
6. Confirm the Linux `/dev/serial/by-id/` names inside the HA VM after passthrough.
7. `utmctl usb connect` (UTM 4.7.5) fails for the CH343 with "OSStatus error -2700 / The device
   cannot be found", both by VID:PID and by location. Passthrough is done in the UTM GUI.
   Unknown: does UTM re-attach it after a VM or Mac reboot?
8. Phase 4 progress (2026-09-26): CH343 passed to the VM via the UTM GUI → `/dev/ttyACM1` =
   `/dev/serial/by-id/usb-1a86_USB_Single_Serial_XXXXXXXXXX-if00`. OTBR app configured
   (460800, flow_control false, watchdog on, boot auto) and started; agent 0.3.0-337711e7,
   Thread 1.4. The otbr integration was auto-added (source hassio) and imported MyHome (ch 25),
   as predicted. Then create_network → **ha-thread-XXXX, ch 15, PAN 0xXXXX, ext PAN
   <ext-pan-id>**, set preferred (dataset <dataset-id>, border agent
   <border-agent-id>, ext addr <ext-address>), MyHome deleted.
   **Gotcha:** after create_network, the meshcop mDNS record still said nn=MyHome…; an app
   restart republished it (#XXXX, nn=ha-thread-XXXX). The old #YYYY record still resolved from
   the Mac afterwards, likely the mDNS cache; recheck.
   **Done:** the user sent credentials to the iPhone and commissioned the TIMMERFLOTTE on the
   first try (12:37). Node 'TIMMERFLOTTE <room>', sleepy_end_device on ha-thread-XXXX, FW
   1.0.21, fabrics Apple Keychain + HA. At 12:38 the old #YYYY meshcop record is still visible
   alongside #XXXX; open question whether the OTBR or the Mac cache serves it.
