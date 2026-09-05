#!/usr/bin/env python3
"""BIZBOT-REBRAND — TEMPORARY launcher / PWA / favicon icon generator.

No owner-approved BIZBOT logo exists yet, so every icon is a deliberately plain
`B` monogram: a bold neutral sans-serif capital on the frozen brand navy
(`kRestoflowSeedColor` = #16335E, packages/design_system/lib/src/tokens.dart).
It is the same tile the shared `RestoflowBrandMark` widget draws in-app, so the
home-screen icon and the in-app mark agree. Nothing here is a designed symbol —
replace the whole set with the approved asset when the owner supplies a logo.

Outputs (sizes/modes mirror the files they replace, per app):
  apps/<app>/web/favicon.png                     64x64   RGBA rounded tile
  apps/<app>/web/icons/Icon-{192,512}.png        RGBA rounded tile
  apps/<app>/web/icons/Icon-maskable-{192,512}   RGBA full-bleed (safe-zone glyph)
  apps/<app>/android/.../mipmap-*/ic_launcher.png RGB full-bleed (launcher-masked)

Run from the repo root:  python3 tools/brand/generate_bizbot_temp_icons.py
Requires Pillow and a bold sans-serif TTF (Liberation Sans Bold — Arial-metric,
matching the design system's `Arial` fallback — or DejaVu Sans Bold).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

NAVY = (0x16, 0x33, 0x5E, 255)
WHITE = (255, 255, 255, 255)
GLYPH = "B"
SUPERSAMPLE = 4

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
]

APPS = ["pos", "kds", "kiosk", "dashboard", "admin"]
ANDROID_APPS = ["pos", "kds", "kiosk", "dashboard"]
MIPMAPS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def _font_path() -> str:
    for candidate in FONT_CANDIDATES:
        if os.path.exists(candidate):
            return candidate
    sys.exit("no bold sans-serif TTF found; install fonts-liberation")


def _tile(size: int, *, radius_ratio: float, glyph_ratio: float, opaque: bool) -> Image.Image:
    """Render one icon at SUPERSAMPLE x and downsample for clean edges.

    radius_ratio: corner radius as a fraction of size (0 = square, full-bleed).
    glyph_ratio:  target cap height of the glyph as a fraction of size.
    opaque:       True -> RGB (no alpha channel), False -> RGBA.
    """
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(big * radius_ratio)
    draw.rounded_rectangle((0, 0, big - 1, big - 1), radius=radius, fill=NAVY)

    # Size the font so the glyph's cap height hits glyph_ratio of the tile.
    font_path = _font_path()
    target_cap = big * glyph_ratio
    font_size = int(target_cap)
    for _ in range(8):
        font = ImageFont.truetype(font_path, font_size)
        left, top, right, bottom = font.getbbox(GLYPH)
        cap = bottom - top
        if abs(cap - target_cap) < big * 0.005:
            break
        font_size = max(8, int(font_size * target_cap / max(cap, 1)))
    font = ImageFont.truetype(font_path, font_size)
    left, top, right, bottom = font.getbbox(GLYPH)
    glyph_w, glyph_h = right - left, bottom - top
    # Optical centering: centre the glyph's ink box, not its advance box.
    x = (big - glyph_w) / 2 - left
    y = (big - glyph_h) / 2 - top
    draw.text((x, y), GLYPH, font=font, fill=WHITE)

    small = img.resize((size, size), Image.LANCZOS)
    if opaque:
        flat = Image.new("RGB", (size, size), NAVY[:3])
        flat.paste(small, (0, 0), small)
        return flat
    return small


def _save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)
    print(f"wrote {path} {img.size} {img.mode}")


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    os.chdir(root)

    # Render each distinct icon once; every app ships the identical set (as the
    # VEYRO set did), so the platform brand stays one mark everywhere.
    favicon = _tile(64, radius_ratio=0.22, glyph_ratio=0.56, opaque=False)
    icon_192 = _tile(192, radius_ratio=0.22, glyph_ratio=0.54, opaque=False)
    icon_512 = _tile(512, radius_ratio=0.22, glyph_ratio=0.54, opaque=False)
    # Maskable: full-bleed, glyph inside the 80% safe zone.
    mask_192 = _tile(192, radius_ratio=0.0, glyph_ratio=0.40, opaque=False)
    mask_512 = _tile(512, radius_ratio=0.0, glyph_ratio=0.40, opaque=False)

    for app in APPS:
        web = root / "apps" / app / "web"
        _save(favicon, web / "favicon.png")
        _save(icon_192, web / "icons" / "Icon-192.png")
        _save(icon_512, web / "icons" / "Icon-512.png")
        _save(mask_192, web / "icons" / "Icon-maskable-192.png")
        _save(mask_512, web / "icons" / "Icon-maskable-512.png")

    # Android legacy launcher icons: opaque RGB (as the files they replace),
    # full-bleed so a launcher's own mask (circle/squircle) crops navy, not a
    # white frame; glyph held to ~48% so every mask keeps it whole.
    for app in ANDROID_APPS:
        res = root / "apps" / app / "android" / "app" / "src" / "main" / "res"
        for density, px in MIPMAPS.items():
            icon = _tile(px, radius_ratio=0.0, glyph_ratio=0.48, opaque=True)
            _save(icon, res / f"mipmap-{density}" / "ic_launcher.png")


if __name__ == "__main__":
    main()
