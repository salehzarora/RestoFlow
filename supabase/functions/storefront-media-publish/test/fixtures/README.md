# Committed JPEG test fixtures (storefront-media-publish)

These four files are the ONLY committed image fixtures of the function's tests.
Every other test source is built at test time without any image engine: PNG with
`node:zlib` (test/fixtures.mjs), WebP with the vendored libwebp encoder the function
itself ships (vendor/jsquash/webp-enc). The JPEG orientation, EXIF (GPS), truncated,
corrupt-entropy, 4-component and over-cap variants are derived from these files at
test time (byte edits in test/fixtures.mjs), never stored.

## Provenance

- Content: SYNTHETIC procedural pixels only (no photograph, no person, no tenant or
  customer data): `photoRgb(width, height, seed 7, noise 10)` of test/fixtures.mjs, a
  smooth gradient with two sine waves and seeded uniform noise.
- Encoder: the mozjpeg ENCODER of `@jsquash/jpeg@1.6.0`
  (`package/codec/enc/mozjpeg_enc.wasm` sha-256
  `24d4177f1c4963e2058b107189249651c61fdef125570e79b1dfb63c8bb49326`,
  `package/codec/enc/mozjpeg_enc.js` sha-256
  `93d3b28a4c9d3278acbbe0e23ff244ec3a6bfb13e51647b87eea311a8d747694`), run ONCE in the
  scratch area of the STOREFRONT-PUBLISH-001 Q031 spike. It is NOT vendored, NOT shipped
  and NOT used by any test; re-running the same encoder with the same settings
  reproduced every file byte for byte (2026-09-25).
- Common settings: quality 88, `optimize_coding` true, `smoothing` 0, `quant_table` 3,
  no trellis (`trellis_multipass` / `trellis_opt_zero` / `trellis_opt_table` false,
  `trellis_loops` 1), `arithmetic` false, `auto_subsample` false,
  `separate_chroma_quality` false, `chroma_quality` 88.

| File | Size | Pixels | Layout | Settings beyond the common ones | sha-256 |
|---|---:|---|---|---|---|
| `prog_420_1600x1200.jpg` | 127,658 B | 1600 x 1200 | progressive, YCbCr 4:2:0 | `progressive` true, `color_space` 3, `chroma_subsample` 2 | `51f81644a35708d49199ea3143cc74e1a61b8101ffec89fbf9cdd34b99beb0c4` |
| `base_444_1200x900.jpg` | 96,115 B | 1200 x 900 | baseline, YCbCr 4:4:4 | `baseline` true, `color_space` 3, `chroma_subsample` 1 | `93ff9d06014d4ba1d90e130c698361ca76532b4a07e0d3d1bb3031f590a9af04` |
| `gray_prog_1000x750.jpg` | 41,840 B | 1000 x 750 | progressive, grayscale | `progressive` true, `color_space` 1 | `bc9b5f3ccc3cb45b5d04990e09937a8c550b312f1315e91578c910d713918199` |
| `base_420_900x450.jpg` | 29,519 B | 900 x 450 | baseline, YCbCr 4:2:0 | `baseline` true, `color_space` 3, `chroma_subsample` 2 | `0539fe2a8cc6ee3cd1074b887cfba33d31784b5d6c317df839fb8254607d4a2e` |

Total: 295,132 bytes (the budget is < 300 KB). test/recipe.test.mjs pins these hashes,
so an edited fixture fails the suite instead of silently moving the goldens.
