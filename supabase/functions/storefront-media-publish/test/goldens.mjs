// The goldens of recipe `storefront-media-c4` (data only; test/recipe.test.mjs runs them).
//
// Each row: [fixture name (test/fixtures.mjs), variant, sha-256 of the derivative, width,
// height, bytes, the ladder trace one rung per call ("q<quality>:<bytes>", ">cap" when
// that rung was over 512 KiB)]. The bucket is the fixture's.
//
// SPIKE_GOLDENS are values the Q031 spike measured identically on Node 22, Node 24 and
// edge-runtime v1.74.3 for the same pixels. SUITE_GOLDENS are new in this suite (the
// orientation set is built on another base image, plus the metadata, 8 MiP-edge and
// ancillary-bomb cases); they are checked on the same three runtimes by the parity gate
// recorded with the change. A golden never changes without a new recipe id.

export const SPIKE_GOLDENS = Object.freeze([
  ['logo_alpha_2000x1000', 'w480', '776e391a19a102e9e62b07d937aebb652fb4b18fa62ca2627ffadd8facdf8483', 480, 240, 6368, 'q82:6368'],
  ['logo_alpha_2000x1000', 'w960', '864ce8a277f79ba1b0c44a12ee648adb581f826b5ca050d96baaf3a378566220', 960, 480, 12974, 'q82:12974'],
  ['logo_opaque_rgb_1200x600', 'w480', 'fa51ede3e3fe1100cd686d36dfe18036da5be3504e576f2673bbf0194549666e', 480, 240, 2526, 'q82:2526'],
  ['logo_opaque_rgb_1200x600', 'w960', '2e99189ba1e505dc147e4259e6f3fb7669ed7bcba4e0a411cb9d314eecb097e1', 960, 480, 5724, 'q82:5724'],
  ['logo_small_300x150', 'w480', '6a2d7f267cab16dd245fbf392e815ea725d629a6ff3fb7e1248496e352113a13', 300, 150, 3336, 'q82:3336'],
  ['logo_small_300x150', 'w960', '6a2d7f267cab16dd245fbf392e815ea725d629a6ff3fb7e1248496e352113a13', 300, 150, 3336, 'q82:3336'],
  ['logo_portrait_600x1800', 'w480', '9a700786f0b719c02be6db293a5faa95cd44065e7511e1db50c569c8ff0da4c7', 160, 480, 3772, 'q82:3772'],
  ['logo_portrait_600x1800', 'w960', '1fbf521ad66eb6ea647a48cd0cf2c082e246ac92198d069f34d9bdaa3b8e96f6', 320, 960, 8120, 'q82:8120'],
  ['hero_alpha_1600x1200', 'w960', 'a7ab8d0fe8fd0f4906a1f169a846384660b9398f920cf44fccea484df3d6c81d', 960, 720, 18150, 'q82:18150'],
  ['palette_trns_640x320', 'w480', 'db2dadda4592d207a0450653d0306c23b9d0b29e35e75e85d07f6c61f075da9b', 480, 240, 8332, 'q82:8332'],
  ['palette_trns_640x320', 'w960', 'd6579b1f7fa6e2f656b7d2c19f0dc8f72fb787803c5e1f5740c4a259ad742601', 640, 320, 11812, 'q82:11812'],
  ['gray_800x400', 'w480', 'f163c16a42a18f5d06d66d6d26c25b8376b8b43773475c41edd9b78d399791e6', 480, 240, 3376, 'q82:3376'],
  ['gray_800x400', 'w960', '0cc66eac352fadfacfa6c381ed37df59a8bf610c065e604da398b28c3c639631', 800, 400, 5254, 'q82:5254'],
  ['gray_alpha_800x400', 'w480', '575c30de87d89352c3a1481984eadeb70ebef0e06d144d0ec97fd91d45593987', 480, 240, 4570, 'q82:4570'],
  ['gray_alpha_800x400', 'w960', '48d4e8ffd6e3b6fbc81593f673b73c63b659343caf90a17a2e1755226b271c5e', 800, 400, 6484, 'q82:6484'],
  ['rgba16_800x400', 'w480', '2a8925d961a5544d9d5cfc316620eef58e384a8cde5c56a87c13835a1bbd62e5', 480, 240, 6196, 'q82:6196'],
  ['rgba16_800x400', 'w960', '0c481b2d5f89c8122ac5afe102d98dd125a21b86accdac4b35a6ccfb741ab013', 800, 400, 10344, 'q82:10344'],
  ['adam7_rgba_777x555', 'w480', '4bb6e5a3e07071870c7134dcccd2165aea90d3744772288b880e9f3b24e799ad', 480, 343, 8184, 'q82:8184'],
  ['adam7_rgba_777x555', 'w960', '0ac178fbe4846cdd3b059985a9ff71ac5d78a307249a4c002e073b4d1d926b1b', 777, 555, 13182, 'q82:13182'],
  ['rgba_all_opaque_800x400', 'w480', '041d0eea47372f74148f5b3a11da0a0dd487267827fd658935e80f3d65060e53', 480, 240, 2892, 'q82:2892'],
  ['rgba_all_opaque_800x400', 'w960', 'bc2e269ebb15583e4ba198e66ab7b76cb7905fc27505f24b59377250504aa199', 800, 400, 5466, 'q82:5466'],
  ['meta_png_with_ancillary', 'w480', 'e7137db7510d86c622a338644b2d788ef351ea3e3ae4ae2e2fbfe6dc4b922fc6', 480, 240, 6320, 'q82:6320'],
  ['meta_png_with_ancillary', 'w960', '6d8e7dcd56d0aa49bf1bc4408c63f184fb224711547250e0a03e438b2bf03871', 700, 350, 8944, 'q82:8944'],
  ['band_q82', 'w960', '24cbd159ac020b41ff716f414dae9f5946c15cc59b7ea1db80bf0ed8770ade48', 960, 960, 266712, 'q82:266712'],
  ['band_q74', 'w960', '6b922ff452ce3eb9947d5f137c76dea1181103d56ee069952a6975fb7d6489f2', 960, 960, 502350, 'q82:584116>cap q74:502350'],
  ['band_alpha_q50', 'w960', 'e4c6fdce33f4cb515c2b2ec489d546868d602db849b6e30fb2d3b7655aad8a7d', 960, 960, 512688, 'q82:678338>cap q74:596678>cap q66:566916>cap q58:541556>cap q50:512688'],
  ['jpeg_prog_1600x1200', 'w960', 'fc57d56ca68faec05660e62514525c6c8dd6b38ddfb8a7c3b60549c92deafa31', 960, 720, 11098, 'q82:11098'],
  ['jpeg_base_444_1200x900', 'w960', '11d058d34b4635281d2d177e17f3ece5e795727531f77e7cca0942a1d89daa17', 960, 720, 10090, 'q82:10090'],
  ['jpeg_gray_1000x750', 'w960', '99a12a4a5bc5b91d2ffff3ff108549f3da56a3505173dc6285a600fbe5c838ba', 960, 720, 4960, 'q82:4960'],
  ['jpeg_logo_900x450', 'w480', '7ae7054db452fe70f862973d270a7f75512e45e331219cbc967b20f9a4a8a86a', 480, 240, 2198, 'q82:2198'],
  ['jpeg_logo_900x450', 'w960', '810f7b4a095b1820be13ffa101b637effde20bcc3cb2834bc7c9a5164d9ed36c', 900, 450, 9242, 'q82:9242'],
  ['webp_lossy_alpha_900x600', 'w960', '541bd18f82e5fb720cbea75b202fcd3c0a00b72ad8dfb660c8d81b478a25febd', 900, 600, 13792, 'q82:13792'],
  ['webp_lossless_alpha_1200x800', 'w480', '9fb69bb3ee714ea04a74621ddb2947bc4756791badce3f159e1911e071da8d62', 480, 320, 8242, 'q82:8242'],
  ['webp_lossless_alpha_1200x800', 'w960', '5c2b8c7a9b4ee66c248265d91239b07dddff3b7322e0c00fd49f2a2d8e4fe453', 960, 640, 17672, 'q82:17672'],
  ['webp_lossy_opaque_1300x900', 'w960', '03b61c11e83da58903fd774a8e9a4cfb1edb1f5266204fd75ef6c4f4cbc0434c', 960, 665, 9938, 'q82:9938'],
]);

