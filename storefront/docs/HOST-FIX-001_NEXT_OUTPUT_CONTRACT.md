# STOREFRONT-HOST-FIX-001 — the Vercel Next.js output contract (decision record)

**Decision.** `storefront/vercel.json` declares **no** `outputDirectory`. The Next.js
preset locates the framework build directory (`.next`) itself, reads its
`routes-manifest.json`, detects `output: 'export'` and serves the `out/` export. An
explicit `outputDirectory` in `vercel.json` overrides that lookup for the deployment —
it is a deployment-level override, not a project-settings default — and the accepted
value `out` made Vercel's Next.js builder fail with `NEXT_NO_ROUTES_MANIFEST` after a
fully successful `next build` (deployment `dpl_BbyQcLBPT7d7aXRndXr4k6qKm9vm`,
2026-09-23). Any explicit value (`out`, `.next`, `dist`, `null`) is therefore outside
the contract and the shared deployment filter fails safe to BUILD on it.

**What does not change.** `next.config.mjs` (`output: 'export'`, pinned by
`STOREFRONT_CONFIG_HASH`, unchanged) still writes the static export to `out/`; every
output/budget test keeps reading `out/`; `framework: nextjs`, `npm ci`, `npm run build`,
Node 24, Root Directory `storefront`, `cleanUrls`, `trailingSlash`, the header set and
the `ignoreCommand` are unchanged; no dependency, CSP or UI change; the export is
byte-equivalent to the accepted UI-001 export (229 files, 4,107,823 B, 0 differing
after build-ID normalisation).

**Three things, kept distinct.**

1. `next.config.mjs` `output: 'export'` produces the `out/` artifact (intended; kept).
2. The Vercel Next.js preset consumes Next build metadata from `.next` and then handles
   the export; the Output Directory is not the export directory. Locally, the cached
   official builder (`vercel build`, CLI 59.19.0, `@vercel/next` 12.0.2) reproduces
   this: old form → `NEXT_NO_ROUTES_MANIFEST`; corrected form with the framework-default
   setting → `Build completed successfully`, Build Output v3 with the 229 export files
   byte-identical under `static/`, no functions, the committed headers in
   `config.json`, "detected `next export`".
3. A project-level Output Directory override (`out`, written at project creation from
   the old source) **survives** the removal of the repository override: with the
   corrected source and that project setting the builder fails identically. Before any
   hosted retry the `bizbot-storefront` project's Output Directory must be reset to
   the framework default (`outputDirectory: null` — a separately authorised
   single-field change; see the HOST-FIX-001 evidence `FUTURE_PROVIDER_DELTA.md`).

**Shared-engine consequence.** `tools/vercel/ignore-build.mjs` now refuses the
`outputDirectory` key on the storefront config (previously it required exactly `out`).
The engine file is `shared_engine` for every selector, so publishing this fix builds the
two linked projects (`resto-flow`, `bizbot-site`) on the branch push and on the merge;
a baseline that still carries the old form makes the storefront selector BUILD with
`unsupported_build_contract` (guard at the baseline) until a corrected-form deployment
exists. Recorded, not suppressed.

**Files.** `storefront/vercel.json` (one line removed); `storefront/tests/contract.test.mjs`
(successor expectation: the key must be absent); `tools/vercel/ignore-build.mjs`
(contract + comment only); `tools/vercel/ignore-build.test.mjs` (fixture, refusal
controls for `out`, `.next`, `dist`, `null`, a different framework, ignoreCommand
variants, and the old-to-new transition); `docs/DEPLOYMENT.md` (the one sentence that
pinned `out`). Evidence: `worktrees/output/storefront-host-fix-001-<UTC>/`.
