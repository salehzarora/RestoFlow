// storefront-background-b1: resize the bounded RGBA raster after integer box reduction.
// Fixed-point pixel-center sampling with clamped edges. Preserve premultiplied color
// across transparency; zero-alpha output pixels retain zero RGB.
export const BACKGROUND_RECIPE = Object.freeze({ id: 'storefront-background-b1', variant: 'bg2560', longEdge: 2560 });

function samples(sourceExtent, outputExtent, stride) {
  const first = new Uint32Array(outputExtent);
  const second = new Uint32Array(outputExtent);
  const weight = new Uint16Array(outputExtent);
  for (let position = 0; position < outputExtent; position++) {
    // (position + .5) * sourceExtent / outputExtent - .5, quantized to 1/256.
    const coordinate = Math.round(((2 * position + 1) * sourceExtent - outputExtent) * 128 / outputExtent);
    const fixed = Math.min((sourceExtent - 1) * 256, Math.max(0, coordinate));
    const left = Math.floor(fixed / 256);
    first[position] = left * stride;
    second[position] = Math.min(left + 1, sourceExtent - 1) * stride;
    weight[position] = fixed - left * 256;
  }
  return { first, second, weight };
}

export function resizeBackgroundBilinear(src, width, height, outWidth, outHeight) {
  if (!(src instanceof Uint8Array) || src.length !== width * height * 4 ||
      ![width,height,outWidth,outHeight].every(n => Number.isSafeInteger(n) && n > 0) ||
      outWidth > width || outHeight > height) throw new RangeError('invalid bound or upscale');
  const cols = samples(width, outWidth, 4);
  const rows = samples(height, outHeight, width * 4);
  const out = new Uint8Array(outWidth * outHeight * 4);
  let dest = 0;
  for (let y = 0; y < outHeight; y++) {
    const top = rows.first[y], bottom = rows.second[y], wy = rows.weight[y];
    for (let x = 0; x < outWidth; x++, dest += 4) {
      const left = cols.first[x], right = cols.second[x], wx = cols.weight[x];
      const tl = top + left, tr = top + right, bl = bottom + left, br = bottom + right;
      const wtl = (256 - wx) * (256 - wy), wtr = wx * (256 - wy);
      const wbl = (256 - wx) * wy, wbr = wx * wy;
      const a = src[tl + 3], b = src[tr + 3], c = src[bl + 3], d = src[br + 3];
      if ((a & b & c & d) === 255) {
        out[dest + 3] = 255;
        for (let ch = 0; ch < 3; ch++) {
          out[dest + ch] = Math.floor((src[tl+ch]*wtl + src[tr+ch]*wtr + src[bl+ch]*wbl + src[br+ch]*wbr + 32768) / 65536);
        }
      } else {
        const at = a * wtl, ar = b * wtr, ab = c * wbl, ad = d * wbr;
        const sumAlpha = at + ar + ab + ad;
        const alpha = Math.floor((sumAlpha + 32768) / 65536);
        out[dest + 3] = alpha;
        if (alpha === 0) continue;
        for (let ch = 0; ch < 3; ch++) {
          out[dest + ch] = Math.floor((src[tl+ch]*at + src[tr+ch]*ar + src[bl+ch]*ab + src[br+ch]*ad + sumAlpha / 2) / sumAlpha);
        }
      }
    }
  }
  return out;
}
