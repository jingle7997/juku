#!/usr/bin/env python3
"""从一张 1024x1024 源图生成 iOS AppIcon 全套尺寸。

纯标准库实现，不依赖 Pillow（本机 PyPI 不通）。
流程：解析 PNG → 反滤波 → 转 RGB（丢 alpha）→ 面积平均缩放 → 重新编码。

面积平均（box filter）在 1024 → 20 这种 50 倍降采样下最稳，不会像
Lanczos 那样在波点/描边处产生振铃光晕。

用法：

    python app/tool/make_app_icons.py 源图.png
    python app/tool/make_app_icons.py 源图.png --dir <AppIcon.appiconset 目录>

要求源图为正方形，建议 1024x1024。
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

DEFAULT_DIR = Path(__file__).resolve().parent.parent / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

# (文件名, 目标边长) —— 与 Contents.json 的声明严格对应
TARGETS: list[tuple[str, int]] = [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

PNG_SIG = b"\x89PNG\r\n\x1a\n"
CT_GRAY, CT_RGB, CT_PALETTE, CT_GRAY_A, CT_RGBA = 0, 2, 3, 4, 6
CHANNELS = {CT_GRAY: 1, CT_RGB: 3, CT_PALETTE: 1, CT_GRAY_A: 2, CT_RGBA: 4}


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _unfilter(raw: bytes, width: int, height: int, bpp: int) -> list[bytearray]:
    stride = width * bpp
    rows: list[bytearray] = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if ftype == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                ul = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(left, prev[i], ul)) & 0xFF
        elif ftype != 0:
            raise ValueError(f"未知滤波类型 {ftype}")
        rows.append(line)
        prev = line
    return rows


def decode_rgb(path: Path) -> tuple[int, int, list[bytearray]]:
    """读 PNG，返回 (宽, 高, 每行 RGB 字节)。alpha 直接丢弃。"""
    data = path.read_bytes()
    if data[:8] != PNG_SIG:
        raise ValueError(f"{path.name} 不是 PNG")
    pos = 8
    w = h = bitdepth = colortype = interlace = None
    idat: list[bytes] = []
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            w, h, bitdepth, colortype, _comp, _filt, interlace = struct.unpack(">IIBBBBB", payload)
        elif ctype == b"IDAT":
            idat.append(payload)
        elif ctype == b"IEND":
            break

    if bitdepth != 8:
        raise ValueError(f"只支持 8 位深，当前 {bitdepth}")
    if interlace:
        raise ValueError("不支持隔行扫描 PNG")
    if colortype == CT_PALETTE:
        raise ValueError("不支持调色板 PNG，请先转成真彩色")

    bpp = CHANNELS[colortype]
    raw = zlib.decompress(b"".join(idat))
    lines = _unfilter(raw, w, h, bpp)

    out: list[bytearray] = []
    if colortype == CT_RGB:
        return w, h, lines
    for line in lines:
        if colortype == CT_GRAY:
            row = bytearray(w * 3)
            row[0::3] = line[0::1]
            row[1::3] = line[0::1]
            row[2::3] = line[0::1]
        elif colortype == CT_GRAY_A:
            row = bytearray(w * 3)
            row[0::3] = line[0::2]
            row[1::3] = line[0::2]
            row[2::3] = line[0::2]
        else:  # RGBA
            row = bytearray(w * 3)
            row[0::3] = line[0::4]
            row[1::3] = line[1::4]
            row[2::3] = line[2::4]
        out.append(row)
    return w, h, out


def _axis_weights(src_n: int, dst_n: int) -> list[list[tuple[int, float]]]:
    """每个目标格对应哪些源格、各占多少权重（面积重叠比例）。"""
    scale = src_n / dst_n
    table: list[list[tuple[int, float]]] = []
    for i in range(dst_n):
        x0, x1 = i * scale, (i + 1) * scale
        taps = []
        for sx in range(int(math.floor(x0)), min(int(math.ceil(x1)), src_n)):
            overlap = min(x1, sx + 1) - max(x0, sx)
            if overlap > 1e-9:
                taps.append((sx, overlap / scale))
        table.append(taps)
    return table


def resize_area(rows: list[bytearray], w: int, h: int, nw: int, nh: int) -> list[bytearray]:
    if nw == w and nh == h:
        return rows

    # 横向：h 行 → h 行，宽度变 nw
    wx = _axis_weights(w, nw)
    mid: list[list[float]] = []
    for row in rows:
        acc = [0.0] * (nw * 3)
        for x, taps in enumerate(wx):
            r = g = b = 0.0
            for sx, wt in taps:
                o = sx * 3
                r += row[o] * wt
                g += row[o + 1] * wt
                b += row[o + 2] * wt
            o = x * 3
            acc[o], acc[o + 1], acc[o + 2] = r, g, b
        mid.append(acc)

    # 纵向：h 行 → nh 行
    wy = _axis_weights(h, nh)
    out: list[bytearray] = []
    for y, taps in enumerate(wy):
        acc = [0.0] * (nw * 3)
        for sy, wt in taps:
            src = mid[sy]
            for i in range(nw * 3):
                acc[i] += src[i] * wt
        out.append(bytearray(min(255, max(0, int(v + 0.5))) for v in acc))
    return out


def _chunk(ctype: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + ctype
        + payload
        + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, w: int, h: int, rows: list[bytearray]) -> int:
    ihdr = struct.pack(">IIBBBBB", w, h, 8, CT_RGB, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    blob = PNG_SIG + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", zlib.compress(raw, 9)) + _chunk(b"IEND", b"")
    path.write_bytes(blob)
    return len(blob)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[2] == "--dir" else DEFAULT_DIR

    if not src.is_file():
        print(f"源图不存在: {src}")
        return 1
    if not out_dir.is_dir():
        print(f"输出目录不存在: {out_dir}")
        return 1

    w, h, rows = decode_rgb(src)
    if w != h:
        print(f"源图必须是正方形，当前 {w}x{h}")
        return 1
    print(f"源图 {src.name}  {w}x{h}  →  {out_dir}")

    cache: dict[int, list[bytearray]] = {}
    total = 0
    for name, size in TARGETS:
        if size not in cache:
            cache[size] = resize_area(rows, w, h, size, size)
        n = write_png(out_dir / name, size, size, cache[size])
        total += n
        print(f"  {name:32}{size}x{size:<6}{n:>7} 字节")
    print(f"\n共 {len(TARGETS)} 个文件，合计 {total / 1024:.0f} KB（全部为 RGB，无 alpha）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
