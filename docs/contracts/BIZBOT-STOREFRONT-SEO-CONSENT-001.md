# BIZBOT-STOREFRONT-SEO-CONSENT-001 contract

This owner-requested additive contract records explicit restaurant-level consent
for a future indexing release. It does not enable indexing. Global crawler
restrictions, canonical URLs, publication, orders, alerts, printing and anonymous
`storefront_menu_v4` remain governed by their existing contracts.

## Storage and default

`app.restaurant_storefront_seo_consent_v1` has one optional row per exact
`(organization_id, restaurant_id)`, enforced by a composite primary key and a
same-organization restaurant foreign key with `ON DELETE RESTRICT`. It records
`consent_enabled` (column default `false`), a positive bigint revision, the server
actor and timestamp of the last state change, and creation time.

A missing row projects `consent_enabled:false`, `revision:"0"`,
`provisioned:false`, and null last-change actor/time. The migration does not seed
any rows or infer consent from publication. This applies equally to existing and
new restaurants. The first explicit decision, including an explicit OFF, creates
revision 1. A later unchanged decision preserves the revision and last-change
actor/time; its independent request receipt still records the deciding actor,
decision and server request timestamp.

Consent is independent of the branch selected for the Storefront, `is_published`,
opening hours, temporary pause, Pickup and order/notification/printing settings.
Suspension and tombstones preserve the state and receipt history. Current RPCs
refuse unavailable organizations/restaurants; no consent is deleted automatically.

`app.storefront_seo_consent_requests_v1` is a feature-owned append-only ledger,
keyed by `(actor_app_user_id, client_request_id)`. It stores exact tenant and
restaurant scope, the operation, a SHA-256 fingerprint of the complete intent,
the result and server timestamp. It records confirmed success, unchanged success
and CAS refusal. It does not share locks or identity with legacy management,
notification or printing request ledgers.

Both tables enable and force RLS, have explicit deny policies for all four row
commands, and revoke every table privilege from PUBLIC, anon, authenticated and
service_role. The ledger rejects UPDATE, DELETE and TRUNCATE through the existing
append-only guard. Business access is exclusively through authorized RPCs.

## Identity and authority

The server requires `auth.uid()` and resolves the actor with
`app.current_app_user_id()`. A GUC-only identity, unlinked JWT, platform-admin
grant, device or PIN capability does not authorize consent.

Existing role evidence is in
`20260619173112_rf015_identity_membership_rls.sql` (six tenant roles and composite
scope FKs) and `20260626090000_rf112_membership_settings_management.sql`
(`role_rank` and `actor_rank_in_scope`). The established ranking is
`org_owner(4) > restaurant_owner(3) > manager(2) > cashier/kitchen_staff/accountant(1)`.
Coverage is downward-only: an organization-wide membership covers its restaurants;
a restaurant membership covers that restaurant; a branch membership cannot cover
the restaurant-level `(organization, restaurant, NULL)` scope.

GET requires a covering active, non-tombstoned membership of rank 2 or higher.
Managers can read with `can_manage:false`. SET and RECONCILE require rank 3 or
higher: `org_owner` or `restaurant_owner` covering the exact restaurant. A manager
does not acquire authority from the ordinary Storefront writer, whose rank-2
gate is intentionally not reused. Platform administration grants no tenant role.

Missing, foreign, deleted or suspended parents and absent covering membership
return `not_found` without current state or receipt data. A covering member with
insufficient rank receives `permission_denied`; a SET denial emits
`settings.storefront.seo_consent.denied` after ancestry has been validated.
Missing authentication raises SQLSTATE `42501`. Malformed required input returns
`invalid_request`. All public wrappers are SECURITY INVOKER with a locked empty
search path. The scoped implementations use the established private SECURITY
DEFINER pattern. Only authenticated receives EXECUTE on the three entrypoints;
all private helpers revoke EXECUTE from every application role.

## Versioned wire API

All responses use `entity:"storefront_seo_consent"`. Function parameters are:

```text
get_storefront_seo_consent_v1(
  p_organization_id uuid, p_restaurant_id uuid)

set_storefront_seo_consent_v1(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_expected_revision bigint, p_consent_enabled boolean)

reconcile_storefront_seo_consent_v1(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_expected_revision bigint, p_consent_enabled boolean)
```

An authorized GET returns:

```json
{
  "ok": true,
  "entity": "storefront_seo_consent",
  "organization_id": "uuid",
  "restaurant_id": "uuid",
  "provisioned": false,
  "consent_enabled": false,
  "revision": "0",
  "can_manage": true,
  "indexing_active": false,
  "effective_indexing_eligible": false,
  "updated_at": null,
  "updated_by_app_user_id": null
}
```

