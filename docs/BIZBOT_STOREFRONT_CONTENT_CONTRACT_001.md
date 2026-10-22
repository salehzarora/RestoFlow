# Storefront content contract 001 — implementation contract draft

**Work ID:** `BIZBOT-STOREFRONT-CONTENT-CONTRACT-001`
**Status:** `DRAFT_FOR_CONTRACT_REVIEW — NO IMPLEMENTATION OR ROLLOUT AUTHORITY`
**Owner:** Codex content-contract workstream; independent reviewer: design workstream/reviewer assigned by the owner.
**Owned file in this preparation:** this document only.
**Branch:** `docs/BIZBOT-STOREFRONT-CONTENT-CONTRACT-001-draft`
**Source base:** remote-main `fe78bbcd4de5befb91c09bd9161380f151fc7c6b`. Design integration context is local `695de2ad916bd746e5995c43877770951113132e`; its foundation/history remain separate.
**Adopted input:** unchanged `CONTENT_COMPLETION_PROPOSAL_R3.md`, SHA-256 `4eccad1a5d1241e2f66a9834085b9faea2c6ba636cd7f347ee78a899eb1e0da4`. This is its concrete contract, not an R4 proposal cycle.

The owner authorized drafting this contract, not applying its proposed DDL, creating an RPC, changing a decoder/shared type/editor, updating reserved shared documents, merging, deploying or changing production. SQL signatures and schemas below specify future work; there is no executable migration in this preparation. Existing website ordering, employee/device authentication, customer request identity, acceptance/ETA, notifications, Cron, pricing, preparation, printing and protected historical records are out of scope.

## 1. Source findings and decisions this contract closes

The source evidence is local Git/source inspection, not hosted-state evidence:

- Home copy lives on `public.restaurant_storefront_profiles`; the existing Home writer has complete three-field CAS input, restaurant manager authority and an idempotency ledger. Its limits are 120/180/240 codepoints. It trims a specified Unicode edge-space set and rejects ASCII controls before trimming.
- The legacy private profile read uses `to_jsonb(profile)`. New content is therefore in private sidecars, not additional profile columns that could silently change that old DTO.
- `storefront_menu_v3` wraps v2 once and intersects Featured IDs with the same public menu. Its exact-key decoder cannot accept new fields in place. New content requires v4 alongside unchanged v1/v2/v3.
- Product identity/price/options/availability and product image paths remain those of the existing menu snapshot. Editorial media is a different binding. No new product price, availability or product-name field is editable here.
- The existing private media list decodes `in_use` as only `logo|hero`. Do not append new usage strings to that old array. A new versioned management read describes content usages; old mutation guards still have to protect those references.
- An ordinary category grid takes its column mode from that **category's** setting. An item override changes its own card/media only. Aggregate search/manager-pick grids retain R3's all-resolved-cutout rule. Existing `card_mode=list` wins over both.
- Public server normalization of stale private data is explicit and distinct from wire validation. A malformed v4 wire envelope is an error, never a reason to turn data into null, retry v3 or use fixtures.

Terminology: **W** is a fresh authenticated `app.current_app_user_id()` with `app.actor_rank_in_scope(org, restaurant, null) >= 2`, including covering owner/manager memberships under existing rules. **P** is one existing, non-deleted restaurant Storefront profile and its saved `storefront_branch_id`. A client-supplied branch is an expected identity, never authorization or an alternative publishing scope.

## 2. Text, scalar values and exact Hero selection semantics

### 2.1 Existing text versus newly introduced text

`LegacyHomeText(max)` preserves the current three-field writer exactly: reject U+0000..U+001F and U+007F before trimming; trim only the explicit set **Wspace** below from both edges; blank becomes null; remaining codepoint length must be 1..max. Do not introduce NFC/NFD/NFKC, case folding, whitespace collapse, digit conversion, character replacement or translation. The same decoded Unicode scalar sequence has the same identity. Invalid UTF-16 surrogate sequences are rejected, never repaired.

Wspace is exactly: U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F, U+205F, U+3000, U+FEFF. This is an explicit application set, not an environment-dependent `\s`, locale word-break rule or claim to equal Unicode's `White_Space` property.

`NewPlainText(max)` uses the same edge trim/blank/null behavior and scalar counting, and rejects U+0000..U+001F, U+007F..U+009F, U+2028 and U+2029 anywhere before trimming. It is for the **new** editorial fields/segments only; it does not retroactively change the legacy writer or v3 validation. Text is rendered as escaped text, not parsed HTML/Markdown. ZWJ/ZWNJ, Arabic/Hebrew marks, punctuation and non-BMP symbols are not removed. Merchant text remains its saved language and is bidi-isolated from generic UI labels.

The existing legacy validator does permit interior U+0085/U+2028/U+2029; its trim set does not remove them from the middle. This compatibility is not silently rewritten. Such a legacy headline may still render naturally, but **format metadata for it is rejected** and projection supplies `format:null`; no embedded line separator is used as a new formatting feature. An owner-approved later text-validation change would be a separate contract.

### 2.2 Units, tokens and boundary authority

Let `S` be the exact normalized, non-null saved `hero_headline`, and `C` its Unicode scalar/codepoint sequence. `N=|C| <=120`. Offsets are zero-based half-open **codepoint** offsets, not UTF-16 units, UTF-8 bytes, glyphs, visual RTL positions or grapheme counts.

A token is a maximal nonempty run of codepoints not in Wspace. Punctuation, hyphens, apostrophes, tatweel, combining marks and joined emoji are not independent word delimiters. This contract deliberately uses whitespace tokens, not linguistic word segmentation.

For all format endpoints additionally require a default **extended grapheme cluster** boundary under **Unicode 15.1.0, UAX #29 revision 43, default extended-cluster rules without tailoring or normalization**. This fixed edition is a contract version, not a claim to be the newest Unicode edition. Runtime `Intl.Segmenter`, JavaScript `\p`, PostgreSQL regex character classes and host ICU locale/version must not become the server authority.

Future implementation owns checked-in generated range data from the Unicode 15.1.0 `GraphemeBreakProperty.txt`, `emoji-data.txt` (`Extended_Pictographic`) and `DerivedCoreProperties.txt` (`Indic_Conjunct_Break`), the required Hangul rule computation, and `GraphemeBreakTest.txt` conformance vectors. Record exact download provenance/SHA-256/license in the **future implementation** before generation; no unverified hashes are invented here. Generate identical frozen interval data for a bounded pure PostgreSQL helper and the TS/Flutter Dashboard selection helpers, with the same vector corpus. Dart here means **Dashboard only**, not POS/KDS or receipt/print code. No new extension/package or dynamic data fetch is implicit in this draft. An implementation that cannot prove parity is blocked, rather than using locale `\b` or a weaker mark heuristic.

