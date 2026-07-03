// RF-112C — POS order flow helpers.
//
// Drives the real POS ordering surface (localhost:52096) after pairing + PIN
// sign-in: dine-in → table → add item → (if the item opens a modifier sheet)
// pick an option + add a note → Send → read the #XXXXXX order code. POS shows
// money (that is fine — only the KDS must stay money-free). Targets by ARIA role
// + accessible name from the Arabic (default) l10n; no Flutter app changes.

import { type Page } from '@playwright/test';
import { POS } from './constants';
import {
  openSurface,
  tapButton,
  tapText,
  fillField,
  waitForText,
  readText,
} from './dashboard';

const P = {
  dineIn: 'تناول في المطعم', // posOrderTypeDineIn (default is takeaway)
  assignTable: 'تعيين طاولة', // posAssignTable
  itemNote: 'ملاحظة للمنتج', // posModifierItemNoteLabel (only inside the modifier sheet)
  addWithTotal: /إضافة ·/, // posAddToCartWithTotal = "إضافة · {total}"
  sendOrder: 'إرسال الطلب', // posSendOrder
  submittedTitle: 'تم إرسال الطلب', // posOrderSubmittedTitle
};

/** '#' + 6 uppercase hex — the human order code (POS confirmation + KDS ticket). */
export const ORDER_CODE_RE = /#[0-9A-F]{6}/;

export async function openPos(page: Page): Promise<void> {
  await openSurface(page, POS);
}

export interface PlacedOrder {
  orderCode: string;
  modifierAdded: boolean;
  noteAdded: boolean;
}

/**
 * Place a dine-in order for `itemName` at `tableLabel`. If the item opens a
 * modifier sheet (a required group like "Drink size"), pick `optionName` and add
 * `note`; otherwise the item is added straight to the cart (modifier/note become
 * unavailable — reported, never faked). Returns the #XXXXXX order code + flags.
 */
export async function placeOrder(
  page: Page,
  opts: {
    tableLabel: string;
    itemName: string;
    optionName: string;
    note: string;
  },
): Promise<PlacedOrder> {
  // Dine-in (default is takeaway) → a table becomes required.
  await tapButton(page, P.dineIn);
  await page.waitForTimeout(400);
  await tapButton(page, P.assignTable);
  await tapText(page, opts.tableLabel); // pick the table tile → auto-closes the sheet
  await page.waitForTimeout(600);

  // Add the item by its (unique) name. A configurable item opens the sheet.
  await tapText(page, opts.itemName);

  let modifierAdded = false;
  let noteAdded = false;
  const option = page.getByRole('button', { name: opts.optionName }).first();
  await option.waitFor({ state: 'attached', timeout: 6_000 }).catch(() => {});
  if (await option.count()) {
    // Modifier sheet is open: pick the option, add the note, confirm.
    await option.click();
    modifierAdded = true;
    try {
      await fillField(page, P.itemNote, opts.note, 6_000);
      noteAdded = true;
    } catch {
      // Note field not reachable this run — leave noteAdded false (reported).
    }
    await page.getByRole('button', { name: P.addWithTotal }).first().click();
    await page.waitForTimeout(600);
  }

  // Send the order and read the human order code off the confirmation.
  await tapButton(page, P.sendOrder);
  await waitForText(page, P.submittedTitle);
  const text = await readText(page);
  const match = text.match(ORDER_CODE_RE);
  if (!match) {
    throw new Error(
      'POS: could not read a #XXXXXX order code after Send. Confirmation text: ' +
        text.slice(0, 200),
    );
  }
  return { orderCode: match[0], modifierAdded, noteAdded };
}
