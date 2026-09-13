-- ============================================================================
-- STOREFRONT-SEC-001 — Public-surface ACL remediation (Postgres role `anon`)
-- BIZBOT Storefront Phase 1A.1 — prerequisite of every public Storefront RPC.
--
-- WHY
--   Hosted Supabase carries a legacy schema-`public` default
--   (`ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ... TO anon`)
--   that hands EVERY function, table, view and sequence created by a migration
--   an explicit, separate grant to the Postgres role `anon` at CREATE time. The
--   local Docker stack does not carry that default, so the repository's usual
--   `REVOKE ... FROM PUBLIC` left the hosted `anon` grants in place: on
--   2026-09-13 a read-only inventory of production (project oqmevrndtivqxgyvcmwy,
--   migrations 139/139, head 20260905090001) found
--     * 78 of 118 `public` functions EXECUTE-able by `anon`,
--     * 51 of 55 `public` relations with full anon DML (`arwdDxtm`),
--     * default privileges for role `postgres` in `public` granting `anon`
--       EXECUTE on functions, ALL on tables and ALL on sequences.
--   Today the only barriers are forced RLS (tables) and the fact that `anon`
--   has no USAGE on schema `app` (every public wrapper is SECURITY INVOKER and
--   dead-ends there). The Storefront will publish the anon key on a public
--   origin and add the first anon-callable RPCs, so the incidental grants must
--   be gone BEFORE that surface exists.
--
-- TARGET POSTURE (Phase 1A — before any Storefront RPC exists)
--   * effective anon EXECUTE on `public` functions ............ EMPTY allowlist
--   * effective anon privileges on `public` tables/views/sequences ...... NONE
--   * anon USAGE on schema `app` ..................................... NONE (unchanged)
--   * anon USAGE on schema `public` ................................... KEPT (PostgREST + future allowlisted RPCs)
--   * `authenticated` EXECUTE / table grants ........................ UNCHANGED
--   * default privileges of the migration-running owner (`postgres`) in
--     `public` (and globally) no longer grant anything to `anon`: future
--     tables/sequences are closed outright; a future FUNCTION still carries the
--     built-in PUBLIC EXECUTE until its own migration issues the house
--     `revoke all on function ... from public` (per-schema defaults are added
--     on top of the built-in default — pgTAP A3/A4 fail if it is forgotten)
--   Later Storefront tickets must GRANT each anon-callable RPC explicitly, one
--   by one, each with its own pgTAP proof (DECISIONS.md D-037).
--
-- SCOPE
--   Grants and default privileges ONLY. No function body, RLS policy, table,
--   index, trigger, auth setting, storage object or business row is touched.
--   Forward-only and idempotent: REVOKE of an absent privilege is a no-op, so
--   the file is safe on the local stack (where most of these grants never
--   existed) and on hosted. Every privilege change is a flat, explicit
--   statement (house style); the two `do` blocks CHANGE NOTHING — step 0
--   checks the owner precondition and step 6 asserts the target posture and
--   aborts the whole transaction if it is not reached, so a partial hosted
--   apply is impossible.
--
-- NOT applied to hosted by this file. Hosted apply requires explicit owner
-- approval; see docs/handoffs/BIZBOT_STOREFRONT_SEC_001_PREAPPLY_REPORT.md for
-- the apply plan, verification queries and the exact recovery script
-- (supabase/recovery/sec001_restore_prior_anon_privileges.sql), which restores
-- ONLY the privileges proven present before apply — never a blanket GRANT ALL.
--
-- Supabase Auth's "anonymous sign-in" users are Postgres role `authenticated`,
-- NOT role `anon`; nothing here affects paired POS/KDS/Kiosk devices.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Ownership precondition. ALTER DEFAULT PRIVILEGES only affects objects
--    created by the named role, so the objects this file protects must be
--    owned by the role it names. Fail loudly if that ever stops being true.
-- ----------------------------------------------------------------------------
do $$
declare
  v_other_owner text;
