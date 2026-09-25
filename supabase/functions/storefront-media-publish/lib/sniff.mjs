// STOREFRONT-PUBLISH-001: pre-decode source validation (recipe storefront-media-c4).
// Carried over from recipe c3 (the sealed Option C spike, every table lookup a
// Map / Set, no ordinary-object indexing); the caps are the recipe's (c4: 8 MiP
// and 8192 px per side for every format, lib/recipe.mjs), and c4 refuses a
// 4-component (CMYK / YCCK) JPEG here, before any decode, as unsupported_format.
//
// Pure JavaScript, no image engine. Runs BEFORE any decoder sees the bytes and
// walks the WHOLE container, so a hostile or pathological source is refused on
// its structure alone (a PNG's image data is then bounded by lib/pngbound.mjs):
//   - only PNG, JPEG (SOF0/SOF1/SOF2, 8-bit, 1 or 3 components) and still WebP
//     are accepted, by signature bytes (never by file name or declared MIME type);
//   - animation is refused (APNG acTL/fcTL/fdAT, WebP VP8X animation / ANIM / ANMF);
//   - dimensions, pixel counts, aspect ratio, JPEG scan layout and progressive
//     coefficient memory, and metadata sizes and counts are checked before decoding;
//   - c3: a sequential JPEG must be ONE interleaved scan (libjpeg buffers the whole
//     image for any other layout), JPEG markers outside entropy data are allowlisted,
//     compressed PNG metadata chunks are counted, WebP chunks are allowlisted.

export class SourceRejected extends Error {
  constructor(code, detail) {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.code = code;
  }
}

const u32be = (b, o) => b[o] * 0x1000000 + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
const u16be = (b, o) => (b[o] << 8) | b[o + 1];
const u24le = (b, o) => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
const u32le = (b, o) => b[o] + (b[o + 1] << 8) + (b[o + 2] << 16) + b[o + 3] * 0x1000000;
const ascii = (b, o, n) => String.fromCharCode(...b.subarray(o, o + n));
const isLetters = (s) => /^[A-Za-z]{4}$/.test(s);

// ----------------------------------------------------------------------------- PNG
const PNG_CRITICAL = new Set(['IHDR', 'PLTE', 'IDAT', 'IEND']);
const PNG_ANIMATION = new Set(['acTL', 'fcTL', 'fdAT']);
// Keyed by the IHDR colour-type byte (a number); a Map, so no lookup can reach a prototype property.
const PNG_COLOR_DEPTHS = new Map([[0, [1, 2, 4, 8, 16]], [2, [8, 16]], [3, [1, 2, 4, 8]], [4, [8, 16]], [6, [8, 16]]]);

function sniffPng(b, caps) {
  if (b.length < 8 + 25 + 12) throw new SourceRejected('truncated', 'png header');
  if (u32be(b, 8) !== 13 || ascii(b, 12, 4) !== 'IHDR') throw new SourceRejected('corrupt', 'png IHDR must be first');
  const width = u32be(b, 16);
  const height = u32be(b, 20);
  const bitDepth = b[24], colorType = b[25], compression = b[26], filter = b[27], interlace = b[28];
  if (!PNG_COLOR_DEPTHS.has(colorType) || !PNG_COLOR_DEPTHS.get(colorType).includes(bitDepth)) throw new SourceRejected('corrupt', `png color type ${colorType} / depth ${bitDepth}`);
  if (compression !== 0 || filter !== 0 || interlace > 1) throw new SourceRejected('corrupt', 'png IHDR method fields');
  let o = 8;
  let chunks = 0, ancillary = 0, iccp = 0, compressedText = 0, idatSeen = false, idatEnded = false, plte = false, iend = false;
  while (o < b.length) {
    if (o + 12 > b.length) throw new SourceRejected('truncated', 'png chunk header');
    const len = u32be(b, o);
    const type = ascii(b, o + 4, 4);
    if (len > 0x7fffffff) throw new SourceRejected('corrupt', 'png chunk length');
    if (!isLetters(type)) throw new SourceRejected('corrupt', 'png chunk type');
    if (o + 12 + len > b.length) throw new SourceRejected('truncated', `png chunk ${type}`);
    if (++chunks > caps.pngMaxChunks) throw new SourceRejected('corrupt', 'png chunk count');
    if (PNG_ANIMATION.has(type)) throw new SourceRejected('animated', `apng ${type} chunk`);
    const critical = type.charCodeAt(0) < 97;
    if (critical && !PNG_CRITICAL.has(type)) throw new SourceRejected('unsupported_format', `png critical chunk ${type}`);
    if (type === 'IHDR' && o !== 8) throw new SourceRejected('corrupt', 'png second IHDR');
    if (type === 'PLTE') plte = true;
    if (type === 'IDAT') {
      if (idatEnded) throw new SourceRejected('corrupt', 'png IDAT not contiguous');
      idatSeen = true;
    } else if (idatSeen) {
      idatEnded = true;
    }
    if (!critical) {
      if (++ancillary > caps.pngMaxAncillaryChunks) throw new SourceRejected('metadata_too_large', 'png ancillary chunk count');
      if (len > caps.maxMetadataBytes) throw new SourceRejected('metadata_too_large', `png ${type} ${len} B`);
      // Compressed metadata is inflated by libpng before the recipe strips it: bound the count.
      if (type === 'iCCP' && ++iccp > caps.pngMaxIccp) throw new SourceRejected('metadata_too_large', 'png iCCP count');
      if ((type === 'zTXt' || type === 'iTXt') && ++compressedText > caps.pngMaxCompressedText) throw new SourceRejected('metadata_too_large', 'png zTXt/iTXt count');
    }
    o += 12 + len;
    if (type === 'IEND') { iend = true; break; }
  }
  if (!iend) throw new SourceRejected('truncated', 'png has no IEND');
  if (o !== b.length) throw new SourceRejected('corrupt', 'png bytes after IEND');
  if (!idatSeen) throw new SourceRejected('corrupt', 'png has no IDAT');
  if (colorType === 3 && !plte) throw new SourceRejected('corrupt', 'png palette image without PLTE');
  return { type: 'png', width, height, bitDepth, colorType };
}

