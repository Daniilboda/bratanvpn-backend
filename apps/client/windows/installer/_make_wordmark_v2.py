"""BRATANVPN wordmark with clean stroke joins (Pillow)."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(r"C:\Users\Daniil\CursorProjects\bratanvpn\docs\bratanvpn_wordmark_drakar_v2.png")

H = 400.0
SW = 16.0
GAP = 48.0
PAD_X = 100.0
PAD_Y = 120.0

WIDTHS = {
    "B": 160.0,
    "R": 172.0,
    "A": 176.0,
    "T": 160.0,
    "N": 188.0,
    "V": 176.0,
    "P": 152.0,
}


def thick_segment(
    draw: ImageDraw.ImageDraw,
    p1: tuple[float, float],
    p2: tuple[float, float],
    width: float,
    fill: tuple[int, int, int] = (255, 255, 255),
) -> None:
    x1, y1 = p1
    x2, y2 = p2
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy) or 1.0
    ox, oy = (-dy / length) * (width / 2.0), (dx / length) * (width / 2.0)
    draw.polygon(
        [
            (x1 + ox, y1 + oy),
            (x1 - ox, y1 - oy),
            (x2 - ox, y2 - oy),
            (x2 + ox, y2 + oy),
        ],
        fill=fill,
    )
    # round caps → clean joints when segments meet
    r = width / 2.0
    draw.ellipse((x1 - r, y1 - r, x1 + r, y1 + r), fill=fill)
    draw.ellipse((x2 - r, y2 - r, x2 + r, y2 + r), fill=fill)


def stroke_poly(
    draw: ImageDraw.ImageDraw,
    pts: list[tuple[float, float]],
    width: float,
) -> None:
    for a, b in zip(pts, pts[1:]):
        thick_segment(draw, a, b, width)


def glyphs(
    ch: str, x: float, y: float, w: float, h: float
) -> list[list[tuple[float, float]]]:
    left, right, top, bottom = x, x + w, y, y + h
    mid = y + h / 2
    cx = x + w / 2
    tip1 = y + h * 0.22
    tip2 = y + h * 0.72

    if ch == "B":
        return [
            [(left, top), (left, bottom)],
            [(left, top), (right, tip1), (left, mid)],
            [(left, mid), (right, tip2), (left, bottom)],
        ]
    if ch == "R":
        return [
            [(left, top), (left, bottom)],
            [(left, top), (right, tip1), (left, mid)],
            [(left, mid), (right, bottom)],
        ]
    if ch == "A":
        # Exact construction from reference alphabet crop:
        # left stem full height; right stem from ~18% down; roof diagonal; mid bar
        right_top = y + h * 0.18
        return [
            [(left, top), (left, bottom)],
            [(right, right_top), (right, bottom)],
            [(left, top), (right, right_top)],
            [(left, mid), (right, mid)],
        ]
    if ch == "T":
        return [
            [(cx, top), (cx, bottom)],
            [(left, top), (right, top)],
        ]
    if ch == "N":
        return [
            [(left, top), (left, bottom)],
            [(right, top), (right, bottom)],
            [(left, top), (right, bottom)],
        ]
    if ch == "V":
        # clean V — no vertical stub / tail
        return [
            [(left, top), (cx, bottom)],
            [(right, top), (cx, bottom)],
        ]
    if ch == "P":
        return [
            [(left, top), (left, bottom)],
            [(left, top), (right, tip1), (left, mid)],
        ]
    raise ValueError(ch)


def main() -> None:
    word = "BRATANVPN"
    widths = [WIDTHS[c] for c in word]
    total_w = int(PAD_X * 2 + sum(widths) + GAP * (len(word) - 1))
    total_h = int(PAD_Y * 2 + H)

    inset = SW / 2.0
    img = Image.new("RGB", (total_w, total_h), (0, 0, 0))
    draw = ImageDraw.Draw(img)

    x = PAD_X
    for ch, w in zip(word, widths):
        for poly in glyphs(ch, x + inset, PAD_Y + inset, w - 2 * inset, H - 2 * inset):
            stroke_poly(draw, poly, SW)
        x += w + GAP

    img.save(OUT, optimize=True)
    print(f"saved {OUT} {img.size} {OUT.stat().st_size}")


if __name__ == "__main__":
    main()
