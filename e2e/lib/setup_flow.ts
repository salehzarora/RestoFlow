// RF-112B/C — shared Dashboard setup flow.
//
// Drives the real Dashboard through the owner setup that prepares a fresh branch
// for POS/KDS, asserts real-mode + Arabic-first + Setup-Center progress (the
// RF-112B checks), and RETURNS the created data — including the two one-time
// pairing codes — so RF-112C can pair the POS/KDS and place an order. Creates
// unique timestamped data each run; no db reset; no deletion of existing data.

import { expect, type Page } from '@playwright/test';
import {
  openDashboard,
  readText,
  waitForText,
  hasText,
  tapButton,
  tapText,
  tapNav,
  fillField,
  fillPassword,
  fillPasswordAt,
  selectDropdown,
} from './dashboard';
import { DEMO_BANNER_PHRASES, ARABIC_SCRIPT } from './tokens';

// Arabic (default-locale) accessible names, from packages/l10n/lib/l10n/app_ar.arb.
const L = {
  createAccountTab: 'إنشاء حساب',
  email: 'البريد الإلكتروني',
  restaurant: 'اسم المطعم',
  branch: 'اسم الفرع (اختياري)',
  createRestaurant: 'إنشاء المطعم',
  real: 'حقيقي',
  setupTitle: 'الإعداد',
  navMenu: 'القائمة',
  navTables: 'الطاولات',
  navDevices: 'الأجهزة',
  navStaff: 'الموظفون',
  navOverview: 'نظرة عامة',
  addCategory: 'إضافة فئة',
  name: 'الاسم',
  save: 'حفظ',
  addItem: 'إضافة عنصر',
  basePrice: 'السعر الأساسي',
  addTemplate: 'إضافة قالب',
  drinkSize: 'حجم المشروب',
  cancel: 'إلغاء',
  addTable: 'إضافة طاولة',
  tableField: 'اسم / رقم الطاولة',
  addDevice: 'إضافة جهاز',
  deviceLabel: 'اسم الجهاز',
  deviceTypePos: 'نقطة بيع',
  deviceTypeKds: 'شاشة مطبخ',
  create: 'إنشاء',
  issueCode: 'إصدار رمز',
  codeIssuedTitle: 'رمز التسجيل',
  shownOnce: 'يُعرض مرة واحدة',
  done: 'تم',
  addStaff: 'إضافة موظف',
  staffName: 'الاسم المعروض',
  roleCashier: 'أمين الصندوق',
  roleKitchen: 'طاقم المطبخ',
  setPin: 'تعيين PIN',
  pinSaved: 'تم حفظ رقم PIN',
};

const PASSWORD = 'Rf112b-Local-Test!'; // local-only test credential

export interface BranchSetup {
  email: string;
  restaurant: string;
  branch: string;
  categoryName: string;
  itemName: string;
  tableLabel: string;
  posDeviceName: string;
  kdsDeviceName: string;
  /** One-time enrollment codes read from the Dashboard issue-code dialogs. */
  posCode: string;
  kdsCode: string;
  cashierName: string;
  kitchenName: string;
  pin: string;
  /** True if the "Drink size" modifier template attached (best-effort). */
  modifierAttached: boolean;
  notes: string[];
}

const CODE_RE = /[0-9a-f]{32}/; // real backend = UUID with dashes stripped

/**
 * Read the one-time code out of the open issue-code dialog. The code renders as a
 * read-only SelectableText painted to canvas — its value is NOT in the DOM
 * (disabled textbox, empty aria-label/textContent). The reliable path is the Copy
 * button: it copies the exact secret to the clipboard (the context must grant
 * clipboard permissions). A DOM read is kept as a best-effort fallback.
 */
