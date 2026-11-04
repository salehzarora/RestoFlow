# PR 379 bounded production release

Work ID: BIZBOT-STOREFRONT-CINEMATIC-001B.

The owner authorized this update's fixes, backward-compatible contracts,
testing, reviewed migration, protected merge, deployment and verification on
2026-11-04. This supersedes this workstream's historical no-merge/no-production
and no-compatibility-change boundaries. It does not change the permissions or
scope of any other workstream. Earlier evidence retains its original verdict.

## Source and isolation

At takeover, main was `be579180d43958f716872dac22daf24ba7cc8c26` and
PR 379 had advanced to `84d73363c218735648ab1b778337fb6ffdebfcd0`.
The latter's bounded-control-progress work is preserved. Normal commits only;
no history rewriting, worktree cleanup, protection bypass or unrelated edits.
The temporary source-export workflow is removed before final CI.

## Verified release ordering

1. Complete CSS, real Flutter interaction and compatibility corrections in
   isolated worktrees. Preserve strict decoders, exact legacy read contracts,
   old writer omission semantics and authoritative media retraction checks.
2. Test and independently review the combined candidate: normal validate,
   full pgTAP, real ephemeral Auth/Storage/Edge/Dashboard acceptance, security,
   money, output, live-build and source guards. Pin SHA/tree and final SQL hash.
3. Recheck hosted history/catalog and protected-state baseline. Apply each
   reviewed migration once through the official HTTPS management operation.
   On an ambiguous result, inspect history/catalog read-only before proceeding.
   If the operation assigns a different version, reconcile only the unapplied
   repository filename/references, preserve SQL bytes and rerun affected CI.
4. Deploy and verify only the reviewed media publisher, preserving JWT
   verification, secrets and unrelated functions, before exposing new writers.
5. Merge the verified final head through normal branch protection. Product
   (`resto-flow`) has automatic production alias assignment ON, so the database
   and publisher must be ready before merge. Its Dashboard editor gate is
   compile-time; inspect its exact production setting before the build.
6. Build the Storefront for the production target from the verified source.
   `bizbot-storefront` has automatic custom-domain assignment OFF; preserve it.
   Verify the deployment and then explicitly assign only the three approved
   Storefront aliases. A Preview promotion is not a substitute for a verified
   production-target build.
7. Verify actual aliases, source identities, locale routes, mobile/desktop
   rendering, cache behavior and Dashboard controls. Verify main CI and the
   unchanged protected state. Do not infer authenticated acceptance from an
   HTTP 200/bootstrap, fixture screenshot or SSO redirect.

## Targets and recovery baseline

Team: `team_yynO6ARGc6VsRrAB69hOTTZy` (`salehzaroras-projects`).
Supabase: `oqmevrndtivqxgyvcmwy` (`RestoFlow`). Hosted history had no
`20261102140930` appearance migration at takeover; newest recorded version was
`20261102015942`. Existing content/media-v1 and menu-v4 ACLs were inspected.

Storefront project: `prj_Vc9MCCeYw96l5lYtbn9qbVQ7djap`, root `storefront`.
All three existing aliases pointed to `dpl_Byg9X3w2cbeyshh9yUqH8TohWaYK`:
`menu.bizbot.systems`, `bizbot-storefront.vercel.app`, and
`bizbot-storefront-salehzaroras-projects.vercel.app`.

Product project: `prj_bNpiCDFniNBVFGurUCkaIW3NmwvN`, root repository.
`app.bizbot.systems` pointed to `dpl_E2RdVTwmqJqk3sqUfEQu4UPVSFNy`.
The project's latest-production record differed from the actual alias;
therefore that record alone is not evidence of what is serving.

The publisher was version 42, JWT verification ON, bundle SHA-256
`5eadbdf32825a97e5f1fb998acb747835836e71faacf3df30c8eaca80eda20fb`.
These are baseline observations, not new-release completion claims.

Frontend recovery must preserve compatibility with saved appearance data.
Versioned legacy projections allow old readers to continue safely; media-use
authority must remain on the server. No data deletion, down-migration,
forced logout, cache purge across applications or guessed history repair.

## Safety and evidence

Write acceptance uses isolated fixtures only. No real merchant content edit,
order submission, payment, notification dispatch, printing or ACK. Preserve
the payment/printer branches, SEO noindex policy, device/alert/print settings
and 625 historical holds. Record hashes and counts without exporting private
merchant data or credentials. Preserve each historical failure separately.

The Vercel connector could read Product but returned 404 for Storefront. The
existing authenticated Vercel CLI 65.11.0 independently verified the intended
Storefront and Product projects under the explicit team scope; no access or
protection setting was changed to obtain access.

## Completion state

Release verification is pending. This document is the release procedure and
baseline, not an assertion that deployment or acceptance has succeeded.
