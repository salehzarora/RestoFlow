# BIZBOT storefront content: local review follow-up 001

Work ID: `BIZBOT-STOREFRONT-CONTENT-CONTRACT-001`.

Status: **LOCAL_CONTENT_IMPLEMENTATION_READY_FOR_REVIEW**. Both scoped corrections and the required local checks pass. This is not final visual approval or authorization to push, merge, deploy or change production.

This follow-up starts at reviewed local commit `0110c2820a92b74b1150f565a749075dfdb2b20a`. It addresses only Dashboard operation ownership and integral-decimal Hero-format offsets. The adopted content contract is unchanged, including its original raw SHA-256 `4aac9a94765eb2ce8614d99996a907c9b8a8ddbef9f60a21d9479683ca85d400`. Earlier implementation, failed attempts, fixtures, receipts and review packages remain preserved.

## Dashboard operation ownership

The real parent `StorefrontSection` and content editor now exchange a typed refresh result: profile/media read success plus the observed profile version and branch. A failed structured read cannot masquerade as a successful acknowledgment. The existing boolean adapter for other parent operations retains its previous successful-absent-profile behavior; content acknowledgment additionally requires a concrete version and branch.

A content save or editorial publication owns the editor and associated parent controls until the confirmed write and required parent/content/media/catalog reads finish. A confirmed write followed by a failed read retains its receipt, locks editing, and offers an explicitly labeled **read-only resume**. It does not prepare another save, issue another publication, or invent another request identity. An uncertain write retains its original immutable attempt and existing exact replay behavior.

The refresh owner handles the parent acknowledgment once. An already verified version/branch acknowledgment does not start a competing `didUpdateWidget` load. Content operations, confirmations and their owned parent-refresh callbacks reject stale completions after disposal or binding replacement. An unresolved original attempt remains held rather than being replayed through a replacement transport or overwritten by a new draft.

Rebuilding auxiliary seams for the same profile repository preserves existing legacy drafts, pending handles and banners. Authoritative version/branch drift remains stale. Replacing a profile transport during an unresolved or active legacy write holds reconciliation; the generic/Home/Featured save pipelines retain their original intent/repository and check the binding after both write and refresh awaits. Old completions cannot refresh or unlock the replacement editor. A retained media-assignment callback also refuses work before accessing a disposed widget.

Catalog loading follows a successful, matching content-and-media read. Failed/denied content reads make no unrelated catalog request. An unowned initial read must also match the current widget version/branch before catalog loading and final acceptance; a delayed older snapshot cannot enable editing after props advance. It exposes an unavailable/read-only reload state. Explicit post-write acknowledgments retain their authoritative returned-version behavior while the parent frame catches up. Successful owned refreshes still require every read and keep controls locked throughout that sequence.

Editorial publication continues to publish a derivative only. The existing recipe deliberately uses wire slot `hero` and variant `w960`; that wire name is **not** a Hero-profile assignment. The tests separately require zero content preparation/writes and zero profile writes. No media publisher, server contract, Hero assignment or automatic content save was added.

## SQL numeric normalization

Only the still-local migration `20261022192530_bizbot_storefront_content_contract_001.sql` changes. After its existing strict JSON-number, integrality, bounds and Unicode-boundary checks, the shape validator converts numeric values to integers and emits canonical integer JSON. The setter's three actual INSERT conversions also use the safe numeric-to-integer path. Values such as `0.0`, `5.0` and `6.0` therefore preserve the selected positions; fractions, invalid types and out-of-range positions remain denied.

The original request fingerprint is calculated from the original document before normalization. The claim/replay order and authorization remain unchanged. Replaying the same original decimal document returns its original version without another mutation. Reusing that identity with a differently represented document remains a fingerprint mismatch, even if the normalized positions would be equivalent.

The tested raw migration SHA-256 is `8ea81169c5aebb6f2590c597e21a4915309e6c988b716d6a26d1333e61a4969a`; the numeric regression file is `0e6ff55747c4f47f905ca5f7a949c0a379416806c518e1f9a9fdca26d679da3e`. The raw CRLF migration/fixture bytes and canonical LF Git blob are distinguished explicitly in the committed-source proof. No historical migration was reformatted or rewritten.

## Verification and evidence disposition

Final source bindings, complete changed files, diff, tool/source hashes and actual execution receipts are in the accompanying follow-up review package. No failed result is relabeled PASS. A test-source correction or Windows line-ending reconciliation is recorded separately from application behavior.

