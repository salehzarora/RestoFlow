-- RF-110 -- menu image storage: object-key parser app.menu_image_scope (DECISION
-- D-032; API_CONTRACT 4.24). Pure string parsing (no table access, no auth context),
-- so assertions run as the test connection. Proves a well-formed key parses to the
-- correct (org, restaurant, branch, menu_item) -- with 'global' mapped to a NULL
-- branch -- and that EVERY malformed key fails CLOSED by returning no row (it must
-- never raise a cast error). Key contract:
--   {org}/{restaurant}/{branch|'global'}/menu_item/{menu_item_id}/{image_id}.{ext}

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(23);

-- ===== well-formed: branch path parses to the exact scope (5) =====
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f1.png'))::int,
  1, 'valid branch key parses to one scope row');
select is((select organization_id from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f1.png')),
  '00000000-0000-0000-0000-0000000000a0'::uuid, 'organization_id parsed from segment 1');
select is((select restaurant_id from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f1.png')),
  '00000000-0000-0000-0000-0000000000a1'::uuid, 'restaurant_id parsed from segment 2');
select is((select branch_id from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f1.png')),
  '00000000-0000-0000-0000-0000000a1a00'::uuid, 'branch_id parsed from segment 3');
select is((select menu_item_id from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f1.png')),
  '00000000-0000-0000-0000-00000000da01'::uuid, 'menu_item_id parsed from segment 5');

-- ===== well-formed: 'global' maps to NULL branch (3) =====
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f2.png'))::int,
  1, 'valid global key parses to one scope row');
select ok((select branch_id is null from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f2.png')),
  'global branch segment maps to branch_id IS NULL');
select is((select menu_item_id from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f2.png')),
  '00000000-0000-0000-0000-00000000da01'::uuid, 'global key still parses menu_item_id');

-- ===== well-formed: allowed extensions, case-insensitive (4) =====
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f3.PNG'))::int,
  1, 'uppercase .PNG extension is accepted (case-insensitive)');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f3.jpg'))::int,
  1, '.jpg extension is accepted');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f3.jpeg'))::int,
  1, '.jpeg extension is accepted');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f3.webp'))::int,
  1, '.webp extension is accepted');

-- ===== malformed keys fail CLOSED -- no row, never raise (11) =====
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'too few segments (no menu_item literal level) -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/extra/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'too many segments -> denied');
select is((select count(*) from app.menu_image_scope(
  'not-a-uuid/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'invalid organization uuid -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/not-a-uuid/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'invalid restaurant uuid -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/not-a-branch/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'branch segment that is neither a uuid nor literal global -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/NOPE/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'wrong literal segment (not menu_item) -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/not-a-uuid/00000000-0000-0000-0000-0000000000f4.png'))::int,
  0, 'invalid menu_item_id uuid -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4.gif'))::int,
  0, 'disallowed extension (.gif) -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/not-a-uuid.png'))::int,
  0, 'image_id that is not a uuid -> denied');
select is((select count(*) from app.menu_image_scope(
  '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-0000000000f4'))::int,
  0, 'filename with no extension -> denied');
select is((select count(*) from app.menu_image_scope(null))::int,
  0, 'null key -> denied (no row, no error)');

select * from finish();
rollback;
