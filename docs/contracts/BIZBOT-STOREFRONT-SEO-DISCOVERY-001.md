# BIZBOT-STOREFRONT-SEO-DISCOVERY-001

Backend read slice only. Contract frozen before implementation on 2026-10-31,
from base `8ee132d5ef214fd92afc14f0ba2735059a643e77`.
Input proposal SHA-256:
`a2f136eee54a3d9e51f11eae851198c1e5e14fc205c86b0e39750f541f6c1a52`.
The owner's read-slice authorization takes precedence over the proposal.

## Frozen interfaces

- Private `app.storefront_seo_read_v1(p_slug text, p_bounded boolean DEFAULT false)`.
  The flag is private discovery work control, never a public policy input.
- Public `public.storefront_seo_page_v1(p_slug text) RETURNS jsonb`.
- Public `public.storefront_seo_discovery_v1(p_after_slug text DEFAULT NULL,
  p_limit integer DEFAULT 10, p_partition integer DEFAULT NULL) RETURNS jsonb`.
- Private `app.storefront_seo_release_gate_v1`: exactly one policy-v1 row,
  positive revision, Boolean enabled default false. Migration seeds only that
  disabled platform row, never restaurant consent. No application-role access,
  no setter, forced RLS. Missing, invalid or inaccessible state is UNKNOWN.
- Private immutable partition helper, no application-role execution, implements
  SHA-256 of the validated ASCII slug, first byte modulo 16.

Successful page envelope has exactly `ok:true`, `schema:1`, `menu` (the existing
v4 object unchanged), and `seo:{eligible,evaluated_at,valid_until}`.
`eligible` is true only when gate ON, explicit consent ON, exact live published
ancestry/profile/selected branch and actual v4 success agree. It is false for
known OFF or missing consent, and null for SEO-only uncertainty. **Only literal
true permits future indexing.** Null preserves a valid ordinary menu; it does
not mean consent=false. This nullable refinement resolves the proposal's
otherwise ambiguous SEO-only outage handling. No private reason is exposed.

Unknown/unpublished/deleted/suspended scope or malformed page slug returns
`{ok:false,schema:1,error:"not_found"}` without identifying the reason.
Existing v4 payload-limit refusal maps to `payload_limit`. An actual menu or
publication dependency failure maps to `unavailable`, without old menu fallback.
All failures contain only `ok`, `schema`, `error`; no exception detail or input
echo. Infrastructure cancellation can instead terminate the RPC with PostgreSQL
SQLSTATE 57014: the consumer must treat every transport/database failure as
unavailable, never successful empty data.

Discovery success has exactly `ok:true,schema:1,items:[{path}],next_after_slug,
has_more,evaluated_at,valid_until`. Paths are `/s/{slug}/menu`, resolved only
against `https://menu.bizbot.systems`. No UUIDs, counts, reasons, menu content,
locale variants, hreflang, lastmod, receipts or customer references. Errors use
the three-field failure envelope with `invalid_request`, `unavailable`, or
`budget_unavailable`, and contain no partial items or cursor.

## Bounds and continuation

Slug/cursor: 1–63 lowercase ASCII letters/digits/hyphens, no edge hyphen.
Null cursor starts traversal; null limit is invalid; limit 1–25 (default 10).
Partition is null or 0–15. Ordering and exclusive keyset comparison use C
collation. Cursor is the last **returned eligible** slug, never an excluded
candidate. Keep partition fixed within a traversal. It is a routing partition,
not authority. Each request recomputes current eligibility; there is no shared
snapshot between requests. Unchanged eligible slugs are not skipped/duplicated;
insertions or renames behind a cursor require a subsequent crawl.

At most 64 consented, live published candidates are evaluated. One extra cheap
candidate witnesses scan exhaustion, and one extra eligible result witnesses
has_more. Before invoking v4, bounded counts stop at 101 categories, 501 items,
2001 modifiers, 8001 options using the reader's live/branch/ancestry filters.
Oversized candidates are excluded before heavy menu aggregation. v4 is invoked
once per surviving candidate, at most 64 times. Partial pages are returned only
when end-of-candidates is proven; otherwise insufficient budget returns
budget_unavailable without partial output. Discovery JSON UTF-8 is capped at
16,384 bytes. Menu size and page availability retain the existing v4 contract.
Indexes support published C-order/keyset and partition scans; LIMIT bounds
candidate evaluation, not physical index pages or the total cost of a join.

## Snapshot, deadline and errors

