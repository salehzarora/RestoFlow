#!/usr/bin/env python3
"""BIZBOT official visual identity — deterministic asset generator.

Source of truth: the owner-supplied masters (byte-identical copies of the files
delivered in `App-logo/`, SHA-256 pinned in MASTERS below). Nothing here is
drawn, typeset, recoloured or reinterpreted: the masters are white-background
JPEGs, so this script only

  1. removes the EXTERIOR white background algorithmically (flood fill from the
     frame, JPEG ringing resolved by un-blending each boundary pixel against
     white with the nearest solid colour as reference — no halo, no fringe),
  2. keeps the symbol's own white (the receipt paper) opaque, resolving the two
     places where paper meets background white-on-white with straight cuts
     (documented in SYMBOL_CUTS — they are alpha decisions, not redrawing),
  3. trims / centres / downsamples (LANCZOS) the resulting RGBA cut-outs into
     every runtime derivative the apps need.

Outputs (all regenerated from scratch, byte-for-byte reproducible):

  packages/design_system/assets/brand/bizbot/bizbot_symbol.png        800x800 RGBA, symbol centred, native scale
  packages/design_system/assets/brand/bizbot/bizbot_wordmark_en.png   trimmed RGBA
  packages/design_system/assets/brand/bizbot/bizbot_wordmark_ar.png   trimmed RGBA
  apps/<app>/web/favicon.png                                          64x64 RGBA, transparent
  apps/<app>/web/icons/Icon-{192,512}.png                             RGBA, transparent, 8% padding
  apps/<app>/web/icons/Icon-maskable-{192,512}.png                    Light Neutral full-bleed, mark 56% (inside the 80% safe circle)
  apps/<app>/android/.../mipmap-*/ic_launcher.png                     legacy launcher: Light Neutral rounded tile
  apps/<app>/android/.../mipmap-*/ic_launcher_foreground.png          adaptive foreground (108dp canvas, mark 43%, inside the 66dp safe circle)
  tools/brand/social/bizbot_avatar_1080.png                           Instagram / social avatar
  tools/brand/BIZBOT_BRAND_ASSETS.md                                  manifest: master hashes + output hashes

Run from the repo root:  python3 tools/brand/generate_bizbot_official_icons.py
Requires Pillow, numpy, scipy. Pass --check to verify the committed outputs
match what the script would generate (CI-friendly).
"""
from __future__ import annotations

import hashlib
import io
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
MASTER_DIR = ROOT / "tools" / "brand" / "masters" / "bizbot"
ASSET_DIR = ROOT / "packages" / "design_system" / "assets" / "brand" / "bizbot"
SOCIAL_DIR = ROOT / "tools" / "brand" / "social"
MANIFEST = ROOT / "tools" / "brand" / "BIZBOT_BRAND_ASSETS.md"

# Official palette (identity board, 2026-09-05).
CHARCOAL = (0x1F, 0x29, 0x37)
EMERALD = (0x05, 0x96, 0x69)
MINT = (0xA7, 0xF3, 0xD0)
LIGHT_NEUTRAL = (0xF4, 0xF6, 0xF5)

# Owner masters — byte-identical copies of App-logo/photo_2026-09-05_23-03-*.jpg.
MASTERS = {
    "symbol": ("bizbot_symbol_master.jpg",
               "d3cafcf6e3bdfbdbd22948d39b6cb6da035af39302348a8ffa7581600813b339"),
    "wordmark_en": ("bizbot_wordmark_en_master.jpg",
                    "486f3aaaff6fc1e8a3b9fad2c62164e5944939d974818f8b8d13713974795c2b"),
    "wordmark_ar": ("bizbot_wordmark_ar_master.jpg",
                    "7d68c76cceeeb397f172019ad32140ab1c6c2cb8dc8d0bb3c92a742eae7b12c8"),
    # Reference sheet only — never bundled, never used as a runtime asset.
    "board": ("bizbot_identity_board_reference.jpg",
              "6a8a3d0364b60b65be5774cc99728e9ce27fd42b86f7fa4f0f5a7e2e3216ffc1"),
}

