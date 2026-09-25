// Deterministic SYNTHETIC source images for the function's tests (procedural pixels,
// no real photo, no tenant data), with NO image engine:
//   - PNG sources are written here with node:zlib (a different zlib may compress
//     differently, but the DECODED pixels, and so every derivative, are identical);
//   - WebP sources are encoded by the vendored libwebp encoder the function ships;
//   - JPEG sources are the four committed files of test/fixtures/ (README.md there:
//     synthetic pixels, the scratch-only mozjpeg encoder and its settings); their
//     orientation / EXIF / truncated / corrupt / 4-component / over-cap variants are
//     byte edits made here at test time.
// The builders and names are those of the Q031 spike vector set (mkvectors.mjs), so the
// goldens of test/recipe.test.mjs are the values the spike agreed on across Node 22,
// Node 24 and edge-runtime v1.74.3.
import { createDeflate, deflateSync, crc32 as zcrc32 } from 'node:zlib';
import { readFile } from 'node:fs/promises';
import { codecs } from './engine.mjs';

const FIXTURE_DIR = new URL('./fixtures/', import.meta.url);

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const clamp = (v) => (v < 0 ? 0 : v > 255 ? 255 : v | 0);

// CRC-32 (zlib.crc32 exists from Node 22.2; a table fallback keeps older runtimes working).
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
function crc(buf) {
  if (typeof zcrc32 === 'function') return zcrc32(buf) >>> 0;
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
export function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
  return Buffer.concat([len, td, c]);
}
export const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

function ihdrOf(width, height, depth, colorType, interlace = 0) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = depth; ihdr[9] = colorType; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = interlace;
  return ihdr;
}

/** Filtered (filter 0) scanlines of a PNG. channels: 1 gray, 2 gray+alpha, 3 rgb, 4 rgba; depth 8 or 16. */
export function pngRaw({ width, height, channels, depth = 8, rows, palette = null }) {
  const bpp = palette ? 1 : channels * (depth / 8);
  const raw = Buffer.alloc((width * bpp + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * bpp + 1)] = 0;
    rows(y, raw.subarray(y * (width * bpp + 1) + 1, (y + 1) * (width * bpp + 1)));
  }
  return raw;
}

/** Minimal PNG writer (the spike's). `idat` overrides the zlib image data; `level` its compression. */
export function png({ width, height, channels, depth = 8, rows, palette = null, trns = null, extraChunks = [], idat = null, level = 9 }) {
  const colorType = palette ? 3 : new Map([[1, 0], [2, 4], [3, 2], [4, 6]]).get(channels);
  const parts = [PNG_SIGNATURE, chunk('IHDR', ihdrOf(width, height, depth, colorType))];
  for (const [t, d] of extraChunks.filter((c) => c[2] === 'beforePLTE')) parts.push(chunk(t, d));
  if (palette) parts.push(chunk('PLTE', Buffer.from(palette)));
  if (trns) parts.push(chunk('tRNS', Buffer.from(trns)));
  for (const [t, d] of extraChunks.filter((c) => c[2] !== 'beforePLTE')) parts.push(chunk(t, d));
  parts.push(chunk('IDAT', idat ?? deflateSync(pngRaw({ width, height, channels, depth, rows, palette }), { level })));
  parts.push(chunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(parts);
}

function coverage(x, y, test) {
  let n = 0;
  for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) if (test(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)) n++;
  return n / 16;
}

