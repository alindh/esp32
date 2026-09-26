# esp32

ESP32 projects. Each one lives in its own folder with its own README, scripts and pinned
toolchain.

| Project | What it does | Status |
|---|---|---|
| [`thread/`](thread/) | Turns a Waveshare ESP32-C6 dev board into an OpenThread **radio co-processor (RCP)**, so Home Assistant's OpenThread Border Router app can run a Thread network for Matter-over-Thread devices. | ✅ Working: an IKEA TIMMERFLOTTE sensor paired and reporting |

## thread/: ESP32-C6 Thread radio for Home Assistant

```
 IKEA TIMMERFLOTTE ))) 802.15.4 / Thread ch 15 ))) ESP32-C6 (ot_rcp firmware)
                                                        │ USB, CH343 UART bridge
                                                        │ Spinel/HDLC, 460800 8N1, no flow control
                                                        ▼
                               Home Assistant OS ── OpenThread Border Router app (otbr-agent)
                                                ├── Thread + OTBR integrations
                                                └── Matter Server app ── Matter integration
```

- **Firmware:** ESP-IDF's own `examples/openthread/ot_rcp`, unmodified, built for
  `esp32c6` with ESP-IDF v6.1 in a digest-pinned `espressif/idf` container. Builds are
  byte-for-byte reproducible.
- **Tooling:** `build.sh` for the container build, `flash.sh` for flashing with host
  `esptool`, and `rcp-probe.sh`, a small Spinel client that prints the RCP's protocol,
  firmware and API versions.
- **Docs:**
  - [INSTALL.md](thread/INSTALL.md): prerequisites for macOS, Home Assistant and the phone
  - [docs/rcp-transport.md](thread/docs/rcp-transport.md): UART bridge vs native USB, with
    bench tests
  - [docs/ha-setup.md](thread/docs/ha-setup.md): step-by-step Home Assistant and pairing
    checklist
  - [CLAUDE.md](thread/CLAUDE.md): decision log, pinned versions and open issues

Quick start (macOS with Colima and Homebrew `esptool`; see [INSTALL.md](thread/INSTALL.md)):

```sh
cd thread
scripts/build.sh            # reproducible build -> dist/
scripts/flash.sh --erase    # first flash over the CH343 port, then Spinel probe
```

Then configure HA's **OpenThread Border Router** app with `baudrate: 460800` and
**`flow_control: false`**. The app's default (`true`) does not work with this board. The
reason is in [docs/rcp-transport.md](thread/docs/rcp-transport.md).

### Things this project found out the hard way

- **Flow control must be off.** On the Waveshare board, the CH343's RTS line drives the
  auto-reset circuit, so HA's default hardware flow control leaves the RCP silent (0/5 in
  bench tests). With it off, the app opens the port with `uart-init-deassert`.
- **Reproducible builds need `SOURCE_DATE_EPOCH`.** ESP-IDF's OpenThread component stamps a
  CMake build timestamp into the RCP version string.
- **HA imports whatever Thread network is preferred.** When the OTBR integration first sees
  an empty radio, it loads that network into it, even a stale one from a dead hub. To start
  fresh, reset the border router, make the new network preferred, then delete the old one.
- **Restart the OTBR app after changing networks.** Its `_meshcop._udp` mDNS record kept
  advertising the old network name until the restart.

## Tested with

| Component | Version |
|---|---|
| Board | Waveshare ESP32-C6-DEV-KIT-N8 (ESP32-C6 rev v0.2, 8 MB flash) |
| ESP-IDF / OpenThread | v6.1 (`fff9895c82d`) / `b678a4f63`; Spinel 4.3, RCP API 11 |
| Home Assistant | HAOS 18.3, Core 2026.9.3, in a UTM VM on an Apple Silicon Mac |
| OTBR app / Matter Server app | 3.2.0 (ot-br-posix `v2026.08.0`) / 9.2.0 |
| Device | IKEA TIMMERFLOTTE, firmware 1.0.21, commissioned from an iPhone (iOS 27) |
