# Optional visual regression review

Build and run the existing local preview first (`npm run build`, then
`node scripts/dev.mjs 8796`). With an existing Playwright installation and Chrome:

```powershell
node review/refinement-browser-check.mjs '<Playwright host package.json>' '<Chrome executable>' '<absolute evidence directory>'
```

The driver adds no dependency to the site. It accepts only localhost URLs,
intercepts every lead request, and uses synthetic form values. It never sends
mail. Generated evidence belongs outside the source checkout and must be
reviewed before sharing. Source images are the already-approved local captures.

Coverage: the 16 requested AR/EN/HE viewport cases, short desktop, physical
printer-port geometry, caption placement, business-overlay coverage, intrinsic
hardware support, lazy image decoding, console errors, 12 no-JS/reduced cases,
forward/reverse/fast scroll, restored geometry, resize, live reduced motion,
keyboard menu, tabs/thumbnails, user-started video, enlarged text/CSS zoom and
mocked lead validation/success. Reports distinguish CSS zoom stress from actual
browser-UI zoom and preserve actual measurements when a run fails.

Cold-load measurements use fresh browser contexts and a load + 2000ms window,
before deliberately loading below-fold images for visual QA. The local server
does not compress HTTP: measured transfer/encoded/decoded values are separate
from computed bundle gzip sizes. They are not production network guarantees.

Screenshots and JSON record the source HEAD and dirty paths. When reviewing an
uncommitted candidate, record its eventual commit and verify its source-file
hashes match the captured candidate. No screenshots or recordings are shipped
as marketing assets.
