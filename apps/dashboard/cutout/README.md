# Local product background removal

Work ID: BIZBOT-STOREFRONT-VISUAL-PARITY-001 (shared editor seam: -MEDIA).

This is a non-generative saliency segmentation pipeline. RGB comes from the
original photograph; only alpha changes. It does not repaint food, replace a
scene, sharpen or synthesize detail. A separate candidate stays local until the
owner explicitly publishes Original or Remove background. The menu image pointer
and private original stay unchanged. The Dashboard gateway owns authenticated
source-generation/selection-version checks and existing media publication.

## Chosen runtime and weights

* Code: ONNX Runtime Web **1.23.2**, MIT, exact npm lockfile. Official code license:
  <https://github.com/microsoft/onnxruntime/blob/v1.23.2/LICENSE>.
* Weights: **U²-Net**, 320×320 FP32 ONNX exported by rembg, from its versioned
  `v0.0.0` release. **175,997,641 bytes**, SHA-256
  `8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491`.
* Weight-license evidence is independent of the code license: the upstream
  model author explicitly confirms that the released models and code share
  Apache 2.0 in <https://github.com/xuebinqin/U-2-Net/issues/208>.
  Upstream license: <https://github.com/xuebinqin/U-2-Net/blob/master/LICENSE>.
  ONNX artifact: <https://github.com/danielgatis/rembg/releases/tag/v0.0.0>.
  Export-project MIT license: <https://github.com/danielgatis/rembg/blob/v2.0.67/LICENSE.txt>.
  These permissive licenses allow commercial use and distribution with notices.
  This does not claim a commercial rights warranty for the original training
  photographs; upstream separately identifies DUTS as training data.
* Full license and third-party notices are in `licenses/` and copied beside the
  runtime/model when preparing a build. The U²-Net paper is Qin et al.,
  “U²-Net: Going Deeper with Nested U-Structure for Salient Object Detection”,
  Pattern Recognition 106 (2020), 107404.

BiRefNet lite 512 has explicit MIT code/weight/export licensing but was rejected
after measurement: FP32 WASM reached 3.16 GB browser working set; FP16 WebGPU
reached 4.11 GB. U²-NetP used less memory but produced inferior sample edges.
BRIA RMBG is not adopted because its free weight license excludes commercial use.

## Build and delivery

From this directory run `npm ci --ignore-scripts`, then `npm run prepare`.
Preparation verifies the model digest, writes 11 pinned chunks (at most 16 MiB)
under **Dashboard** `web/product-cutout/vendor`, and copies the pinned runtime,
notices, and the existing publication engine's bounded pre-decode validators.
Model download happens only during the build. Runtime fetches only same-origin
chunks; no image or metadata is sent to a model provider. The worker verifies
each chunk and the assembled model before inference. One preallocated model
buffer avoids concatenation copies. Browser caching can reuse immutable assets;
deployment should give versioned paths immutable caching, or revalidation otherwise.

`web/index.html` loads only the 1 KB bootstrap. The model/runtime are lazy loaded
by the product editor. No Storefront/POS import, public page script, service,
provider key, or generative API is added. Build artifacts are gitignored and
must be prepared before a Dashboard deployment. Vercel's CLI source upload limit
is aggregate (100 MB Hobby, 1 GB Pro); chunks do not evade that limit. A remote
build can prepare assets from the small committed source manifest. Official
limits: <https://vercel.com/docs/limits>.

## Resource and lifecycle bounds

* One worker/job at a time, with an owner-scoped cancel handle. Retry creates a
  fresh worker. Cancel/dispose/120-second timeout terminate the worker, including
  synchronous inference, and never detach or discard the retained original.
* Input: PNG/JPEG/still WebP, 5 MiB, 8,388,608 pixels, side ≤8192, aspect ≤8:1.
  Existing publication source sniffing runs before decode. PNG decompression is
  bounded and metadata sanitized with the existing publication validator.
* Already-transparent input returns its original bytes and does not fetch the
  model or run segmentation.
* Fixed 320×320 input tensor, one CPU thread, sequential inference. **WASM native
  memory has a hard 512 MiB maximum**. `prepare.mjs` verifies the exact pinned
  runtime JS hash and changes only its memory descriptor maximum from 65536 to
  8192 pages. The model and inference graph are unchanged. A smaller imported
  maximum is valid WASM; failed memory growth becomes a typed processing failure.
  Build tests assert the bound; real sample output is identical before/after it.
* JS memory also stays finite: a 176 MB model buffer, bounded download chunks and
  digest copies, source ≤5 MiB, RGBA canvases ≤8 MiP, and output ≤1600 longest
  side/5 MiB PNG. Browsers may have GC/graphics overhead; this is not a hard
  whole-browser RSS limit. Measured fresh Chrome process tree: ~1.18 GB working
  set / ~1.01 GB private bytes. Devices reporting <4 GB RAM are refused before
  the model loads. Desktop Chrome with ≥4 GB available system memory is the
  tested profile; universal mobile support is not claimed.
* Publication is a separate explicit action. Processing failure never publishes.
  Uncertain publication retains its request ID and selected bytes. Successful
  publication re-reads the authoritative source/selection proof for later choices.

## Evidence and limits

`npm test` covers input bounds, tensor normalization, geometry, model-part and
native-memory integrity, single-job concurrency, owner-scoped cancel, timeout,
retry and original retention. Flutter tests cover explicit choice, existing
images, automatic preparation after original save, failure/retry, cancellation,
late-result rejection and uncertain publication retry.

`benchmark.mjs INPUT OUTPUT` executes the **actual browser worker**. On Windows
it samples the whole launched Chrome process tree; memory includes browser/UI
and does not measure only JS heap. `evidence.mjs ASSETS OUTPUT_DIRECTORY` creates
original/light/dark side-by-side screenshots and source/output measurements.
Inputs are copies of the owner's existing handoff photographs or actual current
published product copies, with provenance explicitly labeled. The CI fixtures in
`e2e/cinematic/fixtures/product-cutout` contain three opaque product photos and
one already-transparent cola image. They do not establish private-original
resolution or four successful segmentation cases. The ordinary UI journey runs
only on the authorized disposable CI stack; local widget/worker checks do not
claim to replace that real-service run.

Review is essential: saliency may remove a dark serving plate, part of packaging,
background objects, or transparent glass. The owner should keep Original when a
candidate loses required food/serving context. The UI starts on Original and
shows both backgrounds for edge inspection; no candidate is silently selected.
The handoff photographs are 600×600 (burger/fries) and 780×495 (platter). The
handoff file called `item-drink.png` depicts a coffee-machine scene and is only
a complex-scene negative example, not a valid drink cutout. Current published
copies are 360×480 (burger/platter), 480×480 (fries cup), and an already-alpha
drink copy. This operation cannot create missing detail or improve resolution.
