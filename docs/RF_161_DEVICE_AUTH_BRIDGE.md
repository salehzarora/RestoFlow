# RF-161 — Device-auth bridge + real POS/KDS order loop (ADR)

> **Status: PROPOSED for human + Codex review. Security-critical (RISK R-003 CRITICAL).**
> This closes the frozen device-auth gap flagged at RF-160. It is additive and
> forward-only, does **not** weaken RLS/auth, uses **no** service-role key, and adds
> **no** anon-role path. It **must not** serve real tenant data until the mandatory
> human RLS/security sign-off + Codex review (AGENTS.md §1).

## 1. Problem — the frozen gap

RestoFlow's operational RPCs authorize from **bearer session ids passed as arguments**,
not from `auth.uid()`:

- `app.sync_push(p_pin_session_id, p_device_id, p_operations)` — looks up the
  `pin_sessions` row, validates it + its backing `device_session`/pairing, and derives
  org/restaurant/branch **from the PIN session** ([rf056](../supabase/migrations/20260622110000_rf056_sync_operations_push.sql) A8, §sync_push).
- `app.sync_pull(p_pin_session_id, p_device_id, …)` — same PIN-session gate ([rf057](../supabase/migrations/20260622120000_rf057_sync_pull.sql)).
- `app.start_pin_session(p_device_session_id, p_employee_profile_id, p_pin_verifier, …)`
  — authorizes from the **device session** + PIN, not `auth.uid()` ([rf051](../supabase/migrations/20260621120000_rf051_pin_session_flow.sql)).

All are granted to `authenticated` (never `anon`/`service_role`). So a device only needs
**some** `authenticated` JWT + the right bearer capabilities. The one missing piece:
`redeem_device_enrollment_code` / `start_device_session` are **management-driven**
(`app.actor_rank_in_scope ≥ manager` — a member), so a device **cannot obtain its own
session**. That is the entire gap.

## 2. Chosen architecture

**Device identity = an authenticated (anonymous) Supabase principal + a device session
minted from a one-time enrollment code.**

1. Owner/manager creates a device + issues a one-time code from the Dashboard (RF-160,
   authenticated manager — this **is** the tenant authorization).
2. The device signs in with **Supabase anonymous auth** → an `authenticated` JWT with
   **no** membership. This satisfies the coarse `authenticated` grant gate while granting
   **zero** tenant authority (preserves DECISION D-011: no `anon`-role path, no
   service-role key; an anonymous *authenticated user* is not the `anon` *role*).
3. The device calls the new **device-originated** `redeem_device_pairing(code, device_type)`.
   The backend (SECURITY DEFINER, `search_path=''`) validates by the **code**, not
   membership; on success it activates the pairing and mints a device session, returning
   the raw session token **once** + non-secret context ids.
4. The device stores the **raw session token in secure storage** and the **non-secret
   context ids in normal prefs**.
5. On every launch the device calls `restore_device_session(device_id, token)` — proving
   possession of the secret — to re-derive its `device_session_id` + validated context
   (fail-closed if revoked/expired/wrong).
6. Real operations reuse the **existing** chain: `start_pin_session` → `sync_push` /
   `sync_pull`. Nothing in the operational grant posture changes.

### Why this does not weaken RLS/auth
- New RPCs are SECURITY DEFINER with a **locked `search_path`**; tables stay RLS
  deny-by-default (direct DML remains revoked — RF-059).
- Scope is **server-derived** from the code's pairing row; the client never supplies org/
  branch/role.
- The device principal is `authenticated` (anonymous), **not** `anon`; no operational RPC
  is re-granted to `anon`.
- Every capability is a one-time / hashed / expiring / revocable bearer; possession of a
  non-secret id alone grants nothing without the secret token (restore) or a code (redeem).

## 3. New RPCs (RF-161, additive)

| RPC (public wrapper → app.*) | Caller | Purpose |
|---|---|---|
| `redeem_device_pairing(p_enrollment_code text, p_device_type text)` | `authenticated` (device) | Validate code by hash (must be `code_issued`, unexpired, unrevoked, `device_type` matches, device+scope live); advance pairing → `active`; mint a device session; return `device_session_id` + `session_token` **once** + context ids. Audited. |
| `restore_device_session(p_device_id uuid, p_session_token text)` | `authenticated` (device) | Hash the token; find the device's **active, non-revoked** session on an **active** pairing with matching `session_token_ref`; return `device_session_id` + context. **No token returned.** |
| `revoke_device_session(p_device_id uuid, p_session_token text)` | `authenticated` (device) | Token-proven **self-unpair**: set `revoked_at` on the caller's own session. Idempotent. |

