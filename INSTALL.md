# INSTALL — prerequisites for the ESP32-C6 Thread RCP + Home Assistant OTBR

Everything to install, in order, before building firmware or touching Home Assistant.
Work top to bottom. Each item has **install**, **verify**, and **why**.

Facts below were checked against Espressif, Waveshare and Home Assistant sources on
**2026-09-26**. Sources are listed at the bottom. Items marked ⚠️ could not be confirmed
from an official source and must be checked when you do that step.

## Assumptions (tell me if any are wrong)

| Thing | Assumed | Why it matters |
|---|---|---|
| Dev machine | macOS 26 on Apple Silicon (arm64) | Detected on this machine. |
| Container runtime | Colima (already installed, `default` profile, aarch64) | Detected. Build runs in a container, flashing runs on the Mac. |
| Home Assistant | **Home Assistant OS** (or Supervised), any hardware | Apps (formerly "add-ons") only exist on HA OS / Supervised. HA Container or Core needs a different OTBR setup. |
| Phone | Not yet known. Both iOS and Android are covered below. | Thread credential sync differs per OS. |
| Board | Waveshare ESP32-C6-DEV-KIT-N8 (ESP32-C6-WROOM-1-N8) | Determines USB chips and ports. |

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
- **⚠️ Blocker found on 2026-09-26 — the Colima VM disk is full.** The first pull of
  the ESP-IDF image failed with `no space left on device`. What I found:

  | Where | Size |
  |---|---|
  | VM disk | 96 GB, 198 MB free |
  | What `docker system df` accounts for | ~5.6 GB |
  | Orphaned build-layer dirs in `/var/lib/docker/overlay2` (374 dirs, created Feb–Mar 2025) | ~87 GB |

  Docker does not track those layers, so `docker system prune` / `docker builder prune`
  will likely **not** free them. I did not delete anything. Pick one fix:

  1. **Recommended: a separate Colima profile just for ESP-IDF.** It is isolated, and
     your existing containers stay untouched:
     ```sh
     colima start esp --arch aarch64 --vm-type vz --cpu 8 --memory 8 --disk 40 \
       --mount /Volumes/Work:w
     docker context use colima-esp      # switch back later with: docker context use colima
     ```
  2. **Grow the default VM disk.** This is non-destructive. Colima can grow a disk but
     never shrink it:
     ```sh
     colima stop && colima start --disk 150
     ```
  3. **Reclaim the orphaned layers.** This is your call, since they may relate to other
     projects. The clean way is `docker save` any images you need, then
     `colima delete` + `colima start`, which recreates the VM from scratch.

  **Verify:** `colima ssh -- df -h /` shows **at least 15 GB free** before continuing to A4.
  If you choose option 1, also run `docker context show`; it must print `colima-esp`.

### A4. ESP-IDF v6.1 container image (pinned)

ESP-IDF **v6.1** is the current stable release (published 2026-08-27, marked "Latest"
on GitHub). The `v6.1` tag is pinned to a digest so a later re-push cannot change the
toolchain under you.

- **Install:**
  ```sh
  docker pull espressif/idf:v6.1@sha256:81893c71bb5e570088901f21def8684c25cd2a9020281bd01b843a7655edb18c
  ```
  The image is several GB.
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

| Port | Chip | USB VID:PID ⚠️ | Typical macOS name ⚠️ |
|---|---|---|---|
| UART bridge | WCH **CH343** → ESP32-C6 UART0 | `1a86:55d3` | `/dev/cu.usbmodem…` |
| Native USB | ESP32-C6 **USB Serial/JTAG** | `303a:1001` | `/dev/cu.usbmodem…` |

Both chips are USB CDC-ACM devices, which macOS supports with its built-in driver.
Neither Espressif's nor Waveshare's docs say this explicitly for macOS 26, hence ⚠️.

- **Install:** nothing yet. Plug the board in with a **data-capable** USB-C cable.
- **Verify:**
  ```sh
  ls /dev/cu.usbmodem*                       # expect TWO new entries
  ioreg -p IOUSB -l -w0 | grep -E '"USB Product Name"|"idVendor"|"idProduct"'
  # expect a CH334 hub, a CH343 / "USB Single Serial" device (idVendor 6790 = 0x1a86)
  # and "USB JTAG/serial debug unit" (idVendor 12346 = 0x303a)
  esptool --port /dev/cu.usbmodemXXXX chip-id   # run on each port: both should report ESP32-C6
  ```
  Send me the output of the `ls` and `ioreg` commands. I'll pin the exact device names
  in the repo.
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
| **USB 2.0 extension cable**, 0.5–1 m | Moves the 2.4 GHz radio away from the HA host. USB 3 ports and cables emit noise in the 2.4 GHz band that degrades Thread, Zigbee and Bluetooth. |
| AAA batteries ×2 for the TIMMERFLOTTE | The sensor enters pairing mode when batteries are inserted. |

On the HA host, plan to plug the board (via the extension) into a **USB 2.0 port** if
the host has one. On a Raspberry Pi the USB 2.0 ports are the black ones; the blue ones
are USB 3.

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

In both cases the phone does the Bluetooth part of commissioning, then hands the device
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

If you own a HomePod mini/HomePod 2 or an Apple TV 4K, those already run an Apple
Thread network. That is fine, but tell me. It changes how we pick the preferred network
in step 4.

### D-Android

| Item | Install | Verify | Why |
|---|---|---|---|
| Android 8.1 minimum, **12+ recommended** | System update | **Settings → About phone** | HA's minimum for Matter commissioning. |
| HA Companion app, **full** Play Store version | Play Store: "Home Assistant" | App → **Settings → Companion app → About** | The F-Droid "minimal" build lacks Google Play services, so it cannot commission Matter or sync Thread credentials. |
| Google Play services up to date | Play Store → Google Play services | **Settings → Apps → Google Play services** | Android's Matter commissioning and Thread credential store are part of Play services. |
| Location permission **Allow all the time** for the HA app | **Settings → Apps → Home Assistant → Permissions → Location** | shows "Allow all the time" | HA's docs require it for Matter commissioning. |
| Nearby devices + Bluetooth on | App permissions / quick settings | — | BLE commissioning. |
| Phone on the same Wi-Fi as HA | — | — | Same as iOS. |

If you own Google/Nest Thread border routers (Nest Hub 2nd gen, Nest Wi-Fi Pro), tell
me. It affects step 4.

---

## Done? Checklist to send back

- [ ] `idf.py --version` output from the container (A4)
- [ ] `esptool version` (A5)
- [ ] `ls /dev/cu.usbmodem*` and the `ioreg` lines with the board plugged in (A6)
- [ ] HA install type and hardware, Core version, and whether the host has USB 2.0 ports (C1)
- [ ] OTBR app and Matter Server app versions (C3, C5)
- [ ] Phone OS and version, and any Apple/Google Thread border routers you own (D)

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
