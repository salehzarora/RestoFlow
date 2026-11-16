// BIZBOT-STOREFRONT-WELCOME-VIDEO-PUBLISH-001. Bounded ISO-BMFF/AVC validation.
// This does not transcode, strip metadata, or claim a full video/audio decode.
export const WELCOME_VIDEO_LIMITS = Object.freeze({
  bytes: 20 * 1024 * 1024, durationMs: 30000, width: 1920, height: 1080,
  boxes: 2048, samples: 7200, nals: 100000,
});
export class WelcomeVideoRejected extends Error {
  constructor(code) { super(code); this.name = 'WelcomeVideoRejected'; this.code = code; }
}
const reject = (code = 'invalid_mp4') => { throw new WelcomeVideoRejected(code); };
const text = (b, p, n) => String.fromCharCode(...b.subarray(p, p + n));

function bits(bytes) {
  let at = 0;
  const read = (n) => {
    if (!Number.isInteger(n) || n < 0 || n > 32 || at + n > bytes.length * 8) reject();
    let v = 0;
    for (let i = 0; i < n; i++, at++) v = v * 2 + ((bytes[at >> 3] >> (7 - (at & 7))) & 1);
    return v;
  };
  const ue = () => { let zeros = 0; while (read(1) === 0) { if (++zeros > 24) reject(); } return 2 ** zeros - 1 + read(zeros); };
  return { read, ue, se: () => { const v = ue(); return v & 1 ? (v + 1) / 2 : -v / 2; } };
}
function rbsp(nal, limit = 65535) {
  if (nal.length < 2 || nal[0] & 0x80) reject();
  const out = [];
  for (let i = 1, zeros = 0; i < nal.length && out.length < limit; i++) {
    const v = nal[i];
    if (zeros >= 2 && v === 3) { if (i + 1 >= nal.length || nal[i + 1] > 3) reject(); zeros = 0; continue; }
    if (zeros >= 2 && v < 3) reject();
    out.push(v); zeros = v === 0 ? zeros + 1 : 0;
  }
  return Uint8Array.from(out);
}
function spsSize(nal) {
  if ((nal[0] & 31) !== 7 || nal.length > 65535) reject();
  const b = bits(rbsp(nal)), profile = b.read(8); b.read(8); const level = b.read(8), id = b.ue();
  if (![66, 77, 88, 100].includes(profile) || level > 42 || id > 31) reject('unsupported_video_codec');
  let chroma = 1;
  if (profile === 100) {
    chroma = b.ue();
    if (chroma !== 1 || b.ue() !== 0 || b.ue() !== 0 || b.read(1) !== 0) reject('unsupported_video_codec');
    if (b.read(1)) {
      for (let i = 0; i < 8; i++) if (b.read(1)) {
        let last = 8, next = 8;
        for (let j = 0; j < (i < 6 ? 16 : 64); j++) {
          if (next) next = (last + b.se() + 256) % 256;
          last = next || last;
        }
      }
    }
  }
  if (b.ue() > 12) reject();
  const order = b.ue();
  if (order === 0) { if (b.ue() > 12) reject(); }
  else if (order === 1) { b.read(1); b.se(); b.se(); const n = b.ue(); if (n > 255) reject(); for (let i = 0; i < n; i++) b.se(); }
  else if (order !== 2) reject();
  if (b.ue() > 16) reject(); b.read(1);
  const macroWidth = b.ue() + 1, mapHeight = b.ue() + 1, frameOnly = b.read(1);
  if (!frameOnly) reject('unsupported_video_layout');
  b.read(1);
  let left = 0, right = 0, top = 0, bottom = 0;
  if (b.read(1)) { left = b.ue(); right = b.ue(); top = b.ue(); bottom = b.ue(); }
  if (b.read(1) && b.read(1)) {
    const aspect = b.read(8);
    if (aspect === 255) { const w = b.read(16), h = b.read(16); if (!w || w !== h) reject('unsupported_video_layout'); }
    else if (aspect !== 0 && aspect !== 1) reject('unsupported_video_layout');
  }
  const width = macroWidth * 16 - (left + right) * 2, height = mapHeight * 16 - (top + bottom) * 2;
  if (width < 1 || height < 1 || macroWidth > 512 || mapHeight > 512) reject();
  return { width, height, id, profile, level, macroblocks: macroWidth * mapHeight };
}