async function readPairingCode(page: Page): Promise<string> {
  await page.waitForTimeout(400);
  // Primary: hook navigator.clipboard.writeText, tap Copy ('نسخ' = adminCopy), and
  // read back the exact string Flutter copied — independent of read permission.
  try {
    await page.evaluate(() => {
      const w = window as unknown as { __copied?: string[] };
      w.__copied = [];
      if (navigator.clipboard && navigator.clipboard.writeText) {
        const orig = navigator.clipboard.writeText.bind(navigator.clipboard);
        navigator.clipboard.writeText = (t: string) => {
          w.__copied!.push(String(t));
          try {
            return orig(t);
          } catch {
            return Promise.resolve();
          }
        };
      }
    });
    await tapButton(page, 'نسخ', { timeout: 6_000 });
    await page.waitForTimeout(300);
    const copied = await page.evaluate(() => {
      const w = window as unknown as { __copied?: string[] };
      const hooked = (w.__copied ?? []).join(' ');
      return navigator.clipboard
        .readText()
        .then((c) => `${hooked} ${c}`)
        .catch(() => hooked);
    });
    const fromCopy = copied.match(CODE_RE);
    if (fromCopy) return fromCopy[0];
  } catch {
    // Copy unreachable / clipboard blocked — fall through to the DOM read.
  }
  // Fallback: scrape any input value / aria-label / text on the page.
  const domText = await page.evaluate(() => {
    const parts: string[] = [];
    document
      .querySelectorAll('input, textarea, [aria-label], flt-semantics')
      .forEach((node) => {
        const el = node as HTMLElement & { value?: string };
        if (el.value) parts.push(el.value);
        const label = el.getAttribute('aria-label');
        if (label) parts.push(label);
        if (el.textContent) parts.push(el.textContent);
      });
    return parts.join(' ');
  });
  const match = domText.match(CODE_RE);
  if (!match) {
    throw new Error(
      'RF-112C: could not read a 32-hex pairing code from the issue-code dialog ' +
        '(clipboard + DOM both empty). Is the Dashboard in real mode with Supabase up, ' +
        'and does the context grant clipboard permissions?',
    );
  }
  return match[0];
}

/**
 * Run the full owner setup on the Dashboard `page` and return the created data.
 * Asserts the RF-112B invariants along the way (real mode, Arabic-first, the
 * Setup-Center steps clearing) so this doubles as the RF-112B test body.
 */