// ---------------------------------------------------------------------------- JPEG
const JPEG_ALLOWED_SOF = new Set([0xc0, 0xc1, 0xc2]); // baseline, extended sequential, progressive (Huffman)
const isSofMarker = (m) => m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc;
// Length-bearing markers allowed outside entropy data (besides the SOFs): DHT, SOS, DQT, DRI, APPn, COM.
const isAllowedSegment = (m) => m === 0xc4 || m === 0xda || m === 0xdb || m === 0xdd || (m >= 0xe0 && m <= 0xef) || m === 0xfe;
const isMetadataSegment = (m) => (m >= 0xe0 && m <= 0xef) || m === 0xfe;

function sniffJpeg(b, caps) {
  let o = 2;
  let sof = null;
  let scans = 0;
  let firstScanComponents = 0;
  let metadataBytes = 0;
  let eoi = false;
  while (o < b.length) {
    if (b[o] !== 0xff) throw new SourceRejected('corrupt', `jpeg marker expected at ${o}`);
    while (o < b.length && b[o] === 0xff) o++; // fill bytes
    if (o >= b.length) throw new SourceRejected('truncated', 'jpeg ends in fill bytes');
    const marker = b[o++];
    if (marker === 0xd9) { eoi = true; break; }
    if (marker === 0xd8) throw new SourceRejected('corrupt', 'jpeg second SOI');
    if ((marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) continue; // standalone
    if (marker === 0xdc) throw new SourceRejected('unsupported_format', 'jpeg DNL marker');
    if (marker === 0xcc) throw new SourceRejected('unsupported_format', 'jpeg DAC marker (arithmetic coding)');
    if (!isSofMarker(marker) && !isAllowedSegment(marker)) throw new SourceRejected('corrupt', `jpeg marker 0x${marker.toString(16)} outside entropy data`);
    if (o + 2 > b.length) throw new SourceRejected('truncated', 'jpeg segment length');
    const len = u16be(b, o);
    if (len < 2) throw new SourceRejected('corrupt', 'jpeg segment length');
    if (o + len > b.length) throw new SourceRejected('truncated', `jpeg segment 0x${marker.toString(16)}`);
    if (isMetadataSegment(marker) && (metadataBytes += len - 2) > caps.maxMetadataBytes) throw new SourceRejected('metadata_too_large', `jpeg APPn/COM payload over ${caps.maxMetadataBytes} B`);
    if (isSofMarker(marker)) {
      if (sof) throw new SourceRejected('corrupt', 'jpeg second SOF');
      if (!JPEG_ALLOWED_SOF.has(marker)) throw new SourceRejected('unsupported_format', `jpeg process SOF 0x${marker.toString(16)}`);
      if (len < 8) throw new SourceRejected('corrupt', 'jpeg SOF length');
      const precision = b[o + 2];
      const height = u16be(b, o + 3);
      const width = u16be(b, o + 5);
      const nc = b[o + 7];
      if (precision !== 8) throw new SourceRejected('unsupported_format', `jpeg precision ${precision}`);
      // c4: Gray or YCbCr only; a 4-component (CMYK / YCCK) JPEG, like any other layout, is refused pre-decode
      if (nc !== 1 && nc !== 3) throw new SourceRejected('unsupported_format', nc === 4 ? 'jpeg with 4 components (CMYK/YCCK)' : `jpeg components ${nc}`);
      if (len !== 8 + 3 * nc) throw new SourceRejected('corrupt', 'jpeg SOF component table');
      if (width === 0 || height === 0) throw new SourceRejected('unsupported_format', 'jpeg zero dimension (DNL)');
      const comps = [];
      for (let i = 0; i < nc; i++) {
        const hv = b[o + 9 + 3 * i];
        const h = hv >> 4, v = hv & 15;
        if (h < 1 || h > 4 || v < 1 || v > 4) throw new SourceRejected('corrupt', 'jpeg sampling factors');
        comps.push({ h, v });
      }
      sof = { marker, width, height, components: nc, comps };
    }
    if (marker === 0xda) {
      if (!sof) throw new SourceRejected('corrupt', 'jpeg scan before SOF');
      const ns = len >= 3 ? b[o + 2] : 0;
      if (ns < 1 || ns > 4 || len !== 6 + 2 * ns) throw new SourceRejected('corrupt', 'jpeg SOS header');
      if (scans === 0) firstScanComponents = ns;
    }
    o += len;
    if (marker === 0xda) {
      if (++scans > caps.jpegMaxScans) throw new SourceRejected('too_many_scans', `more than ${caps.jpegMaxScans} scans`);
      // Skip the entropy-coded segment: 0xFF00 is a stuffed byte and 0xFFD0..D7 are
      // restart markers (both data); any other 0xFFxx ends the segment.
      while (o < b.length) {
        if (b[o] !== 0xff) { o++; continue; }
        const n = b[o + 1];
        if (n === 0x00 || (n >= 0xd0 && n <= 0xd7)) { o += 2; continue; }
        if (n === 0xff) { o++; continue; }
        break;
      }
      if (o >= b.length) throw new SourceRejected('truncated', 'jpeg ends inside scan data');
    }
  }
  if (!sof) throw new SourceRejected('corrupt', 'jpeg has no SOF');
  if (!eoi) throw new SourceRejected('truncated', 'jpeg has no EOI');
  if (scans === 0) throw new SourceRejected('corrupt', 'jpeg has no scan');
  const progressive = sof.marker === 0xc2;
  // A sequential JPEG decodes in one pass only as ONE interleaved scan of every component;
  // any other layout makes libjpeg buffer the whole image's coefficients (jdinput.c
  // has_multiple_scans), so it is refused (real encoders emit one interleaved scan).
  if (!progressive && (scans !== 1 || firstScanComponents !== sof.components)) {
    throw new SourceRejected('too_many_scans', `sequential jpeg must be one interleaved scan (${scans} scans, first has ${firstScanComponents} of ${sof.components} components)`);
  }
  // Coefficient buffer (what a progressive decode must hold in memory): every component,
  // in whole 8x8 blocks of its own subsampled plane rounded up to its sampling factors
  // (jdcoefct.c jround_up), 2 bytes per coefficient.
  const hmax = Math.max(...sof.comps.map((c) => c.h));
  const vmax = Math.max(...sof.comps.map((c) => c.v));
  let coefficients = 0;
  for (const c of sof.comps) {
    const bw = Math.ceil(Math.ceil((sof.width * c.h) / hmax) / 8);
    const bh = Math.ceil(Math.ceil((sof.height * c.v) / vmax) / 8);
    coefficients += Math.ceil(bw / c.h) * c.h * Math.ceil(bh / c.v) * c.v * 64;
  }
  if (progressive && coefficients * 2 > caps.jpegMaxProgressiveCoefficientBytes) {
    throw new SourceRejected('too_many_pixels', `progressive coefficient buffer ${coefficients * 2} B`);
  }
  if (progressive && scans * coefficients > caps.jpegMaxProgressiveScanWork) {
    throw new SourceRejected('too_many_scans', `progressive scan work ${scans} x ${coefficients}`);
  }
  // Bytes after EOI (e.g. an appended MPF/gain-map image) are ignored by the decoder
  // and never decoded; they only count toward the bucket byte cap.
  return { type: 'jpeg', width: sof.width, height: sof.height, components: sof.components, sofMarker: sof.marker, progressive, scans, coefficients };
}

// ---------------------------------------------------------------------------- WebP
function parseVp8(b, off, size) {
  if (size < 10) throw new SourceRejected('corrupt', 'webp VP8 frame too short');
  if ((b[off] & 1) !== 0) throw new SourceRejected('corrupt', 'webp VP8 not a keyframe');
  if (b[off + 3] !== 0x9d || b[off + 4] !== 0x01 || b[off + 5] !== 0x2a) throw new SourceRejected('corrupt', 'webp VP8 start code');
  return { width: (b[off + 6] | (b[off + 7] << 8)) & 0x3fff, height: (b[off + 8] | (b[off + 9] << 8)) & 0x3fff, alpha: false };
}
function parseVp8l(b, off, size) {
  if (size < 5) throw new SourceRejected('corrupt', 'webp VP8L frame too short');
  if (b[off] !== 0x2f) throw new SourceRejected('corrupt', 'webp VP8L signature');
  const bits = b[off + 1] + (b[off + 2] << 8) + (b[off + 3] << 16) + b[off + 4] * 0x1000000;
  if ((bits >>> 29) !== 0) throw new SourceRejected('corrupt', 'webp VP8L version');
  return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1, alpha: ((bits >>> 28) & 1) === 1 };
}

