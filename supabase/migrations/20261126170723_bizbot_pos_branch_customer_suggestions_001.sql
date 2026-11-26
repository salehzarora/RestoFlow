-- BIZBOT-POS-CUSTOMER-SUGGEST-001. A forward-only branch address book derived
-- from accepted cashier orders. Orders retain their original display snapshots.
create table app.pos_customer_contacts (
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  name_key text collate "C" not null,
  phone_key text collate "C" not null,
  display_name text not null,
  display_phone text not null,
  primary key (branch_id, name_key, phone_key),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete cascade
);

create index pos_customer_contacts_phone_idx
  on app.pos_customer_contacts (branch_id, phone_key, name_key);

alter table app.pos_customer_contacts enable row level security;
alter table app.pos_customer_contacts force row level security;
revoke all on app.pos_customer_contacts from public, anon, authenticated, service_role;

create function app.pos_contact_name_key(p_value text)
returns text language sql immutable strict set search_path = '' as $$
  select lower(btrim(regexp_replace(p_value, '[[:space:]]+', ' ', 'g')));
$$;

create function app.pos_contact_phone_key(p_value text)
returns text language sql immutable strict set search_path = '' as $$
  select translate(translate(p_value, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), ' +()-', '');
$$;

revoke all on function app.pos_contact_name_key(text), app.pos_contact_phone_key(text)
  from public, anon, authenticated, service_role;

create function app.remember_pos_customer_contact()
returns trigger language plpgsql security definer set search_path = ''
set lock_timeout = '100ms' as $$
begin
  -- The submit ledger becomes applied AFTER both name and phone are stamped.
  -- Read the actual order, including its device/operation identity. No payload
  -- or client-supplied contact snapshot is trusted independently of that order.
  insert into app.pos_customer_contacts
    (organization_id, restaurant_id, branch_id, name_key, phone_key, display_name, display_phone)
  select o.organization_id, o.restaurant_id, o.branch_id,
         app.pos_contact_name_key(o.customer_name), app.pos_contact_phone_key(o.customer_phone),
         o.customer_name, o.customer_phone
    from public.orders o
    join public.devices d on d.id = o.device_id
   where o.id = (new.result ->> 'order_id')::uuid
     and (o.organization_id, o.restaurant_id, o.branch_id, o.device_id, o.local_operation_id)
       = (new.organization_id, new.restaurant_id, new.branch_id, new.device_id, new.local_operation_id)
     and d.device_type = 'pos' and o.deleted_at is null
     and app.pos_contact_name_key(o.customer_name) <> ''
     and o.customer_phone is not null
  on conflict (branch_id, name_key, phone_key) do nothing;
  return null;
exception when others then
  -- Remembering is optional. Do not propagate directory errors or log customer data.
  raise warning 'POS customer suggestion capture skipped (SQLSTATE %)', sqlstate;
  return null;
end;
$$;

revoke all on function app.remember_pos_customer_contact() from public, anon, authenticated, service_role;

-- A replay either short-circuits in sync_push or resolves to a business replay.
-- The POS web-order conversion uses the reserved web-accept: operation prefix.
create trigger pos_customer_contact_on_submit
after update of status on public.sync_operations
for each row when (
  old.status <> 'applied' and new.status = 'applied' and new.operation_type = 'order.submit'
  and new.result @> '{"ok":true,"idempotency_replay":false}'::jsonb
  and not starts_with(new.local_operation_id, 'web-accept:')
) execute function app.remember_pos_customer_contact();

create function app.pos_customer_suggestions(p_pin_session_id uuid, p_query text, p_by_phone boolean)
returns jsonb language plpgsql stable security definer set search_path = ''
set plan_cache_mode = 'force_custom_plan' as $$
declare
  v_branch uuid;
  v_prefix text;
  v_results jsonb;
