#!/usr/bin/env python3
"""BIZBOT official visual identity — deterministic asset generator.

Source of truth: the owner-supplied masters (byte-identical copies of the files
delivered in `App-logo/`, SHA-256 pinned in MASTERS below). Nothing here is
drawn, typeset, recoloured or reinterpreted: the masters are white-background
images (the symbol a PNG, the wordmarks JPEGs), so this script only

  1. removes the EXTERIOR white background algorithmically (flood fill from the
     frame; each boundary pixel is un-blended against white with the nearest
     solid colour as reference — no halo, no fringe),
  2. keeps the symbol's own white (the receipt paper) opaque, while background
     that is background BY TOPOLOGY (connected to the frame) can never turn
     into paper — the soft tip of the waist notch stays transparent,
  3. renders the symbol's designed fade-to-white elements (the three mint
     motion lines that run out into the background) as a true alpha fade:
     every pixel of such a line is un-blended against white with the line's
     own saturated colour as reference (see FADE_RULE). On white this
     reproduces the master exactly; on any other surface the line fades out
     instead of leaving an opaque white bar,
  4. trims / centres / downsamples (LANCZOS) the resulting RGBA cut-outs into
     every runtime derivative the apps need.

Symbol history: the first official symbol (`photo_2026-09-05_23-03-17 (2).jpg`,
SHA-256 d3cafcf6…) was replaced on 2026-09-06 by the final approved mark
(`c2355a92-43d1-42a2-8dbf-aa13e0121514.png`); its two master-specific straight
cuts were retired with it — the new master's paper is enclosed by ink and needs
none.

Outputs (all regenerated from scratch, byte-for-byte reproducible):

  packages/design_system/assets/brand/bizbot/bizbot_symbol.png        square RGBA (native scale, padded to a multiple of 16), symbol centred
  packages/design_system/assets/brand/bizbot/bizbot_wordmark_en.png   trimmed RGBA
  packages/design_system/assets/brand/bizbot/bizbot_wordmark_ar.png   trimmed RGBA
  apps/<app>/web/favicon.png                                          64x64 RGBA, transparent
  apps/<app>/web/icons/Icon-{192,512}.png                             RGBA, transparent, 8% padding
  apps/<app>/web/icons/Icon-maskable-{192,512}.png                    Light Neutral full-bleed, mark 56% (inside the 80% safe circle)
  apps/<app>/android/.../mipmap-*/ic_launcher.png                     legacy launcher: symbol alone, TRANSPARENT (no tile), mark 80%
  apps/<app>/android/.../mipmap-*/ic_launcher_foreground.png          adaptive foreground (108dp canvas, mark 50% — every ink pixel inside the 72dp circle mask; the adaptive BACKGROUND layer is transparent)
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

# Owner masters — byte-identical copies of the files in App-logo/:
#   symbol      c2355a92-43d1-42a2-8dbf-aa13e0121514.png   (final approved mark, 2026-09-06)
#   wordmarks   photo_2026-09-05_23-03-17.jpg (EN) / photo_2026-09-05_23-03-16.jpg (AR)
#   board       photo_2026-09-05_23-03-17 (3).jpg
MASTERS = {
    "symbol": ("bizbot_symbol_master.png",
               "b09550aa9b283b43c7f3791e2b6b46cbf06584838a875a3d673832a9add651ef"),
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
class FadeRule:
    """How a designed fade-to-white element is recognised in the symbol master.

    A fade is a THICK region of tinted, non-ink pixels (min channel >= min_channel,
    surviving `open_iter` erosions) that runs out into the frame-connected
    background and is not grey (median saturation >= sat) — i.e. the mint motion
    lines, never the receipt paper (grey shading, enclosed by ink) and never an
    antialiased outline (thin). Its pixels get alpha by un-blending against white
    with the region's own most-saturated colour as reference.
    """
    min_channel: int = 100
    sat: int = 25
    open_iter: int = 4


FADE_RULE = FadeRule()


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

def _frame_connected(mask: np.ndarray) -> np.ndarray:
    """The part of `mask` that touches the image frame (background by topology)."""
    lab, _ = ndi.label(mask)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    return np.isin(lab, border[border != 0])


def _channel_alphas(rgb: np.ndarray, ref: np.ndarray) -> np.ndarray:
    """Per-channel alpha of `rgb` as `ref` blended over white (NaN where the
    channel carries no information because ref is itself near white)."""
    denom = 255.0 - ref
    informative = denom > 40
    with np.errstate(invalid="ignore", divide="ignore"):
        return np.where(informative, (255.0 - rgb) / np.maximum(denom, 1e-6), np.nan)


def _unblend(rgb: np.ndarray, ref: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """alpha + un-premultiplied colour of `rgb` read as `ref` over white."""
    a_c = _channel_alphas(rgb, ref)
    with np.errstate(invalid="ignore"):
        a_c = np.where((np.isnan(a_c).all(axis=2))[..., None], 1.0, a_c)
        alpha = np.nanmax(a_c, axis=2)
    alpha = np.clip(np.nan_to_num(alpha, nan=1.0), 0.0, 1.0)
    a3 = alpha[..., None]
    colour = np.where(a3 > 0.15, (rgb - (1.0 - a3) * 255.0) / np.maximum(a3, 1e-6), ref)
    return alpha, colour


def _alpha_spread(a_c: np.ndarray) -> np.ndarray:
    """How much the per-channel alphas disagree (the wrong reference makes the
    channels disagree or overshoot 1)."""
    with np.errstate(invalid="ignore"):
        hi = np.nanmax(a_c, axis=2)
        lo = np.nanmin(a_c, axis=2)
    return np.nan_to_num(hi - lo, nan=9.0) + np.maximum(0.0, np.nan_to_num(hi, nan=0.0) - 1.0)


def cutout(rgb_u8: np.ndarray, *, keep_holes: bool, fades: FadeRule | None = None,
           strict_thr: int = 250, halo_thr: int = 236, band: int = 8,
           close_iter: int = 2, white_open: int = 4, noise_alpha: float = 0.04,
           min_area: int = 50, ink_thr: int = 200, ink_px: int = 20) -> np.ndarray:
    rgb = rgb_u8.astype(np.float64)
    mn = rgb.min(axis=2)
    sat = rgb.max(axis=2) - mn
    ink = mn < ink_thr
    strict_white = mn >= strict_thr

    # 1) Exterior. keep_holes=True: only white connected to the frame (the
    #    symbol's receipt stays). keep_holes=False: every white region (letter
    #    counters are background). `ext_soft` is the frame-connected NEAR-white:
    #    background by topology even where the master rendered it a little
    #    grey (the soft tip of the waist notch) — it never becomes paper.
    if keep_holes:
        ext = _frame_connected(strict_white)
        ext_soft = _frame_connected(mn >= halo_thr)
    else:
        ext = strict_white.copy()
        ext_soft = np.zeros_like(ext)

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
    ext = ~obj

    # 3) Thick genuine white regions inside the object (receipt paper) are solid
    #    no matter how close they come to the exterior — unless they ARE the
    #    exterior by topology.
    near_white = mn >= halo_thr
    if keep_holes:
        white_core = ndi.binary_opening(near_white & obj, iterations=white_open) \
            & ~ndi.binary_dilation(ext_soft, iterations=2)
    else:
        white_core = np.zeros_like(obj)

    # 4) Designed fades (FADE_RULE): thick tinted regions running out into the
    #    background. Each gets its own reference colour (its saturated end).
    fade = np.zeros_like(obj)
    fade_ref = np.zeros_like(rgb)
    if fades is not None:
        pale = obj & (mn >= fades.min_channel)
        fl, nf = ndi.label(ndi.binary_opening(pale, iterations=fades.open_iter))
        ext_near = ndi.binary_dilation(ext, iterations=2)
        for i in range(1, nf + 1):
            comp = fl == i
            if not (comp & ext_near).any():          # enclosed: paper / check mark
                continue
            if np.percentile(sat[comp], 50) < fades.sat:   # grey shading, not a tint
                continue
            region = ndi.binary_dilation(comp, iterations=band) & pale
            top = np.percentile(sat[region], 99)
            fade |= region
            fade_ref[region] = np.median(rgb[region & (sat >= top)], axis=0)

    # 5) Boundary band + un-blend against white with nearest-solid reference.
    ext_d = ndi.binary_dilation(ext, iterations=band)
    solid = ((obj & ~ext_d) | white_core) & ~fade
    edge = obj & ~solid
    idx = ndi.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    ref = rgb[idx[0], idx[1]]
    ref[fade] = fade_ref[fade]
    if keep_holes:
        # A boundary pixel next to the background whose nearest solid is PAPER
        # would be judged "paper, opaque" — wrong for the antialiased rim of a
        # background channel that touches the paper. Use the nearest solid INK.
        paper_ref = edge & (ref.min(axis=2) >= halo_thr) & ndi.binary_dilation(ext_soft, iterations=2)
        if paper_ref.any():
            ink_solid = solid & (mn < halo_thr)
            ii = ndi.distance_transform_edt(~ink_solid, return_distances=False, return_indices=True)
            ref = np.where(paper_ref[..., None], rgb[ii[0], ii[1]], ref)
    alpha, colour = _unblend(rgb, ref)

    # 6) Seam between a fade and dark ink (the 1-2 px antialiased join): such a
    #    pixel is either "dark ink over white" or "the fade over white"; keep
    #    the reference whose per-channel alphas agree.
    if fade.any():
        dark = solid & (mn < fades.min_channel)
        seam = fade & ndi.binary_dilation(dark, iterations=2)
        if seam.any() and dark.any():
            di = ndi.distance_transform_edt(~dark, return_distances=False, return_indices=True)
            dark_ref = rgb[di[0], di[1]]
            use_dark = seam & (_alpha_spread(_channel_alphas(rgb, dark_ref))
                               < _alpha_spread(_channel_alphas(rgb, fade_ref)))
            alpha_d, colour_d = _unblend(rgb, dark_ref)
            alpha = np.where(use_dark, alpha_d, alpha)
            colour = np.where(use_dark[..., None], colour_d, colour)

    alpha[solid] = 1.0
    alpha[ext] = 0.0
    alpha[ext_soft & ~fade] = 0.0  # background by topology is never opaque
    out = rgb.copy()
    out[edge] = np.clip(colour, 0.0, 255.0)[edge]
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

    symbol_rgba = cutout(load_master("symbol"), keep_holes=True, fades=FADE_RULE)
    symbol = to_image(trim(symbol_rgba))
    # Canonical symbol: centred on a square transparent canvas at native scale
    # (side = the trimmed mark's longer side, padded up to a multiple of 16).
    side = -(-max(symbol.size) // 16) * 16
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
            # Legacy launcher icon (BIZBOT-LAUNCHER-TRANSPARENT, 2026-09-06 —
            # owner decision: nothing behind the symbol): the symbol alone on
            # a transparent canvas. 0.80 keeps every ink pixel inside the
            # square (the mark's ink reaches 0.614 x its longer side from the
            # centre; 0.80 x 0.614 = 0.49 <= 0.5).
            out[res / f"mipmap-{density}" / "ic_launcher.png"] = png_bytes(
                transparent_icon(symbol, px, 0.80))
        for density, px in ADAPTIVE_FG.items():
            # Adaptive foreground: 108dp canvas, background layer transparent
            # (values/ic_launcher_background.xml), so the launcher shows the
            # symbol shape alone. 0.50 keeps every ink pixel inside the 72dp
            # circle mask with breathing room (0.50 x 0.614 x 108 = 33.2dp
            # <= 36dp radius) — as large as the mark can be without any
            # launcher mask clipping it.
            out[res / f"mipmap-{density}" / "ic_launcher_foreground.png"] = png_bytes(
                transparent_icon(symbol, px, 0.50))

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
