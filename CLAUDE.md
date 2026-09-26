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
| 2026-09-26 | Thread channel: **not decided**. HA holds a preferred dataset "MyHomeNNNNNNNNNN" on ch 25 (PAN 0xNNNN, ext PAN <old-ext-pan-id>, source iOS app 2026-09-20). OTBR's config flow imports the preferred dataset into an empty RCP (`_set_dataset`), so the default is ch 25, not 15. | Verified with `thread/list_datasets` via the HA MCP and in HA core `otbr/config_flow.py`. Ch 25 = 2475 MHz is far from Zigbee ch 11 but overlaps EU Wi-Fi ch 12–13. |
| 2026-09-26 | Phone = iPhone; no other Thread BRs | User. Credential sync uses "Send credentials to phone". |

## Pinned versions (checked 2026-09-26)

| Component | Version / pin |
|---|---|
| ESP-IDF | `v6.1`, tag commit `fff9895c82d744c7237be8847347bdd1b07c6643` |
| Docker image | `espressif/idf:v6.1@sha256:81893c71bb5e570088901f21def8684c25cd2a9020281bd01b843a7655edb18c` (amd64+arm64 index) |
| esptool (host) | 5.4.0 (Homebrew). CLI: `esptool`, hyphenated subcommands (`write-flash`) |
| HA OTBR app | 3.2.0 (OTBR POSIX `v2026.08.0`). Requires HA Core ≥ 2025.7.0 |
| HA Matter Server app | 9.2.0 (matter.js server 1.4.0) |

## Hardware facts

- Board has **one USB-C** → **CH334 USB hub** → (a) **CH343** USB-UART bridge to C6 UART0
  and (b) C6 native **USB Serial/JTAG**. One cable exposes two serial ports. Source: Waveshare wiki.
- Waveshare says the board is pin-compatible with ESP32-C6-DevKitC-1. That implies UART0
  TX=GPIO16, RX=GPIO17 and an RGB LED on GPIO8. ⚠️ Not verified from a Waveshare schematic.
- Confirmed on the Mac: CH334 hub `1a86:8091`; CH343 `1a86:55d3` = `/dev/cu.usbmodemXXXXXXXXXX1`;
  USB Serial/JTAG `303a:1001` = `/dev/cu.usbmodem831401`. No driver needed.
  Both run at USB full speed (12 Mb/s). The board and the ZBT-2 sit on the same Apple hub.
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
  in setup_retry (the M100 can be a Thread BR); `unifi` in setup_retry, so no Wi-Fi channel data.
- Network: `enp0s1` IPv4 <ha-lan-ip>/24, IPv6 method auto, link-local only (no IPv6 RA on
  the LAN). `enp0s1.20` VLAN 20 exists (IPv6 disabled).
- `dns-sd -B _meshcop._udp` from the Mac: no Thread BRs advertising.
- iPhone: iPhone18,4, iOS 27.0, HA app 2026.9.1, location Always.

## Open issues

1. ~~Colima VM disk full~~ **Resolved 2026-09-26.** The legacy `/var/lib/docker/overlay2`
   (~89 GB) was deleted with user approval. Docker 29 uses the containerd snapshotter,
   so it was unreferenced. Image v6.1 is pulled and `idf.py --version` = ESP-IDF v6.1.
2. Open questions for the user: **keep MyHomeNNNNNNNNNN (ch 25) or delete it and form a fresh network (ch 15)**; where MyHome came from (a past HomePod/Apple TV? the Aqara M100?); the Hue Bridge's Zigbee channel; the 2.4 GHz Wi-Fi channel of "<home 2.4 GHz SSID>"; and whether UTM
   autostarts the VM.
3. Phase 3 input: in a VM, a USB device that re-enumerates can drop out of UTM's USB
   redirection. Find out whether an RCP reset (spinel reset → `esp_restart`)
   re-enumerates USB Serial/JTAG. The CH343 stays enumerated across C6 resets. Also check
   whether the OTBR opening the port toggles DTR/RTS and triggers the auto-reset circuit.
4. Phase 3 decision pending: UART bridge vs USB Serial/JTAG. Leaning toward the CH343 UART.
