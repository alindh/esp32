# INSTALL — prerequisites for the ESP32-C6 Thread RCP + Home Assistant OTBR

Everything to install, in order, before building firmware or touching Home Assistant.
Work top to bottom. Each item has **install**, **verify**, and **why**.

Facts below were checked against Espressif, Waveshare and Home Assistant sources on
**2026-09-26**. Sources are listed at the bottom. Items marked ⚠️ could not be confirmed
from an official source and must be checked when you do that step.

## Your setup (confirmed 2026-09-26)

| Thing | Value | Why it matters |
|---|---|---|
| Dev machine | macOS 26.3, Apple Silicon | Build in a container, flash from the Mac. |
| Container runtime | Colima, `default` profile, aarch64 | Only `/Volumes/Work` is shared into containers. |
| Home Assistant | **HAOS 17.0.rc1 (aarch64) in a UTM VM on this same Mac** (QEMU backend, `/Volumes/Work/VM/Home Assistant.utm`) | The C6 reaches HA by UTM USB passthrough, and the VM's network must carry IPv6 and multicast. |
| VM network | UTM **bridged** to `en0` (wired Ethernet) | Good: HA sits directly on your LAN. The Mac also has a VLAN "IoT_Network" on `en0`; HA is on the untagged LAN. |
| Phone | **iPhone** | Uses "Send credentials to phone" in the HA app. |
| Other radios | Home Assistant **Connect ZBT-2**, passed to the VM, **stays on Zigbee** | The C6 does Thread only. Keep the two radios apart and on non-overlapping channels. |
| Other Thread border routers | None | The HA network will be the only Thread network, which keeps the preferred-network step simple. |
| Board | Waveshare ESP32-C6-DEV-KIT-N8 | See A6 for the ports. |

---

## Part A — Dev machine (macOS, Apple Silicon)

### Recommendation: build in a pinned container, flash from the Mac

- **Build** uses the official `espressif/idf` image, **pinned by digest**. That gives a
  byte-for-byte reproducible toolchain, and the image is native arm64 so it runs at
  full speed under Colima.
- **Flash** runs on the Mac with `esptool`. Colima (like Docker Desktop) cannot pass
  USB devices into containers on macOS, so the container never touches the board.
- A native ESP-IDF install is **optional** (A7). Skip it unless you want to hack on
  firmware outside the container.

### A1. Xcode Command Line Tools + git

- **Install:** `xcode-select --install` (skip if already installed; you have git 2.50.1).
- **Verify:**
  ```sh
  xcode-select -p        # prints /Library/Developer/CommandLineTools (or Xcode path)
  git --version          # git version 2.x
  ```
- **Why:** git for this repo; CLT provides the compilers Homebrew formulae expect.

### A2. Homebrew

- **Install:** already installed (Homebrew 7.0.4). Otherwise see https://brew.sh.
- **Verify:** `brew --version && brew doctor`
- **Why:** installs esptool and (optionally) Espressif's installer.

### A3. Colima + Docker CLI (container runtime)

- **Install:** already installed. Otherwise: `brew install colima docker`
- **Verify:**
  ```sh
  colima status          # "colima is running", arch: aarch64
  docker info --format '{{.Architecture}}'   # aarch64
  ```
- **⚠️ Important — shared folders.** Your Colima config (`~/.colima/default/colima.yaml`)
  shares only `/Volumes/Work` with the VM. The path `~/Projects/esp32/thread` points at
  the same folder on the Mac, but **inside a container it shows up empty**. I tested
  this. Always mount the project by its real path:
  ```sh
  docker run --rm -v /Volumes/Work/Projects/esp32/thread:/w alpine:3 ls /w   # must list INSTALL.md
  ```
  The build script will resolve the real path itself, but keep this in mind for manual
  `docker run` commands.
- **Why:** runs the pinned ESP-IDF toolchain without installing it on the Mac.
- **Disk space (resolved 2026-09-26).** The Colima VM disk was full. Docker 29 had
  switched to the containerd image store, so the ~89 GB legacy
  `/var/lib/docker/overlay2` directory was unused. It was deleted with your approval.
  Running containers were unaffected.
  **Verify:** `colima ssh -- df -h /` shows **at least 15 GB free** before A4.

### A4. ESP-IDF v6.1 container image (pinned)

ESP-IDF **v6.1** is the current stable release (published 2026-08-27, marked "Latest"
on GitHub). The `v6.1` tag is pinned to a digest so a later re-push cannot change the
toolchain under you.

- **Install:**
  ```sh
  docker pull espressif/idf:v6.1@sha256:81893c71bb5e570088901f21def8684c25cd2a9020281bd01b843a7655edb18c
  ```
  The image is several GB. Already pulled and verified on 2026-09-26.