Revision is always a decimal string to prevent bigint rounding in clients.
`updated_at` is the server timestamp of the last state change, encoded by
PostgreSQL as an ISO timestamp. No caller actor or timestamp is accepted.

SET requires a non-null request UUID, non-negative expected revision and non-null
boolean. Success returns the complete state plus `client_request_id`,
`idempotent_replay` and `no_change`. New state changes increment revision by one.
Exact replay returns the original receipt before evaluating current CAS; it never
restores the original state after a later decision. Reusing an actor's UUID with
any different scope, revision or boolean returns `request_conflict`.

A new stale intent returns `ok:false,error:"revision_conflict"`, echoed
organization/restaurant/request identity, `idempotent_replay:false` and `current`
containing the complete authorized state. This refusal is recorded for consistent
replay and recovery. Authorization failures and invalid requests do not consume
the UUID. A state-changing success emits one append-only
`settings.storefront.seo_consent.updated` audit with actor, server timestamp,
before/after state and request identity. No-change saves emit no duplicate
mutation event; their append-only receipt records the decision.

RECONCILE echoes entity and organization/restaurant scope and returns
`mutation_state:"committed"|"refused"|"not_recorded"`, `result` (the original
receipt with `idempotent_replay:true`, or null), and the separate complete `current`
state. It reads receipts and state only: it never claims a request, changes
consent or emits an audit event. A past successful receipt may describe ON while
current consent is OFF; the client must use current authoritative readback.

`not_recorded` is a point-in-time answer, not proof that a delayed original HTTP
request can never arrive. An explicit retry must retain the exact original UUID,
scope, expected revision and boolean. The UI must keep unresolved intent bound
to its originating restaurant and prevent a replacement draft/request until the
uncertainty is safely resolved.

## Concurrency and atomicity

GET stabilizes organization and restaurant rows with SHARE locks and covering
memberships in ascending membership ID order before projecting state. SET and
RECONCILE first authorize without locks, then take a transaction advisory lock on
the actor+request UUID before acquiring any hierarchy locks, including on a
different restaurant. Lock order is request lane -> organization SHARE ->
restaurant UPDATE (SET) or SHARE (GET/RECONCILE) -> covering memberships SHARE in
ID order -> consent row UPDATE (SET) -> private receipt.

The locked pass rechecks active/live parents and current membership authority.
The restaurant row serializes initial creation even when the consent row is
absent, and also aligns with existing publication writers. Exact replay is
resolved before CAS. Consent, receipt and mutation audit are one transaction;
failure in any stage rolls all three back. No legacy ledger, kitchen containment,
notification or printer lock is acquired. No membership/history rows are changed.

## Future candidate predicate and disabled indexing

`app.storefront_seo_eligibility_when_released_v1(organization,restaurant)` is a
private, exact-scope boolean predicate with no application EXECUTE grant. It
checks the current consent row is ON; organization, restaurant and the selected
branch are active and not tombstoned; and the profile is published and not
tombstoned. Missing rows and ancestry mismatches fail closed. Temporary pause and
opening hours do not revoke consent.

That predicate alone does not activate indexing. Every currently exposed consent
state reports `indexing_active:false` and `effective_indexing_eligible:false`.
There is no public restaurant enumeration, anonymous v4 expansion, sitemap,
Search Console integration, crawler/header/canonical change or deployment in this
ticket. Connecting future indexing to this authoritative consent predicate and
releasing global crawler restrictions requires a separately approved release.

## Local verification source

`supabase/tests/storefront_seo_consent_001_test.sql` uses rollback-only synthetic
fixtures for default OFF, owner/manager/security scope, RLS/grants, CAS and replay,
refusal receipts, withdrawal, all future-candidate exclusions, append-only audit,
late-failure rollback and protected checkout/alerts/printing state snapshots.

`supabase/tests/zz_storefront_seo_consent_001_concurrency_test.sql` uses independent
dblink sessions for absent-row races, exact duplicates, read-only uncertain-write
recovery after commit/rollback, cross-scope UUID reuse, private ledger isolation,
membership revocation and restaurant suspension during a blocked write. It fails
closed unless the disposable local database is named `seo_consent_%` and carries
the exact Work ID marker, or the existing ephemeral CI `postgres` database carries
its established Featured CI marker. Both paths require private/loopback IPv4
server and client addresses on port 5432. No null-address fallback is permitted.
Its fixed public fixture password is not a hosted credential.

Only local migration source and disposable local execution are authorized here.
Hosted migration application, merchant consent, deployment, commit/push/PR and
indexing activation remain outside the authorized task. Human RLS/security and
merge approval are separate final gates.
