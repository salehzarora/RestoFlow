// STOREFRONT-PUBLISH-001 — Supabase Edge Function `storefront-media-publish`.
//
// Publishes a restaurant's storefront LOGO (w480) or HERO (w960) as a canonical
// public WebP derivative of an EXISTING private original, AS THE CALLER:
// every upstream request carries the signed-in user's own JWT, and the function
// is configured with the project URL and the public anon key ONLY. It holds no
// service-role key, no secret key and no storage (S3) credential, and it never
// reads any other environment variable (test/static_guard.test.mjs).
//
// Deployment (NOT done by this ticket; each step separately approved): JWT
// verification ON (supabase/config.toml [functions.storefront-media-publish]
// verify_jwt = true), the five pinned codec .wasm files and the third-party
// notices shipped as static files, CLI (Docker) bundling, and the hosted canary /
// performance gate in docs/DEPLOYMENT.md.
//
// Engine: recipe `storefront-media-c4` (lib/recipe.mjs) on five focused jSquash
// WebAssembly codecs vendored byte-exact under vendor/jsquash/ (provenance and
// licences: vendor/README.md, vendor/THIRD_PARTY_NOTICES.txt). Every wasm is
// sha-256-verified before it is compiled, and the engine derives an embedded
// vector against a pinned golden before its first use (EDGE-4): any mismatch
// fails closed as engine_unavailable.
//
// Resource contract: c4 bounds ONE call — every decode raster <= 8 MiP
// (8,388,608 px) and <= 8192 px per side, checked before decode; a PNG's image
// data inflated once, bounded by its exact raw size, before the decoder runs;
// output inside a W x W box; one encode per call; <= 512 KiB or a typed refusal.
// Hosted Supabase meters Edge Function CPU per REQUEST (2 s; async I/O excluded);
// the local CLI edge runtime meters it per worker isolate, a local-only
// difference (docs/DECISIONS.md D-040). The workflow and its recovery model live
// in lib/handler.mjs.

import { createDeriver } from './lib/recipe.mjs';
import { createHandler } from './lib/handler.mjs';

declare const Deno: {
  env: { get(name: string): string | undefined };
  readFile(path: URL): Promise<Uint8Array>;
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

// The ONLY two settings this function reads (both injected by the platform and public by design).
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

// Single-flight engine initialisation: concurrent first requests on one worker share
// ONE promise; it starts only after a request has passed authentication, validation
// and the authority preflight, so unauthenticated traffic never pays for it. The five
// files are the config.toml static_files (a user worker reads only those, by URL).
let enginePromise: Promise<unknown> | null = null;
function engine(): Promise<unknown> {
  enginePromise ??= Promise.all([
    Deno.readFile(new URL('./vendor/jsquash/png/squoosh_png_bg.wasm', import.meta.url)),
    Deno.readFile(new URL('./vendor/jsquash/resize/squoosh_resize_bg.wasm', import.meta.url)),
    Deno.readFile(new URL('./vendor/jsquash/jpeg-dec/mozjpeg_dec.wasm', import.meta.url)),
    Deno.readFile(new URL('./vendor/jsquash/webp-enc/webp_enc.wasm', import.meta.url)),
    Deno.readFile(new URL('./vendor/jsquash/webp-dec/webp_dec.wasm', import.meta.url)),
  ]).then(([png, resize, jpegDec, webpEnc, webpDec]) => createDeriver({ png, resize, jpegDec, webpEnc, webpDec }));
  return enginePromise;
}

// After an engine trap, a self-test mismatch, or an exception out of a one-per-worker
// wasm instance, the engine is not trusted: the handler answers (a typed refusal or a
// retryable 503) and this worker ends itself, so the runtime routes the next request
// to a fresh isolate instead of a cheap-but-broken one. EDGE-2: ending the isolate may
// also end OTHER requests in flight on it, without a contract body; the Dashboard
// treats any bodiless / untyped 5xx as an unknown outcome (re-read, then retry with
// the same request_id, which converges).
let retiring = false;
function retireWorker(): void {
  if (retiring) return;
  retiring = true;
  setTimeout(() => {
    throw new Error('storefront-media-publish: retiring a worker whose engine is not trusted');
  }, 0);
}

Deno.serve(createHandler({
  supabaseUrl,
  anonKey,
  engine,
  retireWorker,
  logError: (msg: string) => console.error(msg),
}));
