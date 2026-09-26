"""Minimal Spinel-over-HDLC-lite client: query an OpenThread RCP's versions.

Frame format per the Spinel spec (draft-rquattle-spinel-unified) and OpenThread's
src/lib/hdlc: 0x7E | escaped(payload + FCS16 little-endian) | 0x7E,
FCS = CRC-16/X.25 (reflected 0x8408, init 0xFFFF, xorout 0xFFFF).
"""
import sys
import time

import serial

FLAG, ESC = 0x7E, 0x7D
ESCAPED = {0x7E, 0x7D, 0x11, 0x13, 0xF8}

CMD_PROP_VALUE_GET, CMD_PROP_VALUE_IS = 2, 6
PROPS = {
    "protocol_version": 1,
    "ncp_version": 2,
    "hwaddr": 8,
    "rcp_api_version": 0xB0,
    "rcp_min_host_api_version": 0xB1,
}


def fcs16(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc ^ 0xFFFF


def packed_uint(v: int) -> bytes:
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        out.append(b | (0x80 if v else 0))
        if not v:
            return bytes(out)


def read_packed_uint(buf: bytes, i: int):
    v = shift = 0
    while True:
        b = buf[i]
        i += 1
        v |= (b & 0x7F) << shift
        shift += 7
        if not b & 0x80:
            return v, i


def encode(payload: bytes) -> bytes:
    fcs = fcs16(payload)
    raw = payload + bytes([fcs & 0xFF, fcs >> 8])
    out = bytearray([FLAG])
    for b in raw:
        if b in ESCAPED:
            out += bytes([ESC, b ^ 0x20])
        else:
            out.append(b)
    out.append(FLAG)
    return bytes(out)


def frames(buf: bytearray):
    """Yield decoded, FCS-valid frames from buf (consumes complete frames)."""
    while True:
        try:
            start = buf.index(FLAG)
            end = buf.index(FLAG, start + 1)
        except ValueError:
            return
        chunk = bytes(buf[start + 1:end])
        del buf[:end]
        if not chunk:
            continue
        dec, esc = bytearray(), False
        for b in chunk:
            if esc:
                dec.append(b ^ 0x20)
                esc = False
            elif b == ESC:
                esc = True
            else:
                dec.append(b)
        if len(dec) >= 3 and fcs16(bytes(dec[:-2])) == (dec[-2] | dec[-1] << 8):
            yield bytes(dec[:-2])


def query(ser, rx: bytearray, tid: int, prop: int, timeout=1.5):
    header = 0x80 | (tid & 0x0F)  # flag bits 10, IID 0
    ser.write(encode(bytes([header, CMD_PROP_VALUE_GET]) + packed_uint(prop)))
    deadline = time.time() + timeout
    while time.time() < deadline:
        rx += ser.read(256)
        for f in frames(rx):
            if f[0] != header or f[1] != CMD_PROP_VALUE_IS:
                continue
            p, i = read_packed_uint(f, 2)
            if p == prop:
                return f[i:]
    return None


def main():
    port, baud = sys.argv[1], int(sys.argv[2])
    print(f">> Spinel probe on {port} @ {baud} baud (8N1, no flow control)")
    ser = serial.Serial()
    ser.port, ser.baudrate, ser.timeout, ser.rtscts = port, baud, 0.1, False
    # Set DTR/RTS before opening: on this board they drive the CH343 auto-reset circuit
    # (EN / GPIO9), and toggling them could reset the chip or strap it into the bootloader.
    ser.dtr = False
    ser.rts = False
    ser.open()
    time.sleep(0.3)
    ser.reset_input_buffer()
    rx = bytearray()
    results = {}
    for attempt in range(2):  # the RCP may still be booting right after a reset
        for n, (name, prop) in enumerate(PROPS.items(), start=1):
            results[name] = query(ser, rx, n, prop)
        if any(v is not None for v in results.values()):
            break
        time.sleep(1.0)
        ser.reset_input_buffer()
    ser.close()

    if all(v is None for v in results.values()):
        print("!! No Spinel response. Not an RCP image, wrong baud rate, or port held by another program.")
        return 1

    def uint(v):
        return read_packed_uint(v, 0)[0] if v else None

    pv = results["protocol_version"]
    if pv:
        major, i = read_packed_uint(pv, 0)
        minor, _ = read_packed_uint(pv, i)
        print(f"Spinel protocol version : {major}.{minor}")
    nv = results["ncp_version"]
    if nv:
        version = nv.split(b"\x00")[0].decode(errors="replace").strip()
        print(f"RCP firmware version    : {version}")
    hw = results["hwaddr"]
    if hw:
        print(f"802.15.4 EUI-64         : {hw[:8].hex(':')}")
    print(f"RCP API version         : {uint(results['rcp_api_version'])}")
    print(f"Min host RCP API version: {uint(results['rcp_min_host_api_version'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