The SQL helper iterates valid UTF-8 text by scalar using `char_length`/`substr` and UTF-8 `ascii`, with zero-to-one-based conversion explicit; it does not assume PostgreSQL supports ECMAScript Unicode property escapes. On this 120-codepoint input, a bounded deterministic rule evaluator is adequate. Codepoints unassigned in 15.1 use that edition's default property values; a future edition needs a versioned contract change.

### 2.3 Exact format value

`HeroFormatInput = null | {text:string, highlight:null|{start:int,end:int}, break_before:null|int}`. All keys are required and extra keys are rejected. Integer means JSON number with no fraction, in range and safe in the client. `text` must equal S **byte-for-byte after UTF-8 encoding**, not collation equality or canonical equivalence. It is a binding, not a second editable headline.

- `highlight=[s,e)` requires `0<=s<e<=N`, `e-s<=60`, C[s] and C[e-1] non-Wspace, `s=0` or C[s-1] in Wspace, and `e=N` or C[e] in Wspace. Thus it covers one or more complete tokens, preserving all interior spaces. Both s/e must be grapheme boundaries.
- `break_before=b` requires `1<=b<N`, C[b] non-Wspace and C[b-1] in Wspace: it is immediately before a token, after the complete preceding space run. b must be a grapheme boundary. When a highlight exists, `s<b<e` is forbidden; b=s is permitted. No automatic rounding, clamping, range expansion, guessed last word or implicit highlight is allowed.
- Neither setting present (both null) normalizes the entire format to null. A null headline cannot have a format. A null format means natural wrapping with no explicit break/highlight/curve, including the existing tagline/display-name fallback.
- The private binding text, offsets and original headline are stored without a new normalization pass. Any different scalar sequence, including NFC versus NFD spellings or a different number/kind of spaces, is a different binding.

### 2.4 Dashboard UTF-16 selection and rendering

The selection widget operates on the exact normalized S it previews. If raw input would change under the **existing** edge trim, first show/confirm that exact normalized preview; never silently offset a selection made against different raw text. Any text edit invalidates the unsaved selection locally. A single atomic save can still send the new normalized text with newly selected metadata.

Build a prefix map `U[0]=0; U[i+1]=U[i]+(C[i]>0xFFFF?2:1)`. Check surrogate pairing before building C. Convert each logical `selectionStart/selectionEnd` UTF-16 offset by **exact lookup** in U; an offset inside a surrogate pair is invalid. Dart's `TextSelection` code-unit offsets use the same mapping; `runes` must not be used to silently replace malformed units. DOM preview selections, if supported, must flatten only the headline's actual text nodes in logical order, excluding decorative nodes; the flattened text must equal S exactly before mapping. Visual RTL anchor order does not reverse codepoint order. Reversed drag endpoints may be ordered with min/max without changing their boundaries; a collapsed range is invalid for highlight. Validate the resulting whole-token/grapheme rules; show a fixed validation message and send nothing on failure. The server repeats all checks.

Render escaped scalar slices in logical order, with one span for the selected range. Insert an aria-hidden visual `<br>` immediately before b, leaving every original whitespace codepoint in its text slice; no saved `\n`, zero-width character or substituted space is added. Decorative curve/SVG is aria-hidden and contains no headline text. Concatenated descendant **text nodes** must equal S scalar-for-scalar (BR itself contributes no text node). If an authored `aria-label` is needed to avoid a decorative reading duplicate, its literal attribute value is also S. Computed accessible names are tested separately under the platform's accessible-name flat-string whitespace normalization; multiple-space collapse there is not permission to alter saved text, DOM text nodes or the authored label. Verify one non-duplicated heading name, not impossible byte equality to a platform-normalized name. CSS may naturally wrap; do not clip/ellipsis content to force a reference line count. A break-only value does not create a highlight, and whole-image fit is unrelated.

Required examples (offsets are CP unless marked CU):

| Exact S | Valid example | Rejection that must remain explicit |
| --- | --- | --- |
| `طَعْم رائع` | first token [0,5); second [6,10); break6 | splitting between Arabic base and mark, or inside either token |
| `שָׁלוֹם טעים` | first [0,7); second [8,12); break8 | visual RTL positions substituted for logical indices |
| `🍔 טָעִים` | second [2,8), CU[3,9); break CP2/CU3 | CU1 splits 🍔's surrogate pair |
| `👩‍🍳 برجر` | emoji [0,3), CU[0,5); Arabic [4,8), CU[6,10) | CP1/CP2 split a token/cluster; no ZWJ stripping |
| `A` + NBSP + SPACE + `B` | highlight[3,4), break3, both spaces retained | break2 points at whitespace |
| `Cafe` + U+0301 + SPACE + `🍔` | first [0,5), emoji[6,7), N7/CU8 | normalizing to `Café` before validating/storing |
| `A ` + U+0301 + `B` | whole [0,4) if otherwise allowed | apparent token start2 is not a grapheme boundary; do not snap it |

Test Prepend-before-space, variation selectors, regional-indicator pairs and emoji skin tone/ZWJ cases as well. A document containing an unpaired surrogate is malformed input, not a success with replacement text.

## 3. Management document, fields and defaults

The new editor uses one complete replacement document for the **current P branch**. All nine top-level keys are required; omitted/extra keys and incorrect JSON types are invalid. Existing profile/Featured/media/phone/hours writers are not repurposed as partial content writers.

```ts
type Fit = null | 'fill' | 'whole-image';       // null = inherit
type Layout = null | 'standard' | 'cutout';    // null = inherit
type HeroFormat = null | {
  text: string; highlight: null | { start: number; end: number };
  break_before: number | null;
};
type CategoryPromoInput = {
  target: { kind: 'category'; category_id: string };
  kicker: string; title: string; body: string; editorial_media_id: string;
};
type ItemPromoInput = {
  target: { kind: 'item'; item_id: string };
  kicker: string; title: string; body: string;
};
type ContentDocumentV1 = {
  hero_headline: string | null; hero_subline: string | null;
  announcement_text: string | null;
  hero: {
    mode: 'editorial' | 'item'; item_id: string | null; format: HeroFormat;
    eyebrow: string | null; stamp: string | null; footnote: string | null;
  };
  announcement_segments: readonly string[] | null;
  promo: CategoryPromoInput | ItemPromoInput | null;
  story: null | {
    kicker: string; title: string; body: string; editorial_media_id: string;
    facts: readonly string[];
  };
  category_presentation: readonly {
    category_id: string; heading: string | null; blurb: string | null;
    editorial_media_id: string | null; image_fit: Fit; card_layout: Layout;
  }[];
  item_presentation: readonly { item_id: string; image_fit: Fit; card_layout: Layout }[];
};
```

