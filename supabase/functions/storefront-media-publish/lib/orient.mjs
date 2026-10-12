// STOREFRONT-PUBLISH-001 recipe `storefront-media-c4`: EXIF orientation
// (carried over from the Q031 spike unchanged).
//
// JPEG only: the orientation is read from the FIRST APP1 "Exif\0\0" segment
// before the first scan (a PNG eXIf chunk is stripped, never applied). The
// transforms are pure integer pixel copies of the RGBA raster, applied AFTER
// the resize (the resize runs in the source orientation), so every oriented
// derivative equals the orientation-1 derivative transformed
// (test/recipe.test.mjs proves both the EXIF definitions and that equality).

/** Orientation 1..8 from the FIRST APP1 Exif segment of a JPEG; 1 when absent or malformed. */
export function jpegExifOrientation(b) {
  let o = 2;
  while (o + 4 <= b.length && b[o] === 0xff) {
    const m = b[o + 1];
    if (m === 0xda || m === 0xd9) break; // scan data / end: no APPn after this point matters
    if (m >= 0xd0 && m <= 0xd7) { o += 2; continue; }
    const len = (b[o + 2] << 8) | b[o + 3];
    if (len < 2 || o + 2 + len > b.length) break;
    if (m === 0xe1 && len >= 8 && b[o + 4] === 0x45 && b[o + 5] === 0x78 && b[o + 6] === 0x69 && b[o + 7] === 0x66 && b[o + 8] === 0 && b[o + 9] === 0) {
      return tiffOrientation(b.subarray(o + 10, o + 2 + len));
    }
    o += 2 + len;
  }
  return 1;
}

function tiffOrientation(t) {
  if (t.length < 8) return 1;
  const le = t[0] === 0x49 && t[1] === 0x49;
  const be = t[0] === 0x4d && t[1] === 0x4d;
  if (!le && !be) return 1;
  const u16 = (o) => (le ? t[o] | (t[o + 1] << 8) : (t[o] << 8) | t[o + 1]);
  const u32 = (o) => (le ? (t[o] | (t[o + 1] << 8) | (t[o + 2] << 16)) + t[o + 3] * 0x1000000 : t[o] * 0x1000000 + ((t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]));
  if (u16(2) !== 42) return 1;
  const ifd = u32(4);
  if (ifd < 8 || ifd + 2 > t.length) return 1;
  const n = u16(ifd);
  for (let i = 0; i < n; i++) {
    const e = ifd + 2 + i * 12;
    if (e + 12 > t.length) return 1;
    if (u16(e) === 0x0112) {
      if (u16(e + 2) !== 3 || u32(e + 4) !== 1) return 1; // SHORT, count 1
      const v = u16(e + 8);
      return v >= 1 && v <= 8 ? v : 1;
    }
  }
  return 1;
}

/**
 * Applies EXIF orientation o to an RGBA raster (w x h). Returns { data, width, height }.
 * Pure integer copies; orientation 1 returns the input unchanged.
 */
export function applyOrientation(src, w, h, o) {
  if (o === 1) return { data: src, width: w, height: h };
  const swap = o >= 5;
  const W = swap ? h : w, H = swap ? w : h;
  const s32 = new Uint32Array(src.buffer, src.byteOffset, w * h);
  const out = new Uint8Array(W * H * 4);
  const d32 = new Uint32Array(out.buffer);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let sx, sy;
      switch (o) {
        case 2: sx = w - 1 - x; sy = y; break; // mirror horizontal
        case 3: sx = w - 1 - x; sy = h - 1 - y; break; // rotate 180
        case 4: sx = x; sy = h - 1 - y; break; // mirror vertical
        case 5: sx = y; sy = x; break; // transpose
        case 6: sx = y; sy = h - 1 - x; break; // rotate 90 CW
        case 7: sx = w - 1 - y; sy = h - 1 - x; break; // transverse
        case 8: sx = w - 1 - y; sy = x; break; // rotate 270 CW
        default: throw new Error(`orientation ${o}`);
      }
      d32[y * W + x] = s32[sy * w + sx];
    }
  }
  return { data: out, width: W, height: H };
}
