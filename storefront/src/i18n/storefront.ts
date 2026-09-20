/**
 * Storefront chrome strings.
 *
 * The design handoff is explicit that there is NO runtime fallback chain and no
 * missing-key state: every key exists in all three dictionaries. That rule is
 * enforced by the shared `StorefrontMessages` type — a locale missing a key is
 * a compile error, not a render-time blank.
 */
import ar from '../../messages/storefront.ar.json';
import he from '../../messages/storefront.he.json';
import en from '../../messages/storefront.en.json';
import type { Locale } from './locales';

export interface StorefrontMessages {
  readonly welcome: string;
  readonly explore: string;
  readonly poweredBy: string;
  readonly langLabel: string;
  readonly search: string;
  readonly openNow: string;
  readonly closed: string;
  readonly paused: string;
  readonly closesAt: string;
  readonly opensAt: string;
  readonly pickup: string;
  readonly delivery: string;
  readonly pickupOff: string;
  readonly deliveryOff: string;
  readonly fromFee: string;
  readonly hours: string;
  readonly back: string;
  readonly close: string;
  readonly unknownTitle: string;
  readonly unknownBody: string;
  readonly prevCategory: string;
  readonly nextCategory: string;
  readonly orderNow: string;
  readonly from: string;
  readonly addShort: string;
  readonly viewAll: string;
  readonly pickupShort: string;
  readonly mostOrdered: string;
  readonly last30: string;
  readonly chefPicks: string;
  readonly chefPick: string;
  readonly rankN: string;
  readonly soldOut: string;
  readonly badgeNew: string;
  readonly badgeDeal: string;
  readonly unavailableNow: string;
  readonly viewCart: string;
  readonly items: string;
  readonly item: string;
  readonly cart: string;
  readonly subtotal: string;
  readonly tax: string;
  readonly total: string;
  readonly checkout: string;
  readonly emptyCart: string;
  readonly closedTitle: string;
  readonly closedBody: string;
  readonly pausedTitle: string;
  readonly pausedBody: string;
  readonly emptyMenu: string;
  readonly emptyMenuBody: string;
  readonly orderingClosed: string;
  readonly orderingPaused: string;
  readonly callRestaurant: string;
  readonly menuLabel: string;
  readonly languageNames: Readonly<Record<Locale, string>>;
}

const DICTIONARIES: Readonly<Record<Locale, StorefrontMessages>> = { ar, he, en };

export function storefrontMessages(locale: Locale): StorefrontMessages {
  return DICTIONARIES[locale];
}

/**
 * Substitute `{name}` placeholders. An unknown placeholder is left verbatim so
 * a missing value is visible in review rather than silently rendering empty.
 */
export function fill(template: string, values: Readonly<Record<string, string>>): string {
  return template.replace(/\{(\w+)\}/g, (whole, key: string) =>
    Object.prototype.hasOwnProperty.call(values, key) ? values[key] : whole,
  );
}