These are proposed names for the dedicated new boundary, not additions to today's shared types. IDs are canonical lowercase UUID strings. Array IDs must be distinct; category/item row input order does not change canonical catalogue order. Full raw JSONB input/order participates in request identity before normalization; object-key order and escape spelling already normalized by JSONB are not claimed to be distinct raw transport bytes.

| Field | Bounds/default/null | Management validation / public behavior |
| --- | --- | --- |
| Three legacy text fields | LegacyHomeText120/180/240; null default | Preserve old behavior; formats can bind only non-null supported headline |
| Hero mode/item | default editorial; item null | item mode requires a currently branch-eligible active item/category, including sold-out; editorial may retain a still-valid eligible selection privately (unused in that mode), but publishes item_id:null |
| Hero format | null | §2; no binding to fallback tagline or synthetic newline |
| Eyebrow/stamp/footnote | NewPlainText60/80/120, null | Null eyebrow preserves current generic welcome/city behavior; absent decorations omitted; no automatic claim text |
| Segments | null; []→null; 1..6 non-null NewPlainText40 strings, sum≤240 | Whole list rejected if any entry invalid; no truncation/filtering/auto-split. Nonempty list takes display priority, never overwrites legacy announcement_text |
| Promo | null or one complete union | kicker/title/body NewPlainText60/120/600 and non-null. Unknown/cross-kind keys refused. Category target requires eligible populated category and owned live w960 media. Item target requires available eligible item with canonical published product image; no editorial_media_id or price key |
| Story | null or complete module | kicker/title/body NewPlainText60/120/600 and owned live w960 editorial media; facts 0..3 non-null NewPlainText80 strings. No platform-generated facts |
| Category rows | [] default; ≤100 distinct eligible category IDs | heading NewPlainText80/null (null→canonical category name at render); blurb NewPlainText120/null; editorial image optional; fit/layout nullable closed enums. All-null metadata is omitted publicly |
| Item rows | [] default; ≤500 distinct eligible item IDs | Storefront-only fit/layout; no price, name, stock, modifier, Featured or POS catalogue update. Both-null metadata is omitted publicly |

The write request has a fixed 256KiB UTF-8 JSONB text-size ceiling before per-field processing. This ceiling is a proposed new-management input bound, not an increase to any existing public/build budget. Counts remain the current public menu's100 categories/500items. A null module disables and clears its new stored fields; an incomplete draft stays local to the unsaved editor. Saved profile defaults require no seed rows or manual per-restaurant activation.

## 4. Proposed private DDL and invariants

No profile column or old public DTO is extended. Proposed new relation names are in the already private `app` schema and must not be added to exposed schemas. Every table carries explicit tenant/restaurant/branch identity, server timestamps and tombstones. Proposed keys:

```sql
-- DDL specification only. Not an executable migration or allocated version.
-- Add these redundant-by-global-id uniqueness targets for same-restaurant FKs:
public.menu_categories UNIQUE (organization_id, restaurant_id, id)
public.menu_items      UNIQUE (organization_id, restaurant_id, id)
public.storefront_media UNIQUE (organization_id, restaurant_id, id)

app.storefront_content_profiles (
  organization_id uuid NOT NULL,
  restaurant_id uuid NOT NULL,
  storefront_branch_id uuid NOT NULL,
  hero_mode text NOT NULL DEFAULT 'editorial',
  hero_item_id uuid NULL,
  headline_format_text text NULL,
  headline_highlight_start integer NULL,
  headline_highlight_end integer NULL,
  headline_break_before integer NULL,
  hero_eyebrow text NULL, hero_stamp text NULL, hero_footnote text NULL,
  announcement_segments text[] NULL,
  promo_kind text NULL, promo_category_id uuid NULL, promo_item_id uuid NULL,
  promo_media_id uuid NULL, promo_kicker text NULL,
  promo_title text NULL, promo_body text NULL,
  story_media_id uuid NULL, story_kicker text NULL,
  story_title text NULL, story_body text NULL, story_facts text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz NULL,
  PRIMARY KEY (organization_id, restaurant_id, storefront_branch_id)
)

app.storefront_category_presentation (
  organization_id uuid NOT NULL, restaurant_id uuid NOT NULL,
  storefront_branch_id uuid NOT NULL, category_id uuid NOT NULL,
  heading text NULL, blurb text NULL, editorial_media_id uuid NULL,
  image_fit text NULL, card_layout text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz NULL,
  PRIMARY KEY (organization_id, restaurant_id, storefront_branch_id, category_id)
)

app.storefront_item_presentation (
  organization_id uuid NOT NULL, restaurant_id uuid NOT NULL,
  storefront_branch_id uuid NOT NULL, item_id uuid NOT NULL,
  image_fit text NULL, card_layout text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz NULL,
  PRIMARY KEY (organization_id, restaurant_id, storefront_branch_id, item_id)
)
```

Each profile-sidecar FK `(org,restaurant)` references the existing profile's unique pair, and `(org,restaurant,branch)` references branches. Each child references its exact content-profile composite key, and its category/item FK is `(org,restaurant,id)`, using the new uniqueness targets. Hero/promo item/category and all editorial media FKs use the same three-part tenant/restaurant identity. All FKs are `ON DELETE RESTRICT`; ordinary catalogue removal remains a tombstone. FK success alone never means published/current-branch/available.

Required CHECKs are exact closed enums; Hero item mode→non-null item; nullable-format either all-null or valid §2 tuple; text caps/normalized edges/control rules; segments one-dimensional, lower bound1, no nulls,1..6,sum≤240; story facts analogous0..3; and complete promo/story nullability groups. Promo null means every promo field null. Category promo means category+media non-null and item null; item promo means item non-null and category/media null. Story disabled means all copy/media null and facts empty; enabled requires all copy/media non-null. Fit/layout null is inherit, not literal `'inherit'` stored text. Pure helpers return a non-null boolean (malformed tuples return false), contain no table lookup in CHECKs, and cannot let SQL NULL bypass validation; scope/eligibility is enforced by FKs, the RPC and projection.

All three tables: `ENABLE ROW LEVEL SECURITY; FORCE ROW LEVEL SECURITY`; revoke all table/sequence privileges from `PUBLIC, anon, authenticated, service_role`. Add explicit SELECT/INSERT/UPDATE/DELETE deny policies for `authenticated` for defense in depth, matching the RPC-only pattern. No direct client policy, view, private-ID listing or service-role grant is added. The migration owner owns the narrow privileged functions. Do not grant new `USAGE app` to anon/service_role or grant internal helpers to app roles.

