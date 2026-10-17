#!/usr/bin/env python3
"""Write a 1024px app icon so the asset catalog can compile on CI."""

import pathlib
import struct
import zlib

SIZE = 1024
OUT = pathlib.Path("PiliPlus/Assets.xcassets/AppIcon.appiconset/AppIcon.png")


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def main() -> None:
    raw = bytearray()
    cx = cy = (SIZE - 1) / 2
    outer = SIZE * 0.46
    inner = SIZE * 0.34
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE):
            dx = x - cx
            dy = y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= inner:
                raw += bytes((251, 114, 153, 255))
            elif d <= outer:
                raw += bytes((28, 28, 34, 255))
            else:
                raw += bytes((0, 0, 0, 0))
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(png)


if __name__ == "__main__":
    main()