const WEBP_EXTENDED_CHUNKS = new Set(['ICCP', 'ALPH', 'VP8 ', 'VP8L', 'EXIF', 'XMP ']); // after VP8X, each at most once

function sniffWebp(b, caps) {
  if (b.length < 20) throw new SourceRejected('truncated', 'webp header');
  const riffSize = u32le(b, 4);
  if (riffSize + 8 > b.length) throw new SourceRejected('truncated', 'webp riff size exceeds data');
  if (riffSize + 8 < b.length) throw new SourceRejected('corrupt', 'webp bytes after the RIFF');
  const chunks = [];
  let o = 12;
  while (o < b.length) {
    if (o + 8 > b.length) throw new SourceRejected('truncated', 'webp chunk header');
    const tag = ascii(b, o, 4);
    const size = u32le(b, o + 4);
    if (o + 8 + size > b.length) throw new SourceRejected('truncated', `webp chunk ${tag}`);
    if (chunks.length >= caps.webpMaxChunks) throw new SourceRejected('corrupt', 'webp chunk count');
    chunks.push({ tag, size, off: o + 8 });
    o += 8 + size + (size & 1);
  }
  if (o !== b.length) throw new SourceRejected('corrupt', 'webp chunk padding');
  if (chunks.length === 0) throw new SourceRejected('corrupt', 'webp has no chunk');
  const first = chunks[0];
  if (first.tag === 'VP8 ' || first.tag === 'VP8L') {
    if (chunks.length !== 1) throw new SourceRejected('corrupt', 'webp simple format with extra chunks');
    const f = first.tag === 'VP8 ' ? parseVp8(b, first.off, first.size) : parseVp8l(b, first.off, first.size);
    return { type: 'webp', width: f.width, height: f.height };
  }
  if (first.tag !== 'VP8X') throw new SourceRejected('corrupt', `webp first chunk ${JSON.stringify(first.tag)}`);
  if (first.size !== 10) throw new SourceRejected('corrupt', 'webp VP8X size');
  const flags = b[first.off];
  if (flags & 0x02) throw new SourceRejected('animated', 'webp VP8X animation flag');
  const width = u24le(b, first.off + 4) + 1;
  const height = u24le(b, first.off + 7) + 1;
  let frame = null, alph = false, vp8l = false;
  const seen = new Set();
  for (const c of chunks.slice(1)) {
    if (c.tag === 'ANIM' || c.tag === 'ANMF') throw new SourceRejected('animated', `webp ${c.tag} chunk`);
    if (!WEBP_EXTENDED_CHUNKS.has(c.tag)) throw new SourceRejected('corrupt', `webp chunk ${JSON.stringify(c.tag)}`);
    if (seen.has(c.tag)) throw new SourceRejected('corrupt', `webp second ${c.tag.trim()} chunk`);
    seen.add(c.tag);
    if (c.tag === 'VP8 ' || c.tag === 'VP8L') {
      vp8l = c.tag === 'VP8L';
      if (frame) throw new SourceRejected('corrupt', 'webp second frame chunk');
      frame = c.tag === 'VP8 ' ? parseVp8(b, c.off, c.size) : parseVp8l(b, c.off, c.size);
      if (c.tag === 'VP8L' && alph) throw new SourceRejected('corrupt', 'webp ALPH with a VP8L frame');
      continue;
    }
    if (c.tag === 'ALPH') {
      if (frame || alph) throw new SourceRejected('corrupt', 'webp ALPH position');
      alph = true;
    }
    if (c.size > caps.maxMetadataBytes && c.tag !== 'ALPH') throw new SourceRejected('metadata_too_large', `webp ${c.tag.trim()} ${c.size} B`);
  }
  if (!frame) throw new SourceRejected('corrupt', 'webp has no frame chunk');
  if (frame.width !== width || frame.height !== height) throw new SourceRejected('corrupt', 'webp canvas and frame sizes differ');
  // The VP8X alpha flag must agree with the alpha actually carried, so the alpha outcome
  // never depends on how a decoder resolves the disagreement.
  if (((flags & 0x10) !== 0) !== (alph || (vp8l && frame.alpha))) throw new SourceRejected('corrupt', 'webp VP8X alpha flag disagrees with the frame');
  return { type: 'webp', width, height };
}