- **Verify:**
  ```sh
  docker run --rm espressif/idf:v6.1@sha256:81893c71bb5e570088901f21def8684c25cd2a9020281bd01b843a7655edb18c idf.py --version
  # expected: ESP-IDF v6.1
  ```
- **Why:** contains ESP-IDF, the RISC-V toolchain, CMake, Ninja and the Python env
  needed to build `examples/openthread/ot_rcp`. Python 3.10+ is required by ESP-IDF;
  the image ships its own, so your Homebrew Python 3.14 is not used for building.
- **Fallback:** if v6.1 misbehaves, v6.0.3 (bug-fix release, 2026-09-02) is the
  conservative alternative. The repo will make the version a single variable.

### A5. esptool (on the Mac, for flashing)

- **Install:** `brew install esptool` (currently 5.4.0).
- **Verify:**
  ```sh
  esptool version        # 5.4.0
  ```
  esptool 5.x names the command `esptool` (the old `esptool.py` still works as an
  alias) and uses hyphenated subcommands: `write-flash`, `chip-id`, `erase-flash`.
- **Why:** writes the built RCP firmware to the C6 over USB. It is the only tool that
  must talk to the board directly.

### A6. USB-serial driver (probably **none** needed)

What the board has, per Waveshare: **one USB-C port** feeding an onboard **CH334 USB
hub**. Behind the hub are two USB devices, so one cable gives you **two serial ports**:

| Port | Chip | USB VID:PID | macOS device (confirmed on your Mac) |
|---|---|---|---|
| (hub) | WCH **CH334** | `1a86:8091` | — |
| UART bridge | WCH **CH343** → ESP32-C6 UART0 (name "USB Single Serial") | `1a86:55d3` | `/dev/cu.usbmodemXXXXXXXXXX1` |
| Native USB | ESP32-C6 **USB Serial/JTAG** (name "USB JTAG/serial debug unit") | `303a:1001` | `/dev/cu.usbmodem831401` |

**Confirmed 2026-09-26: no driver is needed.** Both ports appeared with macOS's built-in
CDC driver. The names can change if you move the board to another USB port.

- **Install:** nothing yet. Plug the board in with a **data-capable** USB-C cable.
- **Verify:**
  ```sh
  ls /dev/cu.usbmodem*                       # expect TWO new entries
  ioreg -p IOUSB -l -w0 | grep -E '"USB Product Name"|"idVendor"|"idProduct"'
  # expect a CH334 hub, a CH343 / "USB Single Serial" device (idVendor 6790 = 0x1a86)
  # and "USB JTAG/serial debug unit" (idVendor 12346 = 0x303a)
  esptool --port /dev/cu.usbmodemXXXX chip-id   # run on each port: both should report ESP32-C6
  ```
- **Fallback, only if no CH343 port appears:** install WCH's macOS driver. Waveshare
  links it from their wiki ("MAC driver", `CH34XSER_MAC.7z`); WCH also publishes it at
  https://www.wch-ic.com/downloads/CH34XSER_MAC_ZIP.html. After installing, approve it
  in **System Settings → Privacy & Security**. The port then appears as
  `/dev/cu.wchusbserial…`.
- **Why:** esptool needs a serial port to flash. The same two ports decide how the RCP
  talks to Home Assistant, which is step 3 of the project.

### A7. (Optional) Native ESP-IDF via Espressif Installation Manager

Only if you want `idf.py` directly on the Mac. EIM is Espressif's recommended installer
for ESP-IDF v6.0 and newer.

- **Install:**
  ```sh
  brew install libgcrypt glib pixman sdl2 libslirp dfu-util cmake python
  brew tap espressif/eim
  brew install eim
  eim install -i v6.1
  ```
- **Verify:** EIM prints "Successfully installed IDF". Then, in a new shell after
  activating the environment EIM tells you about: `idf.py --version` → `ESP-IDF v6.1`.
- **Why:** faster edit-build loops and `idf.py monitor`. Not needed for this project.

---

## Part B — Hardware

| Item | Why |
|---|---|
| USB-C **data** cable | Charge-only cables are the #1 cause of "no serial port". |
| **Two USB 2.0 extension cables**, 1 m+ (one for the C6, one for the ZBT-2) | Moves the 2.4 GHz radio away from the HA host. USB 3 ports and cables emit noise in the 2.4 GHz band that degrades Thread, Zigbee and Bluetooth. |
| AAA batteries ×2 for the TIMMERFLOTTE | The sensor enters pairing mode when batteries are inserted. |

Right now the C6 board and the ZBT-2 hang off the **same Apple hub** on this Mac, and that
hub also has a 10 Gb/s USB 3 side. Two 2.4 GHz radios next to each other, next to USB 3,
is the worst case for both Zigbee and Thread. Give **each radio its own USB 2.0 extension
cable** and keep the radios **at least about 1 m apart**, and away from the Mac, the
monitor, the Cam Link and the USB 3 Ethernet adapter.