The integrated code commit is `ae9ba2c096a4b0524c2e2e899b3cb458f3b8c7b5`, combining SQL commit `c47b5acbedd6e8c2141cb3f5dc2abf6c07572adf` with the reviewed Dashboard author commit `c352948d2d0695df9d5226f143499f08731e2a4a`. All **612** final Dashboard/test/auxiliary raw hashes match the executed source. Two newly checked-out test files were restored to their exact tested raw line endings only after canonical Git-blob equality; no staged or semantic diff remained. The final local HEAD adds this owned report only and is identified exactly by the package binding/readiness receipt.

Independent source and actual execution reviews conclude **APPROVE**. The operation/binding readback proves **14/14** included regressions from the final full run; it is not a separate execution. The first metadata readback's bad aggregate pin flag and the source-proof precheck's `h`/`Get-History` alias collision remain rejected evidence. Corrected fail-stop readbacks verify the pins; neither instrumentation stop executed application code or SQL.

| Check | Result and scope |
| --- | --- |
| Original Dashboard composition | Actual baseline execution completed all 11 cases: 10 assertion failures and one disposal PASS. Nine failures exposed early parent-editor unlocking; another exposed an old repository completion overwriting replacement-scope state. |
| Initial fixed Dashboard run | All 13 cases completed: 12 PASS and one incorrect test expectation. The unchanged editorial recipe uses `hero`/`w960`; its test incorrectly expected wire `editorial`. Production publication behavior was not changed to satisfy the test. |
| Corrected focused Dashboard run | The corrected same 11-case test reproduced 10 failures and one PASS on original 0110 again; the corrected fixed-source 13-case run then passed 13/13. These executions precede the final related-suite compatibility corrections and are not silently rebound to later bytes. |
| Initial full related Dashboard run | All 19 files and 438 terminal events completed: **436 named tests (430 PASS, six errors/failures) plus two passing lifecycle hooks**. Four failures came from missing read-only reference inputs in the isolated snapshot. Two exposed actual compatibility issues: rebuilt same-profile seams erased a retained legacy draft, and an unavailable content read unnecessarily fetched the catalog. The unchanged assertions remain enabled. Earlier shorthand counts are preserved and clarified, not silently rewritten. |
| Second related Dashboard run | Preserved FAIL/incomplete: six required Dashboard-dependent files did not compile because two original-repository receipt fields remained statically nullable. The correction adds only the explicit non-null assertions after the existing capability guards; successful events in other files do not constitute a passing suite. |
| Third related Dashboard run | All 19 files completed **440 named tests (439 PASS, one timeout) plus two passing lifecycle hooks**. The new retained in-flight callback test incorrectly waited for all animations to settle while intentionally holding the saving spinner. Only that fixture uses bounded pumps now; production animation and its strict draft/read-count/no-write/locked assertions remain unchanged. |
| Fourth related run and analyzer | The complete suite passed **441/441 named tests plus two hooks**, then the seven-file fatal-warning analyzer correctly failed on an unnecessary null assertion, an unused test import and a never-overridden optional fixture parameter. Their narrow cleanup changes no test assertion or intended runtime behavior. The final gate below requires actual execution on the cleaned source, rather than borrowing this earlier PASS. |
| Final Dashboard regressions / related suite / analyzer | **PASS on final cleaned source**: all 19 files completed **441/441 named tests plus two passing lifecycle hooks**, with zero skips, failures or incomplete cases. The operation/binding regressions are a subset of that execution, not an additional count. Seven owned files passed the fatal-info/fatal-warning analyzer with `No issues found!`, child exit 0. All 575 source, 19 test and 18 auxiliary input pins remained unchanged. |
| Original SQL failure | Actual original RPC reproduced `22P02` in the shape validator. A transaction-local diagnostic fixing only the shape conversions then reproduced `22P02` in the untouched INSERT path. Both were rolled back and the original definitions/state verified restored. |
| Fresh local migration fixture | All 172 source migration files applied to a new contained PostgreSQL fixture. Its 171 historical files were byte-identical to the original baseline; only this local migration differed. This is not a hosted migration-history count. |
| SQL regression and compatibility suite | 11 files completed **2,027/2,027** assertions, including 80 new numeric checks and 1,947 existing checks. Child exits, plans and wrapper exit all passed; no skipped/TODO/bailout assertions. Concurrency fixture safeguards remain enabled. |
| SQL first test run | Preserved FAIL: ten numeric assertions passed before the test called anon-only public v4 as `authenticated` and received `42501`; the remaining ten files were NOT_RUN. Only the test role transition was corrected, with no ACL/grant/application change. The fresh complete run above passed. |
| Storefront/CSS/visual evidence | Reuse requires exact Storefront Git-tree equality with reviewed 0110. Prior canonical026: 36 routes, 28/28 assertions, **13,993/14,000** Brotli bytes using the same quality-11 method and original raw exception. Prior Storefront unit 408/408 and visual 38/38 remain earlier executions, not new runs. No CSS or visual scope is added. |
| Prior six-case Dashboard→SQL→v4→Next journey | **PRIOR_ONLY** for the previous source: Dashboard/SQL changed in this follow-up. It is not represented as a new-head end-to-end run. New native composition and SQL checks above prove the two scoped corrections independently. |
| Remote CI, deployment, real merchant/device/physical acceptance | **NOT_RUN / NOT_AUTHORIZED**. Local test success is not visual approval or production readiness. |

