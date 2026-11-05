import { LIMITS } from './limits.mjs';
let active = null;
export function unavailableReason(environment = globalThis) {
  if (typeof environment.Worker !== 'function' ||
      typeof environment.OffscreenCanvas !== 'function' ||
      typeof environment.createImageBitmap !== 'function' ||
      typeof environment.WebAssembly !== 'object') {
    return 'Local background removal is unavailable in this browser. Upload and keep Original instead.';
  }
  if (environment.navigator?.deviceMemory && environment.navigator.deviceMemory < 4) {
    return 'This device reports less than 4 GB memory. Upload and keep Original instead.';
  }
  return null;
}
export function cancel(owner) { if (active?.owner === owner) active.cancel(); }
export function process(bytes, mimeType, progress = () => {}, owner = 'benchmark') {
  if (active) return Promise.reject(new Error('Another product image is being processed'));
  if (!bytes?.length || bytes.length > LIMITS.maxInputBytes) return Promise.reject(new Error('Image must be no larger than 5 MiB'));
  // Refuse before creating a worker or decoding a full-resolution RGBA raster.
  // Ordinary image upload and the retained original are independent of this path.
  const unavailable = unavailableReason();
  if (unavailable) {
    progress('unavailable-device');
    return Promise.reject(new Error(unavailable));
  }
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    let timer;
    const finish = (error, value) => {
      clearTimeout(timer); worker.terminate(); active = null;
      error ? reject(new Error(error)) : resolve(value);
    };
    active = { owner, cancel: () => finish('Cancelled; your original is unchanged') };
    timer = setTimeout(() => finish('Local background removal timed out; retry or keep Original'), LIMITS.timeoutMs);
    worker.onerror = () => finish('Local processor unavailable; retry or keep Original');
    worker.onmessage = ({ data }) => {
      if (data.stage) progress(data.stage);
      else if (data.error) finish(data.error);
      else if (data.done) finish(null, { ...data, bytes: new Uint8Array(data.bytes) });
    };
    // A copy crosses the worker boundary; cancellation never detaches the original.
    const copy = Uint8Array.from(bytes);
    worker.postMessage({ bytes: copy.buffer, mimeType }, [copy.buffer]);
  });
}
