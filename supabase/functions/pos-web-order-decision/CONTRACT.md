# POS web-order decision boundary

`POST /functions/v1/pos-web-order-decision` retains the actual caller JWT and
the server's public project key. SQL remains responsible for device/PIN,
employee, tenant, pending-request and winning-decision authority. No service
credential impersonation, legacy fallback or automatic write retry is used.

## BIZBOT-STOREFRONT-ACCEPTANCE-ETA-001

Accept requires the existing `action`, `pin_session_id`, `device_id`,
`device_session_token`, `request_id` and `decision_id` keys. It optionally accepts
`preparation_minutes`, an integer JSON number from 1 through 240. Absence calls
the unchanged five-argument `pos_accept_web_order`. Presence calls the distinct
`pos_accept_web_order_with_eta` with the same five arguments and
`p_preparation_minutes`. Null, strings, booleans, fractional or out-of-range
durations and unknown keys fail before the RPC. Reject still requires `reason`,
forbids `preparation_minutes` and calls `pos_reject_web_order_customer`.

The POS result envelope is unchanged. ETA metadata is not returned here; only
the negotiated customer status reader exposes it. The SQL dependency must be
installed and verified before this optional route is deployed or produced by a
new POS release. This source change authorizes no migration or deployment.

Response headers and body share the existing bounded deadline. An uncertain
outcome retains `decision_outcome_unknown`; it cannot select another RPC or
retry. A validated committed non-replayed decision schedules the existing
best-effort terminal wake once. Notification failures cannot alter its response,
and Cron remains the recovery path. Device/session blocking, authentication,
print leases and kitchen acknowledgment authority are unchanged.