begin
  select string_agg(distinct pg_get_userbyid(p.proowner), ', ')
    into v_other_owner
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.prokind = 'f'
    and pg_get_userbyid(p.proowner) <> 'postgres';
  if v_other_owner is not null then
    raise exception 'SEC-001: public functions owned by % — default-privilege remediation targets role postgres only; stop and review', v_other_owner;
  end if;

  select string_agg(distinct pg_get_userbyid(c.relowner), ', ')
    into v_other_owner
  from pg_class c
  where c.relnamespace = 'public'::regnamespace
    and c.relkind in ('r', 'p', 'v', 'm', 'S')
    and pg_get_userbyid(c.relowner) <> 'postgres';
  if v_other_owner is not null then
    raise exception 'SEC-001: public relations owned by % — default-privilege remediation targets role postgres only; stop and review', v_other_owner;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- 1. Function EXECUTE — explicit, exact identity signatures for every `public`
--    function present in the hosted inventory (118 functions, including the
--    two overload pairs). `authenticated` / `service_role` grants are untouched.
-- ----------------------------------------------------------------------------

revoke all on function public.acknowledge_kitchen_print_dispatch(p_device_id uuid, p_session_token text, p_dispatch_id uuid, p_client_status text, p_error_code text) from anon;
revoke all on function public.activate_device(p_client_request_id uuid, p_device_pairing_id uuid) from anon;
revoke all on function public.approve_device(p_client_request_id uuid, p_device_pairing_id uuid) from anon;
revoke all on function public.create_device(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_device_type text, p_label text) from anon;
revoke all on function public.create_organization(p_client_request_id uuid, p_organization_name text, p_organization_slug text, p_restaurant_name text, p_branch_name text, p_currency_code text, p_timezone text, p_default_station_name text) from anon;
revoke all on function public.create_staff_member(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_display_name text, p_role text, p_capabilities jsonb) from anon;
revoke all on function public.delete_floor_element(p_client_request_id uuid, p_organization_id uuid, p_element_id uuid) from anon;
revoke all on function public.get_branch_kitchen_workflow_mode(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.get_branch_pos_shift_close_enabled(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.get_branch_tax(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.get_device_branch_tax(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.get_device_kitchen_workflow_mode(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.get_device_pos_shift_close_enabled(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.get_device_printer_assignments(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.get_kitchen_workflow_transition_readiness(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.get_my_context() from anon;
revoke all on function public.get_open_shift_summary(p_pin_session_id uuid, p_device_id uuid) from anon;
revoke all on function public.get_restaurant_receipt_logo(p_organization_id uuid, p_restaurant_id uuid) from anon;
revoke all on function public.grant_membership(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_target_app_user_id uuid, p_role text) from anon;
revoke all on function public.issue_device_enrollment_code(p_client_request_id uuid, p_device_id uuid, p_ttl interval) from anon;
revoke all on function public.kiosk_menu(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.kiosk_submit_order(p_device_id uuid, p_session_token text, p_order_id uuid, p_local_operation_id text, p_order_type text, p_table_id uuid, p_currency_code text, p_notes text, p_customer_name text, p_customer_phone text, p_order_items jsonb, p_client_subtotal_minor bigint, p_client_discount_total_minor bigint, p_client_tax_total_minor bigint, p_client_grand_total_minor bigint, p_client_created_at timestamp with time zone, p_claim_kitchen_dispatch boolean) from anon;
revoke all on function public.kiosk_tables(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.list_device_staff(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.list_devices(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.list_kitchen_print_dispatches(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_status_filter text, p_limit integer, p_cursor_created_at timestamp with time zone, p_cursor_id uuid) from anon;
revoke all on function public.list_members(p_organization_id uuid) from anon;
revoke all on function public.list_menu(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.list_org_structure(p_organization_id uuid) from anon;
revoke all on function public.list_printers(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.list_quick_note_presets(p_organization_id uuid, p_restaurant_id uuid) from anon;
revoke all on function public.list_staff(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.list_tables(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.list_timezones() from anon;
revoke all on function public.menu_reorder(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_entity text, p_ids uuid[]) from anon;
revoke all on function public.menu_set_item_availability(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_menu_item_id uuid, p_availability text, p_reason text) from anon;
revoke all on function public.menu_soft_delete(p_organization_id uuid, p_entity text, p_id uuid) from anon;
revoke all on function public.menu_upsert_category(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_name text, p_display_order integer, p_is_active boolean, p_icon_key text) from anon;
revoke all on function public.menu_upsert_item(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_menu_category_id uuid, p_name text, p_description text, p_base_price_minor bigint, p_currency_code text, p_default_station_id uuid, p_display_order integer, p_is_active boolean, p_image_path text, p_item_type text, p_tags jsonb, p_prep_minutes integer, p_sku text, p_kitchen_note text, p_attributes jsonb) from anon;
revoke all on function public.menu_upsert_modifier(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_menu_item_id uuid, p_name text, p_selection_type text, p_min_select integer, p_max_select integer, p_is_required boolean, p_display_order integer, p_is_active boolean, p_allow_quantity boolean, p_max_quantity integer) from anon;
revoke all on function public.menu_upsert_modifier_option(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_modifier_id uuid, p_name text, p_price_delta_minor bigint, p_display_order integer, p_is_active boolean, p_kitchen_meat jsonb) from anon;
revoke all on function public.menu_upsert_size(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_menu_item_id uuid, p_name text, p_price_delta_minor bigint, p_display_order integer, p_is_active boolean) from anon;
revoke all on function public.menu_upsert_variant(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_menu_item_id uuid, p_name text, p_price_delta_minor bigint, p_display_order integer, p_is_active boolean) from anon;
revoke all on function public.owner_active_orders(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_status text, p_order_type text, p_payment text, p_search text, p_limit integer, p_queue text, p_sort text, p_cursor text) from anon;
revoke all on function public.owner_audit_events(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_category text, p_action text, p_sensitive_only boolean, p_actor_app_user_id uuid, p_actor_employee_profile_id uuid, p_limit integer, p_cursor text) from anon;
revoke all on function public.owner_complete_order(p_organization_id uuid, p_order_id uuid, p_expected_revision integer) from anon;
revoke all on function public.owner_daily_report(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.owner_order_detail(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_order_id uuid) from anon;
revoke all on function public.owner_order_history(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_search text, p_status text, p_order_type text, p_payment text, p_limit integer, p_cursor text, p_start date, p_end date) from anon;
revoke all on function public.owner_report_currency_breakdown(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_start date, p_end date) from anon;
revoke all on function public.owner_report_range(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date) from anon;
revoke all on function public.owner_sales_series(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date) from anon;
revoke all on function public.owner_top_items(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date, p_limit integer) from anon;
revoke all on function public.pin_session_capabilities(p_pin_session_id uuid, p_device_id uuid) from anon;
revoke all on function public.platform_admin_audit_search(p_reason text, p_limit integer, p_cursor_occurred_at timestamp with time zone, p_cursor_id uuid, p_action text, p_target_organization_id uuid, p_from timestamp with time zone, p_to timestamp with time zone) from anon;
revoke all on function public.platform_admin_console_overview(p_reason text) from anon;
revoke all on function public.platform_admin_get_organization(p_organization_id uuid, p_reason text) from anon;
revoke all on function public.platform_admin_get_subscriber(p_organization_id uuid, p_reason text) from anon;
revoke all on function public.platform_admin_list_restaurants(p_reason text, p_limit integer, p_offset integer, p_search text, p_org_status text, p_sort text) from anon;
revoke all on function public.platform_admin_list_subscribers(p_reason text, p_limit integer, p_offset integer, p_search text, p_org_status text, p_plan_code text, p_subscription_status text, p_sort text) from anon;
revoke all on function public.platform_admin_organization_overview(p_reason text) from anon;
revoke all on function public.platform_admin_recent_audit(p_reason text, p_limit integer) from anon;
revoke all on function public.platform_admin_restaurant_operations(p_reason text, p_limit integer, p_offset integer, p_search text, p_org_status text, p_sort text, p_with_sales boolean) from anon;
revoke all on function public.platform_admin_start_support_session(p_organization_id uuid, p_restaurant_id uuid, p_reason text) from anon;
revoke all on function public.platform_support_current() from anon;
revoke all on function public.platform_support_end(p_support_session_id uuid) from anon;
revoke all on function public.platform_support_exchange(p_token text) from anon;
revoke all on function public.pos_menu(p_pin_session_id uuid, p_device_id uuid) from anon;
revoke all on function public.pos_order_detail(p_pin_session_id uuid, p_device_id uuid, p_order_id uuid) from anon;
revoke all on function public.pos_order_snapshots(p_pin_session_id uuid, p_device_id uuid, p_since_at timestamp with time zone, p_since_id uuid, p_before_at timestamp with time zone, p_before_id uuid, p_order_ids uuid[], p_limit integer, p_window_days integer) from anon;
revoke all on function public.pos_ready_feed(p_pin_session_id uuid, p_device_id uuid, p_since_ready_at timestamp with time zone, p_since_type text, p_since_id uuid, p_limit integer) from anon;
revoke all on function public.pos_tables(p_pin_session_id uuid, p_device_id uuid) from anon;
revoke all on function public.pull_kitchen_print_dispatches(p_device_id uuid, p_session_token text, p_limit integer, p_cursor_created_at timestamp with time zone, p_cursor_id uuid, p_cursor_type_rank integer) from anon;
revoke all on function public.redeem_device_enrollment_code(p_client_request_id uuid, p_device_id uuid, p_enrollment_code text) from anon;
revoke all on function public.redeem_device_pairing(p_enrollment_code text, p_device_type text) from anon;
revoke all on function public.reorder_quick_note_presets(p_organization_id uuid, p_restaurant_id uuid, p_ids uuid[]) from anon;
revoke all on function public.reorder_table_sections(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_ids uuid[]) from anon;
revoke all on function public.report_kitchen_pos_status(p_device_id uuid, p_session_token text, p_app_build text, p_mode_revision integer, p_secure_spool_available boolean, p_unresolved_local_jobs integer) from anon;
revoke all on function public.report_kitchen_pos_status(p_device_id uuid, p_session_token text, p_app_build text, p_mode_revision integer, p_secure_spool_available boolean, p_unresolved_local_jobs integer, p_spool_count_state text) from anon;
revoke all on function public.report_kitchen_printer_readiness(p_device_id uuid, p_session_token text, p_capability text, p_app_build text, p_printer_purpose text, p_transport_kind text, p_paper_width text, p_printer_fingerprint text, p_secure_spool_available boolean, p_unresolved_local_jobs integer, p_mode_revision integer) from anon;
revoke all on function public.report_kitchen_printer_readiness(p_device_id uuid, p_session_token text, p_capability text, p_app_build text, p_printer_purpose text, p_transport_kind text, p_paper_width text, p_printer_fingerprint text, p_secure_spool_available boolean, p_unresolved_local_jobs integer, p_mode_revision integer, p_printer_assignment_id uuid) from anon;
revoke all on function public.restore_device_session(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.revoke_device_management(p_client_request_id uuid, p_device_id uuid, p_reason text) from anon;
revoke all on function public.revoke_device_session(p_device_id uuid, p_session_token text) from anon;
revoke all on function public.revoke_membership(p_client_request_id uuid, p_membership_id uuid, p_reason text) from anon;
revoke all on function public.sales_summary(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid) from anon;
revoke all on function public.set_branch_pos_shift_close_enabled(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_enabled boolean) from anon;
revoke all on function public.set_branch_tax(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_enabled boolean, p_rate_bp integer) from anon;
revoke all on function public.set_employee_pin(p_client_request_id uuid, p_employee_profile_id uuid, p_pin text) from anon;
revoke all on function public.set_floor_element_style(p_client_request_id uuid, p_organization_id uuid, p_element_id uuid, p_visual_style text) from anon;
revoke all on function public.set_kitchen_workflow_mode(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_mode text) from anon;
revoke all on function public.set_printer_route(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_station_id uuid, p_printer_device_id uuid, p_is_enabled boolean) from anon;
revoke all on function public.set_restaurant_receipt_logo(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_logo_path text, p_enabled boolean, p_expected_version integer) from anon;
revoke all on function public.set_staff_capabilities(p_client_request_id uuid, p_employee_profile_id uuid, p_apply_discount boolean, p_void_order boolean, p_close_shift boolean, p_apply_full_comp boolean, p_manage_menu_availability boolean, p_manage_table_operations boolean) from anon;
revoke all on function public.set_table_layout_position(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_layout_x integer, p_layout_y integer) from anon;
revoke all on function public.set_table_section(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_section_id uuid) from anon;
revoke all on function public.set_table_section_floor_preset(p_client_request_id uuid, p_organization_id uuid, p_section_id uuid, p_floor_preset text) from anon;
revoke all on function public.set_table_section_room_frame_preset(p_client_request_id uuid, p_organization_id uuid, p_section_id uuid, p_room_frame_preset text) from anon;
revoke all on function public.set_table_status(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_status text) from anon;
revoke all on function public.set_table_visual_material(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_visual_material text) from anon;
revoke all on function public.set_table_visual_preset(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_visual_preset text) from anon;
revoke all on function public.soft_delete_printer_device(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid) from anon;
revoke all on function public.soft_delete_quick_note_preset(p_client_request_id uuid, p_organization_id uuid, p_preset_id uuid) from anon;
revoke all on function public.soft_delete_table(p_client_request_id uuid, p_organization_id uuid, p_table_id uuid) from anon;
revoke all on function public.soft_delete_table_section(p_client_request_id uuid, p_organization_id uuid, p_section_id uuid) from anon;
revoke all on function public.start_device_session(p_client_request_id uuid, p_device_pairing_id uuid) from anon;
revoke all on function public.start_pin_session(p_device_session_id uuid, p_employee_profile_id uuid, p_pin_verifier text, p_local_operation_id text) from anon;
revoke all on function public.sync_pull(p_pin_session_id uuid, p_device_id uuid, p_entities text[], p_cursors jsonb, p_limit integer) from anon;
revoke all on function public.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb) from anon;
revoke all on function public.update_branch_settings(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_name text, p_address text, p_timezone text, p_receipt_prefix text, p_status text) from anon;
revoke all on function public.update_organization_settings(p_client_request_id uuid, p_organization_id uuid, p_default_currency text, p_country_code text, p_status text) from anon;
revoke all on function public.update_restaurant_settings(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_name text, p_currency_override text, p_timezone text, p_status text) from anon;
revoke all on function public.update_role(p_client_request_id uuid, p_membership_id uuid, p_new_role text) from anon;
revoke all on function public.upsert_floor_element(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_section_id uuid, p_kind text, p_id uuid, p_layout_x integer, p_layout_y integer, p_width_norm integer, p_height_norm integer, p_orientation_quarter_turns integer, p_label text) from anon;
revoke all on function public.upsert_printer_device(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_display_name text, p_connection_type text, p_role text, p_paper_width text, p_connection_config jsonb, p_is_enabled boolean) from anon;
revoke all on function public.upsert_quick_note_preset(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_id uuid, p_label text, p_is_active boolean) from anon;
revoke all on function public.upsert_table(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_label text, p_seats integer, p_area text, p_is_active boolean) from anon;
revoke all on function public.upsert_table_section(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_name text, p_is_active boolean) from anon;

-- ----------------------------------------------------------------------------
-- 2. Function EXECUTE — schema-wide catch-all (flat, standard SQL) for any
--    `public` function not in the explicit list above (e.g. one created between
--    this inventory and the apply). Only `anon` is named; `authenticated` and
--    `service_role` grants are untouched.
-- ----------------------------------------------------------------------------
revoke all privileges on all functions in schema public from anon;

-- ----------------------------------------------------------------------------
-- 3. Relations — every `public` table and view, explicitly (hosted inventory:
--    49 tables, 6 views). `revoke all privileges` covers SELECT, INSERT,
--    UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and MAINTAIN. RLS stays as
--    it is (enabled + forced everywhere except `plans`, which is enabled).
-- ----------------------------------------------------------------------------
revoke all privileges on table public.app_users from anon;
revoke all privileges on table public.audit_events from anon;
revoke all privileges on table public.branch_receipt_counters from anon;
revoke all privileges on table public.branches from anon;
revoke all privileges on table public.cash_drawer_sessions from anon;
revoke all privileges on table public.device_pairing_attempt_states from anon;
revoke all privileges on table public.device_pairings from anon;
revoke all privileges on table public.device_sessions from anon;
revoke all privileges on table public.devices from anon;
revoke all privileges on table public.employee_profiles from anon;
revoke all privileges on table public.item_sizes from anon;
revoke all privileges on table public.item_variants from anon;
revoke all privileges on table public.kitchen_pos_status_reports from anon;
revoke all privileges on table public.kitchen_print_dispatches from anon;
revoke all privileges on table public.kitchen_printer_readiness_reports from anon;
revoke all privileges on table public.management_request_results from anon;
revoke all privileges on table public.memberships from anon;
revoke all privileges on table public.menu_categories from anon;
revoke all privileges on table public.menu_item_branch_availability from anon;
revoke all privileges on table public.menu_items from anon;
revoke all privileges on table public.modifier_options from anon;
revoke all privileges on table public.modifiers from anon;
revoke all privileges on table public.order_item_modifiers from anon;
revoke all privileges on table public.order_items from anon;
revoke all privileges on table public.order_operations from anon;
revoke all privileges on table public.order_service_rounds from anon;
revoke all privileges on table public.orders from anon;
revoke all privileges on table public.organization_subscriptions from anon;
revoke all privileges on table public.organizations from anon;
revoke all privileges on table public.payments from anon;
revoke all privileges on table public.pin_attempt_states from anon;
revoke all privileges on table public.pin_sessions from anon;
revoke all privileges on table public.plans from anon;
revoke all privileges on table public.platform_admin_audit_events from anon;
revoke all privileges on table public.platform_admin_grants from anon;
revoke all privileges on table public.platform_support_sessions from anon;
revoke all privileges on table public.printer_devices from anon;
revoke all privileges on table public.printer_routes from anon;
revoke all privileges on table public.quick_note_presets from anon;
revoke all privileges on table public.restaurants from anon;
revoke all privileges on table public.shift_operations from anon;
revoke all privileges on table public.shifts from anon;
revoke all privileges on table public.stations from anon;
revoke all privileges on table public.sync_operations from anon;
revoke all privileges on table public.table_floor_elements from anon;
revoke all privileges on table public.table_group_members from anon;
revoke all privileges on table public.table_groups from anon;
revoke all privileges on table public.table_sections from anon;
revoke all privileges on table public.tables from anon;
-- views (security_invoker = true on all six; anon still must not SELECT them)
revoke all privileges on table public.daily_branch_sales_report from anon;
revoke all privileges on table public.daily_branch_shift_lines from anon;
revoke all privileges on table public.daily_branch_void_discount_reasons from anon;
revoke all privileges on table public.dashboard_org_daily_sales from anon;
revoke all privileges on table public.dashboard_restaurant_daily_sales from anon;
revoke all privileges on table public.organization_entitlements from anon;

-- schema-wide catch-all for relations/sequences created after the inventory
revoke all privileges on all tables    in schema public from anon;
revoke all privileges on all sequences in schema public from anon;

-- ----------------------------------------------------------------------------
-- 4. Schema boundary — make the existing state explicit: `anon` never gets
--    USAGE on `app`; `anon` KEEPS USAGE on `public` (PostgREST needs it and the
--    future Storefront allowlist lives there).
-- ----------------------------------------------------------------------------
revoke usage on schema app from anon;

-- ----------------------------------------------------------------------------
-- 5. Default privileges of the migration-running owner role in `public`.
--    Hosted (legacy "auto-expose new entities") carries
--      f: {postgres=X, anon=X, authenticated=X, service_role=X}
--      r: {postgres=arwdDxtm, anon=arwdDxtm, authenticated=arwdDxtm, service_role=arwdDxtm}
--      S: {postgres=rwU, anon=rwU, authenticated=rwU, service_role=rwU}
--    The local CLI stack (v2.107) carries the "always-revoked" shape
--      f: {postgres=X}   r: {…, anon=Dxtm, …}   S: {…, anon=w, …}
--    These statements remove ONLY the `anon` grantee from the `postgres`
--    defaults; `authenticated` / `service_role` defaults are not changed here.
--    Note: this closes the explicit anon stamp only; a new FUNCTION keeps the
--    built-in PUBLIC EXECUTE until `revoke ... from public` runs (house rule).
--    (Defaults owned by `supabase_admin` cannot be altered by `postgres` and do
--    not apply to migration-created objects; they are documented, not touched.)
-- ----------------------------------------------------------------------------
alter default privileges for role postgres in schema public revoke execute        on functions  from anon;
alter default privileges for role postgres in schema public revoke all privileges on tables     from anon;
alter default privileges for role postgres in schema public revoke all privileges on sequences  from anon;
-- global (schema-less) defaults for the same owner: none exist on hosted or
-- locally (inventory 2026-09-13), so these are no-ops that leave no row behind;
-- they close the only other place a future-object anon grant could come from.
alter default privileges for role postgres revoke execute        on functions  from anon;
alter default privileges for role postgres revoke all privileges on tables     from anon;
alter default privileges for role postgres revoke all privileges on sequences  from anon;

-- ----------------------------------------------------------------------------
-- 6. Assert the target posture. Any miss aborts the transaction, so hosted can
--    never end up half-applied.
-- ----------------------------------------------------------------------------
do $$
declare
  v_funcs      int;
  v_func_list  text;
  v_rels       int;
  v_rel_list   text;
  v_app_usage  boolean;
  v_pub_usage  boolean;
  v_defaults   int;
  v_auth_funcs int;
  v_all_funcs  int;
begin
  select count(*), string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_funcs, v_func_list
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.prokind = 'f'
    and has_function_privilege('anon', p.oid, 'EXECUTE');

  select count(*), string_agg(c.relname, ', ' order by c.relname)
    into v_rels, v_rel_list
  from pg_class c
  where c.relnamespace = 'public'::regnamespace
    and (
      (c.relkind in ('r', 'p', 'v', 'm') and (
           has_table_privilege('anon', c.oid, 'SELECT')
        or has_table_privilege('anon', c.oid, 'INSERT')
        or has_table_privilege('anon', c.oid, 'UPDATE')
        or has_table_privilege('anon', c.oid, 'DELETE')
        or has_table_privilege('anon', c.oid, 'TRUNCATE')
        or has_table_privilege('anon', c.oid, 'REFERENCES')
        or has_table_privilege('anon', c.oid, 'TRIGGER')
        or has_table_privilege('anon', c.oid, 'MAINTAIN')))
      or (c.relkind = 'S' and (
           has_sequence_privilege('anon', c.oid, 'USAGE')
        or has_sequence_privilege('anon', c.oid, 'SELECT')
        or has_sequence_privilege('anon', c.oid, 'UPDATE')))
    );

  v_app_usage := has_schema_privilege('anon', 'app', 'USAGE');
  v_pub_usage := has_schema_privilege('anon', 'public', 'USAGE');

  select count(*)
    into v_defaults
  from pg_default_acl d
  left join pg_namespace n on n.oid = d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) a
  where (n.nspname = 'public' or d.defaclnamespace = 0)
    and d.defaclrole = (select oid from pg_roles where rolname = 'postgres')
    and a.grantee   = (select oid from pg_roles where rolname = 'anon');

  select count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')), count(*)
    into v_auth_funcs, v_all_funcs
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.prokind = 'f';

  if v_funcs > 0 then
    raise exception 'SEC-001 posture NOT reached: % public function(s) still anon-executable: %', v_funcs, v_func_list;
  end if;
  if v_rels > 0 then
    raise exception 'SEC-001 posture NOT reached: % public relation(s) still carry an anon privilege: %', v_rels, v_rel_list;
  end if;
  if v_app_usage then
    raise exception 'SEC-001 posture NOT reached: anon has USAGE on schema app';
  end if;
  if not v_pub_usage then
    raise exception 'SEC-001 invariant broken: anon lost USAGE on schema public (PostgREST would break) — this file never revokes it; stop and review';
  end if;
  if v_defaults > 0 then
    raise exception 'SEC-001 posture NOT reached: % default-privilege entr(y/ies) for anon remain for role postgres (schema public or global)', v_defaults;
  end if;
  if v_auth_funcs <> v_all_funcs then
    raise exception 'SEC-001 invariant broken: only % of % public functions remain executable by authenticated — this file never touches authenticated; stop and review', v_auth_funcs, v_all_funcs;
  end if;

  raise notice 'SEC-001 posture reached: anon_exec_functions=0, anon_relations=0, anon_app_usage=false, anon_default_acl_entries(postgres; public+global)=0, authenticated_functions=%/%', v_auth_funcs, v_all_funcs;
end
$$;

-- ----------------------------------------------------------------------------
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   Re-opening anon authority is the defect this file removes, so no generic
--   rollback is provided here. If a hosted regression is proven, run ONLY the
--   evidence-derived recovery script
--   supabase/recovery/sec001_restore_prior_anon_privileges.sql, which re-grants
--   exactly the 78 function grants, 51 relation grants and 3 default-privilege
--   entries that the 2026-09-13 inventory found — never `GRANT ALL`.
-- ----------------------------------------------------------------------------