Wrappers/helper are STABLE and all nested public-menu readers are STABLE. Their
reads use the invoking READ COMMITTED SQL statement snapshot, including profile, v4 menu,
consent and release gate. They do not acquire mutation locks or write anything.
`evaluated_at=statement_timestamp()` and `valid_until=evaluated_at+10 seconds`;
neither is renewed at completion. An in-flight old snapshot can finish after a
withdrawal. New READ COMMITTED statements after a committed withdrawal read the
new state. REPEATABLE READ/SERIALIZABLE are refused as unavailable: a retained
transaction snapshot must not receive a new statement-start freshness lease.
Consumers must reject expired or untrustworthy timing before emitting an
indexable document. No persistent positive cache is introduced.

Function configuration requests a 2-second statement timeout and 500ms lock
timeout. PostgREST >=12.2 hoists function settings; SET inside an already running
PostgreSQL function alone is not a timer proof. Direct SQL callers must set a
transaction/session deadline before the statement. Hosted API timeout behavior
is a separate rollout verification gate; no global timeouts are changed here.
Known gate OFF permits successful empty discovery. Missing/malformed/unavailable
gate or consent dependency while ON returns unavailable, never fabricated zero.
Only v4 not_found/payload_limit are definitive exclusions; unexpected errors fail
discovery. A valid menu survives SEO-only failure with eligible:null.

## Privileges and preserved boundaries

Functions have empty search_path and qualified relations/functions. Explicitly
revoke default PUBLIC/anon/authenticated/service_role privileges, including
table/column grants inherited from default privileges; public wrappers grant
EXECUTE to anon only. Private helpers/gate remain owner-only; FORCE RLS and no
permissive policies. No new client service credentials. Existing v4/consent-v1
definitions, ACLs, fixed-false fields and receipts remain untouched.

No Next.js/Dashboard integration, robots/noindex/canonical change, sitemap,
rate limiter, gate activation, publication write, notification/printing/device
operation, or new indexing permission is included. Public wrappers are not an
indexing release. All existing serving restrictions remain in place.

## Later release dependencies

Separate publication/CI approval; exact additive hosted application with gate
OFF and independent ACL/schema verification; API deadline/rate/cost verification;
Next.js request-scoped single result plus blocking metadata and withdrawal-safe
no-store delivery; bounded sitemap assembly; versioned honest Dashboard status
without changing v1 meanings; authenticated merchant acceptance and explicit
owner approval of indexing activation/withdrawal acceptance. **The <=10-second
end-to-end withdrawal target remains UNVERIFIED by this backend-only slice.**

## Local evidence and integration gate (2026-10-31)

Migration: `20261031121622_bizbot_storefront_seo_discovery_001.sql`.
SHA-256: `0b90d0aed87209bb25ff211397d4e701bb75f996538949f30fb6add61f07b651`.
Only this migration, two feature-owned SQL tests and this contract are changed.
The local working HEAD is the base; no commit/publication is authorized.

| Surface | PUBLIC | anon | authenticated | service_role |
| --- | --- | --- | --- | --- |
| Two new public read wrappers | none | EXECUTE | none | none |
| Two new private helpers | none | none | none | none |
| Private release gate, including columns | none | none | none | none |
| Existing v4 and consent-v1 functions | unchanged | unchanged | unchanged | unchanged |

Gate FORCE RLS has no permissive policy. Effective permissions were also
verified after applying with deliberately permissive synthetic owner defaults.
All 555 pre-existing app/public function definitions, owners and ACLs match the
pre-migration fixture. Existing authenticated profile editing, unpublishing and
publishing work with the new indexes.

Final guarded local results: 193/193 behavioral, 33/33 concurrency and 147/147
existing consent-v1 assertions PASS. Nine real anonymous PostgREST 14.13 cases
PASS, including cancellation around two seconds and SEO-only dependency
failure preserving the ordinary menu. Timeout transport tests use a temporary
fault only in a disposable database and restore the exact v4 definition.
Measured real v4 calls: 64 on budget exhaustion; 26 for 25 results plus an
eligible witness. Dense 1,000/sparse 20-of-1,000 query plans were measured:
underlying scans can exceed 65 rows, so this is an evaluation bound, not a
claim that all physical work is limited to 65 index entries. No hosted API or
large-catalog/rate-limit acceptance is claimed.

Initial harness-only defects (legacy fingerprint query planning and synthetic
branch cleanup dependencies) were corrected; their earlier logs are retained,
not relabeled PASS. No implementation behavior was changed to pass them.

**Prior-slice publication integration was BLOCKED.** The then-unchanged shared
`supabase/tests/public_surface_acl_remediation_001_test.sql` has 59 PASS and
three actual FAIL (A1, A5, D1): its exact allowlist predates the two new anonymous
readers. The file is actively reserved by Claude's payment work. Smallest
coordinated amendment: add exactly `storefront_seo_page_v1(text)` and
`storefront_seo_discovery_v1(text,integer,integer)` to its literal allowlist,
retain the equality assertions, and preserve Claude's separate six service-only
payment exclusions in D1 when integrating streams. No shared file was edited,
no failing assertion disabled, and no full-CI success is claimed. That narrow
coordination/verification precedes a separate Draft PR publication decision.