begin
  -- Successful device redeem/restore binds this JWT subject to a device
  -- session. A PIN UUID from another session is never a bearer credential.
  select ps.branch_id into v_branch
    from public.pin_sessions ps
    join public.device_sessions ds on ds.id = ps.device_session_id
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.employee_profiles ep on ep.id = ps.employee_profile_id
    join public.memberships m on m.id = ps.resolved_membership_id
    join public.branches b on b.id = ps.branch_id
    join public.restaurants r on r.id = ps.restaurant_id
    join public.organizations org on org.id = ps.organization_id
   where ps.id = p_pin_session_id and ds.auth_user_id = (select auth.uid())
     and (ps.organization_id, ps.restaurant_id, ps.branch_id)
       = (ds.organization_id, ds.restaurant_id, ds.branch_id)
     and app.is_pin_session_valid(ps.id)
     and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at > now())
     and dp.status = 'active' and dp.deleted_at is null and dp.revoked_at is null
     and d.is_active and d.deleted_at is null and d.device_type = 'pos'
     and org.status = 'active' and org.deleted_at is null and r.status = 'active' and r.deleted_at is null
     and b.status = 'active' and b.deleted_at is null
     and ep.organization_id = ps.organization_id and ep.employment_status = 'active' and ep.deleted_at is null
     and (ep.restaurant_id is null or ep.restaurant_id = ps.restaurant_id)
     and (ep.branch_id is null or ep.branch_id = ps.branch_id)
     and m.organization_id = ps.organization_id and m.status = 'active' and m.deleted_at is null
     and (m.restaurant_id is null or m.restaurant_id = ps.restaurant_id)
     and (m.branch_id is null or m.branch_id = ps.branch_id)
     and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner')
     and (ep.membership_id = m.id or (
       ep.membership_id is null and ep.app_user_id = m.app_user_id and not exists (
         select 1 from public.memberships other
          where other.organization_id = m.organization_id and other.app_user_id = m.app_user_id
            and other.status = 'active' and other.deleted_at is null and other.id <> m.id
       )
     ));
  if not found then
    raise exception 'Invalid POS staff session' using errcode = '42501';
  end if;

  if p_query is null or char_length(p_query) > 80 or p_by_phone is null then
    return '[]'::jsonb;
  end if;
  if p_by_phone then
    v_prefix := app.pos_contact_phone_key(p_query);
    if char_length(p_query) > 32 or v_prefix !~ '^[0-9]{4,32}$' then return '[]'::jsonb; end if;
  else
    v_prefix := app.pos_contact_name_key(p_query);
    if char_length(regexp_replace(v_prefix, '[^[:alnum:]ء-يא-ת]', '', 'g')) < 2 then return '[]'::jsonb; end if;
  end if;

  -- Literal prefix (no SQL wildcard syntax). A custom plan folds the selected
  -- key and concrete prefix into an ordered range on one of the two C indexes.
  select coalesce(jsonb_agg(jsonb_build_object('name', matched.display_name, 'phone', matched.display_phone)
                            order by matched.lookup_key, matched.tie_key), '[]'::jsonb) into v_results
    from (
      select c.display_name, c.display_phone,
             case when p_by_phone then c.phone_key else c.name_key end as lookup_key,
             case when p_by_phone then c.name_key else c.phone_key end as tie_key
        from app.pos_customer_contacts c
       where c.branch_id = v_branch
         and starts_with(case when p_by_phone then c.phone_key else c.name_key end, v_prefix)
       order by lookup_key, tie_key
       limit 5
    ) matched;
  return v_results;
end;
$$;

create function public.pos_customer_suggestions(p_pin_session_id uuid, p_query text, p_by_phone boolean)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select app.pos_customer_suggestions(p_pin_session_id, p_query, p_by_phone);
$$;
revoke all on function app.pos_customer_suggestions(uuid,text,boolean),
  public.pos_customer_suggestions(uuid,text,boolean) from public, anon, authenticated, service_role;
grant execute on function app.pos_customer_suggestions(uuid,text,boolean),
  public.pos_customer_suggestions(uuid,text,boolean) to authenticated;
