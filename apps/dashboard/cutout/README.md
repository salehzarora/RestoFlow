# Local product background removal

Work ID: BIZBOT-STOREFRONT-VISUAL-PARITY-001 (shared editor seam: -MEDIA).

This is a non-generative saliency segmentation pipeline. RGB comes from the
original photograph; only alpha changes. It does not repaint food, replace a
scene, sharpen or synthesize detail. A separate candidate stays local until the
owner explicitly publishes Original or Remove background. The menu image pointer
and private original stay unchanged. The Dashboard gateway owns authenticated
source-generation/selection-version checks and existing media publication.

## Release: optional explicit preparation

The owner accepted the demonstrated mask limitations for PR380's release on
2026-11-05. Original remains selected; loading a photo or opening/switching the
editor does not process it. The separate **Prepare** action starts the worker;
reviewing a candidate and explicitly publishing a choice remain separate steps.

The existing Production Storefront editor gate enables
`SF_PRODUCT_CUTOUT_REVIEW=true` for Dashboard only. The name is retained for
compatibility. Unset/disabled gates and Preview builds do not ship the heavy
assets. A disabled processor or an unsupported device still permits explicit
Original publication. The isolated CI build enables the same compile flag to
exercise the real action, without using production data.

Known masks lose part of a burger plate, make a fries cup/plate translucent, or
retain unrelated bottles. These errors originate in the raw model confidence;
no threshold/opacity correction or replacement model is claimed to fix them.
Review each candidate and keep Original if food or serving context is lost.
Historical quality reports remain unchanged. Acceptance is not a claim of
perfect segmentation, universal device support, or zero operating cost.

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
The existing Product Vercel build executes those pinned commands only when its
Production editor gate is enabled. Preparation verifies the model and each of
its 11 chunks (at most 16 MiB), copies the pinned runtime, notices and bounded
pre-decode validators, and writes **Dashboard-only** assets under
`web/product-cutout/assets/<64-hex SHA-256>/`. The directory identity covers the
sorted filenames, lengths and SHA-256 digests of all 20 files. `assets.mjs` points
the worker at that revision; no per-tenant copies or URLs are created.

`asset-manifest.json` also binds the stable bootstrap/worker/bridge/limits code.
The build verifies the copied output, the production flag, and exclusion from
POS/KDS/Kiosk, then writes sanitized `product-cutout/build-record.json` with the
source commit, asset revision/digests/bytes and enabled state. CI retains this
record as `dashboard-cutout-build.json`. Disabled builds remove only the fixed
generated processor outputs before Flutter builds, preventing reused-checkout
leakage. These checks do not alter or raise a build/resource budget.

`vercel.json` assigns immutable public caching only to the content-addressed
processor files. Stable modules/manifests revalidate; module/WASM/model/notices
have explicit MIME types and `nosniff`. Missing processor paths return 404
instead of the Dashboard SPA. These headers do not cover private source images,
authenticated Storage requests, tokens, or other API responses. Merchant source
bytes stay in the browser during preparation; authenticated publication uses
the existing media path separately. Runtime verifies each chunk and the assembled
model before inference; one preallocated buffer avoids concatenation copies.

`web/index.html` loads only the tiny bootstrap. No model/runtime is fetched until
an explicit processing call. No Storefront/POS import, public storefront script,
provider key or external inference service is added. Prepared assets are
shared static build files, gitignored, and must exist before an enabled build.
Browser/CDN reuse reduces repeat transfer but is not guaranteed storage: eviction,
new devices/browsers or changed versions require another cold download. The
model alone is about 176 MB, and runtime transfer and browser memory are additional.

`node cache-benchmark.mjs INPUT_JPEG REPORT.json` measures the actual worker twice
in one fresh, un-routed local Chrome context. It records server response body
bytes, model request counts, output hashes and timings using the committed cache
headers. It also checks missing paths and that opening the page loads no heavy
assets. This is local browser-cache evidence, not production CDN measurement,
wire overhead, a permanent cache promise or a real-service save. The routed
acceptance journey disables HTTP cache and labels its resource receipts accordingly.
Production response headers/build identity must be verified after deployment.

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
  set / ~1.01 GB private bytes. Devices reporting <4 GB RAM and browsers missing
  required Worker/OffscreenCanvas/createImageBitmap/WebAssembly APIs are refused
  before worker creation, full image decode or model loading. Reported device
  memory is not a measurement of free RAM. Desktop Chrome is the tested profile;
  universal mobile support is not claimed. Ordinary upload and explicit Original
  publication remain available with a fixed, localized fallback explanation.
* Publication is a separate explicit action. Processing failure never publishes.
  Uncertain publication retains its request ID and selected bytes. Successful
  publication re-reads the authoritative source/selection proof for later choices.
  A changed source snapshot or changed bytes (including a same-key overwrite)
  discards the prior candidate; advancing only selection version retains it.
  Late publication responses cannot replace another source's editor state.

## Evidence and limits

`npm test` covers input bounds, tensor normalization, geometry, model-part and
native-memory integrity, single-job concurrency, owner-scoped cancel, timeout,
retry and original retention. Flutter tests cover explicit choice, existing
images, review-enabled preparation after original save, failure/retry, cancellation,
late-result rejection and uncertain publication retry.
The guarded real-service journey also checks authenticated private original
SHA-256 before/after publication, actual decoded published alpha, UI cancellation,
a failed model request, and successful retry. Service evidence must identify
the actual Actions checkout and review-enabled build; earlier source runs do
not establish execution on a later candidate.

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
