"""Build a Windows-compatible multi-size .ico for tray / Setup / app."""

from __future__ import annotations

import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
RUNNER_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
INSTALLER = Path(__file__).resolve().parent
SIZES = [16, 24, 32, 48, 64, 128, 256]


def _font(size: int) -> ImageFont.ImageFont:
    for name in ("arialbd.ttf", "segoeuib.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def make_mark(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    margin = max(1, round(size * 0.08))
    ring = max(1, round(size * 0.08))
    draw.ellipse(
        [margin, margin, size - margin - 1, size - margin - 1],
        outline=(255, 255, 255, 255),
        width=ring,
    )
    font = _font(max(8, int(size * 0.55)))
    text = "B"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - tw) / 2 - bbox[0]
    y = (size - th) / 2 - bbox[1] - size * 0.02
    draw.text((x, y), text, fill=(255, 255, 255, 255), font=font)
    return img


def _png_bytes(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def _bmp_dib_bytes(im: Image.Image) -> bytes:
    """XOR bitmap + AND mask, as expected inside ICO (no BITMAPFILEHEADER)."""
    rgba = im.convert("RGBA")
    width, height = rgba.size
    # AND mask: 1bpp, each row padded to 4 bytes; all 0 = fully opaque
    and_row = ((width + 31) // 32) * 4
    and_mask = bytes(and_row * height)

    # 32bpp BGRA, bottom-up
    pixels = []
    for y in range(height - 1, -1, -1):
        for x in range(width):
            r, g, b, a = rgba.getpixel((x, y))
            pixels.append(struct.pack("BBBB", b, g, r, a))
    xor = b"".join(pixels)

    header = struct.pack(
        "<IIIHHIIIIII",
        40,  # biSize
        width,
        height * 2,  # includes AND mask height
        1,  # planes
        32,  # bit count
        0,  # BI_RGB
        len(xor) + len(and_mask),
        0,
        0,
        0,
        0,
    )
    return header + xor + and_mask


def save_ico(path: Path, sizes: list[int] | None = None) -> None:
    sizes = sizes or SIZES
    images = [make_mark(s) for s in sizes]
    blobs: list[bytes] = []
    for size, im in zip(sizes, images):
        if size >= 256:
            blobs.append(_png_bytes(im))
        else:
            blobs.append(_bmp_dib_bytes(im))

    count = len(images)
    offset = 6 + 16 * count
    entries = bytearray()
    data = bytearray()
    for size, blob in zip(sizes, blobs):
        # width/height: 0 means 256
        w = 0 if size >= 256 else size
        h = 0 if size >= 256 else size
        entries += struct.pack(
            "<BBBBHHII",
            w,
            h,
            0,  # color count
            0,  # reserved
            1,  # planes
            32,  # bit count
            len(blob),
            offset + len(data),
        )
        data += blob

    path.write_bytes(struct.pack("<HHH", 0, 1, count) + entries + data)

    check = Image.open(path)
    n = getattr(check, "n_frames", 1)
    print(f"wrote {path} frames={n} bytes={path.stat().st_size}")
    for i in range(n):
        check.seek(i)
        print(f"  frame {i}: {check.size}")


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    save_ico(ASSETS / "tray_icon.ico")
    save_ico(INSTALLER / "setup_icon.ico")
    save_ico(RUNNER_ICO)
    make_mark(128).save(INSTALLER / "_preview_icon.png")
    print("wrote", INSTALLER / "_preview_icon.png")


if __name__ == "__main__":
    main()
