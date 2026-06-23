-- ============================================================================
-- RF-075 — pgTAP: report views exist with the documented columns (schema)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

-- the three read-only report views exist in public
select has_view('public', 'daily_branch_sales_report',          'daily_branch_sales_report view exists');
select has_view('public', 'daily_branch_shift_lines',           'daily_branch_shift_lines view exists');
select has_view('public', 'daily_branch_void_discount_reasons', 'daily_branch_void_discount_reasons view exists');

-- sales summary columns (integer _minor buckets + scope/day)
select has_column('public', 'daily_branch_sales_report', 'organization_id',      'sales: organization_id');
select has_column('public', 'daily_branch_sales_report', 'branch_id',            'sales: branch_id');
select has_column('public', 'daily_branch_sales_report', 'business_day',         'sales: business_day');
select has_column('public', 'daily_branch_sales_report', 'currency_code',        'sales: currency_code');
select has_column('public', 'daily_branch_sales_report', 'order_count',          'sales: order_count');
select has_column('public', 'daily_branch_sales_report', 'gross_minor',          'sales: gross_minor');
select has_column('public', 'daily_branch_sales_report', 'discount_total_minor', 'sales: discount_total_minor');
select has_column('public', 'daily_branch_sales_report', 'net_sales_minor',      'sales: net_sales_minor');
select has_column('public', 'daily_branch_sales_report', 'tax_total_minor',      'sales: tax_total_minor');
select has_column('public', 'daily_branch_sales_report', 'void_count',           'sales: void_count');
select has_column('public', 'daily_branch_sales_report', 'void_total_minor',     'sales: void_total_minor');
select has_column('public', 'daily_branch_sales_report', 'collected_total_minor','sales: collected_total_minor');
select has_column('public', 'daily_branch_sales_report', 'collected_cash_minor', 'sales: collected_cash_minor');

-- shift lines: authoritative reconciliation fields + provisional flag
select has_column('public', 'daily_branch_shift_lines', 'variance_minor', 'shift: variance_minor');
select has_column('public', 'daily_branch_shift_lines', 'is_provisional', 'shift: is_provisional');

-- void/discount reasons: AC3 fields
select has_column('public', 'daily_branch_void_discount_reasons', 'reason',        'reasons: reason');
select has_column('public', 'daily_branch_void_discount_reasons', 'discount_type', 'reasons: discount_type');

select * from finish();
rollback;
