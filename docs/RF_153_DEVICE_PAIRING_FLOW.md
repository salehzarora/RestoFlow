# RF-153 — Device / Station Pairing Flow

> Working note for ticket RF-153. Cites the frozen sources of truth
> ([DOMAIN_MODEL.md](DOMAIN_MODEL.md) §3.4, [STATE_MACHINES.md](STATE_MACHINES.md) §9,
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [API_CONTRACT.md](API_CONTRACT.md)
> §4.27–§4.29) and never overrides them. Does not claim production-readiness.

## The real pairing flow

```
Owner/manager (dashboard, real mode)
  1. sign in + select org/branch context           (RF-151 / RF-152)
  2. create a device (pos|kds) for the branch       public.create_device (RF-112)
  3. issue a one-time enrollment code               public.issue_device_enrollment_code
        -> the plaintext code is shown ONCE

Device (POS/KDS, real mode, no device context)
  4. open the shared DevicePairingScreen            (RF-153)
  5. enter the enrollment code                      DevicePairingRepository.pairWithCode(code, deviceType)
        -> backend resolves the org/branch/station the code was issued for
           (public.redeem_device_enrollment_code -> approve -> activate -> start_device_session, RF-112)
  6. on success a scoped DeviceContext is adopted   isPaired == true; org/branch/station/device ids
  7. POS/KDS enter their existing surface           (real data still gated on the PIN bridge — deferred)

Sign-out / unpair -> the device context is cleared (never persisted with a secret).
```

## What RF-153 delivered

- **Backend:** none needed — the full device-pairing surface already exists with
  authenticated-only public wrappers (RF-112: `create_device`,
  `issue_device_enrollment_code`, `redeem_device_enrollment_code`, `approve_device`,
  `activate_device`, `start_device_session`; `revoke_device` RF-061). Deny-by-default
  RLS, cross-org/branch pairing denied, one-time/expiring codes, kitchen money-redaction
  (T-003) are all already enforced + pgTAP-tested. **No migration was added.**
- **Shared model (`restoflow_auth_identity`):** `DeviceContext` (org/branch + restaurant,
  station id/type, device id/type, display name, pairedAt) — `isPaired` only with a real
  device id, `matchesScope` to validate against the active selection — and a pure-Dart
  `DevicePairingRepository` seam (`pairWithCode(code, deviceType) -> Result<DeviceContext,
  PairingFailure>`). The dashboard's RF-152 `DeviceContextController` now uses this shared
  model.
- **Shared UI (`restoflow_feature_auth`):** `DevicePairingScreen` — a money-free pairing
  form; honest states only (never fabricates a paired device; safe localized errors; never
  surfaces a raw provider message, code, or session token). 9 new `pairing*` l10n keys
  (EN/AR/HE).
- **POS + KDS real-mode gates:** `PosPairingGate` / `KdsPairingGate` — when a
  `DevicePairingRepository` is wired, real mode requires a paired device before the
  POS/KDS surface. **Injected + dormant in production** (repo null) so demo mode is
  unchanged and no fake pairing is shown. KDS is money-free.

## What remains deferred (RF-154 / RF-155)

- **Dashboard real device repository.** The device-management UI + `AdminRepository`
  seam already exist (RF-113, `feature_admin`, demo-backed) and map 1:1 to the RF-112
  public RPCs; a `SupabaseAdminRepository` (real wiring behind the runtime-config seam)
  is the remaining step so the owner creates devices/codes against the real backend.
- **Production device-session secret storage.** The device session token is sensitive;
  it must NOT go in `SharedPreferences`/localStorage. A secure-storage abstraction
  (e.g. `flutter_secure_storage`) is required before the production POS/KDS pairing
  repository is wired — hence the gates are dormant in production today (no fake pairing).
- **The PIN-session bridge → real data.** After pairing, POS/KDS still need the human
  PIN session (`start_pin_session`) to reach real order/kitchen data; that bridge is the
  established deferral (RF-131/RF-136).
- **Real-first default, MFA/AAL2 UX, hardware printer transport, a live Supabase E2E,
  and the mandatory human RLS/security sign-off (R-003)** all remain out of scope here.
