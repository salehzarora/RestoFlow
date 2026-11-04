// BIZBOT-STOREFRONT-VISUAL-PARITY-001: one disposable local inference worker.
import { LIMITS, MODEL, outputSize, inputTensor, alphaMatte } from './limits.mjs';
import { sniffSource } from './vendor/sniff.mjs';
import { pngRawSize, sanitizePng } from './vendor/pngbound.mjs';
const stage = value => postMessage({ stage: value });
const hex = bytes => [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');

self.onmessage = async ({ data }) => {
  let bitmap, session;
  try {
    if (!(data.bytes instanceof ArrayBuffer)) throw new Error('Invalid image');
    const bytes = new Uint8Array(data.bytes);
    const info = sniffSource(bytes, LIMITS);
    stage('decoding');
    let decodeBytes = bytes;
    if (info.type === 'png') {
      if (pngRawSize(info.width, info.height, info.bitDepth, info.colorType, info.interlace) > LIMITS.pngMaxRawBytes) throw new Error('Image exceeds memory limit');
      decodeBytes = await sanitizePng(bytes);
    }
    bitmap = await createImageBitmap(new Blob([decodeBytes]), { imageOrientation: 'from-image' });
    if (bitmap.width * bitmap.height > LIMITS.maxPixels || Math.max(bitmap.width, bitmap.height) > LIMITS.maxSide) throw new Error('Image exceeds memory limit');
    const original = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = original.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(bitmap, 0, 0);
    // Any real alpha is already a cutout. Keep bytes exactly; never segment it.
    const pixels = ctx.getImageData(0, 0, bitmap.width, bitmap.height).data;
    let hasAlpha = false;
    for (let i = 3; i < pixels.length; i += 4) if (pixels[i] < 255) { hasAlpha = true; break; }
    if (hasAlpha) {
      postMessage({ done: true, alreadyTransparent: true, bytes: data.bytes, width: bitmap.width, height: bitmap.height, mimeType: data.mimeType }, [data.bytes]);
      return;
    }
    // Refuse devices declaring <4 GB rather than loading a large neural runtime.
    if (navigator.deviceMemory && navigator.deviceMemory < 4) throw new Error('This device has insufficient memory for local background removal');
    stage('loading');
    // Allocate once; fetch one bounded chunk at a time. No concat duplicates.
    const model = new Uint8Array(MODEL.bytes);
    for (let i = 0; i < MODEL.parts.length; i++) {
      const expected = Math.min(MODEL.partBytes, MODEL.bytes - i * MODEL.partBytes);
      const response = await fetch(new URL(`./vendor/u2net-${String(i).padStart(2, '0')}.bin`, import.meta.url), { credentials: 'same-origin' });
      if (!response.ok || (response.headers.get('content-length') && Number(response.headers.get('content-length')) !== expected)) throw new Error('Local model unavailable');
      const reader = response.body.getReader();
      let offset = i * MODEL.partBytes;
      const end = offset + expected;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (offset + value.length > end) { await reader.cancel(); throw new Error('Local model exceeds size limit'); }
        model.set(value, offset); offset += value.length;
      }
      if (offset !== end || hex(new Uint8Array(await crypto.subtle.digest('SHA-256', model.subarray(i * MODEL.partBytes, end)))) !== MODEL.parts[i]) throw new Error('Local model integrity check failed');
    }
    if (hex(new Uint8Array(await crypto.subtle.digest('SHA-256', model))) !== MODEL.sha256) throw new Error('Local model integrity check failed');
    const ort = await import('./vendor/ort.wasm.min.mjs');
    ort.env.wasm.wasmPaths = new URL('./vendor/', import.meta.url).href;
    ort.env.wasm.numThreads = 1;
    ort.env.wasm.proxy = false;
    session = await ort.InferenceSession.create(model, { executionProviders: ['wasm'], executionMode: 'sequential', enableCpuMemArena: false, enableMemPattern: false });
    const inputCanvas = new OffscreenCanvas(LIMITS.modelSide, LIMITS.modelSide);
    const inputContext = inputCanvas.getContext('2d', { willReadFrequently: true });
    inputContext.drawImage(bitmap, 0, 0, LIMITS.modelSide, LIMITS.modelSide);
    const input = inputTensor(inputContext.getImageData(0, 0, LIMITS.modelSide, LIMITS.modelSide).data);
    stage('processing');
    const tensor = new ort.Tensor('float32', input, [1, 3, LIMITS.modelSide, LIMITS.modelSide]);
    const result = await session.run({ [session.inputNames[0]]: tensor });
    const output = result[session.outputNames[0]];
    const matte = new OffscreenCanvas(LIMITS.modelSide, LIMITS.modelSide);
    matte.getContext('2d').putImageData(new ImageData(alphaMatte(output.data), LIMITS.modelSide, LIMITS.modelSide), 0, 0);
    tensor.dispose();
    for (const value of Object.values(result)) value.dispose();
    await session.release(); session = null;
    stage('encoding');
    const size = outputSize(bitmap.width, bitmap.height);
    const canvas = new OffscreenCanvas(size.width, size.height);
    const out = canvas.getContext('2d', { willReadFrequently: true });
    out.drawImage(matte, 0, 0, size.width, size.height);
    const mask = out.getImageData(0, 0, size.width, size.height).data;
    out.clearRect(0, 0, size.width, size.height);
    out.drawImage(bitmap, 0, 0, size.width, size.height);
    const rgba = out.getImageData(0, 0, size.width, size.height);
    for (let i = 0; i < mask.length; i += 4) rgba.data[i + 3] = mask[i];
    out.putImageData(rgba, 0, 0);
    const blob = await canvas.convertToBlob({ type: 'image/png' });
    if (blob.size > LIMITS.maxOutputBytes) throw new Error('Transparent candidate exceeds upload limit; use a smaller original');
    const buffer = await blob.arrayBuffer();
    postMessage({ done: true, bytes: buffer, mimeType: 'image/png', width: size.width, height: size.height, alreadyTransparent: false }, [buffer]);
  } catch (error) {
    postMessage({ error: error.code || error.message || 'Local background removal failed' });
  } finally {
    bitmap?.close();
    if (session) await session.release();
  }
};
