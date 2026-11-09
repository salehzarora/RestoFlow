-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (DECISION D-062): token-only dropped-field evidence on
-- app.card_attempt_finish (gap G1 of the 001E execution packet section 7).
--
-- Forward-only and additive. It re-emits ONLY app.card_attempt_finish, with CREATE OR REPLACE and the unchanged
-- signature, return type, language, volatility, SECURITY DEFINER and empty search_path: the function keeps its OID,
-- owner and ACL (service_role only), and the public wrapper public.card_attempt_finish, every other routine,
-- table, policy and grant stay exactly as 20261023225657_bizbot_zcredit_001d_server_ledger.sql left them.
--
-- The body is the 001D correction-C2 body plus exactly three blocks, each opened by a comment line naming this
-- Work ID: (A) the loop variables; (B) the whole-key validation of the optional p_provider_fields key
-- dropped_fields, before the row lookup, any lock and any write (the existing invalid_request answer); (C) after
-- the existing provider-field loop, one deduplicated security.card_provider_field_dropped event per entry with
-- this call's p_source and the row's scope, and the same M2 essential / tip flags as a field failing here, a TEST
-- attempt's card and provider-reference fields unread. No session proof, caller binding or support check is added
-- (DECISION D-060 point 4), no provider request is started and no tenant audit names the evidence. The execution
-- packet docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md section 5 records the exact delta.

create or replace function app.card_attempt_finish(
  p_attempt_row_id uuid, p_organization_id uuid, p_device_id uuid, p_local_operation_id text,
  p_mode text, p_amount_minor bigint, p_currency_code text, p_source text, p_outcome text,
  p_provider_fields jsonb, p_poll_source text)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  a app.card_provider_attempts;
  n app.card_provider_attempts;
  v_f jsonb := case when jsonb_typeof(p_provider_fields) = 'object' then p_provider_fields else '{}'::jsonb end;
  v_now timestamptz := clock_timestamp();
  v_key text;
  v_val jsonb;
  v_text text;
  v_rule text;
  v_canon text;
  v_test_discard constant text[] := array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id',
                                          'card_last4', 'card_brand_code', 'pan_entry_mode', 'payment_method_code'];
  v_stored jsonb := '{}'::jsonb;
  v_essential_failed boolean := false;
  v_tip_failed boolean := false;
  v_error_flag boolean;
  v_return_code integer;
  v_approval_type text;
  v_phone boolean;
  v_status_code text;
  v_amount bigint;
  v_currency text;
  v_tip bigint;
  v_class text;
  v_target text;
  v_anomaly text;
  v_refusal text;
  v_before jsonb;
  v_after jsonb;
  v_updated integer;
  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): the adapter's dropped-field tokens.
  v_drop jsonb;
  v_drop_field text;
  v_drop_rule text;
  v_drop_seen text[] := array[]::text[];
  v_drop_i integer;