export const SUITE_GOLDENS = Object.freeze([
  // all 8 EXIF orientations of the progressive 4:2:0 fixture (orientation 1 = the fixture's own golden)
  ['jpeg_orient_1', 'w960', 'fc57d56ca68faec05660e62514525c6c8dd6b38ddfb8a7c3b60549c92deafa31', 960, 720, 11098, 'q82:11098'],
  ['jpeg_orient_2', 'w960', 'ed22470730b4f274f764e19caf65108826fdfd7e37ffe325f8177e9fb8709eb0', 960, 720, 10720, 'q82:10720'],
  ['jpeg_orient_3', 'w960', '4441967e22abae265767574c44e05e845ed5831c993a492b30db0d2c3e521cb8', 960, 720, 11148, 'q82:11148'],
  ['jpeg_orient_4', 'w960', 'be72f14bd3a95ed0bef28c7b429c9f2a738cf6ddec1cc9663d3d7c70ee980de9', 960, 720, 11138, 'q82:11138'],
  ['jpeg_orient_5', 'w960', '3981ef6301cf9d4d1530ca3ec610a70cd62e47cd56fa5e101baa20515f5b6364', 720, 960, 11024, 'q82:11024'],
  ['jpeg_orient_6', 'w960', '624dcc936418d55c55e6db5435b413838036bb469e124a5adb8d71ed11141d6f', 720, 960, 11018, 'q82:11018'],
  ['jpeg_orient_7', 'w960', '036f004526a1be4ec651fbaff106768df209aeeec6c5e8a5f84f7ff560c71881', 720, 960, 11080, 'q82:11080'],
  ['jpeg_orient_8', 'w960', '840e5c019c3afff8098e0e777456e2e661d3c46612af33099be5e88130bc90dd', 720, 960, 10628, 'q82:10628'],
  // metadata is stripped: each equals the golden of the same pixels without it
  ['jpeg_exif_gps', 'w480', '7ae7054db452fe70f862973d270a7f75512e45e331219cbc967b20f9a4a8a86a', 480, 240, 2198, 'q82:2198'],
  ['webp_with_metadata', 'w960', '541bd18f82e5fb720cbea75b202fcd3c0a00b72ad8dfb660c8d81b478a25febd', 900, 600, 13792, 'q82:13792'],
  // exactly at the 8 MiP decode cap (4096 x 2048 = 8,388,608 px): derives
  ['png_at_cap_4096x2048', 'w960', '91069b422580182b86dd464e43164ca5d219bc12af0dc1606d5b29ed04a6db2a', 960, 480, 22988, 'q82:22988'],
  // ancillary chunks inflating to 1 GiB never reach the decoder: the same pixels' golden
  ['plain_700x350', 'w480', 'e7137db7510d86c622a338644b2d788ef351ea3e3ae4ae2e2fbfe6dc4b922fc6', 480, 240, 6320, 'q82:6320'],
  ['bomb_ztxt_1gib', 'w480', 'e7137db7510d86c622a338644b2d788ef351ea3e3ae4ae2e2fbfe6dc4b922fc6', 480, 240, 6320, 'q82:6320'],
  ['bomb_itxt_1gib', 'w480', 'e7137db7510d86c622a338644b2d788ef351ea3e3ae4ae2e2fbfe6dc4b922fc6', 480, 240, 6320, 'q82:6320'],
  ['bomb_iccp_1gib', 'w480', 'e7137db7510d86c622a338644b2d788ef351ea3e3ae4ae2e2fbfe6dc4b922fc6', 480, 240, 6320, 'q82:6320'],
]);

