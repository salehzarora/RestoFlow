// Build-time only. No merchant pixels are transmitted. Runtime is same-origin.
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
import { MODEL } from '../web/product-cutout/limits.mjs';
const target = new URL('../web/product-cutout/vendor/', import.meta.url);
await mkdir(target, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
await mkdir(new URL('.cache/', import.meta.url), { recursive: true });
const modelPath = new URL('.cache/u2net.onnx', import.meta.url);
let bytes;
try { bytes = await readFile(modelPath); } catch { /* first build */ }
if (!bytes || bytes.length !== MODEL.bytes || hash(bytes) !== MODEL.sha256) {
  const response = await fetch(MODEL.buildSource);
  if (!response.ok) throw new Error(`Model fetch failed: ${response.status}`);
  bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length !== MODEL.bytes || hash(bytes) !== MODEL.sha256) throw new Error('Model integrity mismatch');
  await writeFile(modelPath, bytes);
}
for (let i = 0; i < MODEL.parts.length; i++) {
  const part = bytes.subarray(i * MODEL.partBytes, Math.min((i + 1) * MODEL.partBytes, MODEL.bytes));
  if (hash(part) !== MODEL.parts[i]) throw new Error('Model part integrity mismatch');
  await writeFile(new URL(`u2net-${String(i).padStart(2, '0')}.bin`, target), part);
}
for (const name of ['ort.wasm.min.mjs', 'ort-wasm-simd-threaded.wasm']) {
  await copyFile(new URL(`node_modules/onnxruntime-web/dist/${name}`, import.meta.url), new URL(name, target));
}
// A bounded private WASM heap: 8192 pages = 512 MiB. The pinned module imports
// memory with maximum 65536; supplying a SMALLER maximum is valid WebAssembly.
// Its allocator catches memory.grow failure. No graph/weights/output changes.
const runtime = await readFile(new URL('node_modules/onnxruntime-web/dist/ort-wasm-simd-threaded.mjs', import.meta.url));
if (hash(runtime) !== '90a557d15c02bac4504d95b67f431d8594635ed2a0a62a7f2cd83d090ff91d3e') throw new Error('Runtime patch source mismatch');
const runtimeText = runtime.toString();
if (runtimeText.split('initial:256,maximum:65536,shared:!0').length !== 2) throw new Error('Runtime heap patch mismatch');
await writeFile(new URL('ort-wasm-simd-threaded.mjs', target),
  '// BIZBOT modification: WASM maximum memory reduced to 512 MiB.\n' + runtimeText.replace('initial:256,maximum:65536,shared:!0', 'initial:256,maximum:8192,shared:!0'));
for (const name of ['ONNX-RUNTIME-LICENSE.txt', 'ONNX-RUNTIME-THIRD-PARTY-NOTICES.txt', 'U2NET-LICENSE.txt', 'REMBG-LICENSE.txt']) {
  await copyFile(new URL(`licenses/${name}`, import.meta.url), new URL(name, target));
}
for (const name of ['sniff.mjs', 'pngbound.mjs']) {
  await copyFile(new URL(`../../../supabase/functions/storefront-media-publish/lib/${name}`, import.meta.url), new URL(name, target));
}
console.log(`Prepared Dashboard-only model (${MODEL.bytes} bytes, SHA-256 verified) and pinned ONNX Runtime 1.23.2.`);