begin
  if p_attempt_row_id is null or p_source is null or p_outcome is null
     or not ((p_source = 'commit' and p_outcome in ('approved', 'declined', 'unknown', 'anomaly'))
             or (p_source = 'lookup' and p_outcome in ('approved', 'declined', 'anomaly', 'not_found', 'pending', 'failed'))
             or (p_source = 'release' and p_outcome in ('released', 'release_failed')))
     or (p_poll_source is not null and p_poll_source not in ('auto', 'operator')) then
    return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
  end if;
  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): the optional dropped_fields key is the
  -- adapter's evidence of a provider field it dropped. The whole key is checked here, before the row lookup,
  -- any lock and any write: an array of at most 17 objects of exactly {field, rule}, closed tokens compared
  -- exactly, one entry per field, a non-text field only with 'format', and no field that is also a key of
  -- p_provider_fields (a declared failure is never overridden by a surviving value). Anything else is the
  -- malformed-argument refusal above, never echoed; an absent key changes nothing. Each test that guards a
  -- function raising on another JSON type is its own IF (SQL fixes no evaluation order inside one expression).
  if v_f ? 'dropped_fields' then
    if jsonb_typeof(v_f -> 'dropped_fields') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
    end if;
    if jsonb_array_length(v_f -> 'dropped_fields') > 17 then
      return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
    end if;
    for v_drop_i in 0 .. jsonb_array_length(v_f -> 'dropped_fields') - 1 loop
      v_drop := v_f -> 'dropped_fields' -> v_drop_i;
      if jsonb_typeof(v_drop) is distinct from 'object' then
        return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
      end if;
      v_drop_field := case when jsonb_typeof(v_drop -> 'field') = 'string' then v_drop ->> 'field' end;
      v_drop_rule := case when jsonb_typeof(v_drop -> 'rule') = 'string' then v_drop ->> 'rule' end;
      if v_drop_field is null or v_drop_rule is null or v_drop - 'field' - 'rule' <> '{}'::jsonb
         or v_drop_field <> all (array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id',
                                       'card_last4', 'card_brand_code', 'pan_entry_mode', 'payment_method_code',
                                       'approval_type', 'provider_status_code', 'provider_return_code',
                                       'provider_saved_at', 'error_flag', 'phone_authorization', 'tip_amount',
                                       'provider_amount', 'provider_currency'])
         or v_drop_rule <> all (array['charset', 'length', 'control_character', 'digit_run', 'masked_pattern',
                                      'format'])
         or (v_drop_field in ('error_flag', 'phone_authorization', 'provider_return_code', 'provider_amount',
                              'tip_amount', 'provider_currency', 'provider_saved_at') and v_drop_rule <> 'format')
         or v_f ? v_drop_field or v_drop_field = any (v_drop_seen) then
        return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
      end if;
      v_drop_seen := v_drop_seen || v_drop_field;
    end loop;
  end if;
  select * into a from app.card_provider_attempts x where x.id = p_attempt_row_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'attempt_not_found', 'server_ts', clock_timestamp());
  end if;
  if a.organization_id is distinct from p_organization_id or a.device_id is distinct from p_device_id
     or a.local_operation_id is distinct from p_local_operation_id or a.mode is distinct from p_mode
     or a.amount_minor is distinct from p_amount_minor or a.currency_code is distinct from p_currency_code then
    perform app.card_private_event_write(a.organization_id, a.restaurant_id, a.branch_id, a.id, a.mode,
      'security.card_finish_scope_mismatch', 'adapter', 'card_adapter', null, null, null, a.device_id, null,
      jsonb_build_object(
        'organization_id', a.organization_id is distinct from p_organization_id,
        'device_id', a.device_id is distinct from p_device_id,
        'local_operation_id', a.local_operation_id is distinct from p_local_operation_id,
        'mode', a.mode is distinct from p_mode,
        'amount_minor', a.amount_minor is distinct from p_amount_minor,
        'currency_code', a.currency_code is distinct from p_currency_code));
    return jsonb_build_object('ok', false, 'error', 'conflict', 'detail', 'attempt_scope_mismatch',
                              'server_ts', clock_timestamp());
  end if;
  if a.resolution is not null then
    -- A resolved attempt is final: a provider fact still reaching it is evidence
    -- only (a lookup that got no reply carries no provider fact).
    if p_outcome <> 'failed' then
      perform app.card_private_event_write(a.organization_id, a.restaurant_id, a.branch_id, a.id, a.mode,
        'security.card_resolution_contradicted', 'adapter', 'card_adapter', null, null, null, a.device_id, null,
        jsonb_build_object('source', p_source, 'outcome', p_outcome));
    end if;
    return app.card_attempt_envelope(a);
  end if;
  if a.state not in ('sent', 'unknown', 'released') or (p_source = 'commit' and a.state <> 'sent') then
    -- approved / declined are final; a commit reply finishes only a still-sent row.
    return app.card_attempt_envelope(a);
  end if;
  v_before := app.card_attempt_derive(a);
  n := a;

  -- (1) Field rules (D-058 point 10). Absent, JSON null or empty after the
  -- canonical trim = absent (no event). A failing present field writes one
  -- security.card_provider_field_dropped (deduplicated per attempt, field, rule).
  foreach v_key in array array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id',
                               'card_last4', 'card_brand_code', 'pan_entry_mode', 'payment_method_code',
                               'approval_type', 'provider_status_code', 'provider_return_code',
                               'provider_saved_at', 'error_flag', 'phone_authorization', 'tip_amount',
                               'provider_amount', 'provider_currency'] loop
    v_val := v_f -> v_key;
    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and app.card_text_absent(v_val #>> '{}')) then
      continue;
    end if;
    if a.mode = 'test' and v_key = any (v_test_discard) then
      continue;
    end if;
    v_rule := null;
    v_text := case when jsonb_typeof(v_val) = 'string' then v_val #>> '{}' end;
    case v_key
      when 'error_flag', 'phone_authorization' then
        if jsonb_typeof(v_val) <> 'boolean' then v_rule := 'format'; end if;
      when 'provider_return_code' then
        if jsonb_typeof(v_val) <> 'number' or (v_val #>> '{}') !~ '^-?[0-9]{1,6}$' then v_rule := 'format'; end if;
      when 'provider_amount', 'tip_amount' then
        if v_text is null or v_text !~ '^(0|[1-9][0-9]{0,8})\.[0-9]{2}$' then v_rule := 'format'; end if;
      when 'provider_currency' then
        if v_text is null or v_text !~ '^[A-Z]{3}$' then v_rule := 'format'; end if;
      when 'provider_saved_at' then
        -- ISO-8601 / RFC 3339 date-time with an explicit offset (up to nine
        -- fraction digits, rounded to microseconds); never a special literal
        -- ('now', 'epoch', 'infinity' ...) or a zone-less local time.
        if v_text is null
           or v_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,9})?([Zz]|[+-][0-9]{2}(:?[0-9]{2})?)$'
           or not pg_input_is_valid(v_text, 'timestamptz') then
          v_rule := 'format';
        end if;
      else
        if v_text is null then
          v_rule := 'format';
        else
          v_rule := app.card_safe_text_failure(v_text, v_key);
          if v_rule is null and v_key = 'card_last4' and app.card_text_canonical(v_text) !~ '^[0-9]{4}$' then
            v_rule := 'charset';
          end if;
        end if;
    end case;
    if v_rule is not null then
      perform app.card_private_event_write(a.organization_id, a.restaurant_id, a.branch_id, a.id, a.mode,
        'security.card_provider_field_dropped', 'adapter', 'card_adapter', null, null, null, a.device_id, null,
        jsonb_build_object('field', v_key, 'rule', v_rule, 'source', p_source));
      if v_key in ('error_flag', 'provider_return_code', 'approval_type', 'phone_authorization',
                   'provider_status_code', 'provider_amount', 'provider_currency') then
        v_essential_failed := true;
      elsif v_key = 'tip_amount' then
        v_tip_failed := true;
      end if;
      continue;
    end if;
    case v_key
      when 'error_flag' then v_error_flag := (v_val #>> '{}')::boolean;
      when 'phone_authorization' then v_phone := (v_val #>> '{}')::boolean;
      when 'provider_return_code' then v_return_code := (v_val #>> '{}')::integer;
      when 'provider_amount' then
        v_amount := split_part(v_text, '.', 1)::bigint * 100 + split_part(v_text, '.', 2)::bigint;
      when 'tip_amount' then
        v_tip := split_part(v_text, '.', 1)::bigint * 100 + split_part(v_text, '.', 2)::bigint;
      when 'provider_currency' then v_currency := v_text;
      when 'provider_saved_at' then v_stored := v_stored || jsonb_build_object(v_key, v_text::timestamptz);
      else
        v_canon := app.card_text_canonical(v_text);
        v_stored := v_stored || jsonb_build_object(v_key, v_canon);
        if v_key = 'approval_type' then v_approval_type := v_canon; end if;
        if v_key = 'provider_status_code' then v_status_code := v_canon; end if;
    end case;
  end loop;
  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): each field the adapter dropped (checked
  -- above) writes the same deduplicated event with this call's source and sets the same M2 flag as a field
  -- failing here; a TEST attempt's card and provider-reference fields stay unread (no event, no flag).
  for v_drop_i in 0 .. coalesce(jsonb_array_length(v_f -> 'dropped_fields'), 0) - 1 loop
    v_drop_field := v_f -> 'dropped_fields' -> v_drop_i ->> 'field';
    v_drop_rule := v_f -> 'dropped_fields' -> v_drop_i ->> 'rule';
    if a.mode = 'test' and v_drop_field = any (v_test_discard) then
      continue;
    end if;
    perform app.card_private_event_write(a.organization_id, a.restaurant_id, a.branch_id, a.id, a.mode,
      'security.card_provider_field_dropped', 'adapter', 'card_adapter', null, null, null, a.device_id, null,
      jsonb_build_object('field', v_drop_field, 'rule', v_drop_rule, 'source', p_source));
    if v_drop_field in ('error_flag', 'provider_return_code', 'approval_type', 'phone_authorization',
                        'provider_status_code', 'provider_amount', 'provider_currency') then
      v_essential_failed := true;
    elsif v_drop_field = 'tip_amount' then
      v_tip_failed := true;
    end if;
  end loop;
  -- M3: the informational class; never decides anything.
  if v_f ? 'provider_return_class' and v_f -> 'provider_return_class' <> 'null'::jsonb
     and not (jsonb_typeof(v_f -> 'provider_return_class') = 'string'
              and app.card_text_absent(v_f ->> 'provider_return_class')) then
    v_class := case when jsonb_typeof(v_f -> 'provider_return_class') = 'string'
                         and (v_f ->> 'provider_return_class') in ('approved', 'declined', 'error', 'pending', 'not_found',
                                                                     'duplicate', 'phone_authorization', 'unclassified')
                    then v_f ->> 'provider_return_class' else 'unclassified' end;
  end if;

  -- (2) The outcome, validated against the essential inputs (M2): missing
  -- approval input never approves; a found / charge-bearing lookup that is not
  -- readable becomes the out_of_contract anomaly, never a decline.
  if p_source = 'commit' then
    if p_outcome = 'anomaly' then
      v_anomaly := case when v_essential_failed or v_tip_failed then 'out_of_contract'
                        when (v_f ->> 'anomaly_code') in ('amount_mismatch', 'currency_mismatch', 'preauthorization',
                                                            'partial_refund', 'refunded', 'voided', 'out_of_contract')
                        then v_f ->> 'anomaly_code' else 'out_of_contract' end;
    elsif v_tip_failed then
      v_anomaly := 'out_of_contract';
    elsif v_essential_failed then
      v_target := 'unknown';
    elsif p_outcome = 'approved' then
      if v_error_flag is false and v_return_code = 0 and v_approval_type is not null
         and v_phone is not true then
        if coalesce(v_tip, 0) <> 0 then
          v_anomaly := 'amount_mismatch';
        elsif v_amount is not null and v_amount <> a.amount_minor then
          v_anomaly := 'amount_mismatch';
        elsif v_currency is not null and v_currency <> a.currency_code then
          v_anomaly := 'currency_mismatch';
        else
          v_target := 'approved';
        end if;
      else
        v_target := 'unknown';
      end if;
    elsif p_outcome = 'declined' then
      v_target := case when v_approval_type is not null then 'declined' else 'unknown' end;
    else
      v_target := 'unknown';
    end if;
  elsif p_source = 'lookup' then
    if p_outcome = 'anomaly' then
      v_anomaly := case when v_essential_failed or v_tip_failed then 'out_of_contract'
                        when (v_f ->> 'anomaly_code') in ('amount_mismatch', 'currency_mismatch', 'preauthorization',
                                                            'partial_refund', 'refunded', 'voided', 'out_of_contract')
                        then v_f ->> 'anomaly_code' else 'out_of_contract' end;
    elsif p_outcome in ('approved', 'declined') and (v_essential_failed or v_tip_failed) then
      v_anomaly := 'out_of_contract';
    elsif p_outcome = 'approved' then
      if v_status_code is not null and v_amount is not null and v_currency is not null
         and v_error_flag is not true and v_phone is not true then
        if v_amount <> a.amount_minor or coalesce(v_tip, 0) <> 0 then
          v_anomaly := 'amount_mismatch';
        elsif v_currency <> a.currency_code then
          v_anomaly := 'currency_mismatch';
        else
          v_target := 'approved';
        end if;
      else
        v_anomaly := 'out_of_contract';
      end if;
    elsif p_outcome = 'declined' then
      if v_approval_type is not null then
        v_target := 'declined';
      else
        v_anomaly := 'out_of_contract';
      end if;
    end if;
    n.last_lookup_at := v_now;
    if p_poll_source = 'auto' then
      n.auto_poll_count := a.auto_poll_count + 1;
    end if;
  else
    if p_outcome = 'released' and a.state = 'sent' and a.start_deadline_at > v_now then
      v_target := 'released';
    elsif p_outcome = 'release_failed' then
      v_refusal := 'release_failed';
    end if;
  end if;
  -- A sent row past its start deadline with no conclusive outcome is unknown.
  if v_target is null and v_anomaly is null and a.state = 'sent' and a.start_deadline_at <= v_now then
    v_target := 'unknown';
  end if;

  -- (3) Apply. An anomaly moves a sent row to unknown and leaves unknown /
  -- released as they are; a later exact approved / declined clears
  -- charge_may_exist and keeps the anomaly code as history.
  if v_anomaly is not null then
    n.provider_anomaly_code := v_anomaly;
    n.charge_may_exist := true;
    if a.state = 'sent' then
      n.state := 'unknown';
    end if;
  elsif v_target is not null and v_target <> a.state then
    n.state := v_target;
    if v_target in ('approved', 'declined') then
      n.charge_may_exist := false;
    end if;
    if v_target = 'approved' then
      n.provider_approved_at := v_now;
    elsif v_target = 'released' then
      n.released_at := v_now;
    end if;
  end if;
  if v_refusal is not null then
    n.refusal_code := v_refusal;
  end if;
  if a.state = 'sent' and n.state <> 'sent' and a.finished_at is null then
    n.finished_at := v_now;
  end if;
  if v_class is not null then
    n.provider_return_class := v_class;
  end if;
  if v_return_code is not null then
    n.provider_return_code := v_return_code;
  end if;
  n.provider_reference := coalesce(v_stored ->> 'provider_reference', a.provider_reference);
  n.approval_number := coalesce(v_stored ->> 'approval_number', a.approval_number);
  n.voucher_number := coalesce(v_stored ->> 'voucher_number', a.voucher_number);
  n.deposit_id := coalesce(v_stored ->> 'deposit_id', a.deposit_id);
  n.card_last4 := coalesce(v_stored ->> 'card_last4', a.card_last4);
  n.card_brand_code := coalesce(v_stored ->> 'card_brand_code', a.card_brand_code);
  n.pan_entry_mode := coalesce(v_stored ->> 'pan_entry_mode', a.pan_entry_mode);
  n.payment_method_code := coalesce(v_stored ->> 'payment_method_code', a.payment_method_code);
  n.approval_type := coalesce(v_stored ->> 'approval_type', a.approval_type);
  n.provider_status_code := coalesce(v_stored ->> 'provider_status_code', a.provider_status_code);
  n.provider_saved_at := coalesce((v_stored ->> 'provider_saved_at')::timestamptz, a.provider_saved_at);
  update app.card_provider_attempts x set
    state = n.state, provider_anomaly_code = n.provider_anomaly_code, charge_may_exist = n.charge_may_exist,
    provider_approved_at = n.provider_approved_at, released_at = n.released_at, refusal_code = n.refusal_code,
    finished_at = n.finished_at, last_lookup_at = n.last_lookup_at, auto_poll_count = n.auto_poll_count,
    provider_return_class = n.provider_return_class, provider_return_code = n.provider_return_code,
    provider_reference = n.provider_reference, approval_number = n.approval_number,
    voucher_number = n.voucher_number, deposit_id = n.deposit_id, card_last4 = n.card_last4,
    card_brand_code = n.card_brand_code, pan_entry_mode = n.pan_entry_mode,
    payment_method_code = n.payment_method_code, approval_type = n.approval_type,
    provider_status_code = n.provider_status_code, provider_saved_at = n.provider_saved_at
  where x.id = a.id
  returning x.* into n;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    select * into n from app.card_provider_attempts x where x.id = a.id;
    return app.card_attempt_envelope(n);
  end if;

  -- (4) Tenant audit, LIVE only: a state or classification change, an anomaly
  -- change, a release_failed refusal — never a stamp- or counter-only write.
  if a.mode = 'live' then
    v_after := app.card_attempt_derive(n);
    if n.state <> a.state or (v_after ->> 'classification') is distinct from (v_before ->> 'classification')
         and (n.provider_anomaly_code is not distinct from a.provider_anomaly_code
              and n.charge_may_exist = a.charge_may_exist) then
      perform app.card_audit_write(n.organization_id, n.restaurant_id, n.branch_id,
        n.initiated_by_employee_profile_id, n.device_id, 'card_attempt.' || n.state,
        jsonb_strip_nulls(jsonb_build_object('attempt_state', n.state, 'refusal_code', n.refusal_code,
          'anomaly_code', n.provider_anomaly_code, 'release_requested', n.release_requested_at is not null)));
    end if;
    if n.provider_anomaly_code is distinct from a.provider_anomaly_code or n.charge_may_exist <> a.charge_may_exist then
      perform app.card_audit_write(n.organization_id, n.restaurant_id, n.branch_id,
        n.initiated_by_employee_profile_id, n.device_id, 'card_attempt.provider_anomaly',
        jsonb_strip_nulls(jsonb_build_object('attempt_state', n.state, 'refusal_code', n.refusal_code,
          'anomaly_code', n.provider_anomaly_code, 'release_requested', n.release_requested_at is not null)));
    end if;
    if v_refusal = 'release_failed' then
      perform app.card_audit_write(n.organization_id, n.restaurant_id, n.branch_id,
        n.initiated_by_employee_profile_id, n.device_id, 'card_attempt.release_failed',
        jsonb_build_object('attempt_state', n.state));
    end if;
  end if;
  return app.card_attempt_envelope(n);
end;
$$;