/** Accept one self-contained, non-fragmented H.264 track and optional AAC-LC audio. */
export function validateWelcomeMp4(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 32) reject();
  if (bytes.length > WELCOME_VIDEO_LIMITS.bytes) reject('input_too_large');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let boxCount = 0, nalCount = 0;
  const ranges = [];
  const u16 = p => { if (p < 0 || p + 2 > bytes.length) reject(); return view.getUint16(p); };
  const u32 = p => { if (p < 0 || p + 4 > bytes.length) reject(); return view.getUint32(p); };
  const u64 = p => { if (p < 0 || p + 8 > bytes.length) reject(); const n = view.getBigUint64(p); if (n > BigInt(Number.MAX_SAFE_INTEGER)) reject(); return Number(n); };
  const boxes = (start, end, depth = 0) => {
    if (depth > 8 || start < 0 || end > bytes.length || start > end) reject();
    const result = [];
    for (let p = start; p < end;) {
      if (end - p < 8 || ++boxCount > WELCOME_VIDEO_LIMITS.boxes) reject();
      let n = u32(p), header = 8;
      const type = text(bytes, p + 4, 4);
      if (n === 1) { if (end - p < 16) reject(); n = u64(p + 8); header = 16; }
      if (n === 0) { if (type !== 'mdat' || depth !== 0) reject(); n = end - p; }
      if (n < header || n > end - p) reject();
      result.push({ type, p: p + header, end: p + n, size: n - header }); p += n;
    }
    return result;
  };
  const one = (list, type, required = true) => {
    const found = list.filter(b => b.type === type);
    if (found.length > 1 || (required && !found.length)) reject(); return found[0];
  };
  const full = (b, versions = [0]) => { if (b.size < 4 || !versions.includes(bytes[b.p]) || bytes[b.p + 1] || bytes[b.p + 2] || bytes[b.p + 3]) reject(); return bytes[b.p]; };
  const timed = b => {
    const v = full(b, [0, 1]), scaleAt = b.p + (v ? 20 : 12), durationAt = scaleAt + 4;
    if (b.size !== (b.type === 'mvhd' ? (v ? 112 : 100) : (v ? 36 : 24))) reject();
    const scale = u32(scaleAt), duration = v ? u64(durationAt) : u32(durationAt);
    if (!scale || scale > 1000000000 || !duration) reject();
    const ms = Math.ceil(duration / scale * 1000); if (ms > WELCOME_VIDEO_LIMITS.durationMs) reject('duration_too_long');
    return { scale, duration, ms };
  };
  const top = boxes(0, bytes.length);
  if (top.some(b => !['ftyp', 'moov', 'mdat', 'free', 'wide', 'skip'].includes(b.type))) reject('unsupported_video_layout');
  const ftyp = one(top, 'ftyp'), moov = one(top, 'moov'), mdat = one(top, 'mdat');
  if (ftyp.size < 8 || ftyp.size > 256 || ftyp.size % 4 || !mdat.size) reject();
  const brands = [text(bytes, ftyp.p, 4)];
  for (let p = ftyp.p + 8; p < ftyp.end; p += 4) brands.push(text(bytes, p, 4));
  if (brands[0] === 'qt  ' || !brands.some(v => ['isom', 'iso2', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1'].includes(v))) reject('unsupported_video_codec');
  const movie = boxes(moov.p, moov.end, 1);
  if (movie.some(b => ['mvex', 'cmov'].includes(b.type))) reject('unsupported_video_layout');
  const movieTime = timed(one(movie, 'mvhd'));
  const tracks = movie.filter(b => b.type === 'trak'); if (tracks.length < 1 || tracks.length > 2) reject('unsupported_video_layout');
  let video = null, audio = null, durationMs = movieTime.ms;
  const trackIds = new Set();

  for (const track of tracks) {
    const t = boxes(track.p, track.end, 2), tkhd = one(t, 'tkhd'), mdia = one(t, 'mdia');
    if (tkhd.size < 84 || ![0, 1].includes(bytes[tkhd.p]) || !(bytes[tkhd.p + 3] & 1)) reject();
    const tv = bytes[tkhd.p], matrixAt = tkhd.p + (tv ? 52 : 40), dimensionAt = tkhd.p + (tv ? 88 : 76);
    if (tkhd.size !== (tv ? 96 : 84)) reject();
    const trackId = u32(tkhd.p + (tv ? 20 : 12));
    if (!trackId || trackIds.has(trackId)) reject(); trackIds.add(trackId);
    const matrix = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824];
    if (matrix.some((v, i) => u32(matrixAt + i * 4) !== v)) reject('unsupported_video_layout');
    const tkWidth = u32(dimensionAt) / 65536, tkHeight = u32(dimensionAt + 4) / 65536;
    const tkDuration = tv ? u64(tkhd.p + 28) : u32(tkhd.p + 20);
    const tkMs = Math.ceil(tkDuration / movieTime.scale * 1000);
    if (!tkDuration) reject(); if (tkMs > WELCOME_VIDEO_LIMITS.durationMs) reject('duration_too_long');
    durationMs = Math.max(durationMs, tkMs);
    const m = boxes(mdia.p, mdia.end, 3), trackTime = timed(one(m, 'mdhd')), handler = one(m, 'hdlr');
    full(handler); if (handler.size < 24) reject();
    const kind = text(bytes, handler.p + 8, 4);
    if (!['vide', 'soun'].includes(kind) || (kind === 'vide' ? video !== null : audio !== null)) reject('unsupported_video_layout');
    const minf = one(m, 'minf'), info = boxes(minf.p, minf.end, 4), dinf = one(info, 'dinf'), stbl = one(info, 'stbl');
    const mediaHeader = one(info, kind === 'vide' ? 'vmhd' : 'smhd');
    if (mediaHeader.size !== (kind === 'vide' ? 12 : 8) || u32(mediaHeader.p) !== (kind === 'vide' ? 1 : 0)) reject();
    const dref = one(boxes(dinf.p, dinf.end, 5), 'dref'); full(dref);
    if (dref.size < 8 || u32(dref.p + 4) !== 1) reject('unsupported_video_layout');
    const references = boxes(dref.p + 8, dref.end, 6);
    if (references.length !== 1 || references[0].type !== 'url ' || references[0].size !== 4 || u32(references[0].p) !== 1) reject('unsupported_video_layout');
    const table = boxes(stbl.p, stbl.end, 5), stsd = one(table, 'stsd'); full(stsd);
    if (stsd.size < 8 || u32(stsd.p + 4) !== 1) reject('unsupported_video_codec');
    const entries = boxes(stsd.p + 8, stsd.end, 6); if (entries.length !== 1) reject();
    const entry = entries[0]; if (entry.size < 8 || u16(entry.p + 6) !== 1) reject();
    let avc = null;
    if (kind === 'vide') {
      if (entry.type !== 'avc1' || entry.size < 78) reject('unsupported_video_codec');
      const width = u16(entry.p + 24), height = u16(entry.p + 26);
      if (width < 1 || height < 1 || width > WELCOME_VIDEO_LIMITS.width || height > WELCOME_VIDEO_LIMITS.height) reject('dimensions_exceeded');
      if (width !== tkWidth || height !== tkHeight) reject('unsupported_video_layout');
      const codecBoxes = boxes(entry.p + 78, entry.end, 7), avcC = one(codecBoxes, 'avcC'), aspect = one(codecBoxes, 'pasp', false);
      if (codecBoxes.some(b => !['avcC', 'pasp', 'btrt', 'colr'].includes(b.type))) reject('unsupported_video_layout');
      if (aspect && (aspect.size !== 8 || !u32(aspect.p) || u32(aspect.p) !== u32(aspect.p + 4))) reject('unsupported_video_layout');
      if (avcC.size < 11 || avcC.size > 131100 || bytes[avcC.p] !== 1 || (bytes[avcC.p + 4] & 252) !== 252 || (bytes[avcC.p + 5] & 224) !== 224) reject();
      const nalBytes = (bytes[avcC.p + 4] & 3) + 1;
      if (nalBytes === 3 || (bytes[avcC.p + 5] & 31) !== 1) reject('unsupported_video_codec');
      let at = avcC.p + 6;
      const getNal = () => { const length = u16(at); at += 2; if (length < 2 || length > avcC.end - at) reject(); const v = bytes.subarray(at, at + length); at += length; return v; };
      const sps = getNal(); if (at >= avcC.end || bytes[at++] !== 1) reject('unsupported_video_codec');
      const pps = getNal(), parsed = spsSize(sps), pb = bits(rbsp(pps));
      if ((pps[0] & 31) !== 8) reject(); const ppsId = pb.ue(); if (ppsId > 255 || pb.ue() !== parsed.id) reject();
      if (parsed.width !== width || parsed.height !== height || parsed.profile !== bytes[avcC.p + 1] || parsed.level !== bytes[avcC.p + 3]) reject();
      if (at !== avcC.end) {
        if (parsed.profile !== 100 || avcC.end - at !== 4 || bytes[at] !== 253 || bytes[at + 1] !== 248 || bytes[at + 2] !== 248 || bytes[at + 3] !== 0) reject('unsupported_video_codec');
      }
      avc = { nalBytes, sps, pps, ppsId, macroblocks: parsed.macroblocks }; video = { width, height };
    } else {
      if (entry.type !== 'mp4a' || entry.size < 28 || tkWidth !== 0 || tkHeight !== 0 || u16(entry.p + 8) !== 0) reject('unsupported_audio_codec');
      const esds = one(boxes(entry.p + 28, entry.end, 7), 'esds'); full(esds);
      const descriptor = (p, end) => {
        if (p >= end) reject(); const tag = bytes[p++]; let size = 0, n = 0, x;
        do { if (p >= end || ++n > 4) reject(); x = bytes[p++]; size = size * 128 + (x & 127); } while (x & 128);
        if (size > end - p) reject(); return { tag, p, end: p + size };
      };
      const es = descriptor(esds.p + 4, esds.end);
      if (es.tag !== 3 || es.end !== esds.end || es.end - es.p < 3 || bytes[es.p + 2] !== 0) reject('unsupported_audio_codec');
      const config = descriptor(es.p + 3, es.end);
      if (config.tag !== 4 || config.end - config.p < 13 || bytes[config.p] !== 64 || (bytes[config.p + 1] >> 2) !== 5) reject('unsupported_audio_codec');
      const sl = descriptor(config.end, es.end);
      if (sl.tag !== 6 || sl.end !== es.end || sl.end - sl.p !== 1 || bytes[sl.p] !== 2) reject('unsupported_audio_codec');
      const specific = descriptor(config.p + 13, config.end);
      if (specific.tag !== 5 || specific.end !== config.end || specific.end - specific.p < 2 || specific.end - specific.p > 5) reject('unsupported_audio_codec');
      const ab = bits(bytes.subarray(specific.p, specific.end));
      if (ab.read(5) !== 2) reject('unsupported_audio_codec');
      const sampleRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];
      const rateIndex = ab.read(4), channels = ab.read(4);
      if (rateIndex >= sampleRates.length || ![1, 2].includes(channels) || u16(entry.p + 16) !== channels || u32(entry.p + 24) / 65536 !== sampleRates[rateIndex]) reject('unsupported_audio_codec');
      if (ab.read(1) || ab.read(1) || ab.read(1)) reject('unsupported_audio_codec');
      audio = { channels };
    }

    const stsz = one(table, 'stsz'); full(stsz);
    if (stsz.size < 12) reject(); const fixed = u32(stsz.p + 4), count = u32(stsz.p + 8);
    if (!count || count > WELCOME_VIDEO_LIMITS.samples || stsz.size !== 12 + (fixed ? 0 : count * 4)) reject('unsupported_video_layout');
    const sizes = Array.from({ length: count }, (_, i) => fixed || u32(stsz.p + 12 + i * 4));
    if (sizes.some(n => !n || n > WELCOME_VIDEO_LIMITS.bytes) || sizes.reduce((n, v) => n + v, 0) > mdat.size) reject();
    const stts = one(table, 'stts'); full(stts);
    if (stts.size < 8) reject(); const runs = u32(stts.p + 4);
    if (!runs || runs > count || stts.size !== 8 + runs * 8) reject();
    const durations = []; let duration = 0;
    for (let i = 0; i < runs; i++) {
      const n = u32(stts.p + 8 + i * 8), delta = u32(stts.p + 12 + i * 8);
      if (!n || !delta || n > count - durations.length) reject();
      duration += n * delta; if (duration / trackTime.scale * 1000 > WELCOME_VIDEO_LIMITS.durationMs) reject('duration_too_long');
      for (let j = 0; j < n; j++) durations.push(delta);
    }
    if (durations.length !== count || duration !== trackTime.duration) reject();
    const ctts = one(table, 'ctts', false), offsets = Array(count).fill(0);
    if (ctts) {
      const version = full(ctts, [0, 1]); if (ctts.size < 8) reject(); const n = u32(ctts.p + 4);
      if (!n || n > count || ctts.size !== 8 + n * 8) reject(); let sample = 0;
      for (let i = 0; i < n; i++) {
        const run = u32(ctts.p + 8 + i * 8), offset = version ? view.getInt32(ctts.p + 12 + i * 8) : u32(ctts.p + 12 + i * 8);
        if (!run || run > count - sample || Math.abs(offset) / trackTime.scale * 1000 > WELCOME_VIDEO_LIMITS.durationMs) reject();
        for (let j = 0; j < run; j++) offsets[sample++] = offset;
      }
      if (sample !== count) reject();
    }
    let decodeTime = 0, first = Infinity, last = -Infinity;
    for (let i = 0; i < count; i++) { first = Math.min(first, decodeTime + offsets[i]); last = Math.max(last, decodeTime + offsets[i] + durations[i]); decodeTime += durations[i]; }
    const sampleMs = Math.ceil((last - first) / trackTime.scale * 1000);
    if (sampleMs > WELCOME_VIDEO_LIMITS.durationMs) reject('duration_too_long');
    durationMs = Math.max(durationMs, trackTime.ms, sampleMs);
    const co = one(table, 'stco', false), co64 = one(table, 'co64', false);
    if (!!co === !!co64) reject(); const chunkBox = co || co64; full(chunkBox);
    if (chunkBox.size < 8) reject(); const chunkCount = u32(chunkBox.p + 4), stride = co ? 4 : 8;
    if (!chunkCount || chunkCount > count || chunkBox.size !== 8 + chunkCount * stride) reject();
    const stsc = one(table, 'stsc'); full(stsc); if (stsc.size < 8) reject(); const mapCount = u32(stsc.p + 4);
    if (!mapCount || mapCount > chunkCount || stsc.size !== 8 + mapCount * 12) reject();
    const chunks = [];
    for (let i = 0; i < mapCount; i++) {
      const base = stsc.p + 8 + i * 12, from = u32(base), perChunk = u32(base + 4);
      if ((i === 0 ? from !== 1 : from <= chunks[i - 1].from) || from > chunkCount || !perChunk || perChunk > count || u32(base + 8) !== 1) reject();
      chunks.push({ from, perChunk });
    }
    const stss = one(table, 'stss', false), sync = new Set();
    if (stss) {
      full(stss); if (stss.size < 8 || u32(stss.p + 4) > count || stss.size !== 8 + u32(stss.p + 4) * 4) reject(); let previous = 0;
      for (let i = 0; i < u32(stss.p + 4); i++) { const n = u32(stss.p + 8 + i * 4); if (n <= previous || n > count) reject(); sync.add(n); previous = n; }
    } else for (let i = 1; i <= count; i++) sync.add(i);
    const sdtp = one(table, 'sdtp', false); if (sdtp) { full(sdtp); if (sdtp.size !== 4 + count) reject(); }
    let sample = 0, map = 0;
    for (let c = 1; c <= chunkCount; c++) {
      if (map + 1 < chunks.length && c >= chunks[map + 1].from) map++;
      let at = co ? u32(chunkBox.p + 8 + (c - 1) * stride) : u64(chunkBox.p + 8 + (c - 1) * stride);
      for (let i = 0; i < chunks[map].perChunk; i++, sample++) {
        if (sample >= count) reject(); const end = at + sizes[sample];
        if (at < mdat.p || end > mdat.end) reject(); ranges.push([at, end]);
        if (avc) {
          let p = at, vcl = false, idr = false;
          while (p < end) {
            if (++nalCount > WELCOME_VIDEO_LIMITS.nals || end - p < avc.nalBytes) reject(); let n = 0;
            for (let j = 0; j < avc.nalBytes; j++) n = n * 256 + bytes[p++];
            if (n < 2 || n > end - p || bytes[p] & 128) reject();
            const nal = bytes.subarray(p, p + n), type = nal[0] & 31;
            if (type < 1 || type > 12 || [2, 3, 4].includes(type)) reject('unsupported_video_codec');
            if (type === 1 || type === 5) {
              // Only bounded slice-header bits are needed; never expand an entire
              // attacker-sized VCL payload into a JavaScript number array.
              const slice = bits(rbsp(nal, 32)), mb = slice.ue(), sliceType = slice.ue(), pps = slice.ue();
              if (mb >= avc.macroblocks || sliceType > 9 || pps !== avc.ppsId) reject();
              vcl = true; if (type === 5 && mb === 0) idr = true;
            }
            if (type === 7 || type === 8) { const expected = type === 7 ? avc.sps : avc.pps; if (nal.length !== expected.length || nal.some((v, j) => v !== expected[j])) reject('unsupported_video_codec'); }
            p += n;
          }
          if (!vcl || (sync.has(sample + 1) && !idr) || (sample === 0 && !idr)) reject();
        }
        at = end;
      }
    }
    if (sample !== count) reject();
    // Edit lists may trim/shift normal MP4 playback, never extend it or change rate.
    const edts = one(t, 'edts', false);
    if (edts) {
      const elst = one(boxes(edts.p, edts.end, 3), 'elst'), version = full(elst, [0, 1]);
      if (elst.size < 8) reject(); const n = u32(elst.p + 4), stride = version ? 20 : 12;
      if (!n || n > 4 || elst.size !== 8 + n * stride) reject(); let sum = 0;
      for (let i = 0; i < n; i++) {
        const at = elst.p + 8 + i * stride, length = version ? u64(at) : u32(at), mediaTime = version ? Number(view.getBigInt64(at + 8)) : view.getInt32(at + 4), rateAt = at + (version ? 16 : 8);
        if (!Number.isSafeInteger(mediaTime) || mediaTime < -1 || mediaTime > trackTime.duration || u32(rateAt) !== 65536) reject('unsupported_video_layout'); sum += length;
      }
      const editMs = Math.ceil(sum / movieTime.scale * 1000);
      if (editMs > WELCOME_VIDEO_LIMITS.durationMs) reject('duration_too_long'); durationMs = Math.max(durationMs, editMs);
    }
  }
  if (!video) reject('unsupported_video_codec');
  ranges.sort((a, b) => a[0] - b[0]); let end = mdat.p;
  for (const range of ranges) { if (range[0] !== end) reject(); end = range[1]; }
  if (end !== mdat.end) reject();
  return Object.freeze({ width: video.width, height: video.height, durationMs, byteLength: bytes.length, mimeType: 'video/mp4', audioTracks: audio ? 1 : 0 });
}
