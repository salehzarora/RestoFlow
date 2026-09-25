# Vendored image codecs of `storefront-media-publish` (recipe `storefront-media-c4`)

This directory holds the ONLY third-party code of the Edge Function: ten codec files
from four jSquash npm packages, each **byte-identical to its npm tarball copy and
unmodified** (no edit, no re-minification, no re-encoding, no line-ending change;
`.gitattributes` marks `vendor/**` as `-text` and the `.wasm` files as `binary`), plus
the third-party notices that cover exactly these files.

- `lib/recipe.mjs` (`RECIPE.engine.files`) pins the sha-256 of every file below;
  `createDeriver()` refuses to start unless each of the five `.wasm` files matches its
  pin, BEFORE anything is compiled.
- `test/license.test.mjs` re-hashes all ten files and `THIRD_PARTY_NOTICES.txt` on every
  test run (CI included), checks that this directory holds nothing else, and checks
  that `supabase/config.toml` ships exactly the five `.wasm` files and the notices as
  the function's `static_files`, so the notices travel inside every deploy bundle.

This software is based in part on the work of the Independent JPEG Group.

## Upgrade rule

ANY byte change to any file here (a new package version, a rebuild, a patched glue
file, an added codec) is a NEW recipe: it needs a new recipe id (c5, ...) and new
goldens, a re-run of the licence inventory and a regenerated `THIRD_PARTY_NOTICES.txt`
(never edited by hand), and a new owner decision before it is committed. Nothing here
may be fetched at runtime or at build time: the function imports these files by
relative path only.

## Files

| Vendored path | From (npm package, path inside the tarball) | Bytes | sha-256 |
|---|---|---:|---|
| `jsquash/png/squoosh_png_bg.wasm` | `@jsquash/png@3.1.1` `package/codec/pkg/squoosh_png_bg.wasm` | 181,088 | `263d6e658808a74b72a1a99c5cc1d619237e70c150db6e41d5d84d3d117ab9be` |
| `jsquash/png/squoosh_png.js` | `@jsquash/png@3.1.1` `package/codec/pkg/squoosh_png.js` | 8,818 | `65ebe1192f970c46263d52a122edf6bd01be81174c6bf1736a16f1e6f0e9b411` |
| `jsquash/jpeg-dec/mozjpeg_dec.wasm` | `@jsquash/jpeg@1.6.0` `package/codec/dec/mozjpeg_dec.wasm` | 166,470 | `a7c4b12169817e779ff4af137981393ae924944e167ad1bd95747c9199162d3e` |
| `jsquash/jpeg-dec/mozjpeg_dec.js` | `@jsquash/jpeg@1.6.0` `package/codec/dec/mozjpeg_dec.js` | 36,057 | `a6836b2d03d4fdda64b4aef380e6298d7421c070e7e1e4cf13ec129df7aa0b5e` |
| `jsquash/webp-enc/webp_enc.wasm` | `@jsquash/webp@1.5.0` `package/codec/enc/webp_enc.wasm` (non-SIMD) | 281,261 | `b6085bb6702f144e9dc6016d58d230b34a84976bf0d080b7390b4b4b137d6ab7` |
| `jsquash/webp-enc/webp_enc.js` | `@jsquash/webp@1.5.0` `package/codec/enc/webp_enc.js` | 38,665 | `5fd62301662e37785aec38e38807926f72933d4c8b919018a43faf1b1ca760f6` |
| `jsquash/webp-dec/webp_dec.wasm` | `@jsquash/webp@1.5.0` `package/codec/dec/webp_dec.wasm` | 137,960 | `30fb52fa2a80166d25ba7debf902218904ba1f05ccce9f959f722beff9e2f344` |
| `jsquash/webp-dec/webp_dec.js` | `@jsquash/webp@1.5.0` `package/codec/dec/webp_dec.js` | 34,823 | `c57971611f4d9ec04e4636ce7bb4a35c031b24cbdb013518f0a017d9f6014370` |
| `jsquash/resize/squoosh_resize_bg.wasm` | `@jsquash/resize@2.1.1` `package/lib/resize/pkg/squoosh_resize_bg.wasm` | 34,545 | `5b1f702d502c4d0a70b99f78691bd554d566ba95859e4c57af5435955a1d74a5` |
| `jsquash/resize/squoosh_resize.js` | `@jsquash/resize@2.1.1` `package/lib/resize/pkg/squoosh_resize.js` | 5,558 | `e974c442bb6a7f2b57a7c86a879f55a008ffd6fccea5f9ed9fee14900ae56225` |
| `THIRD_PARTY_NOTICES.txt` | the final licence inventory of these ten files (see below) | 103,282 | `aca02b5e7f056fc00e9defe6784456d1852fcf7d81c2c0bf2c41dcd640411af5` |

## npm packages

