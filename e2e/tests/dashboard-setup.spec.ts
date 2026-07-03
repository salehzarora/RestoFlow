// RF-112B — Dashboard setup browser smoke.
//
// Drives the real Dashboard (localhost:57026) through the owner setup flow that
// prepares a branch for POS/KDS: sign up → onboard → menu category + item →
// (best-effort) modifier → table → POS + KDS devices with pairing codes → cashier
// + kitchen staff with PINs → assert the Setup Center reflects real progress.
//
// It creates UNIQUE data each run (timestamped) and needs NO db reset. Each test
// gets a fresh Playwright context (isolated storage), so it always starts signed
// out. Targets elements by ARIA role + accessible name from the Arabic (default)
// l10n — no Flutter app changes. POS/KDS deep flow (pairing, PIN sign-in, orders,
// ticket receipt) is RF-112C, intentionally NOT here.

import { test, expect } from '@playwright/test';
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
} from '../lib/dashboard';
import { DEMO_BANNER_PHRASES, ARABIC_SCRIPT } from '../lib/tokens';

// A wide viewport so the shell's side-nav (with always-visible labels) is used,
// not the narrow bottom bar (which hides non-selected tab labels).
test.use({ viewport: { width: 1600, height: 1200 } });

// Arabic (default-locale) accessible names the smoke targets. Centralised so an
// l10n change is a one-line update. Sourced from packages/l10n/lib/l10n/app_ar.arb.
const L = {
  // auth + onboarding
  createAccountTab: 'إنشاء حساب',
  email: 'البريد الإلكتروني',
  restaurant: 'اسم المطعم',
  branch: 'اسم الفرع (اختياري)',
  createRestaurant: 'إنشاء المطعم',
  // shell
  real: 'حقيقي',
  setupTitle: 'الإعداد',
  navMenu: 'القائمة',
  navTables: 'الطاولات',
  navDevices: 'الأجهزة',
  navStaff: 'الموظفون',
  navOverview: 'نظرة عامة',
  // menu
  addCategory: 'إضافة فئة',
  name: 'الاسم',
  save: 'حفظ',
  addItem: 'إضافة عنصر',
  basePrice: 'السعر الأساسي',
  addTemplate: 'إضافة قالب',
  drinkSize: 'حجم المشروب',
  cancel: 'إلغاء',
  // tables
  addTable: 'إضافة طاولة',
  tableField: 'اسم / رقم الطاولة',
  // devices
  addDevice: 'إضافة جهاز',
  deviceLabel: 'اسم الجهاز',
  deviceTypePos: 'نقطة بيع',
  deviceTypeKds: 'شاشة مطبخ',
  create: 'إنشاء',
  issueCode: 'إصدار رمز',
  codeIssuedTitle: 'رمز التسجيل',
  shownOnce: 'يُعرض مرة واحدة',
  done: 'تم',
  // staff
  addStaff: 'إضافة موظف',
  staffName: 'الاسم المعروض',
  roleCashier: 'أمين الصندوق',
  roleKitchen: 'طاقم المطبخ',
  setPin: 'تعيين PIN',
  pinSaved: 'تم حفظ رقم PIN',
};

const PASSWORD = 'Rf112b-Local-Test!'; // local-only test credential

