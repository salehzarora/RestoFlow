# Background quality fixture

`background-2816.jpg` is a 2816 × 2112 test copy of the camera photograph *Hamburger (9).jpg* by Miansari66, released under CC0 1.0. See the [original provenance](../../../../docs/visual-references/PR380-quality-review/highres/provenance.json).

The original is 4,989,591 bytes, SHA256 `81f08a1cb0256293b862db2a661b76f9f9a54067ae5651469a454f7899b50bb3`. The independent background upload accepts at most 2 MiB. Pillow 12.3.0 saved the original at its full pixel dimensions once as a quality-92 JPEG with 4:2:0 subsampling. The resulting file is 1,463,022 bytes, SHA256 `3e6b8197d0f1e17da8a86b5f0db95330394e11bc30c34b16ca0a076959346d54`. JPEG recompression changes color values and retains the source pixel dimensions.

The isolated Dashboard journey uploads this file unchanged. Its expected c4 and b1 hashes pin both independently encoded outputs against the actual private upload.
