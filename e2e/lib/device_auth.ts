// RF-112C — shared POS/KDS device pairing + staff PIN sign-in.
//
// POS and KDS use the SAME shared screens (feature_auth DevicePairingScreen +
// PinLoginScreen), so these helpers drive both. Money-free by design (a KDS
// renders them too — SECURITY T-003). Targets by ARIA role + accessible name from
// the Arabic (default) l10n; no Flutter app changes.

import { type Page } from '@playwright/test';
import {
  tapButton,
  tapText,
  fillField,
  fillPassword,
  waitForText,
} from './dashboard';

const L = {
  pairingCodeLabel: 'رمز الاقتران', // pairingCodeLabel
  pairAction: 'اقتران الجهاز', // pairingPairAction
  invalidCode: 'لم يُقبل رمز الاقتران', // pairingInvalidCode
  pinPickName: 'اختر اسمك', // pinLoginPickName
  pinSubmit: 'تسجيل الدخول', // pinLoginSubmit
  pinWrong: 'رقم PIN خاطئ', // pinLoginWrongPin
};

/** Enter a one-time enrollment code on the pairing screen and submit. */
export async function pairDevice(page: Page, code: string): Promise<void> {
  await waitForText(page, L.pairAction); // pairing screen is up
  await fillField(page, L.pairingCodeLabel, code);
  await tapButton(page, L.pairAction);
}

/**
 * Sign in on the staff PIN screen: pick the member by display name, enter the
 * PIN (obscured field), submit. Assumes pairing already succeeded (the PIN screen
 * is shown). Throws on a wrong-PIN banner rather than hanging.
 */
export async function pinSignIn(
  page: Page,
  staffName: string,
  pin: string,
): Promise<void> {
  await waitForText(page, L.pinPickName); // staff picker is up
  await tapText(page, staffName); // the staff tile (name + role in its a11y name)
  await fillPassword(page, pin); // the single obscured PIN field
  await tapButton(page, L.pinSubmit);
}
