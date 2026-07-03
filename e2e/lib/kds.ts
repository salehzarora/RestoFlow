// RF-112C — KDS live-board helpers.
//
// Drives the real KDS kitchen board (localhost:49622) after pairing + PIN
// sign-in: wait for the board, wait for the pushed ticket to arrive (polling
// sync, ~5s cadence), and expose the board text for the ticket-content +
// money-free assertions. The kitchen surface is money-REDACTED (SECURITY T-003).

import { expect, type Page } from '@playwright/test';
import { KDS } from './constants';
import {
  openSurface,
  tapButton,
  waitForText,
  readText,
  hasText,
} from './dashboard';

const K = {
  boardTitle: 'شاشة المطبخ', // kdsAppTitle = "ريستوفلو - شاشة المطبخ"
  acknowledge: 'استلام', // kdsAcknowledgeAction
};

export async function openKds(page: Page): Promise<void> {
  await openSurface(page, KDS);
}

/** Wait until the live kitchen board is up (app-bar title present). */
export async function waitForKdsBoard(page: Page, timeout = 30_000): Promise<void> {
  await waitForText(page, K.boardTitle, timeout);
}

/** Wait until a ticket carrying `orderCode` has arrived on the board (polling sync). */
export async function waitForTicket(
  page: Page,
  orderCode: string,
  timeout = 45_000,
): Promise<void> {
  await expect
    .poll(async () => await hasText(page, orderCode), {
      timeout,
      intervals: [1000, 1500, 2500],
    })
    .toBe(true);
}

/** The current board's aggregated accessible text (for content assertions). */
export async function readBoard(page: Page): Promise<string> {
  return readText(page);
}

/** Advance a received ticket one step (new → acknowledged). Best-effort. */
export async function acknowledgeTicket(page: Page): Promise<void> {
  await tapButton(page, K.acknowledge);
}