Owner-side revoke reuses the existing `revoke_device` (RF-061), which invalidates sessions.

## 4. Secret handling (SECURITY REQUIREMENT)

| Secret | Stored in DB as | Returned to client | Client storage |
|---|---|---|---|
| Enrollment code | `device_pairings.enrollment_code_hash` (SHA-256, existing) | once, at issue (RF-160) | shown once, never persisted |
| Device session token | `device_sessions.session_token_ref` (SHA-256 via `app.hash_provisioning_secret`) | once, at redeem | **secure storage only** (`flutter_secure_storage`) |
| Non-secret context | — | yes | normal prefs OK (device_id, org/rest/branch/station ids, device_type, display name) |

Raw secrets are **never** stored plaintext in the DB, **never** in audit_events, **never**
logged, and **never** placed in `SharedPreferences`. `list_devices` (RF-160) and all read
RPCs never return a secret ref. Redeem is consume-once (a re-redeem of a spent code fails
closed with `invalid_code` — it never re-mints/re-returns a token).

**`device_session_id` is capability-bearing, not "non-secret context."** The existing
operational chain (`start_pin_session` → `sync_push`/`sync_pull`) authorizes from the
`device_session_id` **and never re-verifies the session token** (a pre-existing RF-051/RF-056
property). So RF-161's client MUST NOT persist `device_session_id` in normal prefs — it is
**re-derived from the raw token via `restore_device_session` on every launch** and held only
in memory. Only the raw token (secure storage) + the non-secret `device_id` + display context
(prefs) are persisted.

## 5. How POS/KDS restore + the order loop are authorized

- **Restore (both):** prefs give `device_id` + context; secure storage gives the raw token;
  `restore_device_session` returns the live `device_session_id` (fail-closed otherwise).
- **POS order:** `device_session_id` → `start_pin_session(device_session_id, employee, PIN
  verifier)` → `pin_session_id` → `sync_push(pin_session_id, device_id, [order.submit,
  payment.create, …])`. Money stays server-authoritative (D-007) inside the dispatched RPCs.
- **KDS tickets:** `device_session_id` → `start_pin_session` → `pin_session_id` →
  `sync_pull(pin_session_id, device_id, [kitchen entities])`. **KDS money-redaction** is
  enforced by `sync_pull`'s projection (verified in Phase E).

## 6. Deliberate trade-offs (for review)

- **Manager-approval checkpoint collapsed.** The frozen lifecycle is
  `code_issued → pending → paired → active` with a manager approval at `pending → paired`
  (STATE_MACHINES §9). RF-161 treats **redeeming the one-time code as the owner's
  authorization** and advances straight to `active`. Mitigations: the code is one-time
  (consumed on redeem), short-TTL (15 min, RF-112), high-entropy, scoped, and the owner can
  `revoke_device` at any time. This is the RF-161-specified single-step device flow.

## 7. Remaining limits (honest — NOT production-ready)

- **PIN verifier is interim/dev-only** (RF-051: "MUST NOT be treated as production
  cryptography"). Both POS **and** KDS operational RPCs require a PIN session, so the real
  order loop is **demonstrable** but **not production-secure** until real PIN credential
  provisioning + verification lands.
- **Anonymous sign-ins must be enabled** in the Supabase project (config, not a secret).
- **Employee provisioning** (employee_profiles + PIN credentials) for real logins is deferred.
- **Offline auth staleness** (Q-009 / RISK R-007): revoke→invalid-on-reconnect mechanism
  exists (RF-061); the validity window is interim, not frozen.
- **No session expiry window.** `device_sessions.expires_at` is left NULL (Q-009/RF-112), so a
  leaked token is valid **until an explicit owner-side revoke**. A bounded validity window is
  recommended before real tenant service.
- **Operational-chain tombstone gap (pre-existing).** `restore_device_session` now fails closed
  on a soft-deleted branch/restaurant (RF-161 fix), but the downstream `start_pin_session` /
  `sync_push` / `sync_pull` gates do **not** yet re-check those tombstones — an already-restored
  session survives a mid-session branch decommission until `revoke_device`. Closing that requires
  changes to frozen RPCs (tracked for the human sign-off; out of RF-161's additive scope).
- **Rate-limiting / brute-force.** `redeem`/`restore`/`revoke` are callable by any authenticated
  (incl. anonymous) principal with no attempt throttle; guessing resistance rests on 122-bit code/
  token entropy. Anonymous-sign-in + RPC rate limits are an operational dependency to enforce.
- **Mandatory human RLS/security sign-off + Codex review** before any real tenant use.
- KDS still requires a PIN session (a device-session-only kitchen read path is a future
  simplification).