test('Dashboard setup: prepare a fresh branch for POS/KDS', async ({ page }) => {
  test.slow(); // long real-mode flow with several DDC debug screen loads
  const stamp = Date.now();
  const email = `rf112b-smoke-${stamp}@example.test`;
  const restaurant = `RF112B Diner ${stamp}`;
  const branch = `RF112B Branch ${stamp}`;
  const categoryName = `قسم ${stamp}`;
  const itemName = `طبق ${stamp}`;
  const tableLabel = `T-RF112B-${stamp % 100000}`;
  const posName = `POS ${stamp}`;
  const kdsName = `KDS ${stamp}`;
  const cashierName = `كاشير ${stamp}`;
  const kitchenName = `مطبخ ${stamp}`;
  const pin = '4321';
  const notes: string[] = [];

  // ── Sign up ──────────────────────────────────────────────────────────────
  await openDashboard(page);
  const landing = await readText(page);
  for (const phrase of DEMO_BANNER_PHRASES) expect(landing).not.toContain(phrase);
  expect(ARABIC_SCRIPT.test(landing), 'Arabic-first landing').toBeTruthy();

  await tapButton(page, L.createAccountTab, { which: 'first' });
  await fillField(page, L.email, email);
  await fillPassword(page, PASSWORD);
  await fillField(page, L.restaurant, restaurant);
  await fillField(page, L.branch, branch);
  await tapButton(page, L.createAccountTab, { which: 'last' });

  // ── Onboard (create restaurant) ──────────────────────────────────────────
  await waitForText(page, L.createRestaurant);
  await fillField(page, L.restaurant, restaurant);
  await fillField(page, L.branch, branch);
  await tapButton(page, L.createRestaurant, { which: 'last' });

  // ── Land in the shell: real mode, not demo ───────────────────────────────
  await waitForText(page, L.real);
  const shell = await readText(page);
  for (const phrase of DEMO_BANNER_PHRASES) expect(shell).not.toContain(phrase);
  expect(shell, 'setup center present').toContain(L.setupTitle);

  // ── Menu: category + item (+ best-effort modifier) ───────────────────────
  await tapNav(page, L.navMenu);
  await tapButton(page, L.addCategory, { which: 'first' });
  await fillField(page, L.name, categoryName);
  await tapButton(page, L.save);
  await waitForText(page, categoryName);
  await tapText(page, categoryName); // select the category

  await tapButton(page, L.addItem, { which: 'first' });
  await fillField(page, L.name, itemName);
  await fillField(page, L.basePrice, '45');
  await tapButton(page, L.save); // item editor top-bar save (auto-closes)
  await waitForText(page, itemName);

  // Modifier attach is best-effort (re-open item → add a mixed free+paid template).
  // The inline editor is a full-screen surface that covers the side-nav and an
  // existing-item save does NOT auto-close it, so we always close via Cancel.
  try {
    await tapText(page, itemName); // re-open the item (opens the inline editor)
    await tapButton(page, L.addTemplate, { timeout: 8_000 });
    await tapText(page, L.drinkSize);
    await waitForText(page, L.drinkSize, 12_000);
    notes.push('modifier: attached "Drink size" template (free+paid options)');
  } catch (error) {
    notes.push(`modifier: SKIPPED (best-effort) — ${String(error).slice(0, 120)}`);
  } finally {
    await tapButton(page, L.cancel, { timeout: 8_000 }).catch(() => {});
    await page.waitForTimeout(600);
  }

  // ── Tables: add T-RF112B ─────────────────────────────────────────────────
  await tapNav(page, L.navTables);
  await tapButton(page, L.addTable, { which: 'first' });
  await fillField(page, L.tableField, tableLabel);
  await tapButton(page, L.save, { which: 'last' }); // dialog Save (adminSave = حفظ)
  await waitForText(page, tableLabel);

  // ── Devices: POS + KDS, each with a one-time pairing code ────────────────
  await tapNav(page, L.navDevices);
  // POS device (type defaults to POS).
  await tapButton(page, L.addDevice, { which: 'first' });
  await fillField(page, L.deviceLabel, posName);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, posName);
  // KDS device (switch the type dropdown).
  await tapButton(page, L.addDevice, { which: 'first' });
  await fillField(page, L.deviceLabel, kdsName);
  await selectDropdown(page, L.deviceTypePos, L.deviceTypeKds);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, kdsName);

  // Issue a pairing code for each. After the POS code is issued its own "Issue
  // code" button disappears, so .first() then targets the KDS tile.
  await tapButton(page, L.issueCode, { which: 'first' });
  await waitForText(page, L.codeIssuedTitle);
  expect(await hasText(page, L.shownOnce), 'shown-once warning').toBeTruthy();
  await tapButton(page, L.done, { which: 'last' });

  await tapButton(page, L.issueCode, { which: 'first' });
  await waitForText(page, L.codeIssuedTitle);
  await tapButton(page, L.done, { which: 'last' });

  // ── Staff: cashier + kitchen, each with a PIN ────────────────────────────
  await tapNav(page, L.navStaff);
  // Cashier (role defaults to cashier).
  await tapButton(page, L.addStaff, { which: 'first' });
  await fillField(page, L.staffName, cashierName);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, cashierName);
  // Kitchen staff (switch the role dropdown).
  await tapButton(page, L.addStaff, { which: 'first' });
  await fillField(page, L.staffName, kitchenName);
  await selectDropdown(page, L.roleCashier, L.roleKitchen);
  await tapButton(page, L.create, { which: 'last' });
  await waitForText(page, kitchenName);

  // Set a PIN for each. After the first card's PIN is set its button becomes
  // "Reset PIN", so the remaining "Set PIN" card button targets the other member.
  await tapButton(page, L.setPin, { which: 'first' });
  await fillPasswordAt(page, 0, pin);
  await fillPasswordAt(page, 1, pin);
  await tapButton(page, L.setPin, { which: 'last' }); // dialog confirm
  await waitForText(page, L.pinSaved).catch(() => notes.push('staff: pinSaved snackbar not observed (transient)'));

  await tapButton(page, L.setPin, { which: 'first' });
  await fillPasswordAt(page, 0, pin);
  await fillPasswordAt(page, 1, pin);
  await tapButton(page, L.setPin, { which: 'last' });
  await page.waitForTimeout(1500);

  // ── Setup Center reflects meaningful progress ────────────────────────────
  await tapNav(page, L.navOverview);
  await waitForText(page, L.setupTitle);
  // Meaningful progress = the pending-setup steps for the dimensions we completed
  // have disappeared. The printer step and the device-PAIRING step legitimately
  // remain (adding a printer + pairing on-device are out of RF-112B scope), so we
  // assert per-dimension resolution rather than "everything done".
  const resolvedSteps: Record<string, string> = {
    'menu item': 'لا توجد أصناف في القائمة بعد', // setupNoMenu
    'POS device': 'لا يوجد جهاز نقطة بيع بعد', // setupNoPosDevice
    'KDS device': 'لا توجد شاشة مطبخ بعد', // setupNoKdsDevice
    'staff PIN': 'لا يملك أي موظف رقم PIN بعد', // setupNoStaffPin
  };
  // Let the setup center reload its counts, then confirm the staff-PIN step cleared.
  await expect
    .poll(async () => await hasText(page, resolvedSteps['staff PIN']), {
      timeout: 20_000,
      intervals: [500, 800, 1200],
    })
    .toBe(false);
  const overview = await readText(page);
  for (const [dimension, phrase] of Object.entries(resolvedSteps)) {
    expect(overview, `setup step for "${dimension}" should be resolved`).not.toContain(
      phrase,
    );
  }

  // eslint-disable-next-line no-console
  console.log('RF-112B notes:', notes.join(' | ') || '(none)');
});
