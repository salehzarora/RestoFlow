// RF-112C — POS → KDS real-flow browser smoke.
//
// The end-to-end local MVP path: Dashboard setup → POS pairing → KDS pairing →
// staff PIN sign-in → POS dine-in order → KDS receives the ticket. Uses THREE
// isolated Playwright contexts (Dashboard / POS / KDS) so a prior manual session
// never interferes and each device starts UNPAIRED. Creates unique data each run
// (via the shared RF-112B setup), captures the real one-time pairing codes, and
// asserts the ticket's contents cross-app — including that the KDS stays
// money-free (SECURITY T-003). No db reset; no deletion of existing data; no app
// changes (drives by ARIA role + accessible name from the Arabic default l10n).

import { test, expect, type Browser } from '@playwright/test';
import { createBranchSetup } from '../lib/setup_flow';
import { pairDevice, pinSignIn } from '../lib/device_auth';
import { openPos, placeOrder, ORDER_CODE_RE } from '../lib/pos';
import { openKds, waitForKdsBoard, waitForTicket, readBoard, acknowledgeTicket } from '../lib/kds';
import { KDS_MONEY_TOKENS } from '../lib/tokens';

const WIDE = {
  viewport: { width: 1600, height: 1200 },
  // Dashboard reads the one-time pairing code via Copy → clipboard (canvas-painted).
  permissions: ['clipboard-read', 'clipboard-write'],
};

async function freshPage(browser: Browser) {
  const context = await browser.newContext(WIDE);
  const page = await context.newPage();
  return { context, page };
}

test('POS → KDS: a real dine-in order reaches the kitchen ticket board', async ({
  browser,
}) => {
  test.slow(); // long cross-app real-mode flow with several DDC debug boots
  const notes: string[] = [];

  // ── 1. Dashboard: create a fresh branch + capture the pairing codes ──────
  const dash = await freshPage(browser);
  const setup = await createBranchSetup(dash.page);
  expect(setup.posCode, 'POS pairing code captured').toMatch(/^[0-9a-f]{32}$/);
  expect(setup.kdsCode, 'KDS pairing code captured').toMatch(/^[0-9a-f]{32}$/);
  notes.push(...setup.notes);

  // ── 2. POS: pair → PIN sign-in (cashier) → place a dine-in order ─────────
  const pos = await freshPage(browser);
  await openPos(pos.page);
  await pairDevice(pos.page, setup.posCode);
  await pinSignIn(pos.page, setup.cashierName, setup.pin);
  const note = 'RF112C بدون بصل';
  const order = await placeOrder(pos.page, {
    tableLabel: setup.tableLabel,
    itemName: setup.itemName,
    optionName: 'صغير', // menuTemplateOptSmall (free option of the Drink size group)
    note,
  });
  expect(order.orderCode, 'POS shows a #XXXXXX order code').toMatch(ORDER_CODE_RE);
  notes.push(
    `POS order ${order.orderCode} — modifier ${order.modifierAdded ? 'added' : 'N/A'}, ` +
      `note ${order.noteAdded ? 'added' : 'N/A'}`,
  );

  // ── 3. KDS: pair → PIN sign-in (kitchen) → receive the ticket ────────────
  const kds = await freshPage(browser);
  await openKds(kds.page);
  await pairDevice(kds.page, setup.kdsCode);
  await pinSignIn(kds.page, setup.kitchenName, setup.pin);
  await waitForKdsBoard(kds.page);
  await waitForTicket(kds.page, order.orderCode);

  const board = await readBoard(kds.page);
  expect(board, 'KDS ticket carries the same order code').toContain(order.orderCode);
  expect(board, 'KDS ticket shows the table').toContain(setup.tableLabel);
  expect(board, 'KDS ticket shows the item').toContain(setup.itemName);
  if (order.modifierAdded) {
    expect(board, 'KDS ticket shows the selected modifier').toContain('صغير');
  }
  if (order.noteAdded) {
    expect(board, 'KDS ticket shows the item note').toContain(note);
  }

  // KDS must NEVER expose money (T-003) — no currency, on a LIVE ticket.
  for (const token of KDS_MONEY_TOKENS) {
    expect(board, `KDS live ticket must stay money-free (no "${token}")`).not.toContain(
      token,
    );
  }

  // Optional single forward step (new → acknowledged); best-effort, non-blocking.
  await acknowledgeTicket(kds.page).catch(() =>
    notes.push('kds: acknowledge step skipped'),
  );

  // eslint-disable-next-line no-console
  console.log('RF-112C notes:', notes.join(' | '));
});