APPS = ["pos", "kds", "kiosk", "dashboard", "admin"]
ANDROID_APPS = ["pos", "kds", "kiosk", "dashboard"]
MIPMAPS = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_FG = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


@dataclass(frozen=True)
class Cut:
    """A straight alpha decision inside a white-on-white ambiguity.

    kind='exterior': non-ink pixels inside the window with x >= x_cut become
                     background (the receipt's right edge continues vertically
                     between the two bowl tips instead of leaking into the
                     background channel between them).
    kind='paper':    non-ink pixels inside the window with x >= x_cut are the
                     receipt paper (opaque); x < x_cut is background (the paper
                     fills the pocket between the top bar and the spine dome,
                     flush with the bar's rounded corner).
    Coordinates are master pixels; each cut also carries an ink-geometry guard
    so a different master cannot silently be cut in the wrong place.
    """
    kind: str
    x_cut: int
    y0: int
    y1: int
    x_max: int
    guard: tuple[int, int, int]  # (x, y, expected ink? 1/0) sampled on the master


SYMBOL_CUTS = (
    # Waist notch: the upper and lower bowl tips meet at x≈850, y≈586.
    Cut("exterior", x_cut=850, y0=555, y1=620, x_max=960, guard=(850, 585, 1)),
    # Top-left pocket under the bar: bar corner ends at x≈289 (row 422); the
    # spine dome starts at row 448.
    Cut("paper", x_cut=289, y0=422, y1=470, x_max=500, guard=(345, 450, 1)),
)


def sha256(path: Path | bytes) -> str:
    data = path if isinstance(path, bytes) else path.read_bytes()
    return hashlib.sha256(data).hexdigest()


def load_master(key: str) -> np.ndarray:
    name, digest = MASTERS[key]
    path = MASTER_DIR / name
    actual = sha256(path)
    if actual != digest:
        sys.exit(f"master {name} hash mismatch: {actual} != {digest}")
    return np.asarray(Image.open(path).convert("RGB"))


# ─── background removal ────────────────────────────────────────────────────

def cutout(rgb_u8: np.ndarray, *, keep_holes: bool, cuts: tuple[Cut, ...] = (),
           strict_thr: int = 250, halo_thr: int = 236, band: int = 8,
           close_iter: int = 2, white_open: int = 4, noise_alpha: float = 0.04,
           min_area: int = 50, ink_thr: int = 200, ink_px: int = 20) -> np.ndarray:
    rgb = rgb_u8.astype(np.float64)
    mn = rgb.min(axis=2)
    ink = mn < ink_thr
    strict_white = mn >= strict_thr

    # 1) Exterior. keep_holes=True: only white connected to the frame (the
    #    symbol's receipt stays). keep_holes=False: every white region (letter
    #    counters are background).
    if keep_holes:
        lab, _ = ndi.label(strict_white)
        border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
        ext = np.isin(lab, border[border != 0])
    else:
        ext = strict_white.copy()

    # 2) Object = the rest, minus stray dust / ringing blobs; narrow channels
    #    (< 2*close_iter px, white-on-white anyway) bridged.
    obj = ~ext
    obj_lab, n_obj = ndi.label(obj)
    if n_obj:
        index = np.arange(1, n_obj + 1)
        areas = ndi.sum(np.ones_like(mn), obj_lab, index=index)
        inkpx = ndi.sum(ink.astype(np.int64), obj_lab, index=index)
        drop = [i + 1 for i in range(n_obj)
                if areas[i] < min_area or (inkpx[i] < ink_px and areas[i] < 2000)]
        if drop:
            obj &= ~np.isin(obj_lab, drop)
    if close_iter:
        obj = ndi.binary_closing(obj, iterations=close_iter) | obj

    # 3) Straight cuts for the documented white-on-white ambiguities.
    forced_solid = np.zeros_like(obj)
    h, w = mn.shape
    yy, xx = np.mgrid[0:h, 0:w]
    for cut in cuts:
        gx, gy, expect = cut.guard
        if bool(ink[gy, gx]) != bool(expect):
            sys.exit(f"symbol cut guard failed at {(gx, gy)} — master geometry changed")
        window = (yy >= cut.y0) & (yy <= cut.y1) & (xx <= cut.x_max) & ~ink
        if cut.kind == "exterior":
            obj &= ~(window & (xx >= cut.x_cut))
        elif cut.kind == "paper":
            paper = window & (xx >= cut.x_cut)
            obj |= paper
            forced_solid |= paper
            obj &= ~(window & (xx < cut.x_cut))
        else:
            raise ValueError(cut.kind)
    ext = ~obj

    # 4) Thick genuine white regions inside the object (receipt paper) are solid
    #    no matter how close they come to the exterior.
    near_white = mn >= halo_thr
    white_core = ndi.binary_opening(near_white & obj, iterations=white_open) if keep_holes \
        else np.zeros_like(obj)

    # 5) Boundary band + un-blend against white with nearest-solid reference.
    ext_d = ndi.binary_dilation(ext, iterations=band)
    solid = (obj & ~ext_d) | white_core | forced_solid
    edge = obj & ~solid
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    ref = rgb[idx[0], idx[1]]
    denom = 255.0 - ref
    num = 255.0 - rgb
    informative = denom > 40
    with np.errstate(invalid="ignore", divide="ignore"):
        a_c = np.where(informative, num / np.maximum(denom, 1e-6), np.nan)
        a_c = np.where((~informative.any(axis=2))[..., None], 1.0, a_c)
        alpha = np.nanmax(a_c, axis=2)
    alpha = np.clip(np.nan_to_num(alpha, nan=1.0), 0.0, 1.0)
    alpha[solid] = 1.0
    alpha[ext] = 0.0
    a3 = alpha[..., None]
    fg = np.where(a3 > 0.15, (rgb - (1.0 - a3) * 255.0) / np.maximum(a3, 1e-6), ref)
    out = rgb.copy()
    out[edge] = np.clip(fg, 0.0, 255.0)[edge]
    out[ext] = ref[ext]  # transparent pixels carry the nearest solid colour
    alpha[edge & (alpha < noise_alpha)] = 0.0
    return np.dstack([out, alpha * 255.0]).round().astype(np.uint8)


