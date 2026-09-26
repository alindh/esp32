# Shared helpers for host-side scripts (sourced, not executed).
# Python that ships with Homebrew's esptool; it includes pyserial.
esptool_python() {
  local p
  p="$(brew --prefix esptool 2>/dev/null)/libexec/bin/python"
  [ -x "$p" ] || { echo "esptool (Homebrew) not found: brew install esptool" >&2; return 1; }
  echo "$p"
}

# find_port uart|usb  -> prints /dev/cu.* for the board's CH343 bridge or native USB.
#   uart: WCH CH343   1a86:55d3
#   usb:  Espressif USB Serial/JTAG 303a:1001
find_port() {
  local kind="$1" vidpid py
  case "$kind" in
    uart) vidpid="1a86:55d3" ;;
    usb)  vidpid="303a:1001" ;;
    *) echo "find_port: kind must be uart|usb" >&2; return 2 ;;
  esac
  py="$(esptool_python)" || return 1
  "$py" - "$vidpid" <<'PY'
import sys
from serial.tools import list_ports
vid, pid = (int(x, 16) for x in sys.argv[1].split(":"))
hits = [p.device for p in list_ports.comports()
        if p.vid == vid and p.pid == pid and p.device.startswith("/dev/cu.")]
if len(hits) != 1:
    sys.stderr.write(f"expected exactly one {sys.argv[1]} port, found {hits or 'none'}.\n"
                     "Is the board plugged into the Mac (not passed through to the UTM VM)?\n")
    sys.exit(1)
print(hits[0])
PY
}