/** Logo-like RGBA: a disc + a bar, soft anti-aliased edges, a semi-transparent shadow. */
export function logoRgba(width, height, { opaqueBackground = null } = {}) {
  const cx = width * 0.33, cy = height * 0.5, r = Math.min(width, height) * 0.36;
  const bx0 = width * 0.58, bx1 = width * 0.93, by0 = height * 0.38, by1 = height * 0.62, br = height * 0.08;
  const inDisc = (x, y) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
  const inBar = (x, y) => {
    const qx = Math.max(bx0 + br - x, 0, x - (bx1 - br));
    const qy = Math.max(by0 + br - y, 0, y - (by1 - br));
    return qx * qx + qy * qy <= br * br && x >= bx0 && x <= bx1 && y >= by0 && y <= by1;
  };
  const shadowOff = Math.max(2, Math.round(Math.min(width, height) * 0.02));
  return (y, row) => {
    for (let x = 0; x < width; x++) {
      const nearDisc = Math.abs(Math.hypot(x + 0.5 - cx, y + 0.5 - cy) - r) < 2;
      const cDisc = nearDisc ? coverage(x, y, inDisc) : (inDisc(x + 0.5, y + 0.5) ? 1 : 0);
      const cBar = coverage(x, y, inBar);
      const cShadow = 0.45 * coverage(x - shadowOff, y - shadowOff, (a, b) => inDisc(a, b) || inBar(a, b));
      const shape = Math.max(cDisc, cBar);
      const gx = x / width, gy = y / height;
      let r8 = cDisc >= cBar ? 200 + 40 * gx : 40 + 30 * gy;
      let g8 = cDisc >= cBar ? 90 + 60 * gy : 110 + 80 * gx;
      let b8 = cDisc >= cBar ? 40 : 190 - 40 * gy;
      const a = shape + cShadow * (1 - shape);
      if (a > 0 && shape < 1) {
        const sa = cShadow * (1 - shape);
        r8 = (r8 * shape + 30 * sa) / a; g8 = (g8 * shape + 30 * sa) / a; b8 = (b8 * shape + 34 * sa) / a;
      }
      if (opaqueBackground) {
        const [R, G, B] = opaqueBackground;
        row[x * 3] = clamp(r8 * a + R * (1 - a)); row[x * 3 + 1] = clamp(g8 * a + G * (1 - a)); row[x * 3 + 2] = clamp(b8 * a + B * (1 - a));
      } else {
        row[x * 4] = clamp(r8); row[x * 4 + 1] = clamp(g8); row[x * 4 + 2] = clamp(b8); row[x * 4 + 3] = clamp(Math.round(a * 255));
      }
    }
  };
}

/** Photo-like RGB with seeded texture + noise (the committed JPEGs use seed 7, noise 10). */
export function photoRgb(width, height, seed, noise) {
  const rnd = mulberry32(seed);
  return (y, row) => {
    for (let x = 0; x < width; x++) {
      const gx = x / width, gy = y / height;
      const wave = Math.sin(x * 0.013 + y * 0.007) * 30 + Math.sin(x * 0.051 - y * 0.043) * 12;
      const n = (rnd() - 0.5) * noise;
      row[x * 3] = clamp(90 + 120 * gx + wave + n);
      row[x * 3 + 1] = clamp(70 + 100 * gy - wave * 0.5 + n);
      row[x * 3 + 2] = clamp(60 + 80 * (1 - gx) * gy + wave * 0.3 + n);
    }
  };
}

/**
 * Ladder bands: a 960x960 PNG (no resize at w960), two-level RGB noise of amplitude 58
 * over the top fraction f of the rows; optional two-level alpha (255/128) over the top
 * fraction g. The VP8 size scales with f and the ALPH size with g, which selects the rung.
 * (zlib level 1: the spike used 9; the decoded pixels, and so the derivatives, are identical.)
 */
export function bandC3(f, alpha, g) {
  const S = 960, A = 58, seed = Math.round(f * 1000) + (alpha ? 7 : 0);
  const rnd = mulberry32(seed); const arnd = mulberry32(seed + 99991); const ch = alpha ? 4 : 3; const rows = Math.round(S * f);
  const raw = Buffer.alloc((S * ch + 1) * S);
  for (let y = 0; y < S; y++) {
    const o = y * (S * ch + 1); raw[o] = 0;
    for (let x = 0; x < S; x++) {
      const p = o + 1 + ch * x;
      for (let c = 0; c < 3; c++) raw[p + c] = y < rows ? 128 + (rnd() < 0.5 ? -A : A) : 128;
      if (alpha && g !== null) raw[p + 3] = y < Math.round(S * g) && arnd() < 0.5 ? 128 : 255;
      else if (alpha) raw[p + 3] = x < S / 2 ? 255 : Math.round(((x - S / 2) * 255) / (S / 2 - 1));
    }
  }
  return Buffer.concat([PNG_SIGNATURE, chunk('IHDR', ihdrOf(S, S, 8, alpha ? 6 : 2)), chunk('IDAT', deflateSync(raw, { level: 1 })), chunk('IEND', Buffer.alloc(0))]);
}

