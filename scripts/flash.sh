#!/usr/bin/env bash
# Flash dist/ot_rcp-<target>-merged.bin to the board from the Mac, then probe it.
#
#   scripts/flash.sh            # auto-detect the CH343 UART port
#   scripts/flash.sh --erase    # erase the whole flash first (recommended the first time)
#   scripts/flash.sh --port /dev/cu.usbmodemXXXX
#
# The board must be attached to the Mac, not captured by the UTM VM.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/firmware/config.env"
source "$ROOT/scripts/_lib.sh"

PORT="" ERASE=() BAUD=460800 PROBE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --erase) ERASE=(--erase-all); shift ;;
    --baud) BAUD="$2"; shift 2 ;;
    --no-probe) PROBE=0; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

IMG="$ROOT/dist/ot_rcp-$IDF_TARGET-merged.bin"
[ -f "$IMG" ] || { echo "missing $IMG - run scripts/build.sh first" >&2; exit 1; }
(cd "$ROOT/dist" && shasum -a 256 -c SHA256SUMS --quiet) || { echo "dist/ checksum mismatch" >&2; exit 1; }

[ -n "$PORT" ] || PORT="$(find_port uart)"
echo ">> Flashing $(basename "$IMG") to $PORT at $BAUD baud"
cat "$ROOT/dist/build-info.txt"

esptool --chip "$IDF_TARGET" --port "$PORT" --baud "$BAUD" \
  --before default-reset --after hard-reset \
  write-flash ${ERASE[@]+"${ERASE[@]}"} 0x0 "$IMG"

if [ "$PROBE" = 1 ]; then
  sleep 1
  "$ROOT/scripts/rcp-probe.sh" --port "$PORT"
fi