---

## Part B2 — The UTM VM that runs Home Assistant

Checked on 2026-09-26 from the running VM. Items to confirm in UTM are marked ⚠️.

### B2.1 USB passthrough slot

- **What you have:** the VM runs on UTM's QEMU backend with an emulated USB controller
  and **3 USB redirection slots**. The ZBT-2 already uses one.
- **Install:** nothing. In phase 3 you'll pass **one** of the C6's two ports to the VM
  (UTM toolbar → USB icon → pick the device). Only one of them goes to the VM; the hub
  itself stays on the Mac.
- **Verify (later):** in HA, **Settings → System → Hardware → All hardware** lists a
  `/dev/ttyACM…` or `/dev/serial/by-id/…` entry for the C6.
- **Why:** the OTBR app inside the VM must own the serial port. While the VM holds it,
  the Mac can't flash the board; release it in UTM first.

### B2.2 The VM and the Mac stay up

- **Current state:** macOS system sleep is **off** (`sleep 0`), and restart after power
  failure is **on**. Good.
- **⚠️ Check in UTM:** make sure the VM starts automatically after a Mac reboot.
  - Mac: **System Settings → General → Login Items → Open at Login → add UTM**.
  - Then either start the VM by hand after reboots, or have a login item run
    `open "utm://start?name=Home%20Assistant"`.
- **Why:** the Mac is now your Thread border router. When the VM stops, the Thread
  network keeps its mesh, but HA loses every Thread device.

### B2.3 HAOS release channel

- **Current state:** the VM runs **HAOS 17.0.rc1**, a release candidate.
- **Recommendation:** fine to keep. If something odd shows up with USB or networking,
  first check whether stable HAOS behaves the same.
- **Verify:** **Settings → About** shows the Operating System version.

### B2.4 Same network for the iPhone and HA

- **Confirmed 2026-09-26:** the iPhone uses the Wi-Fi networks **"<home 2.4 GHz SSID>"** and
  **"<home SSID>"**. Both are **untagged**, so they share a LAN with HA on `en0`. Keep the
  iPhone off the "IoT_Network" VLAN during commissioning.
- **Verify (after the OTBR app is started in phase 4):** from the Mac, which is on the
  same LAN, run the command below. HA's border router should appear within a few seconds.
  If the Mac sees it but the iPhone still reports "Thread border router required", check
  the access point for multicast filtering or "multicast to unicast" and IGMP-snooping
  options.
  ```sh
  dns-sd -B _meshcop._udp
  ```
- **Why:** during commissioning the iPhone must find HA's Thread border router via mDNS
  and reach HA directly. mDNS and IPv6 link-local traffic don't cross VLANs.

---

## Part C — Home Assistant (HA OS)

Home Assistant renamed add-ons to **apps**. The menu is now **Settings → Apps**.

Install everything now. **Do not configure or start the OpenThread Border Router app
yet.** Its settings depend on firmware decisions we make in steps 2–3.

### C1. Home Assistant up to date

- **Install:** **Settings → System → Updates**, install any Core / OS / Supervisor updates.
- **Verify:** **Settings → About** shows Core **2025.7.0 or newer**. That is the minimum
  the current OTBR app (3.2.0) declares.
- **Why:** older Core versions cannot run the current OTBR app.

### C2. IPv6 enabled, set to Automatic

- **Install:** **Settings → System → Network**. Set IPv6 to **Automatic** on the main
  interface, then save.
- **Verify:** the network page shows an IPv6 address (at least a link-local `fe80::`
  one) on that interface.
- **Why:** Thread is IPv6-only. HA must accept router advertisements to learn the route
  into the Thread network. People who pair IKEA Matter sensors have hit failures caused
  by a **static** IPv6 setting that ignores those advertisements.

### C3. OpenThread Border Router app

- **Install:** **Settings → Apps → App store → OpenThread Border Router → Install**.
  Do **not** press Start yet.
- **Verify:** the app page shows version **3.2.0** or newer (OTBR POSIX `v2026.08.0`).
- **Why:** runs the Thread border router (`ot-br-posix`) on the HA host. It drives the
  ESP32-C6 RCP over USB and routes between Thread and your LAN.
- **Heads-up for later:** the app defaults to **baudrate 460800** and **hardware flow
  control ON**. Espressif's `ot_rcp` example uses 460800 with flow control **OFF**. We
  will set this in step 3; do not change anything yet.

### C4. Thread and OpenThread Border Router integrations