| Package | Tarball | npm `dist.integrity` (sha512) | tarball sha-1 | jSquash gitHead | Licence |
|---|---|---|---|---|---|
| `@jsquash/png@3.1.1` | `jsquash-png-3.1.1.tgz` | `sha512-C10pc+0H6j0h8fENOfnGOvkXCmvpSQTDGlfGd0sHphZhPSGTyLjIrHba0FaZZdsKqA/wlmhYicUHb92vfZphaw==` | `26b154c35f297ca8d1d31e7ecb23ef2447b9a986` | `b7fa9ac9ec02f224847ad23d19d115f9e296a368` | Apache-2.0 |
| `@jsquash/jpeg@1.6.0` | `jsquash-jpeg-1.6.0.tgz` | `sha512-zwN46Awh1VM6gXlIcALwb5WzqK5H2e6+Awcs1QP8AvS8ohsK/sbE4esvmH4jhlhW7+CgiUUww66vg0aTnlSIMA==` | `45474ce6d5b6165740d135c7bdf36dee9ba8618e` | `1f62015f53e28bd18b2d7c8a3ca3326577efc445` | Apache-2.0 |
| `@jsquash/webp@1.5.0` | `jsquash-webp-1.5.0.tgz` | `sha512-KggLoj2MnRSfIqTeKe1EmbljTX2vuV7mh79k89PCL1pyqiDULcPM1L47twxXt0hkb68F70bXiL31MxsuoZtKFw==` | `1e8ce357cde2decf4f880a8c436f8f1529cd3f48` | `8bcd212da8c2be7c9c223e8f222eb3d9574a713b` | Apache-2.0 |
| `@jsquash/resize@2.1.1` | `jsquash-resize-2.1.1.tgz` | `sha512-0R5UL1ZLHUT+carjVikcE1QfA+kfNQ2YamYyGVRmhfh4zttU5EY3bQBGxPIPtY2xIAw1P4Kgyxm2xrceRw1r2w==` | `f245f1945f12c8c73c313ba3ace58b3f2898c4ff` | `da47a2be3b302beb5a5ae164a2ab7aa21a041d90` | Apache-2.0 |

Upstream source: https://github.com/jamsinclair/jSquash at the gitHead of each package
(the four gitHeads are those recorded in the header of `THIRD_PARTY_NOTICES.txt`).

## What the binaries contain (upstream versions and commits)

From the licence inventory (binary evidence cross-checked against the build definitions
at each gitHead):

- **libwebp 1.1.0**, commit `d2e245ea9e959a5a79e1db0ed2085206947e98f2` (`webp_enc.wasm`,
  `webp_dec.wasm`; the embind `version()` returns `0x10100`). BSD-3-Clause plus Google's
  additional patent grant.
- **mozjpeg 3.3.1**, commit `f154ccc091cbc22141cdfd531e5ad1fdc5bc53c7` (`mozjpeg_dec.wasm`;
  built `--without-turbojpeg`). IJG AND Zlib.
- **Emscripten** runtime + embind, LLVM libc++ / libc++abi / compiler-rt, musl, dlmalloc:
  Emscripten **3.1.57** (`mozjpeg_dec`), **3.1.31 - 3.1.36** (`webp_enc`, `webp_dec`).
- **Rust**: `squoosh_png_bg.wasm` built with rustc **1.81.0-nightly**
  (`d8a38b00024cd7156dea4ce8fd8ae113a2745e7f`): png 0.17.10, fdeflate 0.3.3, flate2 1.0.28,
  miniz_oxide 0.7.1, crc32fast 1.3.2, simd-adler32 0.3.7, wasm-bindgen 0.2.89; jSquash
  `packages/png/codec/Cargo.lock` sha-256
  `7d03d3d3be9ab24ab56c7b28f69e5d2e4cee488bef27d5261d2c02ac37eb6205`.
  `squoosh_resize_bg.wasm` built with rustc **1.77.1** (`7cf61ebde7b22796c69757901dd346d0fe70bd97`):
  resize 0.5.5, hashbrown 0.14.3, compiler_builtins 0.1.105 (with its musl-derived libm),
  wasm-bindgen 0.2.92; jSquash `packages/resize/lib/resize/Cargo.lock` sha-256
  `62f0544b9bb58e89193828ba089026ac755bdcecb4da12c32482f17d6ef917a9`.
- **Squoosh** C++ / Rust wrappers at commit `e8d35e0fb66eb16eff6fe8fc773eabcbb7128de3`
  (Apache-2.0), and the jSquash `pre.js` shim in all five `.js` files (Apache-2.0).

Copyleft: NONE evidenced in any of the ten files (no GPL, LGPL, MPL, EPL, CDDL, AGPL,
OSL or EUPL code is linked; the MPL-2.0 `wee_alloc` of upstream Squoosh is absent from
both Cargo.lock files). No source-code offer is required. This is an engineering
inventory, not legal advice.

## Licences and notices

`THIRD_PARTY_NOTICES.txt` is the final notices file of the licence inventory, shipped
byte-exact (sha-256 above) and never edited by hand. It lists the ten files with their
sha-256, the REQUIRED STATEMENTS (the IJG statement above; the libwebp patent grant; the
Sun Microsystems msun notices; the Unicode notice), a component map, and the verbatim
licence texts (Apache-2.0, libwebp BSD-3 + PATENTS, IJG / libjpeg-turbo / zlib, the
Emscripten, LLVM, musl, Arm, dlmalloc, Rust standard library, compiler_builtins and Rust
crate MIT texts). The `LICENSE.codec.md` files inside the npm packages are NOT used:
the `@jsquash/png` one is libwebp's text, and the others are stale or incomplete.

## Not vendored (deliberately)

- the SIMD WebP encoder (`package/codec/enc/webp_enc_simd.*`) and the other package
  entry points and TypeScript wrappers (the function drives the codec glue directly);
- the mozjpeg ENCODER (`package/codec/enc/mozjpeg_enc.*`): it was used once, outside the
  repository, to make the four committed JPEG test fixtures (test/fixtures/README.md);
- `@jsquash/resize`'s `lib/hqx` and `lib/magic-kernel` (licence lineage not reviewed);
- any other codec (AVIF, JPEG XL, QOI, OxiPNG ...).

Re-run the licence inventory before vendoring any of them.
