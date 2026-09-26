#!/usr/bin/env bash
# Build ESP-IDF's ot_rcp example for the ESP32-C6 inside the pinned container.
# Output: dist/ (merged image, per-partition images, flash args, sdkconfig, manifest).
set -euo pipefail

# Resolve the *real* path: Colima only shares /Volumes/Work, so a ~/Projects alias
# would mount as an empty directory inside the container.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../firmware/config.env
source "$ROOT/firmware/config.env"

command -v docker >/dev/null || { echo "docker not found (see INSTALL.md A3)" >&2; exit 1; }

# Parallelism: this Mac has 10 cores shared by Colima and the HA VM (UTM). Overcommitting
# (ninja's default is nproc+2 = 18 jobs on 16 vCPUs) made compiles ~10x slower, so cap it.
JOBS="${BUILD_JOBS:-8}"
echo ">> Building ot_rcp for $IDF_TARGET with $IDF_IMAGE (jobs=$JOBS)"
mkdir -p "$ROOT/dist"

# Build in the container's own filesystem (fast, fixed paths); only copy results to /w.
docker run --rm \
  -e IDF_TARGET="$IDF_TARGET" -e IDF_COMMIT="$IDF_COMMIT" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e JOBS="$JOBS" \
  --cpus "$JOBS" \
  -v "$ROOT:/w" \
  -v ot-rcp-ccache:/root/.cache/ccache \
  "$IDF_IMAGE" \
  bash -c '
set -euo pipefail
actual=$(git -C "$IDF_PATH" rev-parse HEAD)
[ "$actual" = "$IDF_COMMIT" ] || { echo "IDF commit mismatch: $actual != $IDF_COMMIT" >&2; exit 1; }

# Reproducibility: ESP-IDF'"'"'s openthread component bakes a CMake string(TIMESTAMP) into the
# RCP version string. CMake honours SOURCE_DATE_EPOCH, so pin it to the IDF commit time.
export SOURCE_DATE_EPOCH="$(git -C "$IDF_PATH" log -1 --format=%ct)"

P=/tmp/ot_rcp B=/tmp/ot_rcp/build
cp -r "$IDF_PATH/examples/openthread/ot_rcp" "$P"
cd "$P"
idf.py -B "$B" \
  -D SDKCONFIG="$B/sdkconfig" \
  -D SDKCONFIG_DEFAULTS="sdkconfig.defaults;/w/firmware/sdkconfig.defaults.project" \
  set-target "$IDF_TARGET"
# set-target configured the build dir; run ninja directly so the job count is honoured.
ninja -C "$B" -j "$JOBS" all
idf.py -B "$B" -D SDKCONFIG="$B/sdkconfig" merge-bin -o merged.bin >/dev/null

D=/w/dist
rm -rf "$D"/*
cp "$B/merged.bin" "$D/ot_rcp-$IDF_TARGET-merged.bin"
cp "$B/esp_ot_rcp.bin" "$B/bootloader/bootloader.bin" "$B/partition_table/partition-table.bin" "$D/"
cp "$B/flasher_args.json" "$B/flash_args" "$D/"
cp "$B/sdkconfig" "$D/sdkconfig.used"
{
  echo "idf_version=$(cat "$IDF_PATH/version.txt" 2>/dev/null || git -C "$IDF_PATH" describe --tags)"
  echo "idf_commit=$actual"
  echo "openthread_commit=$(git -C "$IDF_PATH/components/openthread/openthread" rev-parse HEAD)"
  echo "source_date_epoch=$SOURCE_DATE_EPOCH"
  echo "target=$IDF_TARGET"
  echo "transport=$(grep -oE "^CONFIG_OPENTHREAD_RCP_(UART|SPI|USB_SERIAL_JTAG)=y" "$B/sdkconfig" | sed "s/=y//")"
} > "$D/build-info.txt"
(cd "$D" && sha256sum *.bin > SHA256SUMS)
chown -R "$HOST_UID:$HOST_GID" "$D" 2>/dev/null || true
'

echo ">> Done. Artifacts in $ROOT/dist:"
cat "$ROOT/dist/build-info.txt"
cat "$ROOT/dist/SHA256SUMS"
