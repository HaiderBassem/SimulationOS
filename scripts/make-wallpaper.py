#!/usr/bin/env python3
"""Generate the SimulationOS wallpaper.

Pure stdlib (zlib + struct) so it runs anywhere without Pillow. Re-run to
regenerate airootfs/usr/share/backgrounds/simulationos/simulationos-alpha.png.
"""
import math
import os
import struct
import sys
import zlib

W, H = 1920, 1080
BASE = (0x10, 0x12, 0x16)      # near-black
ACCENT = (0x17, 0x93, 0xD1)    # SimulationOS blue
GLOW = (0x33, 0xCC, 0xFF)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def build_rows():
    cx, cy = W * 0.72, H * 0.28
    maxd = math.hypot(W, H)
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            # Radial falloff from an off-centre light source.
            d = math.hypot(x - cx, y - cy) / maxd
            t = max(0.0, 1.0 - d * 1.55) ** 2.2
            r, g, b = mix(BASE, ACCENT, t * 0.85)

            # Diagonal sheen.
            sheen = (math.sin((x + y) * math.pi / 900.0) + 1.0) * 0.5
            r, g, b = mix((r, g, b), GLOW, t * sheen * 0.18)

            # Faint 60px "simulation" grid, brighter near the light source.
            if x % 60 == 0 or y % 60 == 0:
                r, g, b = mix((r, g, b), GLOW, 0.05 + t * 0.10)

            row += bytes((r, g, b))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "airootfs/usr/share/backgrounds/simulationos/simulationos-alpha.png",
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write_png(out, build_rows())
    print(f"wrote {out} ({os.path.getsize(out)} bytes, {W}x{H})")
