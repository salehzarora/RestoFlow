# Actual product sources

BIZBOT-STOREFRONT-VISUAL-PARITY-001. These four files are copies of the owner's
existing public product photographs, observed in the current Storefront on
2026-11-04 and downloaded read-only for the authorized nonproduction review.
They are existing published `storefront-media-c4/w480` derivatives, **not private
originals** and not synthetic alpha fixtures. The task authorizes local product
processing and isolated CI copies; this is not a claim of a general asset license.

| File | Dimensions | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| burger.webp | 360×480 | 27156 | 5bcfca1884ff3d0cb5dea89a4553664a4f2c205c65081781918e2e75b8ead994 |
| fries-cup.webp | 480×480 | 46612 | 698cee5bb2f9281e3be57d78adbc100685b1a8d04969f8248fe6ebe12609106e |
| platter.webp | 360×480 | 33756 | f3bb4d896712f0acb9dc1359495e5c2aa3ca0025afff4b39e7fa8bc0118ad2b6 |
| drink.webp | 480×480 | 14562 | 30a7eaf7427448ad96994e0e69da4bf5a603812c1bf2d4db1f4ec6a0aedb891e |

The first three are opaque and run through the actual worker. The cola already
has alpha, so the correct behavior is byte-identical Original without loading
model weights. This proves three segmentation executions plus the transparent
bypass; it does not prove four successful opaque-photo cutouts.

The CI test uploads these through the normal menu image panel, automatically
prepares a local candidate, reviews light/dark backgrounds, explicitly publishes,
and reads actual local service state and both public variants. It also switches
the burger back to Original and verifies the original source snapshot survives.
The test is guarded to run only in the disposable Actions service stack. It does
not write production, change the real merchant, or send images to a model host.

Visual acceptance remains separate: U2Net's current raw soft mask removes part
of the burger's dark plate, leaves bottles in the fries/platter scenes, and makes
parts of the cup/plate translucent. Those examples require Original or a better
validated matte; passing the service journey alone is not a visual-quality pass.

## Genuine high-resolution original

The fifth pass uses `burger-highres.jpg`, the unchanged 2816×2112 camera JPEG
from [Miansari66's “Hamburger (9).jpg”](https://commons.wikimedia.org/wiki/File:Hamburger_(9).jpg),
released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
It is 4,989,591 bytes and 5,947,392 pixels, within the unchanged 5 MiB / 8 MiP
limits. SHA-256: `81f08a1cb0256293b862db2a661b76f9f9a54067ae5651469a454f7899b50bb3`.
Full source revision, download URL, EXIF orientation and reuse details are in
[the provenance receipt](../../../../docs/visual-references/PR380-quality-review/highres/provenance.json).

The isolated Actions review build explicitly enables `SF_PRODUCT_CUTOUT_REVIEW`.
It publishes the experimental candidate and then Original, verifies both actual
480×360 and 960×720 public resources, and records mobile/desktop DPR 1/2/3
`currentSrc`, response hash, painted geometry, fit, blur and native-pixel cap.
This does not enable removal in the default application or assert a clean mask.
The genuine source is not a substituted version of the owner's four photos.