def trim(rgba: np.ndarray) -> np.ndarray:
    ys, xs = np.where(rgba[..., 3] > 0)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def to_image(rgba: np.ndarray) -> Image.Image:
    return Image.fromarray(rgba, "RGBA")


# ─── compositing helpers ───────────────────────────────────────────────────

def fit(symbol: Image.Image, box: int) -> Image.Image:
    """Downsample the symbol so its longer side is `box` px (LANCZOS,
    premultiplied so transparent pixels never bleed)."""
    w, h = symbol.size
    scale = box / max(w, h)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    arr = np.asarray(symbol).astype(np.float64)
    a = arr[..., 3:4] / 255.0
    pre = np.dstack([arr[..., :3] * a, arr[..., 3:4]])
    pre_img = Image.fromarray(pre.round().astype(np.uint8), "RGBA")
    small = np.asarray(pre_img.resize(size, Image.LANCZOS)).astype(np.float64)
    sa = small[..., 3:4] / 255.0
    rgb = np.where(sa > 0, small[..., :3] / np.maximum(sa, 1e-6), 0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), small[..., 3:4]]).round().astype(np.uint8), "RGBA")


def place(canvas: Image.Image, mark: Image.Image) -> Image.Image:
    x = (canvas.width - mark.width) // 2
    y = (canvas.height - mark.height) // 2
    canvas.alpha_composite(mark, (x, y))
    return canvas


def transparent_icon(symbol: Image.Image, size: int, fill_ratio: float) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return place(canvas, fit(symbol, round(size * fill_ratio)))


def tile_icon(symbol: Image.Image, size: int, fill_ratio: float, bg: tuple,
              radius_ratio: float) -> Image.Image:
    """Symbol on an opaque bg tile; radius_ratio 0 = full-bleed square."""
    ss = 4
    big = size * ss
    tile = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((0, 0, big - 1, big - 1),
                                           radius=int(big * radius_ratio), fill=bg + (255,))
    tile = tile.resize((size, size), Image.LANCZOS)
    return place(tile, fit(symbol, round(size * fill_ratio)))


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


