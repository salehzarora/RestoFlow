# Product-mask diagnosis, 2026-11-05

**Decision: no mask correction is justified by these measurements. Keep background removal unavailable by default.** The raw model output already discards the burger's left plate, treats the fries cup and plate as partially salient, and strongly retains unwanted condiment bottles. Normalization, resizing, PNG alpha assignment and c4 publication do not introduce that subject-selection failure. No threshold, opacity remapping, global transparency change, model swap or manual editor was adopted.

This is an evidence-only replay of PR380 candidate `e006ee2f145020b12d4d3a096d2c46fdcafbc0a8`. The three inputs are the same existing published c4/w480 copies used in the successful isolated service run; they are **not private production originals**. The local diagnostic runner uses cached, SHA-verified U2Net FP32 weights and the existing c4 deriver. It performs no service writes, hosted image transfer or production mutation.

| Sample | Source dimensions | Source bytes | Source SHA-256 |
| --- | --- | ---: | --- |
| burger | 360 × 480 | 27156 | `5bcfca1884ff3d0cb5dea89a4553664a4f2c205c65081781918e2e75b8ead994` |
| fries-cup | 480 × 480 | 46612 | `698cee5bb2f9281e3be57d78adbc100685b1a8d04969f8248fe6ebe12609106e` |
| platter | 360 × 480 | 33756 | `f3bb4d896712f0acb9dc1359495e5c2aa3ca0025afff4b39e7fa8bc0118ad2b6` |

The [machine-readable observation](mask-diagnosis.json) includes source/candidate/output hashes, raw float statistics, all region definitions, all stage alpha hashes, publication dimensions and local-versus-CI comparison flags. The [prior actual-service receipt](ci-e006ee2f-product-cutout.json) is preserved separately. No local replay is labelled as a new real-service run.

**Stages and where the error starts.** The runner serves an instrumented copy of the shipped worker in memory. Three observations capture: (1) the first output tensor's original Float32 bytes before `alphaMatte`; (2) the actual 320×320 min/max-normalized grayscale matte; (3) the actual source-sized grayscale matte before it is copied into alpha. The shipped worker file, public message protocol, model graph/weights and arithmetic remain unchanged. The normal PNG result is then decoded, passed through the pinned c4 encoder independently for w480/w960, and decoded again.

The raw-mask PNG uses a fixed 0–1 → 0–255 display scale with no contrast normalization. The binary Float32 file is authoritative. This model output is a saliency confidence signal, not calibrated physical transparency. Raw model and normalized images are 320×320; the source-size stages restore the source aspect ratio. The boards intentionally show that geometry difference.

| Sample | Raw output range | Max byte difference: raw ×255 vs normalized | Pixels changed: resized mask → PNG alpha | Pixels changed: PNG alpha → c4 alpha |
| --- | --- | ---: | ---: | ---: |
| burger | 0–1 | 0 | 0 | 0 |
| fries-cup | 7.152557e-7–0.9999982 | 1 | 0 | 0 |
| platter | 0–1 | 0 | 0 | 0 |

The cup normalization difference is at most one 8-bit level. It cannot explain a cup median alpha of 103/255. PNG assignment and c4 publication each change **zero** alpha pixels. Both target variants stay at source size and have identical bytes per sample; no upscaling or w480-to-w960 cascade occurs.

**Regions in the original photo.** Each box is `x, y, width, height` in source pixels, visualized in the linked ROI image. Raw statistics cover the corresponding floor/ceil-mapped 320×320 box; final statistics cover the exact source-pixel box. They diagnose visible areas and are not a manually labelled whole-image ground truth.

| Sample / region | Source box | Raw min / median / max | Final alpha min / median / max |
| --- | --- | --- | --- |
| burger / plateLeft | 15, 260, 45, 60 | 0 / 0.000001788139 / 0.00003501773 | 0 / 0 / 0 |
| burger / food | 140, 240, 85, 100 | 0.9999963 / 1 / 1 | 255 / 255 / 255 |
| fries-cup / cup | 225, 360, 75, 90 | 0.1565911 / 0.4017012 / 0.7082272 | 41 / 103 / 178 |
| fries-cup / plate | 110, 410, 65, 45 | 0.3614893 / 0.4778938 / 0.5810015 | 92 / 122 / 148 |
| fries-cup / food | 220, 275, 60, 40 | 0.4919968 / 0.7740222 / 0.8863994 | 127 / 198 / 224 |
| fries-cup / bottle | 380, 100, 60, 150 | 0.9951206 / 0.999406 / 0.9999902 | 254 / 255 / 255 |
| platter / food | 100, 270, 120, 120 | 0.9999843 / 0.9999999 / 1 | 255 / 255 / 255 |
| platter / bottle | 135, 70, 50, 100 | 0.002191842 / 0.9126161 / 0.9724399 | 1 / 233 / 248 |

