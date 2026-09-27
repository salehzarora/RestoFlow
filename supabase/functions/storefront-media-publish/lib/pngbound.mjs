// STOREFRONT-PUBLISH-001 recipe `storefront-media-c4`: PNG pre-decode sanitation
// (closes review finding EDGE-1). Runs AFTER sniffSource accepted the container
// and BEFORE the PNG decoder sees a byte:
//
//   - keeps only the chunks the pixels depend on (IHDR, PLTE, tRNS, IDAT..., IEND),
//     so no ancillary chunk (iCCP / zTXt / iTXt ... however far it would inflate)
//     ever reaches the decoder;
//   - inflates the concatenated IDAT stream ONCE with the platform inflater,
//     bounded by the EXACT filtered-scanline size the IHDR implies (Adam7-aware):
//     a stream that produces more (a compressible tail / decompression bomb) is
//     cancelled as soon as it passes the bound (the compressed data is fed in
//     PIECE-byte steps, so no single step can expand past ~4 MiB on any
//     runtime), and one that produces less
//     (truncated) is refused, all before the decoder runs;
//   - checks the zlib wrapper itself (header, and the Adler-32 trailer against
//     the inflated bytes). The platform inflaters disagree at the edges: Node 22
//     ignores bytes after the end of the stream, Node 24 and the edge runtime
//     refuse them, and the edge runtime accepts a stream whose trailer is cut
//     (the PNG decoder ignores checksums). The trailer check makes the vector
//     outcomes identical on every runtime (junk after the stream, a truncated
//     trailer, a wrong checksum: all `corrupt`). Residual, documented: a crafted
//     stream + junk whose LAST FOUR bytes equal the Adler-32 of the image data is
//     refused by Node 24 / the edge runtime but reaches the decoder on Node 22.
//
// This is output-neutral: the decoder receives the same critical chunks in the
// same order with their original CRCs, so every derivative is unchanged.

export class PngRejected extends Error {
  /** @param {string} code public refusal code  @param {string} detail  @param {number|null} produced */
  constructor(code, detail, produced = null) {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.code = code;
    this.detail = detail;
    this.produced = produced; // inflated bytes when the stream was stopped (tests prove the bound)
  }
}

const u32be = (b, o) => b[o] * 0x1000000 + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
const ascii = (b, o, n) => String.fromCharCode(...b.subarray(o, o + n));
const KEEP = new Set(['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND']);
// Samples per pixel by IHDR colour type (a Map: no prototype lookup can resolve).
const CHANNELS = new Map([[0, 1], [2, 3], [3, 1], [4, 2], [6, 4]]);
const ADAM7 = Object.freeze([[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]);
// Compressed bytes per inflate step: bounds one step's output to ~4 MiB.
export const PIECE = 4096;

/** Exact filtered-scanline byte count of a PNG image (Adam7-aware). */
export function pngRawSize(width, height, bitDepth, colorType, interlace) {
  const bpp = CHANNELS.get(colorType) * bitDepth; // bits per pixel
  const rowBytes = (w) => (w === 0 ? 0 : 1 + Math.ceil((w * bpp) / 8));
  if (!interlace) return height * rowBytes(width);
  let total = 0;
  for (const [x0, y0, dx, dy] of ADAM7) {
    const pw = width > x0 ? Math.ceil((width - x0) / dx) : 0;
    const ph = height > y0 ? Math.ceil((height - y0) / dy) : 0;
    if (pw && ph) total += ph * rowBytes(pw);
  }
  return total;
}

/** Adler-32 over successive chunks (NMAX = 5552 keeps the sums below 2^32). */
function adlerUpdate(state, buf) {
  let a = state.a, b = state.b;
  let i = 0;
  const n = buf.length;
  while (i < n) {
    const end = Math.min(i + 5552, n);
    for (; i < end; i++) { a += buf[i]; b += a; }
    a %= 65521; b %= 65521;
  }
  state.a = a; state.b = b;
}

/**
 * Inflates a zlib stream given as parts, refusing (PngRejected 'corrupt') unless it
 * produces EXACTLY `expected` bytes and carries a valid header and Adler-32 trailer.
 * Never holds the inflated bytes: they are counted and checksummed, then dropped.
 */
export async function inflateExact(parts, expected) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  if (total < 6) throw new PngRejected('corrupt', 'png image data is too short for a zlib stream');
  const byteAt = (k) => { for (const p of parts) { if (k < p.length) return p[k]; k -= p.length; } return 0; };
  const cmf = byteAt(0), flg = byteAt(1);
  if ((cmf & 0x0f) !== 8 || (cmf >> 4) > 7 || ((cmf << 8) | flg) % 31 !== 0 || (flg & 0x20) !== 0) {
    throw new PngRejected('corrupt', 'png image data has an invalid zlib header');
  }
  const trailer = byteAt(total - 4) * 0x1000000 + (byteAt(total - 3) << 16) + (byteAt(total - 2) << 8) + byteAt(total - 1);
  const ds = new DecompressionStream('deflate');
  const writer = ds.writable.getWriter();
  const reader = ds.readable.getReader();
  const feed = (async () => {
    try {
      // Fed in small pieces: one inflate step can then produce at most ~PIECE x 1032 bytes
      // (deflate's maximum expansion), so the bound is enforced step by step on every
      // runtime. (The edge runtime inflates each written chunk completely before the
      // reader sees any of it: a single 260 KB write of a 256 MiB tail hit the 256 MB
      // worker memory limit there, measured in the Q031 parity run.)
      for (const part of parts) for (let o = 0; o < part.length; o += PIECE) await writer.write(part.subarray(o, o + PIECE));
      await writer.close();
    } catch { /* reader cancelled or stream error */ }
  })();
  const adler = { a: 1, b: 0 };
  let produced = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      produced += value.length;
      if (produced > expected) {
        await reader.cancel().catch(() => {});
        throw new PngRejected('corrupt', `png image data inflates beyond the ${expected} B the header implies`, produced);
      }
      adlerUpdate(adler, value);
    }
  } catch (e) {
    if (e instanceof PngRejected) throw e;
    throw new PngRejected('corrupt', 'png image data is not a valid zlib stream', produced);
  } finally {
    await feed;
  }
  if (produced !== expected) throw new PngRejected('corrupt', `png image data inflates to ${produced} of ${expected} B`, produced);
  if (((adler.b * 65536) + adler.a) !== trailer) throw new PngRejected('corrupt', 'png image data does not end with its checksum', produced);
  return produced;
}

/** Returns the sanitized PNG bytes (only KEEP chunks, original CRCs), or throws PngRejected. */
export async function sanitizePng(b) {
  const width = u32be(b, 16), height = u32be(b, 20);
  const bitDepth = b[24], colorType = b[25], interlace = b[28];
  const expected = pngRawSize(width, height, bitDepth, colorType, interlace);
  const keep = [b.subarray(0, 8)];
  const idat = [];
  let o = 8;
  while (o < b.length) {
    const len = u32be(b, o);
    const type = ascii(b, o + 4, 4);
    if (KEEP.has(type)) keep.push(b.subarray(o, o + 12 + len));
    if (type === 'IDAT') idat.push(b.subarray(o + 8, o + 8 + len));
    o += 12 + len;
    if (type === 'IEND') break;
  }
  await inflateExact(idat, expected);
  const out = new Uint8Array(keep.reduce((n, p) => n + p.length, 0));
  let w = 0;
  for (const p of keep) { out.set(p, w); w += p.length; }
  return out;
}
