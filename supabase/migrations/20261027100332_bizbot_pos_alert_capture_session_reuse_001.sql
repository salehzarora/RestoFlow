-- BIZBOT-POS-ALERT-OWNERSHIP-RECONCILIATION-001: retain separate closed
-- observations when the same authorized device/session needs a later window.
-- Operator arming must serialize and refuse intersecting capture windows; see
-- tools/pos_alerts/arm_registration_capture.sql. The existing observation helper
-- still returns UNKNOWN when multiple active candidates exist.
begin;

alter table app.pos_alert_registration_captures
  drop constraint pos_alert_capture_session;
create index pos_alert_capture_session_lookup
  on app.pos_alert_registration_captures(target_device_session_id)
  where target_device_session_id is not null;

-- No data, function, principal uniqueness, window/anchor check, ACL or RLS edit.
commit;