Burger's left-plate box is nearly zero in raw Float32 and entirely zero in final alpha, while its food box is essentially one/255. For the cup, even the strongest sampled cup confidence (0.7082) is below the weakest sampled unwanted-bottle confidence (0.9951). A monotonic global threshold cannot keep that cup region while rejecting that bottle. The platter food is strong, but its background bottle is also strong (median 0.9126). These are model-level selection errors; preserving the serving context and excluding bottles requires evidence beyond an alpha conversion adjustment.

**Independent stage images and actual composites.**

| Sample | Input and region boxes | Raw model mask | Actual processed matte | Decoded alpha | Composite comparison |
| --- | --- | --- | --- | --- | --- |
| burger | [Source](burger-source.webp) / [ROIs](burger-source-regions.png) | [Raw float32](burger-raw-mask.float32le) / [fixed-scale view](burger-raw-mask-unit-scale.png) | [Normalized](burger-normalized-mask.png) / [resized](burger-resized-mask.png) | [PNG alpha](burger-final-alpha.png) / [WebP alpha](burger-published-alpha.png) | [Light/dark board](burger-diagnostic-board.png) |
| fries-cup | [Source](fries-cup-source.webp) / [ROIs](fries-cup-source-regions.png) | [Raw float32](fries-cup-raw-mask.float32le) / [fixed-scale view](fries-cup-raw-mask-unit-scale.png) | [Normalized](fries-cup-normalized-mask.png) / [resized](fries-cup-resized-mask.png) | [PNG alpha](fries-cup-final-alpha.png) / [WebP alpha](fries-cup-published-alpha.png) | [Light/dark board](fries-cup-diagnostic-board.png) |
| platter | [Source](platter-source.webp) / [ROIs](platter-source-regions.png) | [Raw float32](platter-raw-mask.float32le) / [fixed-scale view](platter-raw-mask-unit-scale.png) | [Normalized](platter-normalized-mask.png) / [resized](platter-resized-mask.png) | [PNG alpha](platter-final-alpha.png) / [WebP alpha](platter-published-alpha.png) | [Light/dark board](platter-diagnostic-board.png) |

The boards show the input, raw model output, normalized matte, resized matte, final PNG alpha, published-WebP alpha, and the actual candidate on light/dark backgrounds. Individual [burger](burger-candidate.png), [cup](fries-cup-candidate.png) and [platter](platter-candidate.png) PNG candidates and both `*-published-w480.webp` / `*-published-w960.webp` replay outputs are retained. The cup board makes the translucent cup/plate and retained bottles visible; the burger board shows missing left dish; the platter board shows retained bottles despite recognizable food and foil dish.

**Raw and final identity.**

| Sample | Original raw Float32 SHA-256 | Final PNG / local published alpha SHA-256 |
| --- | --- | --- |
| burger | `a4aa3d0c56ab031f84b086738d74ef1f12906e90c36029d6253ecaa92eccc205` | `dd8169027577275079663474f2d674a3f6de55f86e5508f0926f1ff6d8524ca9` |
| fries-cup | `cf7c75d1734013e383da99e7e64ffcef058535204bc4b93a824512be45ea522c` | `0ec443e0ea39083b4da928ff2ce48d56f955cbb997472e460130f004d1124e47` |
| platter | `3b7d6d6ef53777a95c860a33ba5fd73940fadbfbd0f6d4d7a069e6a139eafc36` | `09f55aa60dd0d376dc9a752c8a9879e53115a53dbd3def759ec87dd0d29659aa` |

The local browser was Chrome `156.0.8078.80` on Windows. All three diagnostic candidate PNG hashes match the saved, uninstrumented worker results from 2026-11-04 byte-for-byte, confirming that the observation hooks did not alter those outputs. The local final-alpha/publication hashes do **not** equal the Linux CI receipts; the JSON comparison flags explicitly remain false. The bundled CI Chromium executable was not available in the existing local cache; no browser/model download was introduced to erase this distinction. The precise cross-platform cause is not established here. Local stage equality and prior real-service candidate-to-public-alpha equality are separate evidence chains, and both expose the same visible preservation defects.

Reproduction: from `apps/dashboard/cutout`, run `node diagnose-mask.mjs INPUT_DIRECTORY OUTPUT_DIRECTORY CI_PRODUCT_JSON` with the saved three WebP inputs and the prior service receipt. It uses the already prepared vendor/cache and existing locked dependencies, one 120-second-bounded worker per photo, then the actual pinned c4 codec. Raw tensor binaries and PNG/WebP files in this directory are small diagnostic artifacts; no model/runtime assets are committed here.

The owner's accepted original-photo upload/publication path remains usable. Original is the correct choice for these failed preservation examples. This report does not claim four clean cutouts, universal mobile support, or recovery of lost source detail.