/** Adam7 interlaced RGBA PNG (8-bit), for the interlaced raw-size bound. */
function pngAdam7(W, H, rowsFn) {
  const full = Buffer.alloc(W * H * 4); const row = Buffer.alloc(W * 4);
  for (let y = 0; y < H; y++) { rowsFn(y, row); row.copy(full, y * W * 4); }
  const passes = [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]];
  const parts = [];
  for (const [x0, y0, dx, dy] of passes) {
    const pw = W > x0 ? Math.ceil((W - x0) / dx) : 0; const ph = H > y0 ? Math.ceil((H - y0) / dy) : 0;
    if (!pw || !ph) continue;
    for (let j = 0; j < ph; j++) {
      const r = Buffer.alloc(1 + pw * 4);
      for (let i = 0; i < pw; i++) full.copy(r, 1 + i * 4, ((y0 + j * dy) * W + x0 + i * dx) * 4, ((y0 + j * dy) * W + x0 + i * dx) * 4 + 4);
      parts.push(r);
    }
  }
  return Buffer.concat([PNG_SIGNATURE, chunk('IHDR', ihdrOf(W, H, 8, 6, 1)), chunk('IDAT', deflateSync(Buffer.concat(parts), { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

/** A zlib stream of `prefix` followed by `zeroMiB` MiB of zero bytes, streamed (never allocated whole). */
export async function zlibWithZeroTail(prefix, zeroMiB, level = 9) {
  const z = createDeflate({ level, chunkSize: 1 << 20 });
  const out = [];
  z.on('data', (c) => out.push(c));
  const done = new Promise((resolve, reject) => { z.on('end', resolve); z.on('error', reject); });
  const zero = Buffer.alloc(1 << 20);
  if (prefix) z.write(prefix);
  for (let i = 0; i < zeroMiB; i++) { if (!z.write(zero)) await new Promise((r) => z.once('drain', r)); }
  z.end();
  await done;
  return Buffer.concat(out);
}

// One zlib stream that inflates to exactly 1 GiB of zeros (~1.04 MB), shared by the ancillary bombs.
let gibStream = null;
const oneGibOfZeros = () => (gibStream ??= zlibWithZeroTail(null, 1024));

// ------------------------------------------------------------------------- JPEG
const jpegFile = async (name) => new Uint8Array(await readFile(new URL(name, FIXTURE_DIR)));
export const JPEG_FIXTURE_SHA256 = Object.freeze(new Map([
  ['prog_420_1600x1200.jpg', '51f81644a35708d49199ea3143cc74e1a61b8101ffec89fbf9cdd34b99beb0c4'],
  ['base_444_1200x900.jpg', '93ff9d06014d4ba1d90e130c698361ca76532b4a07e0d3d1bb3031f590a9af04'],
  ['gray_prog_1000x750.jpg', 'bc9b5f3ccc3cb45b5d04990e09937a8c550b312f1315e91578c910d713918199'],
  ['base_420_900x450.jpg', '0539fe2a8cc6ee3cd1074b887cfba33d31784b5d6c317df839fb8254607d4a2e'],
]));

/** Inserts an APP1 segment (payload = "Exif\0\0" + tiff) right after SOI. */
function withApp1(j, tiff) {
  const payload = Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff]);
  const seg = Buffer.alloc(4); seg[0] = 0xff; seg[1] = 0xe1; seg.writeUInt16BE(payload.length + 2, 2);
  return new Uint8Array(Buffer.concat([Buffer.from(j.subarray(0, 2)), seg, payload, Buffer.from(j.subarray(2))]));
}

/** Inserts an APP1 Exif segment carrying orientation o right after SOI (the spike's). */
export function withOrientation(j, o, bigEndian = true) {
  const t = Buffer.alloc(26);
  if (bigEndian) { t.write('MM', 0, 'latin1'); t.writeUInt16BE(42, 2); t.writeUInt32BE(8, 4); t.writeUInt16BE(1, 8); t.writeUInt16BE(0x0112, 10); t.writeUInt16BE(3, 12); t.writeUInt32BE(1, 14); t.writeUInt16BE(o, 18); t.writeUInt32BE(0, 22); }
  else { t.write('II', 0, 'latin1'); t.writeUInt16LE(42, 2); t.writeUInt32LE(8, 4); t.writeUInt16LE(1, 8); t.writeUInt16LE(0x0112, 10); t.writeUInt16LE(3, 12); t.writeUInt32LE(1, 14); t.writeUInt16LE(o, 18); t.writeUInt32LE(0, 22); }
  return withApp1(j, t);
}

export const GPS_MARKER = 'RF-PRIVATE-GPS-CAMERA';
/** An EXIF block with a Make string and a GPS IFD (latitude N 32 4' 50") — private metadata that must never be published. */
export function withExifGps(j) {
  const make = Buffer.from(`${GPS_MARKER}\0`, 'latin1');
  const t = Buffer.alloc(8 + 2 + 2 * 12 + 4 + 2 + 2 * 12 + 4 + 24 + make.length);
  let o = 0;
  t.write('MM', 0, 'latin1'); t.writeUInt16BE(42, 2); t.writeUInt32BE(8, 4); o = 8;
  const ifd0 = o; const gpsIfd = ifd0 + 2 + 2 * 12 + 4; const rationals = gpsIfd + 2 + 2 * 12 + 4; const makeAt = rationals + 24;
  t.writeUInt16BE(2, ifd0);
  // Make (0x010F), ASCII, count, offset
  t.writeUInt16BE(0x010f, ifd0 + 2); t.writeUInt16BE(2, ifd0 + 4); t.writeUInt32BE(make.length, ifd0 + 6); t.writeUInt32BE(makeAt, ifd0 + 10);
  // GPSInfo (0x8825), LONG, 1, offset of the GPS IFD
  t.writeUInt16BE(0x8825, ifd0 + 14); t.writeUInt16BE(4, ifd0 + 16); t.writeUInt32BE(1, ifd0 + 18); t.writeUInt32BE(gpsIfd, ifd0 + 22);
  t.writeUInt32BE(0, ifd0 + 26);
  t.writeUInt16BE(2, gpsIfd);
  // GPSLatitudeRef (1), ASCII, 2, "N\0" inline
  t.writeUInt16BE(1, gpsIfd + 2); t.writeUInt16BE(2, gpsIfd + 4); t.writeUInt32BE(2, gpsIfd + 6); t.write('N', gpsIfd + 10, 'latin1');
  // GPSLatitude (2), RATIONAL, 3, offset
  t.writeUInt16BE(2, gpsIfd + 14); t.writeUInt16BE(5, gpsIfd + 16); t.writeUInt32BE(3, gpsIfd + 18); t.writeUInt32BE(rationals, gpsIfd + 22);
  t.writeUInt32BE(0, gpsIfd + 26);
  [[32, 1], [4, 1], [5000, 100]].forEach(([n, d], i) => { t.writeUInt32BE(n, rationals + i * 8); t.writeUInt32BE(d, rationals + i * 8 + 4); });
  make.copy(t, makeAt);
  return withApp1(j, t);
}

/** Offset of the first SOF0/SOF1/SOF2 marker (0xFF at the returned index). */
function sofOffset(j) {
  let o = 2;
  while (o < j.length) {
    const m = j[o + 1];
    if (m === 0xc0 || m === 0xc1 || m === 0xc2) return o;
    o += 2 + ((j[o + 2] << 8) | j[o + 3]);
  }
  throw new Error('no SOF');
}
/** The same JPEG with its SOF declaring width x height (the scan data is untouched). */
export function withSofSize(j, width, height) {
  const out = new Uint8Array(j);
  const o = sofOffset(out);
  out[o + 5] = height >> 8; out[o + 6] = height & 255; out[o + 7] = width >> 8; out[o + 8] = width & 255;
  return out;
}
/** The same JPEG with a 4-component (CMYK-shaped) SOF: refused before any decode. */
export function withFourComponentSof(j) {
  const o = sofOffset(j);
  const len = (j[o + 2] << 8) | j[o + 3];
  const sof = Buffer.alloc(2 + 8 + 3 * 4);
  sof[0] = 0xff; sof[1] = j[o + 1]; sof.writeUInt16BE(8 + 3 * 4, 2);
  sof[4] = 8; sof[5] = j[o + 5]; sof[6] = j[o + 6]; sof[7] = j[o + 7]; sof[8] = j[o + 8]; sof[9] = 4;
  for (let c = 0; c < 4; c++) { sof[10 + 3 * c] = c + 1; sof[11 + 3 * c] = 0x11; sof[12 + 3 * c] = 0; }
  return new Uint8Array(Buffer.concat([Buffer.from(j.subarray(0, o)), sof, Buffer.from(j.subarray(o + 2 + len))]));
}
/** The spike's entropy corruption: 400 bytes in the middle rewritten without introducing 0xFF. */
export function withCorruptEntropy(j) {
  const c = new Uint8Array(j);
  for (let i = Math.floor(c.length * 0.5); i < Math.floor(c.length * 0.5) + 400; i++) c[i] = (c[i] * 7 + 13) & 0x7f;
  return c;
}

// ------------------------------------------------------------------------- WebP
const WEBP_BASE = Object.freeze({ target_size: 0, target_PSNR: 0, method: 4, sns_strength: 50, filter_strength: 60, filter_sharpness: 0, filter_type: 1, partitions: 0, segments: 4, pass: 1, show_compressed: 0, preprocessing: 0, autofilter: 0, partition_limit: 0, alpha_compression: 1, alpha_filtering: 1, alpha_quality: 100, lossless: 0, exact: 0, image_hint: 0, emulate_jpeg_size: 0, thread_level: 0, low_memory: 0, near_lossless: 100, use_delta_palette: 0, use_sharp_yuv: 0 });

export function rgbaFromRows(W, H, rowsFn, ch) {
  const out = new Uint8ClampedArray(W * H * 4); const row = new Uint8Array(W * ch);
  for (let y = 0; y < H; y++) {
    rowsFn(y, row);
    for (let x = 0; x < W; x++) { const o = (y * W + x) * 4; out[o] = row[x * ch]; out[o + 1] = row[x * ch + 1]; out[o + 2] = row[x * ch + 2]; out[o + 3] = ch === 4 ? row[x * ch + 3] : 255; }
  }
  return out;
}
/** A WebP source encoded by the vendored encoder (the spike's settings). */
export async function webp(W, H, { alpha = true, lossless = false, quality = 80 } = {}) {
  const rgba = alpha ? rgbaFromRows(W, H, logoRgba(W, H), 4) : rgbaFromRows(W, H, photoRgb(W, H, 3, 12), 3);
  return new Uint8Array(await (await codecs()).encodeWebp(rgba, W, H, { ...WEBP_BASE, quality, lossless: lossless ? 1 : 0 }));
}
const riff = (chunks) => {
  const body = Buffer.concat(chunks.map(([tag, data]) => {
    const h = Buffer.alloc(8); h.write(tag, 0, 'latin1'); h.writeUInt32LE(data.length, 4);
    return Buffer.concat([h, data, data.length & 1 ? Buffer.alloc(1) : Buffer.alloc(0)]);
  }));
  const head = Buffer.alloc(12); head.write('RIFF', 0, 'latin1'); head.writeUInt32LE(4 + body.length, 4); head.write('WEBP', 8, 'latin1');
  return new Uint8Array(Buffer.concat([head, body]));
};
/** Splits an extended WebP into [tag, data] chunks (after RIFF/WEBP). */
function webpChunkList(b) {
  const out = []; let o = 12; const buf = Buffer.from(b);
  while (o + 8 <= buf.length) { const tag = buf.toString('latin1', o, o + 4); const size = buf.readUInt32LE(o + 4); out.push([tag, buf.subarray(o + 8, o + 8 + size)]); o += 8 + size + (size & 1); }
  return out;
}
/** The same extended (VP8X) WebP with ICCP, EXIF and XMP chunks added and flagged. */
export function withWebpMetadata(b) {
  const list = webpChunkList(b);
  if (list[0][0] !== 'VP8X') throw new Error('extended webp expected');
  const vp8x = Buffer.from(list[0][1]); vp8x[0] |= 0x20 | 0x08 | 0x04;
  const icc = Buffer.from(`RF-PRIVATE-ICC-${'x'.repeat(40)}`, 'latin1');
  const exif = Buffer.from(`MM\0*\0\0\0\x08\0\0\0\0\0\0${GPS_MARKER}`, 'latin1');
  const xmp = Buffer.from(`<x:xmpmeta xmlns:x="adobe:ns:meta/">${GPS_MARKER}</x:xmpmeta>`, 'latin1');
  return riff([['VP8X', vp8x], ['ICCP', icc], ...list.slice(1), ['EXIF', exif], ['XMP ', xmp]]);
}

// ------------------------------------------------------------------------- the named set
const B = 'restaurant-logos', M = 'menu-images';
const both = ['w480', 'w960'];
const W960 = ['w960'], W480 = ['w480'];
// Cheap, highly compressible RGB for the 8 MiP cap edge (rows repeat in 64-row bands, so it fits the 5 MiB source cap).
const bandedRgb = (W) => (y, row) => { const band = (y >> 6) & 31; for (let x = 0; x < W; x++) { row[x * 3] = x & 255; row[x * 3 + 1] = (band * 8 + (x >> 8) * 4) & 255; row[x * 3 + 2] = (((x >> 5) ^ band) * 7) & 255; } };

/** name -> { bucket, variants, build }. Builders are lazy (some are several MB of pixels). */
export const FIXTURES = new Map([
  // ---- PNG (the spike's goldens)
  ['logo_alpha_2000x1000', { bucket: B, variants: both, build: async () => png({ width: 2000, height: 1000, channels: 4, rows: logoRgba(2000, 1000) }) }],
  ['logo_opaque_rgb_1200x600', { bucket: B, variants: both, build: async () => png({ width: 1200, height: 600, channels: 3, rows: logoRgba(1200, 600, { opaqueBackground: [246, 243, 236] }) }) }],
  ['logo_small_300x150', { bucket: B, variants: both, build: async () => png({ width: 300, height: 150, channels: 4, rows: logoRgba(300, 150) }) }],
  ['logo_portrait_600x1800', { bucket: B, variants: both, build: async () => png({ width: 600, height: 1800, channels: 4, rows: logoRgba(600, 1800) }) }],
  ['hero_alpha_1600x1200', { bucket: M, variants: W960, build: async () => png({ width: 1600, height: 1200, channels: 4, rows: logoRgba(1600, 1200) }) }],
  ['palette_trns_640x320', { bucket: B, variants: both, build: async () => {
    const pal = []; const trns = [];
    for (let i = 0; i < 256; i++) { pal.push(i, 255 - i, (i * 3) & 255); trns.push(i < 64 ? i * 4 : 255); }
    return png({ width: 640, height: 320, channels: 1, palette: pal, trns, rows: (y, row) => { for (let x = 0; x < 640; x++) row[x] = (x + y) & 255; } });
  } }],
  ['gray_800x400', { bucket: B, variants: both, build: async () => png({ width: 800, height: 400, channels: 1, rows: (y, row) => { for (let x = 0; x < 800; x++) row[x] = (x * 255 / 799 + y) & 255; } }) }],
  ['gray_alpha_800x400', { bucket: B, variants: both, build: async () => png({ width: 800, height: 400, channels: 2, rows: (y, row) => { for (let x = 0; x < 800; x++) { row[x * 2] = (x + y) & 255; row[x * 2 + 1] = x < 400 ? 255 : (x - 400) * 255 / 399; } } }) }],
  ['rgba16_800x400', { bucket: B, variants: both, build: async () => png({ width: 800, height: 400, channels: 4, depth: 16, rows: (() => { const f = logoRgba(800, 400); const tmp = Buffer.alloc(800 * 4); return (y, row) => { f(y, tmp); for (let i = 0; i < tmp.length; i++) { row[i * 2] = tmp[i]; row[i * 2 + 1] = (i * 37 + y) & 255; } }; })() }) }],
  ['adam7_rgba_777x555', { bucket: B, variants: both, build: async () => pngAdam7(777, 555, logoRgba(777, 555)) }],
  ['rgba_all_opaque_800x400', { bucket: B, variants: both, build: async () => png({ width: 800, height: 400, channels: 4, rows: (y, row) => { for (let x = 0; x < 800; x++) { row[x * 4] = (x * 3) & 255; row[x * 4 + 1] = y & 255; row[x * 4 + 2] = 128; row[x * 4 + 3] = 255; } } }) }],
  ['meta_png_with_ancillary', { bucket: B, variants: both, build: async () => {
    const exif = Buffer.from('4d4d002a00000008000101120003000000010006000000000000', 'hex'); // eXIf orientation 6: never applied to a PNG
    return png({ width: 700, height: 350, channels: 4, rows: logoRgba(700, 350), extraChunks: [['tEXt', Buffer.from('Comment\0private-text', 'latin1')], ['eXIf', exif], ['gAMA', Buffer.from([0, 0, 0xb1, 0x8f])]] });
  } }],
  ['band_q82', { bucket: M, variants: W960, build: async () => bandC3(0.5, false, null) }],
  ['band_q74', { bucket: M, variants: W960, build: async () => bandC3(0.98, false, null) }],
  ['band_alpha_q50', { bucket: M, variants: W960, build: async () => bandC3(0.98, true, 0.8) }],
  ['band_none', { bucket: M, variants: W960, build: async () => bandC3(1.0, false, null) }],
  // ---- JPEG (committed fixtures + test-time byte edits)
  ['jpeg_prog_1600x1200', { bucket: M, variants: W960, build: async () => jpegFile('prog_420_1600x1200.jpg') }],
  ['jpeg_base_444_1200x900', { bucket: M, variants: W960, build: async () => jpegFile('base_444_1200x900.jpg') }],
  ['jpeg_gray_1000x750', { bucket: M, variants: W960, build: async () => jpegFile('gray_prog_1000x750.jpg') }],
  ['jpeg_logo_900x450', { bucket: B, variants: both, build: async () => jpegFile('base_420_900x450.jpg') }],
  ...[1, 2, 3, 4, 5, 6, 7, 8].map((o) => [`jpeg_orient_${o}`, { bucket: M, variants: W960, build: async () => withOrientation(await jpegFile('prog_420_1600x1200.jpg'), o, o % 2 === 0) }]),
  ['jpeg_exif_gps', { bucket: B, variants: W480, build: async () => withExifGps(await jpegFile('base_420_900x450.jpg')) }],
  // ---- WebP (the vendored encoder)
  ['webp_lossy_alpha_900x600', { bucket: M, variants: W960, build: async () => webp(900, 600, { alpha: true }) }],
  ['webp_lossless_alpha_1200x800', { bucket: B, variants: both, build: async () => webp(1200, 800, { alpha: true, lossless: true }) }],
  ['webp_lossy_opaque_1300x900', { bucket: M, variants: W960, build: async () => webp(1300, 900, { alpha: false }) }],
  ['webp_with_metadata', { bucket: M, variants: W960, build: async () => withWebpMetadata(await webp(900, 600, { alpha: true })) }],
  ['entropy_webp_lossless', { bucket: M, variants: W960, build: async () => {
    const W = 1100, H = 1100; const rnd = mulberry32(2026); const rgba = new Uint8ClampedArray(W * H * 4); for (let i = 0; i < rgba.length; i++) rgba[i] = (rnd() * 256) | 0;
    return new Uint8Array(await (await codecs()).encodeWebp(rgba, W, H, { ...WEBP_BASE, quality: 100, method: 0, lossless: 1, exact: 1 }));
  } }],
  // ---- the 8 MiP decode cap (c4): exactly at the cap derives, one row over is refused
  ['png_at_cap_4096x2048', { bucket: M, variants: W960, build: async () => png({ width: 4096, height: 2048, channels: 3, rows: bandedRgb(4096), level: 1 }) }],
  ['png_over_cap_4096x2049', { bucket: M, variants: W960, build: async () => png({ width: 4096, height: 2049, channels: 3, rows: bandedRgb(4096), level: 1 }) }],
  ['png_over_cap_header', { bucket: B, variants: W480, build: async () => png({ width: 4096, height: 2049, channels: 4, rows: () => {}, idat: deflateSync(Buffer.alloc(1024)) }) }],
  ['jpeg_over_cap_sof', { bucket: M, variants: W960, build: async () => withSofSize(await jpegFile('base_420_900x450.jpg'), 4096, 2049) }],
  ['jpeg_over_side_sof', { bucket: M, variants: W960, build: async () => withSofSize(await jpegFile('base_420_900x450.jpg'), 8193, 1100) }],
  ['webp_over_cap_header', { bucket: M, variants: W960, build: async () => {
    const bits = (4096 - 1) | ((2049 - 1) << 14); // VP8L: 14-bit width-1, 14-bit height-1, alpha 0, version 0
    return riff([['VP8L', Buffer.from([0x2f, bits & 255, (bits >>> 8) & 255, (bits >>> 16) & 255, (bits >>> 24) & 255, 0, 0, 0])]]);
  } }],
  // ---- hostile / refused
  ['bad_apng', { bucket: B, variants: W480, build: async () => { const actl = Buffer.alloc(8); actl.writeUInt32BE(2, 0); return png({ width: 64, height: 64, channels: 4, rows: logoRgba(64, 64), extraChunks: [['acTL', actl]] }); } }],
  ['bad_webp_animated', { bucket: M, variants: W960, build: async () => {
    const vp8x = Buffer.alloc(10); vp8x[0] = 0x02 | 0x10; vp8x.writeUIntLE(63, 4, 3); vp8x.writeUIntLE(63, 7, 3);
    return riff([['VP8X', vp8x], ['ANIM', Buffer.alloc(6)], ['ANMF', Buffer.alloc(16)]]);
  } }],
  ['bad_gif', { bucket: M, variants: W960, build: async () => Buffer.from('4749463839610100010080000000000000ffffff21f90401000000002c00000000010001000002024401003b', 'hex') }],
  ['bad_svg', { bucket: M, variants: W960, build: async () => Buffer.from('<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64"><image xlink:href="https://example.invalid/x.png" width="64" height="64"/></svg>', 'utf8') }],
  ['bad_empty', { bucket: M, variants: W960, build: async () => Buffer.alloc(0) }],
  ['bomb_png_header', { bucket: B, variants: W480, build: async () => png({ width: 65535, height: 65535, channels: 4, rows: () => {}, idat: deflateSync(Buffer.alloc(1024)) }) }],
  ['bad_aspect_3200x100', { bucket: M, variants: W960, build: async () => png({ width: 3200, height: 100, channels: 3, rows: (y, row) => row.fill(128) }) }],
  ['bad_jpeg_truncated', { bucket: M, variants: W960, build: async () => { const j = await jpegFile('base_420_900x450.jpg'); return j.subarray(0, Math.floor(j.length * 0.6)); } }],
  ['bad_jpeg_corrupt_entropy', { bucket: M, variants: W960, build: async () => withCorruptEntropy(await jpegFile('base_420_900x450.jpg')) }],
  ['bad_jpeg_cmyk', { bucket: M, variants: W960, build: async () => withFourComponentSof(await jpegFile('base_420_900x450.jpg')) }],
  // ---- EDGE-1: the PNG image-data bound
  ['bomb_idat_tail_256mib', { bucket: B, variants: W480, build: async () => {
    // a valid 640x480 image followed, INSIDE the same zlib stream, by 256 MiB of zeros
    const raw = pngRaw({ width: 640, height: 480, channels: 4, rows: logoRgba(640, 480) });
    return png({ width: 640, height: 480, channels: 4, rows: () => {}, idat: await zlibWithZeroTail(raw, 256) });
  } }],
  ['bad_png_short_idat', { bucket: B, variants: W480, build: async () => {
    const raw = pngRaw({ width: 400, height: 200, channels: 4, rows: logoRgba(400, 200) }); const z = deflateSync(raw, { level: 9 });
    return png({ width: 400, height: 200, channels: 4, rows: () => {}, idat: z.subarray(0, Math.floor(z.length / 2)) });
  } }],
  ['bad_png_junk_after_zlib', { bucket: B, variants: W480, build: async () => {
    const raw = pngRaw({ width: 400, height: 200, channels: 4, rows: logoRgba(400, 200) });
    return png({ width: 400, height: 200, channels: 4, rows: () => {}, idat: Buffer.concat([deflateSync(raw, { level: 9 }), Buffer.from([1, 2, 3, 4, 5, 6, 7, 8])]) });
  } }],
  ['bad_png_trailer_cut', { bucket: B, variants: W480, build: async () => {
    const raw = pngRaw({ width: 400, height: 200, channels: 4, rows: logoRgba(400, 200) }); const z = deflateSync(raw, { level: 9 });
    return png({ width: 400, height: 200, channels: 4, rows: () => {}, idat: z.subarray(0, z.length - 4) });
  } }],
  ['bad_png_wrong_checksum', { bucket: B, variants: W480, build: async () => {
    const raw = pngRaw({ width: 400, height: 200, channels: 4, rows: logoRgba(400, 200) }); const z = Buffer.from(deflateSync(raw, { level: 9 }));
    z[z.length - 1] ^= 0x01;
    return png({ width: 400, height: 200, channels: 4, rows: () => {}, idat: z });
  } }],
  ['bad_png_raw_too_short', { bucket: B, variants: W480, build: async () => {
    // a complete, valid zlib stream of one row fewer than the IHDR implies
    const raw = pngRaw({ width: 400, height: 199, channels: 4, rows: logoRgba(400, 199) });
    return png({ width: 400, height: 200, channels: 4, rows: () => {}, idat: deflateSync(raw, { level: 9 }) });
  } }],
  ...[['zTXt', (z) => Buffer.concat([Buffer.from('Comment\0\0', 'latin1'), z])],
    ['iTXt', (z) => Buffer.concat([Buffer.from('Comment\0\x01\0\0\0', 'latin1'), z])],
    ['iCCP', (z) => Buffer.concat([Buffer.from('bomb profile\0\0', 'latin1'), z]), 'beforePLTE']].map(([type, wrap, pos]) => [
    `bomb_${type.toLowerCase()}_1gib`, { bucket: B, variants: W480, build: async () => {
      const data = wrap(await oneGibOfZeros());
      return png({ width: 700, height: 350, channels: 4, rows: logoRgba(700, 350), extraChunks: [[type, data, ...(pos ? [pos] : [])]] });
    } }]),
  ['plain_700x350', { bucket: B, variants: W480, build: async () => png({ width: 700, height: 350, channels: 4, rows: logoRgba(700, 350) }) }],
  // a PNG whose container and image-data size are valid but one scanline has filter type 9:
  // the PNG decoder throws (decode_failed) and the deriver is poisoned (engine_poison.test.mjs)
  ['bad_png_filter_type', { bucket: B, variants: W480, build: async () => {
    const raw = pngRaw({ width: 600, height: 300, channels: 4, rows: logoRgba(600, 300) }); raw[150 * (600 * 4 + 1)] = 9;
    return png({ width: 600, height: 300, channels: 4, rows: () => {}, idat: deflateSync(raw, { level: 9 }) });
  } }],
]);

const cache = new Map();
/** The bytes of a named fixture (built once per process). */
export async function fixture(name) {
  if (!FIXTURES.has(name)) throw new Error(`unknown fixture ${name}`);
  if (!cache.has(name)) cache.set(name, FIXTURES.get(name).build().then((b) => new Uint8Array(b)));
  return cache.get(name);
}
export const fixtureSpec = (name) => FIXTURES.get(name);
