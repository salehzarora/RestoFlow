export const MODEL = Object.freeze({
  revision: 'rembg-v0.0.0-u2net',
  bytes: 175997641,
  sha256: '8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491',
  buildSource: 'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx',
  partBytes: 16777216,
  parts: Object.freeze([
    '13a46bb203e4a251b113043429bb89f8a57a9a7619dea953f46db4cddef8c4d5',
    '8f3319e1fd85e0fcb411bab548e2151bf501e3591332e2402daf43306f37d244',
    'bc356d5416d679a19ca2256f9c7a06be38e5fd17c7a7e1b43583332957e21a1c',
    '535f58237bde236208d854811219015a6b740bfa28eaef016e2547f0e28a530f',
    '4007be3b9ede86cc8841a815c596bbfdb57664d9ad863deec1e149aecf4317fa',
    'ed7297b7dfb54459204ff4f00c789fb7e3182382747c9873ff3b6f8378455cb7',
    '8d7c6c6b6c64f05026db67cea4c675a0c5e6a1911b65750c5a227f919bd7d622',
    '41b4d80f5500372fa2d2626b43b7fe095d30495d4b773dc2bfd55d43f72f4c39',
    'bcbd235a5a3e9ceb80b0de6e558778154f669c97f91c577c5c9655bd36893865',
    '55fa240f69de6ec546ae779b85afc63a3b7fa408d1df3e82e1a5322fa5bc87e5',
    'fcc71a5a83209d32e190213898c4cd3e3a438cb323c50f66d9b96a1d10d108ca',
  ]),
});
export const LIMITS = Object.freeze({
  maxInputBytes: 5242880, maxOutputBytes: 5242880, outputSide: 1600,
  timeoutMs: 120000, modelSide: 320,
  // Identical pre-decode resource limits to the authorized publication engine.
  decodeMaxPixels: 8388608, maxSide: 8192, maxPixels: 8388608,
  jpegMaxSide: 8192, jpegMaxPixels: 8388608, jpegMaxScans: 16,
  jpegMaxProgressiveCoefficientBytes: 33554432, jpegMaxProgressiveScanWork: 400000000,
  maxAspect: 8, maxMetadataBytes: 1048576, pngMaxRawBytes: 33570816,
  pngMaxChunks: 65536, pngMaxAncillaryChunks: 32, pngMaxIccp: 1,
  pngMaxCompressedText: 4, webpMaxChunks: 16,
});
export function outputSize(width, height) {
  const scale = Math.min(1, LIMITS.outputSide / Math.max(width, height));
  return { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) };
}
export function inputTensor(rgba) {
  const size = LIMITS.modelSide ** 2;
  if (rgba.length !== size * 4) throw new Error('Invalid input raster');
  const data = new Float32Array(3 * size);
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  for (let i = 0; i < size; i++) for (let c = 0; c < 3; c++) data[c * size + i] = (rgba[i * 4 + c] / 255 - mean[c]) / std[c];
  return data;
}
export function alphaMatte(logits) {
  if (logits.length !== LIMITS.modelSide ** 2) throw new Error('Invalid model output');
  let min = Infinity, max = -Infinity;
  for (const value of logits) {
    if (!Number.isFinite(value)) throw new Error('Invalid model output');
    min = Math.min(min, value); max = Math.max(max, value);
  }
  if (max - min < 1e-6) throw new Error('No clear subject found');
  const rgba = new Uint8ClampedArray(logits.length * 4);
  for (let i = 0; i < logits.length; i++) {
    const alpha = Math.round(255 * (logits[i] - min) / (max - min));
    rgba.set([alpha, alpha, alpha, 255], i * 4);
  }
  return rgba;
}