/** Returns {type,width,height,...} or throws SourceRejected. */
export function sniffSource(bytes, caps) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) throw new SourceRejected('empty');
  if (bytes.length > caps.maxInputBytes) throw new SourceRejected('input_too_large', `${bytes.length} > ${caps.maxInputBytes}`);
  let info;
  if (bytes.length >= 8 && bytes[0] === 0x89 && ascii(bytes, 1, 3) === 'PNG' && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) {
    info = sniffPng(bytes, caps);
  } else if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    info = sniffJpeg(bytes, caps);
  } else if (bytes.length >= 12 && ascii(bytes, 0, 4) === 'RIFF' && ascii(bytes, 8, 4) === 'WEBP') {
    info = sniffWebp(bytes, caps);
  } else {
    throw new SourceRejected('unsupported_format');
  }
  const { width, height } = info;
  if (!(width > 0 && height > 0)) throw new SourceRejected('corrupt', 'zero dimension');
  const maxSide = info.type === 'jpeg' ? caps.jpegMaxSide : caps.maxSide;
  const maxPixels = info.type === 'jpeg' ? caps.jpegMaxPixels : caps.maxPixels;
  if (width > maxSide || height > maxSide) throw new SourceRejected('dimensions_too_large', `${width}x${height} > side ${maxSide}`);
  if (width * height > maxPixels) throw new SourceRejected('too_many_pixels', `${width * height} > ${maxPixels}`);
  const long = Math.max(width, height);
  const short = Math.min(width, height);
  if (long > short * caps.maxAspect) throw new SourceRejected('aspect_ratio', `${width}x${height} exceeds ${caps.maxAspect}:1`);
  return info;
}

