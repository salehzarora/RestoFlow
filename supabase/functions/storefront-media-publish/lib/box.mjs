// STOREFRONT-PUBLISH-001 recipe `storefront-media-c4`: the exact integer box
// pre-reduction (carried over from the Q031 spike unchanged).
//
// Before the triangle resize, a large source is reduced by an integer factor
// k >= 2 (k = floor(min(srcW / resizeW, srcH / resizeH)), chosen in recipe.mjs)
// with an alpha-weighted (premultiplied) mean over each k x k block. Integer
// arithmetic only, round half up, so the result is identical on every runtime;
// fully transparent blocks keep colour 0. The output is ceil(w/k) x ceil(h/k);
// edge blocks average only the pixels they cover. Sums fit Uint32: at most
// k*k*255*255 per channel with k <= 17 (8192 / 480).

/** Reduces an RGBA raster (w x h) by the integer factor k. Returns { data, width, height }. */
export function boxReduce(src, w, h, k) {
  const W = Math.ceil(w / k), H = Math.ceil(h / k);
  const out = new Uint8Array(W * H * 4);
  const sA = new Uint32Array(W), sR = new Uint32Array(W), sG = new Uint32Array(W), sB = new Uint32Array(W), cnt = new Uint32Array(W);
  for (let by = 0; by < H; by++) {
    sA.fill(0); sR.fill(0); sG.fill(0); sB.fill(0); cnt.fill(0);
    const y1 = Math.min(h, (by + 1) * k);
    for (let y = by * k; y < y1; y++) {
      let p = y * w * 4;
      for (let x = 0; x < w; x++, p += 4) {
        const bx = (x / k) | 0;
        const a = src[p + 3];
        sA[bx] += a; sR[bx] += src[p] * a; sG[bx] += src[p + 1] * a; sB[bx] += src[p + 2] * a; cnt[bx]++;
      }
    }
    let q = by * W * 4;
    for (let bx = 0; bx < W; bx++, q += 4) {
      const n = cnt[bx], a = sA[bx];
      out[q + 3] = Math.floor((2 * a + n) / (2 * n));
      if (a > 0) {
        out[q] = Math.floor((2 * sR[bx] + a) / (2 * a));
        out[q + 1] = Math.floor((2 * sG[bx] + a) / (2 * a));
        out[q + 2] = Math.floor((2 * sB[bx] + a) / (2 * a));
      }
    }
  }
  return { data: out, width: W, height: H };
}