export const GOLDENS = Object.freeze([...SPIKE_GOLDENS, ...SUITE_GOLDENS]);

// Every hostile / out-of-contract vector and its typed refusal: [fixture, variant, code, the
// rung it is refused at]. SourceRejected codes come before any decode.
export const REFUSALS = Object.freeze([
  ['band_none', 'w960', 'output_too_large', 4],
  ['entropy_webp_lossless', 'w960', 'output_too_large', 0],
  ['png_over_cap_4096x2049', 'w960', 'too_many_pixels', 0],
  ['png_over_cap_header', 'w480', 'too_many_pixels', 0],
  ['jpeg_over_cap_sof', 'w960', 'too_many_pixels', 0],
  ['jpeg_over_side_sof', 'w960', 'dimensions_too_large', 0],
  ['webp_over_cap_header', 'w960', 'too_many_pixels', 0],
  ['bad_apng', 'w480', 'animated', 0],
  ['bad_webp_animated', 'w960', 'animated', 0],
  ['bad_gif', 'w960', 'unsupported_format', 0],
  ['bad_svg', 'w960', 'unsupported_format', 0],
  ['bad_empty', 'w960', 'empty', 0],
  ['bomb_png_header', 'w480', 'dimensions_too_large', 0],
  ['bad_aspect_3200x100', 'w960', 'aspect_ratio', 0],
  ['bad_jpeg_truncated', 'w960', 'truncated', 0],
  ['bad_jpeg_corrupt_entropy', 'w960', 'decode_warning', 0],
  ['bad_jpeg_cmyk', 'w960', 'unsupported_format', 0],
  ['bomb_idat_tail_256mib', 'w480', 'corrupt', 0],
  ['bad_png_short_idat', 'w480', 'corrupt', 0],
  ['bad_png_junk_after_zlib', 'w480', 'corrupt', 0],
  ['bad_png_trailer_cut', 'w480', 'corrupt', 0],
  ['bad_png_wrong_checksum', 'w480', 'corrupt', 0],
  ['bad_png_raw_too_short', 'w480', 'corrupt', 0],
]);