Owned pure helper signatures (no app-role EXECUTE):

```sql
app.storefront_content_text_v1(text, integer, boolean) returns boolean IMMUTABLE
-- boolean identifies legacy versus new domain; exact behavior §2, no normalization output
app.storefront_content_grapheme_boundaries_v1(text) returns integer[] IMMUTABLE
-- frozen Unicode15.1 interval/rule implementation; offsets0..N, no locale property calls
app.storefront_content_hero_format_valid_v1(text, integer, integer, integer)
  returns boolean IMMUTABLE
-- §2 whole-token/grapheme rules; null tuple accepted, never silently repaired
```

Generated Unicode constants/data are private immutable function-owned literals (or an equally immutable checked-in generated representation), not writable configuration or public data. No database extension or language installation is implied.

## 5. One management revision, atomic writes and legacy compatibility

Proposed new signatures:

```sql
public.get_restaurant_storefront_content_v1(
  p_organization_id uuid, p_restaurant_id uuid) returns jsonb
public.set_restaurant_storefront_content_v1(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_expected_version integer, p_expected_storefront_branch_id uuid,
  p_document jsonb) returns jsonb
```

Public wrappers are `SECURITY INVOKER SET search_path=''` and call corresponding `app` implementations, `SECURITY DEFINER SET search_path=''`, fully qualified and owned by the existing privileged migration owner. Revoke EXECUTE from `PUBLIC, anon, authenticated, service_role` first, then grant only the app/public wrapper signatures required by the existing authenticated RPC pattern to `authenticated`. No grant to anon/service_role. Internals outside those wrappers remain uncallable by app roles. Get is STABLE; Set is VOLATILE. Tenant authority is never inferred from user-editable metadata or a browser item ID.

There is **one revision authority**: existing profile `version`, not independent sidecar counters. The read is manager-only and returns exactly `{ok:true,entity:'restaurant_storefront_content',restaurant_id,version,storefront_branch_id,document,warnings}` for an existing profile. No profile→`not_found`, not an implicit creation. Warnings contain only fixed field paths and enums (`relation_unavailable`, `media_unavailable`, `legacy_value_invalid`), never foreign raw IDs or secret/private source details. It returns the same server-normalized editable document for current P; missing/tombstoned sidecars give defaults with the three real legacy text values. No write occurs during a read.

Set sequence, one SQL transaction:

1. Resolve authenticated actor; missing required IDs/version or no covering membership raises42501 before a profile/idempotency disclosure. Rank1 gets the established audited `permission_denied` shape. Scope is restaurant-wide W, not a device UUID allowlist.
2. Lock restaurant, then existing profile, then current content-profile/children in deterministic category/item/media-ID order. Media publication/retraction uses the same hierarchy. Recheck W **after lock waits**. Derive the current P branch from the locked profile, but defer expected-branch comparison until after the exact stored replay check. No caller can redirect scope.
3. Fingerprint actor/operation/new request identity with full raw JSONB document + org/restaurant/expected-version/expected-branch before normalization. Call the existing management idempotency helpers with distinct operation `set_restaurant_storefront_content_v1`. Check a matching stored replay only after fresh authority/locks; replay returns its original result and never reapplies changes or new catalogue/time data. Reusing a request ID with different operation/fingerprint raises42501 from the existing helper; do not rename that conflict to `stale_request` (the latter is the separate media-lifecycle readback contract).
4. For a **new, non-replayed request**, compare expected branch first (`branch_conflict` on mismatch), then require exact profile version. A stored, freshly authorized exact replay returns its original result even if the profile branch/version subsequently changed; it never restores old branch settings or revalidates/reapplies old targets. Validate the new request's complete schema/types/bounds, Unicode tuple, all same-restaurant/current-branch relationships and published editorial media; don't disclose foreign existence. A new valid profile may be unpublished while its content is configured, but configuration does not publish catalogue/media/profile.
5. Prepare the complete result; claim the request through the existing ledger **inside the transaction**. Update legacy copy first and then the current content sidecar/child rows, using §5.1's trigger ordering. Missing previous child rows are tombstoned, not hard-deleted. Update profile.version exactly once to old+1 even for a new non-replay no-op, matching existing writer behavior. Do not touch Featured IDs, phone/hours/theme/card_mode/motion/order gates or catalogue values.
6. Append the established management audit (old/new content snapshot, actor and P branch; no customer data), including fixed reason for format invalidation. A simulated failure after text/sidecar/audit work must roll back **text, sidecars, profile version, audit and idempotency claim**. Returning `{ok:false}` after partial mutation is not an acceptable rollback implementation.

Success exact keys: `{ok:true,idempotent_replay:boolean,entity:'restaurant_storefront_content',restaurant_id,version,slug,is_published}`. Do not return a public authority or immutable full document in the success result. Client refreshes the management read and reconciles the exact request on uncertain transport outcomes using existing bounded identity handling; never invent a new request to retry a potentially committed save.

The existing public `menu_version` includes profile.version. A content save therefore advances that key exactly as existing Home/profile saves do. Existing cart-version invalidation/requote behavior is unchanged; this contract does not promise a cart survives a merchant content edit, nor alter storage or silently carry lines to another menu version. Tests must cover old open tabs, refreshed new-version documents and immutable already-submitted requests. If retaining carts across content-only changes becomes a requirement, review a separate menu-version contract rather than quietly decoupling this CAS.

Typed failures use `{ok:false,error,entity}` plus only the documented fields: `version_conflict` adds current `restaurant_id,version,slug,is_published`; `branch_conflict` adds current version but no guessed branch; `invalid` adds fixed `reason,field`; `permission_denied` and `not_found` keep current conventions. Invalid reason enums: `document_not_object`, `document_too_large`, `unknown_field`, `missing_field`, `text_invalid`, `headline_format_invalid`, `segments_invalid`, `target_invalid`, `media_invalid`, `presentation_invalid`, `duplicate_id`. UUID parsing/type mismatch is `invalid`, never an uncaught cast that leaks a row. Operational lock/statement timeout or connection loss is an uncertain transport result, not proof of rollback/commit; no raw SQL or input is logged to customers.

### 5.1 All old writers clear stale Hero formatting atomically