- **Install:** nothing to do now. Once the OTBR app is started (later step), HA
  auto-discovers it. You will then accept **OpenThread Border Router** under
  **Settings → Devices & services**, which also brings in the **Thread** integration.
- **Verify (later):** **Settings → Devices & services** lists both **OpenThread Border
  Router** and **Thread**.
- **Why:** the Thread integration holds network credentials, picks the *preferred*
  network, and shares credentials with the Companion app.

### C5. Matter integration + Matter Server app

- **Install:** **Settings → Devices & services → Add integration → Matter**, then
  **Submit**. On HA OS this installs and starts the official **Matter Server** app for
  you.
- **Verify:**
  - **Settings → Devices & services** lists **Matter**.
  - **Settings → Apps → Matter Server** shows **9.2.0 or newer** and is running.
- **Why:** the Matter Server is the Matter controller that commissions and talks to the
  TIMMERFLOTTE.
- **Version note:** **Matter Server 9.0.x** had a reported bug where TIMMERFLOTTE
  commissioning hung at PASE and timed out. The issue is home-assistant/addons#4677, and
  it was closed as not planned. Make sure you are on 9.2.0+ and not pinned to an old
  version with the `matter_server_version` option.

---

## Part D — Phone

The iPhone does the Bluetooth part of commissioning, then hands the device
the Thread credentials. So the phone must **know your HA Thread network's credentials**.
That sync happens in step 4, but the prerequisites are below.

### D-iOS

| Item | Install | Verify | Why |
|---|---|---|---|
| iOS 16 or newer | **Settings → General → Software Update** | **Settings → General → About** | Apple's Matter framework, used by the HA app for commissioning, needs iOS 16+. |
| HA Companion app, latest | App Store: "Home Assistant" | App → **Settings → Companion App → About** | Commissioning and **Send credentials to phone** live in the app. |
| Bluetooth on | Control Center | — | Matter commissioning starts over BLE. |
| Local Network permission ⚠️ | **Settings → Privacy & Security → Local Network → Home Assistant = On** | toggle is on | Without it the app cannot reach HA or discover devices on the LAN. |
| Phone on the same LAN/Wi-Fi as HA | — | — | The phone must reach HA directly, not through remote access. |

You said you own no HomePod or Apple TV. So the iPhone will only know HA's Thread
network, which avoids the most common "wrong preferred network" problem.

---

## Done? Checklist to send back

- [x] ESP-IDF image pulled; `idf.py --version` = ESP-IDF v6.1 (A4, done 2026-09-26)
- [ ] `esptool version` (A5)
- [x] Board ports identified; no driver needed (A6)
- [ ] Two USB 2.0 extension cables in hand (B)
- [ ] UTM starts the VM after a Mac reboot (B2.2)
- [x] iPhone on untagged Wi-Fi "<home 2.4 GHz SSID>" / "<home SSID>" (B2.4)
- [ ] HA Core version; IPv6 set to Automatic (C1, C2)
- [ ] OTBR app installed but not started; Matter Server app version (C3, C5)
- [ ] iOS version (D)
- [ ] ZBT-2's current Zigbee channel: **Settings → Devices & services → Zigbee Home Automation → Configure** (needed to pick the Thread channel)

---

## Sources (checked 2026-09-26)

- ESP-IDF releases and tags: https://github.com/espressif/esp-idf/releases
- ESP-IDF v6.1 macOS setup (EIM): https://docs.espressif.com/projects/esp-idf/en/v6.1/esp32c6/get-started/macos-setup.html
- `ot_rcp` UART config (460800 baud, HW flow control disabled): https://github.com/espressif/esp-idf/blob/v6.1/examples/openthread/ot_rcp/main/esp_ot_config.h
- Docker image tags and digests: https://hub.docker.com/r/espressif/idf/tags
- esptool 5.4.0: https://pypi.org/project/esptool/
- Waveshare board (CH343 + CH334, single USB-C): https://www.waveshare.com/wiki/ESP32-C6-DEV-KIT-N8 and https://docs.waveshare.com/ESP32-C6-DEV-KIT-N8
- OTBR app config and defaults: https://github.com/home-assistant/addons/blob/master/openthread_border_router/config.yaml
- OTBR app changelog: https://github.com/home-assistant/addons/blob/master/openthread_border_router/CHANGELOG.md
- Matter Server app config and changelog: https://github.com/home-assistant/addons/tree/master/matter_server
- HA Thread integration: https://www.home-assistant.io/integrations/thread/
- HA Matter integration: https://www.home-assistant.io/integrations/matter/
- TIMMERFLOTTE PASE timeout on Matter Server 9.0.x: https://github.com/home-assistant/addons/issues/4677
- Static IPv6 breaking IKEA Matter pairing: https://majornetwork.net/2026/01/home-assistant-was-unable-to-add-ikea-matter-devices/
