# RestoFlow — Menu / Product Readiness Audit

> Closing document of the Menu + Product Media + Admin Access sprint
> (2026-07-04, branch `feature/product-rescue-visible-mvp`). Honest status of
> the product/menu system for restaurant use. Companion: `LOCAL_RUNBOOK.md`
> (§7b platform admin), `RESTAURANT_DEMO_READINESS_AUDIT.md` (whole-app view).

## 1. READY — works end to end, for real

- **Product image upload** (dashboard): pick (web file dialog, zero-dep) →
  validate (png/jpeg/webp, ≤5 MiB, localized errors) → preview → upload to
  the private RF-110 `menu-images` bucket (org/restaurant/branch/item-scoped
  paths, membership-gated write policies) → the pointer persists on
  `menu_items.image_path` → replace/remove. Failures are visible and
  nothing ever pretends success.
- **POS shows product images** (real mode): items carry `image_path`; the
  paired POS device (a new, narrowly-scoped, read-only storage policy —
  POS devices only, own org only, KDS excluded) batch-resolves signed URLs
  and renders the image on the card and in the option sheet, falling back to
  the tinted icon band when anything is missing or fails.
- **Rich product fields**: description, item type (food/drink/side/combo/
  other), tags (spicy/vegetarian/popular/new — stored as stable wire strings,
  displayed localized), prep minutes, kitchen note, SKU (dashboard-only,
  never served to devices), and a generic attributes bag (portion label,
  patty count, patty weight g) — additive columns, validated server-side,
  round-tripping through the editor's six sections (Basic / Image / Pricing /
  Preparation / Options / Advanced-collapsed).
- **Modifier templates**: six one-tap templates (burger toppings, doneness,
  patty count, extras, drink size, spiciness) with sensible required/min/max
  and ILS-minor deltas; applied as ordinary per-item groups via the existing
  RPCs (copy-on-attach — D-031's per-item model respected), fully editable/
  deletable afterwards; names seed in the dashboard's active language
  (Arabic-first by default).
- **Cashier flow**: tapping an item with options opens the sheet with image +
  name + base price; every group shows Required/Optional and a live selected
  count (n/m, danger while a required minimum is unmet, warning at capacity);
  free options say "free", paid ones show signed ₪ deltas; a running total
  and the Add button update live; invalid selections are impossible; cart
  lines show each chosen option with its paid delta.
- **Kitchen display**: tickets keep structured `+ option` lines (Arabic data
  arrives in Arabic since templates seed localized names); kitchen note and
  prep fields now flow to kitchen sessions; money and images stay redacted
  (T-003 / T-014).
- **Catalog display**: dashboard item rows show thumbnail, price, tags,
  active state, and modifier-group count; the editor opens with a product
  summary strip; POS cards show up to two tag pills and an option-count
  indicator.
- **Admin access clarity**: the admin app now explains itself (Arabic-first:
  "هذه لوحة إدارة المنصة، وليست لوحة صاحب المطعم." / "استخدم Dashboard
  لإدارة المطعم.") with Open-Dashboard + Retry actions, an unconfigured help
  page, and a documented local platform-admin provisioning flow
  (LOCAL_RUNBOOK §7b + `_run_admin_real.bat`). No bypass was added; owners
  are never auto-granted platform access; live platform data still requires
  grant + MFA + audited reason server-side.

## 2. PARTIALLY READY

- **Device image reads need the standing human RLS sign-off** (RISK R-003):
  the new `menu_images_device_select` policy + `device_sessions.auth_user_id`
  binding are additive, read-only, POS-only and pgTAP-covered (9-cell
  matrix), but they are a new device→storage authorization primitive.
  Devices paired before this sprint must re-pair once to gain the binding.
- **Signed URLs expire (~30 min)** and the clients cache them per session —
  an expired URL degrades to the placeholder until reload. Fine for a demo;
  an expiry-aware cache is a follow-up.
- **Sizes/variants** are managed in the dashboard and served by `pos_menu`,
  but the POS still sells base-price items only (choosing a size on the POS
  is a follow-up).
- **Orphaned blobs**: a failed best-effort delete can leave an unreachable
  object in the bucket (no cleanup job yet).
- **Demo mode** previews images in memory only (honest "demo — not uploaded"
  note); demo POS cards are imageless.

## 3. NOT READY (known future features — none started)

Combos/meals as composed products · inventory/stock · taxes · delivery
integrations · advanced allergens · nutrition info · item availability by
time/day · reusable cross-item modifier groups (needs a D-031 architecture
ticket) · size selection on POS · image cropping/resizing.

## 4. How an owner configures a burger (exact flow)

1. Dashboard → Menu → add category (e.g. برجر), add item "برجر كلاسيك",
   price ₪48.00, type food, tags: popular.
2. In the item editor: Image section → pick photo → save image.
3. Preparation: prep minutes 12, kitchen note "بدون بصل عند الطلب".
4. Advanced (optional): patty count 1, patty weight 150g.
5. Options & modifiers → Add template → درجة الاستواء (required, choose 1)
   → Add template → إضافات البرجر (free toppings) → Add template →
   الإضافات المدفوعة (extras with ₪ deltas). Adjust any prices/names inline.

## 5. What the cashier sees

The burger card (photo, price, "3 option groups" hint, tag pill) → tap →
sheet: photo + برجر كلاسيك + السعر الأساسي ₪48.00 → درجة الاستواء marked
إلزامي 0/1 in red until chosen → toppings marked اختياري with مجاني labels →
extras with +₪ deltas → running الإجمالي updates → Add. The cart line lists
each chosen option (paid ones with +₪), and Send goes straight to the kitchen.

## 6. What the kitchen sees

The KDS ticket: order code + table + "برجر كلاسيك ×1" with indented lines
"+ وسط", "+ جبنة", "+ خس" (whatever was chosen, in the language the menu was
authored in). No prices, no images — quantities and preparation info only.

## 7. Verification status

Backend: pgTAP **170 files / 2,733 assertions PASS** on a fresh
`db reset` (includes the new 43-assertion image suite and 49-assertion
details suite: cross-tenant image write/read denials, KDS device denial,
kitchen key-omission, RPC single-overload + grants). Clients: all app and
package suites green after every part (POS 204, dashboard 158, feature_menu
113, KDS 80, admin 42). Guards: no hardcoded strings, no float money, no
secrets, l10n parity en/ar/he.