A new **AFTER UPDATE** trigger on `public.restaurant_storefront_profiles` compares `convert_to(OLD.hero_headline,'UTF8') IS DISTINCT FROM convert_to(NEW.hero_headline,'UTF8')`. This is exact-byte identity, not potentially nondeterministic text-collation equality. Any changed normalized headline atomically sets every saved format binding/offset tuple for that restaurant to null and appends the fixed invalidation audit. No extra profile version increment, recursive profile update, implicit commit, UI callback or asynchronous cleanup. No change→retain valid formatting. Updates only to subline/announcement leave valid headline formatting intact.

Its owned signature is `app.invalidate_storefront_content_v1() RETURNS trigger`, `VOLATILE SECURITY DEFINER SET search_path=''`, with app-role EXECUTE revoked. The row trigger is `AFTER UPDATE OF hero_headline, storefront_branch_id, deleted_at ... FOR EACH ROW`; its body checks actual old/new values and returns NEW. A version-only/unrelated update or an unchanged value performs no invalidation. A missing sidecar is a no-op, not implicit settings creation.

The new Set updates the legacy headline **before** writing newly validated format metadata to the current branch sidecar, all in the same transaction. The trigger clears old values first; the new validated tuple may then replace them. Thus an explicit combined save succeeds; any later error fully rolls back both operations. Existing Home/generic profile writers keep their signatures, input check order, response keys, CAS and ledger operation names. Their old replay does not re-clear/reapply content. Direct owner-level SQL writes, if ever separately authorized, are covered by the same trigger rather than being a hidden bypass.

On `storefront_branch_id` change the trigger tombstones active content settings of the old branch (including child settings), clears Hero tuples for all branches, and records `storefront_branch_changed`. It does not copy products/category targets to a new branch or resurrect a previously tombstoned branch configuration. The new branch reads defaults until a fresh complete manager save validates it. Previous settings remain in tombstones/audit, not destroyed. Legacy profile text/editorial Hero slot keeps its existing behavior. On profile tombstone, all new settings become non-public through P; the new sidecars are tombstoned in the same transaction.

### 5.2 Writer/read compatibility matrix

| Caller | After future additive migration | Required proof |
| --- | --- | --- |
| Old profile/Home editor | Same signature/DTO and unchanged existing validation; changed headline clears format, same headline retains it | Old success/error/replay tests plus injected post-trigger failure rollback |
| Old Featured editor | Same set/get fields and semantics; global CAS detects concurrent new content save | No Featured overwrite/lost update |
| Old v1/v2/v3 public reader/open tab | Identical old envelopes, grants and behaviour; no new keys in place | Original strict decoder fixtures and served live-shaped payload tests |
| New content editor | New v1 private RPCs; complete document plus profile version/expected branch | W/role/tenant/branch/CAS/Unicode/unknown-outcome tests |
| New v4 Storefront | Only v4 new decoder/adapter on success; canonical order APIs unchanged | No downgrade on missing RPC, timeout, malformed body or unexpected keys |

## 6. One public snapshot, normalization and strict v4 boundary

Proposed `public.storefront_menu_v4(p_slug text) RETURNS jsonb`, STABLE, `SECURITY DEFINER SET search_path=''`, existing migration owner. Revoke EXECUTE from PUBLIC/anon/authenticated/service_role, grant exactly anon+service_role as v3; do not grant authenticated or private-schema access. It is the same narrow enumerative public read pattern, subject to explicit future RLS/security signoff.

Call `storefront_menu_v3(p_slug)` **exactly once**. On its failure, return that unchanged failure envelope. On success, re-establish the same admitted P identity inside the same STABLE statement snapshot and attach only `content_v1`. No second menu/pricing/stock algorithm, unrelated browser lookup or additional public table access. All organizations/restaurants/branches/profile admission, catalogue caps and v1/v2/v3 behaviours remain untouched. New settings alter presentation, never order admission or employee authority.

Define I as IDs of served menu items with a category in that exact menu; C as served categories having at least one such item. Item/category relations may only reference I/C, not saved private IDs, slugs guessed from names, first catalogue entries or another snapshot. Canonical name, integer price including0, group/options/from-price flag, availability and product image come directly from that same base envelope.

Success is exact v3 keys plus required `content_v1`. Required inner keys:

```ts
type PublicContentV1 = {
  schema: 1;
  hero: {
    mode: 'editorial' | 'item'; item_id: string | null; format: HeroFormat;
    eyebrow: string | null; stamp: string | null; footnote: string | null;
  };
  announcement_segments: readonly string[] | null;
  promo: null | {
    kind: 'category'; category_id: string; kicker: string; title: string;
    body: string; image_url: string;
  } | { kind: 'item'; item_id: string; kicker: string; title: string; body: string };
  story: null | {
    kicker: string; title: string; body: string; image_url: string;
    facts: readonly string[];
  };
  category_presentation: readonly {
    category_id: string; heading: string | null; blurb: string | null;
    image_url: string | null; image_fit: Fit; card_layout: Layout;
  }[];
  item_presentation: readonly { item_id: string; image_fit: Fit; card_layout: Layout }[];
};
```

No org/restaurant/branch/device UUID, raw media UUID/source key/storage snapshot, private object URL, employee state, new price, order capability or credential is public. Category/item IDs above already exist in the same base menu. Wire editorial `image_url` values are **relative paths only**, matching the existing `/storage/v1/object/public/storefront-media/<32lowerhex>/<64lowerhex>.webp` grammar. The adapter attaches the current approved configured media origin; even a same-origin absolute URL is not a replacement wire shape. Item images are never duplicated/copied into a new editorial field. Arrays preserve base-menu order, contain distinct eligible IDs and obey100/500 bounds. An absent sidecar produces the complete default object, not a missing key: editorial Hero/item_id null/format null/decorations null; segments/promo/story null; empty presentation arrays.

### 6.1 Server projection normalization — not decoder repair

| Private saved state becoming stale/invalid | Server result |
| --- | --- |
| Format text/offsets invalid or not byte-bound to current headline | `format:null`; keep exact legacy headline. Never clamp or rebind to fallback |
| Hero editorial mode | public editorial/item_id:null; legacy editorial Hero URL only, never product captions |
| Hero item missing/deleted/unpublished/out-of-branch | editorial/item_id:null together; omit every product fact/action; use only existing editorial Hero image/copy |
| Hero valid but sold-out | keep valid item relation/canonical facts; disabled unavailable opener |
| Hero valid item photo absent/revoked | keep valid relation/facts with neutral no-photo treatment; **no editorial or other-product substitution** |
| Promo invalid target/copy/image, or item sold-out/no image | whole promo null; no stale target ID, price or photo leaks |
| Category promo target valid but no served members | whole promo null |
| Story missing/invalid required copy/media/facts | whole story null; no guessed facts |
| New optional text/enum invalid | that optional value null; old text retained; no arbitrary truncation |
| Segments invalid as a list | whole list null; existing announcement_text stays intact |
| Category/item relationship not in C/I | omit that row entirely; do not serialize saved private IDs |
| Category editorial media invalid only | image_url:null; retain other independently valid row fields |

