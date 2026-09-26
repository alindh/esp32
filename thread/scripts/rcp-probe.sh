#!/usr/bin/env bash
# Talk Spinel to the RCP and print its versions. Proves the firmware is an OpenThread
# RCP and gives the numbers needed to debug RCP/host (OTBR) version mismatches.
#   scripts/rcp-probe.sh [--port /dev/cu.X] [--baud 460800]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT/scripts/_lib.sh"
PORT="" BAUD=460800
while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --baud) BAUD="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$PORT" ] || PORT="$(find_port uart)"
exec "$(esptool_python)" "$ROOT/scripts/rcp_probe.py" "$PORT" "$BAUD"
