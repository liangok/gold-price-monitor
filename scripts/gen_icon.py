#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成应用图标（不依赖任何第三方库）。

为什么手写 PNG：本机没有 Pillow，而图标需要精确控制且可复现。
做法：先在 1024x1024 上绘制（硬边），再用 macOS 自带的 sips 缩小到各密度，
放大->缩小天然带来抗锯齿效果。

产出：
  app/android/app/src/main/res/mipmap-*/ic_launcher.png            传统图标
  app/android/app/src/main/res/mipmap-*/ic_launcher_foreground.png 自适应图标前景
  app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  app/android/app/src/main/res/values/colors.xml

用法: python3 scripts/gen_icon.py
"""
from __future__ import annotations

import os
import struct
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "app", "android", "app", "src", "main", "res")
TMP = os.path.join(ROOT, ".toolhome", "icon-work")

MASTER = 1024

BG_TOP = (16, 19, 26)
BG_BOTTOM = (27, 32, 48)
GRID = (255, 255, 255, 14)
GOLD = (247, 203, 85, 255)
GOLD_BRIGHT = (255, 224, 138, 255)
GOLD_FILL_TOP = (240, 194, 75, 70)
GOLD_FILL_BOTTOM = (240, 194, 75, 0)

# 折线走势（左上 -> 右下再冲高），给人「价格上行」的直觉
POINTS = [(150, 706), (392, 520), (612, 614), (876, 300)]
LINE_WIDTH = 36
BASELINE = 860


def write_png(path, width, height, pixels):
    """pixels: bytearray，长度 width*height*4（RGBA）。"""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


class Canvas:
    def __init__(self, size, background=None, gradient=None):
        self.size = size
        self.px = bytearray(size * size * 4)
        if gradient is not None:
            (r0, g0, b0), (r1, g1, b1) = gradient
            for y in range(size):
                t = y / float(size - 1)
                r = int(r0 + (r1 - r0) * t)
                g = int(g0 + (g1 - g0) * t)
                b = int(b0 + (b1 - b0) * t)
                base = y * size * 4
                for x in range(size):
                    i = base + x * 4
                    self.px[i] = r
                    self.px[i + 1] = g
                    self.px[i + 2] = b
                    self.px[i + 3] = 255
        elif background is not None:
            self.px = bytearray(bytes(background) * (size * size))

    def blend(self, x, y, color):
        if x < 0 or y < 0 or x >= self.size or y >= self.size:
            return
        r, g, b, a = color
        i = (y * self.size + x) * 4
        if a >= 255:
            self.px[i] = r
            self.px[i + 1] = g
            self.px[i + 2] = b
            self.px[i + 3] = 255
            return
        if a <= 0:
            return
        ia = 255 - a
        da = self.px[i + 3]
        out_a = a + da * ia // 255
        if out_a == 0:
            return
        # 标准 source-over：out_c = (c*a + dc*da*(1-a)) / out_a
        # 整数化后分母为 255*out_a，分子首项需再乘 255。
        den = 255 * out_a
        self.px[i] = max(0, min(255, (r * a * 255 + self.px[i] * da * ia) // den))
        self.px[i + 1] = max(0, min(255, (g * a * 255 + self.px[i + 1] * da * ia) // den))
        self.px[i + 2] = max(0, min(255, (b * a * 255 + self.px[i + 2] * da * ia) // den))
        self.px[i + 3] = max(0, min(255, out_a))

    def hline(self, x0, x1, y, color):
        for x in range(x0, x1 + 1):
            self.blend(x, y, color)

    def disc(self, cx, cy, radius, color):
        r2 = radius * radius
        for dy in range(-radius, radius + 1):
            span = int((r2 - dy * dy) ** 0.5)
            for dx in range(-span, span + 1):
                self.blend(int(cx) + dx, int(cy) + dy, color)

    def segment(self, p0, p1, width, color):
        steps = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1]))) + 1
        half = width / 2.0
        for s in range(steps + 1):
            t = s / float(steps)
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            self.disc(x, y, int(half), color)

    def column_fill(self, x, y0, y1, color_at):
        """自上而下填充一列，颜色按 t 渐变。"""
        if y1 <= y0:
            return
        for y in range(int(y0), int(y1) + 1):
            t = (y - y0) / float(max(1, y1 - y0))
            r = int(color_at[0] + (color_at[4] - color_at[0]) * t)
            g = int(color_at[1] + (color_at[5] - color_at[1]) * t)
            b = int(color_at[2] + (color_at[6] - color_at[2]) * t)
            a = int(color_at[3] + (color_at[7] - color_at[3]) * t)
            self.blend(x, y, (r, g, b, a))


def y_at(pts, x):
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        if x0 <= x <= x1:
            t = (x - x0) / float(x1 - x0)
            return y0 + (y1 - y0) * t
    return pts[-1][1]


def draw_art(canvas, scale=1.0, grid=True, offset=(0, 0)):
    size = canvas.size
    ox, oy = offset

    def T(p):
        return (ox + (p[0] - size / 2.0) * scale + size / 2.0,
                oy + (p[1] - size / 2.0) * scale + size / 2.0)

    pts = [T(p) for p in POINTS]
    baseline = T((0, BASELINE))[1]
    width = max(2, int(LINE_WIDTH * scale))

    # 1. 淡淡的横向网格（自适应前景里留白多，网格会显得突兀，故只画在传统图标上）
    if grid:
        for frac in (0.34, 0.52, 0.70):
            y = int(size * frac)
            canvas.hline(int(size * 0.13), int(size * 0.87), y, GRID)

    # 2. 折线下方的渐变填充
    for x in range(int(pts[0][0]), int(pts[-1][0]) + 1):
        canvas.column_fill(
            x, y_at(pts, x), baseline,
            (GOLD_FILL_TOP[0], GOLD_FILL_TOP[1], GOLD_FILL_TOP[2], GOLD_FILL_TOP[3],
             GOLD_FILL_BOTTOM[0], GOLD_FILL_BOTTOM[1], GOLD_FILL_BOTTOM[2], GOLD_FILL_BOTTOM[3]),
        )

    # 3. 折线本体
    for i in range(len(pts) - 1):
        canvas.segment(pts[i], pts[i + 1], width, GOLD)

    # 4. 末端高亮点（提示「当前价」）
    canvas.disc(pts[-1][0], pts[-1][1], int(width * 1.05), GOLD_BRIGHT)
    canvas.disc(pts[-1][0], pts[-1][1], int(width * 0.45), (255, 255, 255, 235))


def main():
    os.makedirs(TMP, exist_ok=True)

    # 传统图标：深色渐变背景 + 金色折线
    full = Canvas(MASTER, gradient=(BG_TOP, BG_BOTTOM))
    draw_art(full, 1.0)
    master_full = os.path.join(TMP, "ic_launcher.png")
    write_png(master_full, MASTER, MASTER, full.px)

    # 自适应图标前景：透明背景，画在中间 62% 的安全区
    fg = Canvas(MASTER, background=(0, 0, 0, 0))
    draw_art(fg, 0.62, grid=False)
    master_fg = os.path.join(TMP, "ic_launcher_foreground.png")
    write_png(master_fg, MASTER, MASTER, fg.px)

    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

    for bucket, size in legacy.items():
        d = os.path.join(RES, "mipmap-" + bucket)
        os.makedirs(d, exist_ok=True)
        subprocess.run(["sips", "-z", str(size), str(size), master_full,
                        "--out", os.path.join(d, "ic_launcher.png")],
                       check=True, capture_output=True)
    for bucket, size in adaptive.items():
        d = os.path.join(RES, "mipmap-" + bucket)
        subprocess.run(["sips", "-z", str(size), str(size), master_fg,
                        "--out", os.path.join(d, "ic_launcher_foreground.png")],
                       check=True, capture_output=True)

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as fh:
            fh.write('<?xml version="1.0" encoding="utf-8"?>\n'
                     '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                     '    <background android:drawable="@color/ic_launcher_background"/>\n'
                     '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                     '</adaptive-icon>\n')

    values = os.path.join(RES, "values")
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, "colors.xml"), "w", encoding="utf-8") as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<resources>\n'
                 '    <color name="ic_launcher_background">#10131A</color>\n'
                 '</resources>\n')

    print("[ok] 图标已生成")
    print("     传统图标 48/72/96/144/192 px")
    print("     自适应前景 108/162/216/324/432 px")
    print("     自适应配置 mipmap-anydpi-v26/ic_launcher{,_round}.xml")
    print("     预览大图 " + os.path.relpath(master_full, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