/** RIFF chunk list of a WebP, for output validation. */
export function webpChunks(b) {
  if (ascii(b, 0, 4) !== 'RIFF' || ascii(b, 8, 4) !== 'WEBP') throw new Error('not a webp');
  if (u32le(b, 4) + 8 !== b.length) throw new Error('riff size mismatch');
  const out = [];
  let o = 12;
  while (o + 8 <= b.length) {
    const tag = ascii(b, o, 4);
    const size = u32le(b, o + 4);
    out.push({ tag, size, offset: o });
    o += 8 + size + (size & 1);
  }
  if (o !== b.length) throw new Error('trailing bytes after last chunk');
  return out;
}

/** Canvas size, alpha flag and chunk list of a still WebP (output self-check). */
export function webpInfo(b) {
  const chunks = webpChunks(b);
  const first = chunks[0];
  if (first.tag === 'VP8X') {
    const flags = b[20];
    return { chunks, width: u24le(b, 24) + 1, height: u24le(b, 27) + 1, alphaFlag: (flags & 0x10) !== 0, animated: (flags & 0x02) !== 0, metadataFlags: { icc: (flags & 0x20) !== 0, exif: (flags & 0x08) !== 0, xmp: (flags & 0x04) !== 0 } };
  }
  const f = first.tag === 'VP8 ' ? parseVp8(b, first.offset + 8, first.size) : parseVp8l(b, first.offset + 8, first.size);
  return { chunks, width: f.width, height: f.height, alphaFlag: f.alpha, animated: false, metadataFlags: { icc: false, exif: false, xmp: false } };
}