These are deliberate server output rules for private stored drift/lifecycle states. They do not authorize saving malformed new input and do not sanitize malformed **wire** objects in the browser. Base v3 errors remain base errors; v4 does not silently repair an invalid base-menu payload.

### 6.2 Strict new decoder

New `decodeContentV1.ts` and `decodeStorefrontMenuV4` require exact top-level/nested keys and explicit nulls; reject missing/extra keys, wrong types, non-integer offsets, invalid strings/enums, unknown schema, malformed/cross-kind targets, duplicate IDs, invalid cardinality/media path, foreign/nonserved targets, sold-out/no-photo item promo, invalid Hero tuples or format.text unequal to home_content.hero_headline. Item mode requires a served item; editorial requires public item_id:null. A category promo requires populated C. A nullable field being malformed is **not** null. Throw the existing fixed-category `EnvelopeError` without logging raw customer/merchant payloads or private details.

The decoder may strip `content_v1` into a local copy and delegate the remaining object to unchanged v3 decoding, then validate/rejoin the new content. It must never call a v3 **endpoint** as a fallback. No decoder/adaptor filtering of bad rows, catch→fixture, hidden `mediaUrl()` null repair of malformed v4 URLs, or automatic retry on another version. Adaptation only accepts a validated v4 envelope. Existing source/server-only environment and output credential guards remain intact.

Client/server source selection for a new deployment is explicit v4 at build/runtime composition, not per-tenant manual activation or error-driven negotiation. Existing v3 bundles and open tabs continue on v3. Existing framework ISR may retain an already cached good document under its current error policy; that is not a second request to downgrade. A never-cached failure remains the existing framework error/not-found policy, not an invented menu.

## 7. Rendering, layout and real action contract

### 7.1 Hero and media authority

Editorial mode uses the current profile Hero slot and current missing-photo fallback. Item mode uses only `I[item_id]` for image/name/current price/from-price/groups/availability and existing ProductSheet opener. Editorial marketing headline/subline remain independent saved copy. No product ID→name heuristic, picture recognition, product stamp inference or free-standing editable price. If target is invalid, switch the **whole product-specific presentation** back to editorial; never retain a product caption over another product's photo. Valid target with no image stays visibly no-photo.

Product-image fit resolves `item.image_fit ?? category.image_fit ?? 'fill'`. Card layout resolves `item.card_layout ?? category.card_layout ?? 'standard'`. Null is inherit. Fill keeps intended crop. Whole-image requires contain+center, full source aspect within the role's image box, no inherited negative offset/translation/scale/mask crop on normal/mobile/hover. Verify all product-media consumers: Home cards, search, ProductSheet, cart/preview, product-mode Hero and item promo. No fallback photo or asset editing is implied.

Editorial Hero/Story/category Promo/category-representative images keep their editorial role framing and do **not** inherit product fit/layout. Logos stay complete/contain. Product fit must not change the media slot, canonical source association or an ordering decision.

### 7.2 Deterministic columns, ordinary categories and aggregate grids

Apply precedence in this order:

1. `restaurant.card_mode='list'`: list at every width. An item cutout changes only that row/card's appearance, never creates a grid.
2. Ordinary category grid: `category.card_layout ?? 'standard'` determines **all section columns**, independently of item overrides. Thus one cutout item in a standard category does not turn the section into4columns; one standard item in a cutout category does not reduce its4columns. Each item still resolves its own card/fit.
3. Search and aggregate manager-pick/Featured grids: use cutout columns iff the rendered result is nonempty and **every** item resolves cutout; otherwise standard columns. This explicitly applies to these aggregate surfaces even when a result happens to contain one category. It retains R3's mixed-category rule without relying on first item, result count, names or IDs. Preserve existing filtering/order and never create a ranking claim. Empty means existing empty state.

| CSS viewport | Cutout columns | Standard columns |
| --- | ---:| ---:|
| w>900 | 4 | 3 |
| 650<w<=900 | 3 | 3 |
| w<=650 | 2 | 2 |

900 and650 belong to their lower band. Test650/651/900/901 plus320/390/430/768/1440. The server supplies settings, not CSS arbitrary strings; the UI implements this closed algorithm. `card_mode`, canonical item/category order and existing click/keyboard/focus behavior remain authoritative.

### 7.3 Promo, Story, categories and announcement

- Category promo CTA selects its target category, leaves aggregate search/picks, scrolls its real section with sticky offset and focuses the category heading. It has generic translated browse text and no product price. Item promo delegates to the current ProductSheet opener; it does not add to cart/submit. Valid module CTA must be enabled; remove the old unconditional disabled binding. Pointer/Enter/Space, required choices, Back/Forward/Escape and focus restoration are acceptance requirements.
- Category editorial heading overrides only the rendered section heading; canonical rail/catalogue name/order/icon/ID do not change. Null heading uses canonical name; absent blurb omitted; representative media absent uses the current icon fallback.
- Story is complete-or-null. Merchant facts remain their own statements; no invented platform sales/statistics or automatic translation.
- Valid nonempty announcement segments are rendered in saved order with decorative separators between segments, not appended to the legacy text. Null/clear uses the complete legacy announcement_text, or no strip when that is null. Editing old text does not clear active segments. No auto-split, hidden words, clipping to a fixed line, or forced tiny type; permit wrapping. Retain service-state visibility, current-tab/slug dismissal, keyboard/touch behavior and reduced-motion.

## 8. Media ownership, publication, replacement and retraction

New editorial references require a live `storefront_media` w960 derivative from the same org+restaurant and the existing permitted private source buckets. Use the existing stage→upload→finalize publisher recipe, size/type/hash/provenance checks and fixed public content-addressed path. Selecting a published editorial derivative does not change existing `hero_media_id`. Publishing a new category/Promo/Story derivative must not assign the Hero slot as a side effect: extend the Dashboard's typed publish target to **publish-only editorial**, then save the selected content reference separately by CAS. No arbitrary URL input, new bucket, public private-original key or general HTML uploader.

Product-mode images use the exact canonical w480 item image already projected by v3, with its current item/branch/source-generation checks. Do not use a convenient w960/editorial image as a substitute or create a weaker second item-image read.

