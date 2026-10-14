# BIZBOT-POS-AUDIO-PRINT-003 — targeted web-order kitchen transmission

Implementation contract; hosted installation, APK release, physical testing and
merge require separate owner authorization. This changes neither acceptance nor
canonical order/dispatch creation. Customer receipts and payments are unchanged.

## Scope and authorization

Four authenticated RPCs use the existing `app.pos_web_order_context` proof:
live paired POS device and device session, actual PIN session, active employee and
membership, supported cashier/manager/owner role, and server-derived tenant,
restaurant and branch. The transport JWT is not staff authority. No client may
select an authoritative branch, canonical order or dispatch. No direct grants
exist on the private attempt table, including for `service_role`.

All calls take `p_pin_session_id`, `p_device_id`, `p_device_session_token` and
`p_request_id` (the internal inbox request ID, not the public client UUID).

| RPC | Additional input | Result |
| --- | --- | --- |
| `pos_claim_web_order_print` | None | One exact initial dispatch envelope when claimable; otherwise safe state without payload. |
| `pos_begin_web_order_print` | `p_attempt_id` UUID | `send_authorized=true` once, only when the claim is still owned and valid. Every replay returns false. |
| `pos_finish_web_order_print` | Same attempt UUID, `p_client_status`, optional bounded `p_error_code` | An immutable transport outcome; identical finish replay is safe. |
| `pos_web_order_print_status` | None | Identity and state without printable payload or customer contact. |

Successful responses include `request_id`, `canonical_order_id`, `decision_id`,
`dispatch_id`, `attempt_id`, `printer_assignment_id`, `send_authorized` and `state`.
The claim-only `dispatch` matches the existing pull decoder: `id`,
`dispatch_type`, `order_id`, `service_round_id`, `payload_version`, `payload`,
`created_at` and `claim_expires_at`. Its payload is the existing authoritative,
money-free kitchen snapshot, not client-provided order data. The client must
compare all identities and the stable printer assignment before import/send.

Claim and begin additionally require a live open device shift, current
`printer_only` mode, fresh assignment-aware printer readiness and an enabled
80 mm kitchen-capable printer. `kds` never starts a competing POS print.
Finish/status retain valid staff/device authorization but do not require the
shift, mode or printer to remain unchanged, allowing honest outcome recovery.

## Atomic exclusion and at-most-once boundary

An AFTER INSERT trigger on the existing append-only accepted-decision ledger
records the initial dispatch in `web_order_print_attempts` in the same transaction
as acceptance. It runs only for future printer-only acceptances. It neither
backfills old decisions nor modifies old dispatches. An unavailable old target
returns `target_unavailable`.

All three existing broad-feed queries (claim candidates, returned page and
`has_more`) exclude this ledger's dispatch IDs. Other ordinary POS and historical
dispatches keep their original broad-feed behavior. Before acceptance commits,
another transaction sees neither new dispatch nor fence; afterward it sees both.
There is no broad-pull window between acceptance and targeted claim.

The target has a two-minute claim lease. A crash **before begin commits** permits
safe claim reassignment; a stale owner cannot begin. Begin serializes on the
private target and atomically writes a permanent attempt UUID, device/PIN owner
and reservation timestamp. Only that first response grants transmission. A lost
begin reply, a crash before bytes, a possible physical send, another device,
lease expiry or any callback retry can never produce another grant.

The client must never send after a timeout or unknown begin response. A durable
reservation is deliberately conservative: it can prevent delivery if the process
dies before bytes are sent. That case requires operator reconciliation. This is
**at-most-once automatic transmission, not guaranteed exactly-once paper**.

Finish accepts the existing transport vocabulary: `transport_accepted`,
`possibly_printed`, `failed_retryable`, `blocked_configuration`. After begin, every
non-success outcome means `reconciliation_required`; even a native zero-byte
failure does not clear the permanent fence. Existing dispatch ACK calls remain
compatible but cannot remove or change that fence. `transport_accepted` is not
proof of paper. A physical printer test requires the owner's direct observation.

Private request/decision/dispatch identities and reservations cannot be changed,
deleted or truncated. No retry, background drain or restart may mint another
canonical order, dispatch or automatic attempt for a fenced request.

## Focused verification

`supabase/tests/bizbot_pos_audio_print_003_test.sql` uses rollback-only synthetic
fixtures and real SQL roles. It covers scope/PIN/role denial, current readiness
and mode, history isolation, broad-feed exclusion, safe lease recovery, lost
responses/ACKs, immutable fences, native failure reconciliation and KDS behavior.

`supabase/tests/support/run_bizbot_pos_audio_print_003_concurrency.mjs` uses
separate `psql` connections and checks actual lock waits for two-device claims,
begin/claim races and duplicate callbacks. It creates and removes only a
uniquely named disposable database cloned from a prepared local test template.

Example after applying baseline migrations plus this migration to an isolated
localhost template named `audio_print_003`:

```text
node supabase/tests/support/run_bizbot_pos_audio_print_003_concurrency.mjs \
  --psql /absolute/path/to/psql --port 55439 --template audio_print_003 \
  --expected-data-dir /absolute/path/to/isolated/postgres/data
```

The data directory's parent must contain a `WORK-ID` file with the exact line
`BIZBOT-POS-AUDIO-PRINT-003`. The runner pins localhost, verifies the server's
actual data directory and port, validates all identifiers, and refuses a hosted
connection. Normal pgTAP CI runs the SQL tests; the separate lock harness is a
focused local verification, not a claimed extra CI job.

## Release boundary

This PR installs no hosted changes. The migration fences future accepted web
initial dispatches away from old broad pullers, so any later authorized release
must use a compatible POS before accepting new web orders. Keep general and test
admission off throughout installation until a separately approved acceptance
test. Existing unresolved historical dispatches are intentionally not selected
or repaired by the new flow. No automatic reprint or reconciliation override is
introduced here.