Independent backend/security and SEO/integration reviews approve this scoped
implementation; neither approval waives the shared guard integration gate or
the separate hosted/frontend/merchant/indexing release requirements.

## Narrow shared ACL integration (owner-authorized local exception)

Status: **LOCAL_ACL_INTEGRATION_REVIEWED**. The preceding 59/3 outcome remains
historical evidence; it is not relabeled PASS. The owner subsequently authorized
only this worktree's guard copy and narrow feature-owned test/document updates.
No migration, runtime function, grant or live state was changed.

Fresh remote main and local HEAD remain `8ee132d5ef214fd92afc14f0ba2735059a643e77`.
The four reviewed files matched their prior manifest before editing. Main guard
Git blob: `5bf379c5e1c1d4b1f6e56ee1c15fb301b5cb4dba`; LF-byte SHA-256:
`bc795868f2392c890aaad66022823afb4483abaa4e7f07630c396d9fcaa96b56`.
The checkout's pre-edit raw SHA-256 was
`aebaf87a745eb69bc2f074909e3588fffe008bf73afcd945a71fcb9c1a32875c`:
the difference was only 431 CRLF sequences. Both forms are recorded explicitly.

The original failed exact sets differed ONLY by:

```text
storefront_seo_page_v1(text)
storefront_seo_discovery_v1(text,integer,integer)
```

A1 saw these two additional effective anonymous readers; A5 saw these two
additional public DEFINER functions; D1 saw the same two additionally denied to
authenticated. No expected identity was missing and no other extra identity
existed. Both functions are postgres-owned, STABLE, SECURITY DEFINER, anon-only;
PUBLIC/authenticated/service_role have no EXECUTE. Private helper/table/column
denials and gate FORCE RLS were freshly verified in the disposable schema.

The guard change adds exactly those two full signatures to its literal
`sec001_allowlist`, plus three adjacent wording corrections. All 62 assertions,
catalog/equality predicates, app boundary, PUBLIC checks, table/sequence/RLS and
default-privilege tests, legacy readers and existing D1 exclusions are retained.
Post-change raw SHA-256:
`171b961b19a47711500a7161f342cf7ab556aa330959b6b601a68b64c907f932`.

Final local batch: shared guard 62/62 PASS without SKIP/TODO; original 193
behavioral assertions plus 12 appended negative controls = 205/205 PASS;
concurrency 33/33; compatibility 147/147; API 9/9. Five separate rollback-only
executions of the actual 62-test guard detected their deliberately injected
faults: unexpected anonymous identity (A1/D1), unexpected public DEFINER (A5),
PUBLIC EXECUTE (A1/A4), unapproved same-name overload (A1), and a private helper
grant (A6). A clean post-rollback guard run again passed 62/62. These controlled
failures prove detection; they are not production faults or skipped assertions.
The appended feature tests also verify private helpers/gate remain inaccessible.

### Payment-workstream handoff

Fresh payment PR #370 remains Draft at
`54b19ab58ce72a2fa9a43860e31181a08222b254`, with guard blob
`10b6b06582355a9da140ac2b026a1d2386477296`.
Claude 001F `d7ce9990...` and its correction `bd281721...` were clean with no
uncommitted guard delta at preflight. Neither worktree was edited. Payment's
separate D1-only hunk retains these exact service-only exclusions:

```text
card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)
card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)
card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)
card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)
card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)
card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)
```

Whoever integrates second must retain BOTH the two SEO literal allowlist entries
AND those six payment D1 entries, apply the corresponding reviewed migrations in
a separate disposable snapshot and rerun the exact guard. Payment functions
must never enter the anonymous/DEFINER allowlist; neither stream may copy over
the other's whole file or hide missing expected signatures. The combined set
logic was independently reviewed. **Combined-payment-schema executable
acceptance: NOT_RUN.** Textual compatibility does not establish that acceptance.

Source scope is five files: the original four plus the shared guard. Additional
edits inside that scope are only this handoff/closure appendix and the 12
feature-owned negative assertions. The race test and migration bytes remain
unchanged. Fresh independent security review approves the exact exception and
its controls; prior approvals were not reused as approval of this guard change.
Git publication/remote CI and every hosted/frontend/indexing release action
still require their separate authorization. The public withdrawal target
remains UNVERIFIED; all merchant/device/printing boundaries are unchanged.