The SQL tests verify canonical spellings for all three positions in shape/private/public v4 reads, actual INSERT, integral decimals/exponents/negative zero, null optional tuples, rejected fractions/types/bounds, complete unchanged profile/sidecar/claim/audit state on denial, postwrite rollback, and exact replay. Numeric equality alone is not used to claim canonical integer serialization.

## Ownership, composition and preserved boundaries

| Comparison | Changed paths, including this report |
| --- | ---: |
| Follow-up against reviewed `0110c2820a92b74b1150f565a749075dfdb2b20a` | 10 |
| Cumulative against adopted design `614a4c0144872dea3e70f5a9b3849b76ce88e330` | 68 |
| Git comparison against freshly observed remote main `fe78bbcd4de5befb91c09bd9161380f151fc7c6b` | 88 |

These are distinct comparisons, not 88 new follow-up edits. The follow-up owns seven Dashboard production/test files, the unpublished migration, its new numeric test and this report. The package records the complete path inventories and final clean HEAD. No original worktree or prior review packet is reset or replaced.

The fresh preflight inspected current main, registered worktrees, relevant status and the heads/file sets of printer PRs #314/#315, Claude #362/#363 and ETA/status #366. No follow-up target overlaps those active changes. The existing `public_surface_acl_remediation_001_test.sql` overlap remains disjoint: content v4 and status_v2 additions must both survive later composition. This follow-up does not edit that file or assemble the other branch.

Owned production files are the two Dashboard editor/parent files, their local copy strings, and the one unpublished local migration. Associated focused tests and this separate owned report complete the follow-up. No reserved shared document, checkout/ETA/runtime, POS/KDS/printer, historical migration or approved contract is rewritten.

The local fixture uses a fresh internal Docker network, no host database ports or bind mounts, a loopback-only PostgreSQL listener and public synthetic credentials. No production client configuration, password or endpoint is used. Native Flutter tests use synthetic repositories, an application `HttpOverrides` denial and a cleared/private tool environment with loopback-only proxy exceptions. These are containment measures, not an OS sandbox or proof of zero background connectivity. The earlier incident-prone harness was not reused; its historical connectivity remains **UNKNOWN_UNCHANGED**.

## Resume and remaining limits

After exact-head owner/GPT review, any push/PR, merge or deployment still needs its separate authorization. A future rollout remains backend-first: apply the reviewed exact additive migration through the established exact-version process, independently reconcile schema/history, then deploy explicitly selected v4/editor consumers. Do not edit merchant copy, products or media selections automatically. Never recover a read failure with a new save identity or retry an ambiguous write blindly.

Issue #360 remains open for coordinated final visual/content acceptance, real media binary upload/transformation/publication verification, acceptance of the locally implemented promo/story/category controls and merchant content choices. Other roadmap slices retain their separate ownership. The previously captured reference comparisons classify intentional language/service/full-logo controls, saved merchant copy, product choices and live cart as functional/content adaptations; they do not prove pixel equivalence or owner visual approval. No new screenshots or image edits are needed to fix these two points.

Full authenticated Dashboard onboarding/boot, the natural stale-ISR branch, production migration/deployment and physical acceptance remain unverified by this follow-up. The live status-page continuation stays coordinated with #366. Reserved shared API/domain/security/checklist documentation requires an explicit owner and bounded edit scope before later updates; this report does not replace it.

Ordering, notifications, Cron, production POS v68, pairings, printing authority, BLOCKED revision 1264 and all 625 historical holds receive no production mutation. Their live state is not re-read or certified from these local tests. No production order, call, notification, print replay, APK build or device action occurs.
