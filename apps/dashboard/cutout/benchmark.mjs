import { chromium } from '@playwright/test';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { extname } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = new URL('../web/', import.meta.url);
const server = createServer(async (req, res) => {
  try {
    if (req.url === '/') { res.setHeader('Content-Type', 'text/html'); res.end('<title>Local cutout benchmark</title>'); return; }
    const path = new URL(`.${req.url}`, root);
    if (!path.href.startsWith(root.href)) { res.writeHead(403).end(); return; }
    const bytes = await readFile(path);
    res.setHeader('Content-Type', ({ '.mjs': 'text/javascript', '.wasm': 'application/wasm' })[extname(path.pathname)] || 'application/octet-stream');
    res.setHeader('Content-Length', bytes.length); res.end(bytes);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browserServer = await chromium.launchServer({ headless: true, channel: 'chrome' });
const browser = await chromium.connect(browserServer.wsEndpoint());
let peakWorkingSet = 0, peakPrivateBytes = 0;
const monitor = spawn('powershell', ['-NoProfile', '-File', fileURLToPath(new URL('./measure-memory.ps1', import.meta.url)), '-BrowserProcessId', String(browserServer.process().pid)], { windowsHide: true });
monitor.stdout.on('data', chunk => {
  for (const line of chunk.toString().trim().split('\n')) {
    const [working, privateBytes] = line.split(',').map(Number);
    if (working) peakWorkingSet = Math.max(peakWorkingSet, working);
    if (privateBytes) peakPrivateBytes = Math.max(peakPrivateBytes, privateBytes);
  }
});
const page = await browser.newPage();
page.on('console', message => console.log('browser:', message.text()));
page.on('pageerror', error => console.log('browser error:', error.message));
await page.goto(`http://127.0.0.1:${server.address().port}`);
try {
  const input = [...await readFile(process.argv[2])];
  const started = Date.now();
  const mimeType = process.argv[2].endsWith('.webp') ? 'image/webp' : /\.jpe?g$/.test(process.argv[2]) ? 'image/jpeg' : 'image/png';
  const result = await page.evaluate(async ({ input, mimeType }) => {
    const bridge = await import('/product-cutout/bridge.mjs');
    const result = await bridge.process(new Uint8Array(input), mimeType, stage => console.log(stage));
    return { ...result, bytes: [...result.bytes] };
  }, { input, mimeType });
  const extension = ({ 'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp' })[result.mimeType];
  if (!extension) throw new Error('Unexpected output MIME');
  const output = process.argv[3].replace(/\.(?:png|jpe?g|webp)$/i, '') + extension;
  await writeFile(output, new Uint8Array(result.bytes));
  console.log(JSON.stringify({ output, mimeType: result.mimeType, elapsedMs: Date.now() - started, bytes: result.bytes.length, width: result.width, height: result.height, alreadyTransparent: result.alreadyTransparent, peakWorkingSet, peakPrivateBytes }));
} finally { await browser.close(); await browserServer.close(); monitor.kill(); server.close(); }