Future migration narrowly extends existing `app.finalize_storefront_media` to repoint active current-branch content editorial refs atomically on a valid same-source replacement, preserving stage/finalize contracts and every existing source/snapshot/object check. Lock restaurant→profile→content refs→media deterministically, recheck W after waits, retract old then publish/repoint new in one transaction, increment global profile.version **once total** if any existing/new pointer moved, and audit the replacement. Existing success keys including profile_version remain; a replay never repoints a second time.

Existing `app.retract_storefront_media` must also refuse active new editorial refs as `media_in_use` before any mutation, with fresh authorization/lock checks. Its old `slots` field remains the **old logo/hero subset**; for content-only use it is an empty list, not a fabricated Hero label or a new enum. Old clients therefore get a safe generic refusal, not unknown enum data or a successful destructive action. Managers clear/replace the content reference through the new editor, then retract explicitly. Tombstoned/inactive prior-branch settings are not public in-use pointers. No automatic retraction, hard deletion, CDN purge or unrelated profile change occurs.

New management read:

```sql
public.list_storefront_content_media_v1(p_organization_id uuid,p_restaurant_id uuid)
  returns jsonb
-- Same W floor as existing media list, same wrapper/app privilege pattern.
```

It returns exactly `{ok:true,entity:'storefront_content_media',restaurant_id,version,media_prefix,media}`; rows are existing legacy media-row keys plus `content_in_use`, a closed list of `{kind:'promo'}`, `{kind:'story'}` or `{kind:'category',category_id}` for current-branch active settings. Keep the old `in_use` values logo/hero only. At most200 eligible w960 editorial rows, stable newest-first/id order; private source details remain manager-only as in the existing list. `list_storefront_media` signature/keys/enums and item-image list stay unchanged. New Dashboard uses the new read for explanations; old readers continue to decode.

If an object/media is retracted/replaced outside the supported manager path by separately authorized administration, v4 still revalidates published state/current source and outputs null/omits the affected module as §6.1 specifies. Retraction stops new references on the next successful projection; current route cache is60s revalidate with the existing possible300s stale allowance, and an already downloaded/public-CDN object cannot be recalled. This contract does not promise immediate erasure or change cache policy. A revoked/foreign media ID is never serialized in place of a public path.

## 9. Error and compatibility acceptance matrix

The following are **required future tests**, not results of this drafting task:

| Layer | Required cases |
| --- | --- |
| Auth/tenancy | anonymous/no identity, rank0/cross-org/cross-restaurant→42501 without disclosure; rank1 denied+audit; covering manager/owner allowed; removal while lock waits; no platform-admin bypass/new device allowlist |
| ACL/RLS | forced RLS/all four deny policies/no app-role table access; exact RPC grants; anon cannot call management/app helpers; authenticated cannot call public v4 if current v3 forbids it; no new app-schema usage |
| Revision/atomicity | one global CAS, old and new writers concurrent; request replay/raw JSONB mismatch; missing profile; branch change; rollback after injected failure after legacy text and sidecar updates, including audit+ledger absence; deadlock/timeout/connection-loss readback without fabricated outcome |
| Unicode | all §2 vectors; limits counted CP; same text different normalization remains different; every UTF16 offset mapping; invalid surrogate; grapheme conformance corpus; whitespace runs/NBSP/FEFF; no silent range/break correction; old/new writer format clear/retain; DOM text nodes/authored label equal S; computed accessible name follows platform flat-string normalization without duplicate reading |
| Server normalization | corrupt/stale optional private values→explicit null/module omission; foreign/unpublished/deleted/soldout/no-photo relations differ; no raw private IDs/source snapshots; no writes in projection |
| Strict wire boundary | missing/extra fields, unknown schema/enums, wrong null/type/offsets, bad URI, stale format binding, duplicate/nonserved IDs, wrong target union, malformed segments all throw; assert zero v3/fixture fallback requests |
| Media | stage/finalize ownership, source generation, unpublished/revoked/deleted object; category/Story/Promo no Hero assignment; replacement global version exactly once; old list still decodes; old retract protects new refs; versioned list shows usage; no new storage grants |
| UI bindings | real Dashboard save→fresh v4→actual Home for every control; actual eligible enabled promo CTA; category scroll/focus, ProductSheet options/history/cart unchanged; all AR/HE/EN and two isolated restaurants; no automatic merchant claims, cart add, order submission or telephone call |
| Layout | ordinary category determines columns despite opposite item overrides; aggregate mixed/all-cutout/empty; list priority; fill/whole-image every role; no persistent crop/zoom; stated breakpoints/RTL/focus/reduced-motion |
| Compatibility | old v1/v2/v3 DTO exact-key tests unchanged; old editor/open-tab reads/writes and new/old concurrency; old cached HTML permitted without runtime downgrade; unchanged checkout payload/phone/idempotency/price/options/acceptance/ETA/notifications/printing |
| Build/quality | focused SQL/concurrency/RLS, Dashboard, TS/Storefront tests; real local browser screenshots/computed styles; original all36route/output28 gates and CSS<=14,000, unchanged raw exception/compressor; secret/source/output guards, independent review and actual CI after separately authorized push |

Do not create production test orders or print jobs to prove this contract. Later live merchant save/display acceptance is owner-operated and separately scoped. No result above is claimed passed now; current design motion/CSS/capture verification is a separate Work ID.

## 10. Ownership, coordination and shared documents

Fresh pre-edit overlap preflight is part of the design followup003 evidence. It reports zero of the82 named PR-reserved paths overlapping this **new document**; PR363 advanced to89da0a02bc3131960f8e5f7a1bb24d97afc0c0d7 and remains reserved, #366 remains separate. Local primary `main`556136f1 is stale historical#319; do not mistake it for remote-mainfe78 or alter that checkout. Contract worktree is separately rooted atfe78. Refresh actual heads/dirty paths again before future implementation; this table grants no simultaneous edit reservation.

