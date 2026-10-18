#!/usr/bin/env python3
"""去掉 iOS 图标 PNG 的 Alpha 通道。

App Store Connect 要求 1024x1024 的营销图标不能带 alpha 通道，
否则上传时直接报 "Invalid Image - Alpha channel is not supported"。
Xcode 也会对带 alpha 的图标给警告。

本脚本纯标准库实现（不依赖 Pillow）：解析 IDAT → 反滤波 → 丢掉 alpha 通道
→ 重新编码为 color type 2 (RGB)。若原图 alpha 并非全不透明，会先提示。

用法（在 app/ios/Runner/Assets.xcassets/AppIcon.appiconset 的上级任意位置执行）：

    python app/tool/strip_icon_alpha.py            # 处理默认图标目录
    python app/tool/strip_icon_alpha.py <目录>      # 处理指定目录下所有 png
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

DEFAULT_DIR = Path(__file__).resolve().parent.parent / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

PNG_SIG = b"\x89PNG\r\n\x1a\n"
CT_GRAY = 0
CT_RGB = 2
CT_PALETTE = 3
CT_GRAY_A = 4
CT_RGBA = 6
CHANNELS = {CT_GRAY: 1, CT_RGB: 3, CT_PALETTE: 1, CT_GRAY_A: 2, CT_RGBA: 4}


def read_chunks(data: bytes) -> tuple[dict, list[tuple[str, bytes]]]:
    assert data[:8] == PNG_SIG, "不是 PNG 文件"
    pos = 8
    ihdr = None
    idat_parts: list[bytes] = []
    others: list[tuple[str, bytes]] = []
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            ihdr = payload
        elif ctype == b"IDAT":
            idat_parts.append(payload)
        elif ctype == b"IEND":
            break
        else:
            others.append((ctype.decode("ascii", "replace"), payload))
    assert ihdr is not None, "缺少 IHDR"
    w, h, bitdepth, colortype, comp, filt, interlace = struct.unpack(">IIBBBBB", ihdr)
    meta = {
        "width": w,
        "height": h,
        "bitdepth": bitdepth,
        "colortype": colortype,
        "interlace": interlace,
    }
    return meta, [(c, p) for c, p in others] + [("IDAT", b"".join(idat_parts))]


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def unfilter(raw: bytes, width: int, height: int, bpp: int) -> list[bytearray]:
    """把 PNG 扫描线还原成逐行的原始像素字节。"""
    stride = width * bpp
    rows: list[bytearray] = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if ftype == 1:  # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                upleft = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + paeth(left, prev[i], upleft)) & 0xFF
        elif ftype != 0:
            raise ValueError(f"未知滤波类型 {ftype}")
        rows.append(line)
        prev = line
    return rows


def chunk(ctype: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + ctype
        + payload
        + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)
    )


def strip_alpha(path: Path) -> str:
    data = path.read_bytes()
    meta, chunks = read_chunks(data)
    w, h = meta["width"], meta["height"]
    ct = meta["colortype"]

    if ct in (CT_RGB, CT_GRAY):
        return "跳过（本来就没有 alpha）"
    if meta["bitdepth"] != 8:
        return f"跳过（位深 {meta['bitdepth']}，本脚本只处理 8 位）"
    if meta["interlace"]:
        return "跳过（隔行扫描格式，本脚本不支持）"
    if ct == CT_PALETTE:
        return "跳过（调色板格式，需先转真彩色）"

    bpp = CHANNELS[ct]
    raw = zlib.decompress(dict(chunks)["IDAT"])
    rows = unfilter(raw, w, h, bpp)

    # 检查 alpha 是否全不透明
    if ct == CT_RGBA:
        min_alpha = min(min(r[3::4]) for r in rows)
        if min_alpha != 255:
            return f"中止（存在半透明像素，最小 alpha={min_alpha}，不能直接丢通道）"
        rgb_rows = [bytearray(b for i, b in enumerate(r) if i % 4 != 3) for r in rows]
        out_ct = CT_RGB
    else:  # 灰度 + alpha
        gray_rows = [bytearray(b for i, b in enumerate(r) if i % 2 == 0) for r in rows]
        if min(min(r[1::2]) for r in rows) != 255:
            return "中止（存在半透明像素，不能直接丢通道）"
        rgb_rows = [bytearray(v for g in row for v in (g, g, g)) for row in gray_rows]
        out_ct = CT_RGB

    # 重新编码：每行前加滤波字节 0
    out_raw = b"".join(b"\x00" + bytes(r) for r in rgb_rows)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, out_ct, 0, 0, 0)
    out = (
        PNG_SIG
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(out_raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(out)
    return f"已去 alpha（{w}x{h}，{len(data)} → {len(out)} 字节）"


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    if not target.is_dir():
        print(f"目录不存在: {target}")
        return 1
    files = sorted(target.glob("*.png"))
    if not files:
        print(f"{target} 下没有 png")
        return 1
    changed = 0
    for f in files:
        result = strip_alpha(f)
        print(f"{f.name:32} {result}")
        if result.startswith("已去 alpha"):
            changed += 1
    print(f"\n共 {len(files)} 个文件，处理 {changed} 个")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
