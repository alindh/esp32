# RCP transport: UART bridge vs native USB

**Decision (2026-09-26): the CH343 UART bridge, 460800 baud, 8N1, no hardware flow control.**
This is the stock `ot_rcp` configuration. The only HA setting that differs from the app's
defaults is `flow_control: false`.

## The board's two ports

One USB-C connector feeds an onboard CH334 hub. The hub exposes two serial devices, so one
cable gives two ports:

| | UART bridge | Native USB |
|---|---|---|
| Chip | WCH CH343 → ESP32-C6 UART0 | ESP32-C6 USB Serial/JTAG |
| USB ID | `1a86:55d3` | `303a:1001` |
| macOS | `/dev/cu.usbmodemXXXXXXXXXX1` | `/dev/cu.usbmodem831401` |
| Linux (HA VM) ⚠️ | expected `/dev/serial/by-id/usb-1a86_USB_Single_Serial_XXXXXXXXXX-if00` | expected `/dev/serial/by-id/usb-Espressif_USB_JTAG_serial_debug_unit_10:51:db:xx:xx:xx-if00` |
| Firmware option | `CONFIG_OPENTHREAD_RCP_UART` (example default) | `CONFIG_OPENTHREAD_RCP_USB_SERIAL_JTAG` |
| Survives a chip reset | **Yes.** The CH343 is a separate chip and stays enumerated. | No. The USB device disconnects and re-enumerates whenever the C6 resets. |
| Extra wiring | DTR/RTS drive the EN/GPIO9 auto-reset circuit | none |

⚠️ The Linux paths are predicted from udev's naming rules. Confirm them in HA under
**Settings → System → Hardware → All hardware** once the port is passed through.

## What the HA OTBR app does to the port

From `openthread_border_router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/run` in
home-assistant/addons at commit `ceb80015`, app version 3.2.0:

```
spinel+hdlc+uart://${device}?uart-baudrate=${baudrate}${flow_control}
  flow_control: true  -> &uart-flow-control    (RTS/CTS on)
  flow_control: false -> &uart-init-deassert   (DTR and RTS driven low on open)
```

Before `otbr-agent` starts, `migrate_otbr_settings.py` opens the port the same way. With
flow control off it drives RTS/DTR low, sends a Spinel stack reset, and reads HWADDR.

App defaults (`config.yaml`): `baudrate: "460800"`, **`flow_control: true`**.
Firmware (`ot_rcp/main/esp_ot_config.h`, ESP-IDF v6.1): `460800`, `UART_HW_FLOWCTRL_DISABLE`.
The baud rate is a constant in that header, not a Kconfig option, so there is no sdkconfig
line for it. We keep the upstream value because it already matches the app's default.

## Bench tests (macOS, CH343 port, UART firmware, 2026-09-26)

Each cycle opens the port, sends Spinel `RESET` (stack), closes, reopens, and waits up to
5 s for `PROP_NCP_VERSION`. This is the sequence OTBR and its migration script perform.

| How the port is opened | Equivalent HA setting | Result |
|---|---|---|
| DTR/RTS low (init-deassert) | `flow_control: false` | **20/20 recovered**, port never disappeared |
| RTS/CTS hardware flow control | `flow_control: true` (the default) | **0/5**: the RCP never answers |
| DTR/RTS both high | a naive tool | 10/10 recovered: the auto-reset circuit ignores "both high" |

With flow control on, RTS is under the UART's control, and on this board RTS is wired to
the auto-reset circuit rather than to a C6 CTS pin. The link cannot work, which is why
`flow_control: false` is mandatory.

## Why not native USB

- **UTM passthrough.** HA runs in a UTM VM, and the RCP reaches it by USB redirection. The
  native USB device disappears on every C6 reset, and OTBR resets the RCP at startup and
  during recovery. Each reset forces UTM to recapture a re-enumerated device. The CH343
  never re-enumerates, so the VM always keeps the same device.
- **Seen stuck.** Before a power cycle, the native port stopped answering esptool even with
  the ROM confirmed in download mode. It only recovered after a replug.
- **No advantage here.** Its benefits, no baud limit and no reset circuit, don't matter:
  460800 baud is plenty for 802.15.4's 250 kbit/s, and init-deassert neutralises the reset
  circuit.

A native-USB variant exists for experiments (`firmware/variants/usb-serial-jtag.defaults`,
built into `dist-usb/`). Flashed on 2026-09-26, it answered **0/20** reset cycles and no plain
probe either, while the port stayed present. That is the same "enumerated but silent"
symptom seen earlier, which only a power cycle cleared. Without a power cycle between flashing
and testing, the result is inconclusive. Either way, it doesn't support switching to native
USB.

## HA OTBR app settings to use

| Option | Value |
|---|---|
| `device` | the CH343 `by-id` path from the Hardware page (see ⚠️ above) |
| `baudrate` | `460800` |
| `flow_control` | **`false`** |

Leave everything else at the defaults. Phase 4's checklist covers the full setup.