export async function createBranchSetup(page: Page): Promise<BranchSetup> {
  const stamp = Date.now();
  const setup: BranchSetup = {
    email: `rf112c-smoke-${stamp}@example.test`,
    restaurant: `RF112 Diner ${stamp}`,
    branch: `RF112 Branch ${stamp}`,
    categoryName: `قسم ${stamp}`,
    itemName: `طبق ${stamp}`,
    tableLabel: `T-RF112-${stamp % 100000}`,
    posDeviceName: `POS ${stamp}`,
    kdsDeviceName: `KDS ${stamp}`,
    posCode: '',
    kdsCode: '',
    cashierName: `كاشير ${stamp}`,
    kitchenName: `مطبخ ${stamp}`,
    pin: '4321',
    modifierAttached: false,
    notes: [],
  };

  // ── Sign up ──────────────────────────────────────────────────────────────
  await openDashboard(page);
  const landing = await readText(page);
  for (const phrase of DEMO_BANNER_PHRASES) expect(landing).not.toContain(phrase);
  expect(ARABIC_SCRIPT.test(landing), 'Arabic-first landing').toBeTruthy();

  await tapButton(page, L.createAccountTab, { which: 'first' });
  await fillField(page, L.email, setup.email);
  await fillPassword(page, PASSWORD);
  await fillField(page, L.restaurant, setup.restaurant);
  await fillField(page, L.branch, setup.branch);
  await tapButton(page, L.createAccountTab, { which: 'last' });

  // ── Onboard ──────────────────────────────────────────────────────────────
  await waitForText(page, L.createRestaurant);
  await fillField(page, L.restaurant, setup.restaurant);
  await fillField(page, L.branch, setup.branch);
  await tapButton(page, L.createRestaurant, { which: 'last' });

  // ── Shell: real mode, not demo ───────────────────────────────────────────
  await waitForText(page, L.real);
  const shell = await readText(page);
  for (const phrase of DEMO_BANNER_PHRASES) expect(shell).not.toContain(phrase);
  expect(shell, 'setup center present').toContain(L.setupTitle);

  // ── Menu: category + item (+ best-effort modifier) ───────────────────────
  await tapNav(page, L.navMenu);
  await tapButton(page, L.addCategory, { which: 'first' });
  await fillField(page, L.name, setup.categoryName);
  await tapButton(page, L.save);
  await waitForText(page, setup.categoryName);
  await tapText(page, setup.categoryName);

  await tapButton(page, L.addItem, { which: 'first' });
  await fillField(page, L.name, setup.itemName);
  await fillField(page, L.basePrice, '45');
  await tapButton(page, L.save);
  await waitForText(page, setup.itemName);

  try {
    await tapText(page, setup.itemName);
    await tapButton(page, L.addTemplate, { timeout: 8_000 });
    await tapText(page, L.drinkSize);
    await waitForText(page, L.drinkSize, 12_000);
    setup.modifierAttached = true;
    setup.notes.push('modifier: attached "Drink size" template (free+paid options)');
  } catch (error) {
    setup.notes.push(
      `modifier: SKIPPED (best-effort) — ${String(error).slice(0, 120)}`,
    );
  } finally {
    await tapButton(page, L.cancel, { timeout: 8_000 }).catch(() => {});
    await page.waitForTimeout(600);
  }

  // ── Tables ───────────────────────────────────────────────────────────────
  await tapNav(page, L.navTables);
  await tapButton(page, L.addTable, { which: 'first' });
  await fillField(page, L.tableField, setup.tableLabel);
  await tapButton(page, L.save, { which: 'last' });
  await waitForText(page, setup.tableLabel);

  // ── Devices: POS + KDS, capturing each one-time pairing code ─────────────
  // Create + issue INTERLEAVED so the code belongs to the right device: the tile
  // list is newest-first, so we issue each device's code while it is the only one
  // present (its "Issue code" is unambiguous), then create the next.
  await tapNav(page, L.navDevices);
  // POS device (type defaults to POS) → issue + capture its code.
  await tapButton(page, L.addDevice, { which: 'first' });
  await fillField(page, L.deviceLabel, setup.posDeviceName);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, setup.posDeviceName);
  await tapButton(page, L.issueCode, { which: 'first' });
  await waitForText(page, L.codeIssuedTitle);
  expect(await hasText(page, L.shownOnce), 'shown-once warning').toBeTruthy();
  setup.posCode = await readPairingCode(page);
  await tapButton(page, L.done, { which: 'last' });
  // KDS device → issue + capture its code (POS is now code_issued, so its Issue
  // button is gone → the only remaining "Issue code" is the KDS tile's).
  await tapButton(page, L.addDevice, { which: 'first' });
  await fillField(page, L.deviceLabel, setup.kdsDeviceName);
  await selectDropdown(page, L.deviceTypePos, L.deviceTypeKds);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, setup.kdsDeviceName);
  await tapButton(page, L.issueCode, { which: 'first' });
  await waitForText(page, L.codeIssuedTitle);
  setup.kdsCode = await readPairingCode(page);
  await tapButton(page, L.done, { which: 'last' });

  // ── Staff: cashier + kitchen, each with a PIN ────────────────────────────
  await tapNav(page, L.navStaff);
  await tapButton(page, L.addStaff, { which: 'first' });
  await fillField(page, L.staffName, setup.cashierName);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, setup.cashierName);
  await tapButton(page, L.addStaff, { which: 'first' });
  await fillField(page, L.staffName, setup.kitchenName);
  await selectDropdown(page, L.roleCashier, L.roleKitchen);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, setup.kitchenName);

  await tapButton(page, L.setPin, { which: 'first' });
  await fillPasswordAt(page, 0, setup.pin);
  await fillPasswordAt(page, 1, setup.pin);
  await tapButton(page, L.setPin, { which: 'last' });
  await waitForText(page, L.pinSaved).catch(() =>
    setup.notes.push('staff: pinSaved snackbar not observed (transient)'),
  );

  await tapButton(page, L.setPin, { which: 'first' });
  await fillPasswordAt(page, 0, setup.pin);
  await fillPasswordAt(page, 1, setup.pin);
  await tapButton(page, L.setPin, { which: 'last' });
  await page.waitForTimeout(1500);

  // ── Setup Center reflects meaningful progress ────────────────────────────
  await tapNav(page, L.navOverview);
  await waitForText(page, L.setupTitle);
  const resolvedSteps: Record<string, string> = {
    'menu item': 'لا توجد أصناف في القائمة بعد',
    'POS device': 'لا يوجد جهاز نقطة بيع بعد',
    'KDS device': 'لا توجد شاشة مطبخ بعد',
    'staff PIN': 'لا يملك أي موظف رقم PIN بعد',
  };
  await expect
    .poll(async () => await hasText(page, resolvedSteps['staff PIN']), {
      timeout: 20_000,
      intervals: [500, 800, 1200],
    })
    .toBe(false);
  const overview = await readText(page);
  for (const [dimension, phrase] of Object.entries(resolvedSteps)) {
    expect(
      overview,
      `setup step for "${dimension}" should be resolved`,
    ).not.toContain(phrase);
  }

  return setup;
}
