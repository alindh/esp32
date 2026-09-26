# Home Assistant setup checklist: OTBR on the ESP32-C6 RCP, then TIMMERFLOTTE

For this install: HAOS 18.3 / Core 2026.9.3 in a UTM VM on the Mac, an iPhone on the
untagged "<home SSID>" Wi-Fi, and the ZBT-2 kept on Zigbee (Zigbee2MQTT, channel 11).
Values were verified on 2026-09-26 unless marked ⚠️.

Legend: 🧑 you do it (UI, phone, hardware) · 🤖 can be done via the HA MCP · ✅ done

## 0. Before you start

- ✅ The board runs the UART RCP build. `scripts/rcp-probe.sh` reports Spinel 4.3, RCP API 11.
- ✅ HA IPv6 = Automatic on `enp0s1`. Matter integration and Matter Server 9.2.0 running.
- ✅ The OpenThread Border Router app 3.2.0 is **installed but stopped** (boot: auto).
- 🧑 Put the board on a **USB 2.0 extension cable**, away from the ZBT-2, the Mac and other
  USB 3 devices (INSTALL.md, Part B).

## 1. Pass the CH343 UART bridge into the HA VM 🧑

`utmctl usb connect` fails on UTM 4.7.5 with "OSStatus error -2700 / The device cannot be
found", by VID:PID and by location alike. So use the UTM window:

1. In the **Home Assistant** VM window toolbar, click the **USB** icon.
2. Select **USB Single Serial** (`1A86:55D3`). **Not** "USB JTAG/serial debug unit", and
   leave **ZBT-2** connected.
3. On the Mac, `ls /dev/cu.usbmodem5AF6*` should now find nothing; the VM owns the port.

**Verify** in HA: **Settings → System → Hardware → ⋮ → All hardware**, search `tty`. A new
entry should appear next to `/dev/ttyACM0` (the ZBT-2), expected
`/dev/serial/by-id/usb-1a86_USB_Single_Serial_XXXXXXXXXX-if00` ⚠️. Always use the
`by-id` path in the app; `/dev/ttyACMx` numbering can change between boots.

⚠️ Check after the next Mac/VM reboot whether UTM re-attaches the device by itself. If not,
repeat this step after each reboot. Open issue in CLAUDE.md.

## 2. Configure and start the OTBR app 🤖/🧑

**Settings → Apps → OpenThread Border Router → Configuration:**

| Option | Value | Why |
|---|---|---|
| Device | the CH343 `by-id` path from step 1 | stable across reboots |
| Baudrate | `460800` | matches `ot_rcp` (`esp_ot_config.h`) |
| Hardware flow control | **off** | **The default (on) does not work.** RTS drives the board's reset circuit, bench result 0/5. Off also makes the app use `uart-init-deassert`. See docs/rcp-transport.md. |
| OTBR firewall | on (default) | |
| NAT64 | off (default) | the TIMMERFLOTTE doesn't need IPv4 |

**Info tab:** Start on boot **on**, Watchdog **on**. Then **Start**.

**Verify, Log tab:** the settings migration reads the RCP's hardware address
`1051dbfffexxxxxx` ⚠️, `otbr-agent` starts, and there are no repeating `RCP failure` /
`Failed to communicate with RCP` lines.

## 3. Add the OpenThread Border Router integration 🤖/🧑

**Settings → Devices & services**: accept the discovered **OpenThread Border Router**.

What happens here: HA's OTBR config flow (`otbr/config_flow.py`, `_set_dataset`) loads the
current **preferred** Thread dataset into the empty radio. That is still the orphaned
**MyHomeNNNNNNNNNN** (channel 25) from the broken Aqara hub, so the C6 briefly forms that
network. Step 4 replaces it.

## 4. Replace it with a fresh HA-owned network on channel 15 🤖/🧑

HA refuses to delete the preferred dataset (`DatasetPreferredError`), so the order matters:

1. **Settings → Devices & services → Thread → Configure.** On the OTBR entry, **⋮ →
   Reset border router** ⚠️ (UI name; websocket `otbr/create_network`). HA factory-resets
   the RCP's dataset and forms a new network on **channel 15** (`DEFAULT_CHANNEL`) with a
   random PAN ID, named `ha-thread-xxxx`.
2. On the new network, **Make preferred network**.
3. On **MyHomeNNNNNNNNNN**, **⋮ → Delete** (allowed now that it isn't preferred).

**Verify:** exactly one network remains, marked preferred, channel 15, with this border
router listed under it. From the Mac:

```sh
dns-sd -B _meshcop._udp     # should list the HA border router
```

## 5. Send the Thread credentials to the iPhone 🧑

In the **HA Companion app on the iPhone** (not a browser):
**Settings → Devices & services → Thread → Configure**, and at the bottom of the preferred
network's box tap **Send credentials to phone**.

Why: iOS commissions Matter-over-Thread devices with the Thread credentials in the iPhone's
keychain. Without them, pairing fails with "this device requires a border router". The
keychain still holds the old MyHome network too; that's harmless.

## 6. Commission the TIMMERFLOTTE 🧑

Do the first pairing **within a few metres of the C6**.

1. Insert 2× AAA batteries. The sensor enters pairing mode when powered ⚠️ (per
   third-party guides; see IKEA's leaflet).
2. iPhone on "<home SSID>" / "<home 2.4 GHz SSID>", Bluetooth on.
3. HA app → **Settings → Devices & services → Matter** → **Add device** → **No, it's new.**
4. Scan the Matter QR code on the **back of the sensor**, or use **More options…** to type the
   11-digit code.
5. **Add to Home Assistant**, then wait. iOS joins it to the preferred Thread network, and the
   Matter Server takes over.

**Verify:** a device with temperature, humidity and battery entities appears under
**Matter**. In **Thread → Configure**, the network shows a new child/node.

**Factory reset** ⚠️ (third-party guide): hold the system button ~10 s, until the red LED
stops blinking. Do this before retrying if a pairing attempt got halfway.

## 7. Afterwards

- Move the sensor to its real spot. It's a sleepy end device that talks through a router,
  and your only Thread router is the C6. For rooms far away, add a mains-powered Thread
  router device later.
- If pairing fails, see the troubleshooting doc (phase 5).