# ─── main ──────────────────────────────────────────────────────────────────

def build() -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}

    symbol_rgba = cutout(load_master("symbol"), keep_holes=True, cuts=SYMBOL_CUTS)
    symbol = to_image(trim(symbol_rgba))
    # Canonical symbol: centred on a square transparent canvas at native scale.
    side = 800
    assert max(symbol.size) <= side, symbol.size
    canonical = place(Image.new("RGBA", (side, side), (0, 0, 0, 0)), symbol)
    out[ASSET_DIR / "bizbot_symbol.png"] = png_bytes(canonical)

    for key in ("wordmark_en", "wordmark_ar"):
        wm = to_image(trim(cutout(load_master(key), keep_holes=False)))
        out[ASSET_DIR / f"bizbot_{key}.png"] = png_bytes(wm)

    for app in APPS:
        web = ROOT / "apps" / app / "web"
        out[web / "favicon.png"] = png_bytes(transparent_icon(symbol, 64, 0.94))
        for px in (192, 512):
            out[web / "icons" / f"Icon-{px}.png"] = png_bytes(transparent_icon(symbol, px, 0.84))
            # Maskable: full-bleed Light Neutral, mark inside the 80% safe zone.
            out[web / "icons" / f"Icon-maskable-{px}.png"] = png_bytes(
                tile_icon(symbol, px, 0.56, LIGHT_NEUTRAL, 0.0))

    for app in ANDROID_APPS:
        res = ROOT / "apps" / app / "android" / "app" / "src" / "main" / "res"
        for density, px in MIPMAPS.items():
            # Legacy launcher icon: Light Neutral rounded tile (transparent corners).
            out[res / f"mipmap-{density}" / "ic_launcher.png"] = png_bytes(
                tile_icon(symbol, px, 0.72, LIGHT_NEUTRAL, 0.2))
        for density, px in ADAPTIVE_FG.items():
            # Adaptive foreground: 108dp canvas, mark inside the 66dp safe zone.
            out[res / f"mipmap-{density}" / "ic_launcher_foreground.png"] = png_bytes(
                transparent_icon(symbol, px, 0.43))

    out[SOCIAL_DIR / "bizbot_avatar_1080.png"] = png_bytes(
        tile_icon(symbol, 1080, 0.64, LIGHT_NEUTRAL, 0.0))
    return out


def write_manifest(outputs: dict[Path, bytes]) -> bytes:
    lines = [
        "# BIZBOT brand assets — generated manifest",
        "",
        "Generated by `tools/brand/generate_bizbot_official_icons.py`. Do not edit by hand;",
        "re-run the script (or `--check`) instead.",
        "",
        "## Owner masters (byte-identical copies of `App-logo/`)",
        "",
        "| Role | File | SHA-256 |",
        "|---|---|---|",
    ]
    for key, (name, digest) in MASTERS.items():
        lines.append(f"| {key} | `tools/brand/masters/bizbot/{name}` | `{digest}` |")
    lines += ["", "## Generated outputs", "", "| File | SHA-256 |", "|---|---|"]
    for path in sorted(outputs):
        lines.append(f"| `{path.relative_to(ROOT).as_posix()}` | `{sha256(outputs[path])}` |")
    lines.append("")
    return "\n".join(lines).encode("utf-8")


def main(argv: list[str]) -> int:
    os.chdir(ROOT)
    outputs = build()
    outputs[MANIFEST] = write_manifest(outputs)
    if "--check" in argv:
        def same(path: Path, data: bytes) -> bool:
            if not path.exists():
                return False
            actual = path.read_bytes()
            if path.suffix == ".md":  # tolerate CRLF checkouts for the text manifest
                actual = actual.replace(b"\r\n", b"\n")
            return actual == data

        stale = [p for p, data in outputs.items() if not same(p, data)]
        for p in stale:
            print(f"STALE: {p.relative_to(ROOT).as_posix()}")
        print(f"checked {len(outputs)} files, {len(stale)} stale")
        return 1 if stale else 0
    for path, data in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        print(f"wrote {path.relative_to(ROOT).as_posix()} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