| Future owned surface | Owner and exact scope before editing |
| --- | --- |
| This new contract document | Content-contract001; independent local review now. No shared canonical document edit |
| New additive migration, scoped SQL/concurrency tests, Unicode generated SQL constants | Content-contract001 implementation only after contract approval; allocate a migration with approved tooling then, never invent/rewrite an existing version now |
| Existing profile-trigger/media app functions | Same future migration owner; preserve existing signatures/DTOs. Coordinate media publisher owner and all fresh overlapping PRs; no unrelated migration rewrite |
| `storefront/src/source/live/decodeContentV1.ts` (new), `client.ts`, `adapter.ts`, `storefront/src/source/types.ts`; new source tests | Content-contract001 decoder/adapter implementation, only after approval; no change to v3 exact-key boundaries |
| `apps/dashboard/lib/src/storefront/storefront_content_{models,repository,section}.dart` (new), narrow `storefront_section.dart` insertion and typed publish-only target | Content-contract001 Dashboard owner; existing profile/Home/Featured/contact remain independent and version-compatible |
| Existing `storefront_models.dart`, media publisher/list files | Future content editor/media owner, narrow new versioned DTO/target hunks only; old in_use enum remains untouched |
| New Unicode TS/Dart utility + shared conformance fixtures | Content-contract001; project-local utility, no shared package. Generator/data SHA provenance reviewed before implementation |
| Home `{Home,HomeParts,HomeChrome,MenuParts}.tsx`, `home.module.css`, product/search/cart media consumers | Future content UI owner after current design Work ID freezes/handsoff; do not overlap root's reduced-motion fix or rebase away its evidence |
| `storefront/src/i18n/storefront.ts`, `storefront/messages/storefront.{ar,he,en}.json`, Dashboard l10n | Future coordinated storefront-content key namespace/hunks; do not reserve/edit entire shared translation files implicitly |
| `docs/API_CONTRACT.md` | Canonical API owner, future reviewed addendum only: new v4 and managementv1 contracts/grants/DTOs. **Not edited now** |
| `docs/DOMAIN_MODEL.md`, `docs/SECURITY_AND_THREAT_MODEL.md` | Respective schema/security owners, future exact new-sidecar/trigger/ACL/RLS/media sections. **Not edited now** |
| `docs/DECISIONS.md`, `docs/OPEN_QUESTIONS.md` | Owner/planning authority records approved choices later; do not allocate or freeze a guessed decision ID. **Not edited now** |
| `docs/IMPLEMENTATION_CHECKLIST.md`, shared session tracker | Backlog/session owner schedules an approved #360 addendum/handoff; own resume evidence does not replace the canonical backlog. **Not edited now** |

Excluded: Claude payment/card/POS work and its reserved shared documents; printer#314/#315; #366's `LiveRequestRuntime.tsx`, orders contract/controller/transport, orders i18n, acceptance ETA/receipt-phone implementation; device/APK/release ledgers, notification Edge/worker/Cron, checkout/payment/order/print authority. If future UI binding needs #366's live status page, agree file/hunk and integration order with that owner instead of taking it here.

## 11. Future activation order, rollback and resume

1. Owner/GPT review this exact document, independent security/database/Unicode review and explicit contract adoption. Resolve any requested corrections in this document; do not create an R4 content-proposal loop or implement from an unreviewed draft.
2. Refresh source/worktree/PR ownership; authorize a distinct implementation scope. Implement and locally test additive private schema/helpers/trigger/new RPC/v4 and versioned media safeguards first, old consumers still active. No historical backfill or merchant content selection.
3. After reviewed exact source, actual CI/RLS signoff and separate production authorization, install/independently verify migration and old/new ACL/schema/read contracts with writes disabled in new UI. Preserve existing ordering/notifications/Cron/printing gates.
4. Deploy serverv4 availability **before** the Storefront consumer. Deploy reviewed v4 decoder/adapter/UI using the separately controlled menu project with existing defaults; failed v4 never downgrades. Verify published merchant copy/phone/Featured and old open tabs remain correct.
5. Deploy Dashboard new typed controls/publish-only editorial target only after backend and real UI binding exist. Existing restaurants have defaults; no per-restaurant backend activation, seed content or static ID lists. Owner chooses/saves their own content with CAS and verifies display after normal cache refresh.
6. Complete controlled multi-restaurant/role/branch/media and real keyboard/visual checks under #360. Content/control completion is separate from order/physical acceptance and does not close the whole roadmap by CI alone.

Emergency rollback is stop new editor writes, preserve exact evidence/content/audit, and explicitly deploy the reviewed prior v3 consumer/editor if separately authorized. This is an operator rollback, **not runtime fallback**. Additive sidecars/history are retained; do not delete successfully saved content or migration history, weaken grants, revert media ownership guards, change merchant values, or replay orders/print jobs. Reconcile ambiguous writes by manager read and the original request identity; never blindly submit a replacement or repair a ledger.

Resume record: current preparation writes this one owned document and external evidence only. R3/previous design commits and all imagery remain unchanged. Next decision is review/adoption of this exact contract, then separately ticketed implementation. Remaining #360 work stays tracked: data-driven Hero/promo/story/category/media controls and owner visual acceptance, full journey/multi-restaurant verification, coordinated #366 ETA/status work and compatible receipt-phone display. None is dropped or declared complete here.

## 12. References and verification limits

Local controlling sources: `AGENTS.md`, authoritative `docs/AGENT_WORKFLOW.md`; migrations `20260923120000_storefront_read_001.sql`, `20260925100000_storefront_publish_001.sql`, `20261013140622_storefront_publish_002_item_images.sql`, `20261021161242_bizbot_storefront_home_content_001.sql`, `20261021223048_bizbot_storefront_featured_items_001.sql`; current strict live decoders/client/adapter; Dashboard private media/slot models. Full R3 evidence map/proposal are preserved at their original hashes; these observations do not query a hosted project.

Public standards inspected read-only for this drafting:

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security): grants and RLS are independent controls. This draft retains the repository's stronger RPC-only forced-RLS boundary.
- [Supabase changelog](https://supabase.com/changelog): HTML fallback inspected because `changelog.md` could not be fetched by the tool. The observed TLS deprecation concerns future old HTTP clients; no dependency/transport/config change is made or claimed necessary by this draft.
- [Unicode UAX#29 revision43, Unicode15.1](https://www.unicode.org/reports/tr29/tr29-43.html): pinned grapheme-boundary reference. Latest-edition detection does not silently change this contract.
- [ECMAScript text processing](https://tc39.es/ecma262/multipage/text-processing.html#sec-string.prototype.codepointat): strings/code-unit versus codepoint distinction; the explicit prefix map here is the application protocol.
- [PostgreSQL17 string functions](https://www.postgresql.org/docs/17/functions-string.html): the bounded SQL implementation uses the UTF-8 scalar semantics, not JavaScript regex/property syntax.
- [W3C Accessible Name1.1 §4.3.1](https://www.w3.org/TR/accname-1.1/#terminology): computed names are flat strings with specified whitespace handling; literal merchant text preservation is a separate DOM/storage requirement.

Unicode data-file content/hash acquisition and generator parity remain required **implementation evidence**, not claims of downloads or tests performed now. This contract provides their exact version/source/semantics and acceptance gate; it does not fabricate those hashes. No Supabase CLI, database connection/query, migration, RPC deployment, package install, device action, order, print or production mutation was performed to draft it.
