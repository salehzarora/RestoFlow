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
  /** "opens {d} {t}" - the next window on another day (STOREFRONT-READ-001 B). */
  readonly opensOn: string;
  /** "closed for now" - closed with no trustworthy next window. */
  readonly closedNow: string;
  readonly closedBodyOn: string;
  readonly closedBodyNoHours: string;
  readonly weekday0: string;
  readonly weekday1: string;
  readonly weekday2: string;
  readonly weekday3: string;
  readonly weekday4: string;
  readonly weekday5: string;
  readonly weekday6: string;
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
  // STOREFRONT-READ-001 (owner decision D5): the ONE new family for a
  // browse-only storefront - never a reuse of orderingPaused, which claims
  // that the restaurant paused.
  readonly orderingOfflineTitle: string;
  readonly orderingOfflineBody: string;
  readonly callRestaurant: string;
  readonly menuLabel: string;
  readonly compactMenuLabel: string;
  readonly searchPh: string;
  readonly noResults: string;
  readonly tryOther: string;
  readonly required: string;
  readonly optional: string;
  readonly chooseOne: string;
  readonly upTo: string;
  readonly included: string;
  readonly notes: string;
  readonly notesHint: string;
  readonly addToCart: string;
  readonly updateItem: string;
  readonly chooseToContinue: string;
  readonly requiredError: string;
  readonly maxReached: string;
  readonly decrease: string;
  readonly increase: string;
  readonly clearSearch: string;
  readonly edit: string;
  readonly remove: string;
  readonly deliveryFee: string;
  readonly emptyCartBody: string;
  readonly browseMenu: string;
  readonly howReceive: string;
  readonly pickupDesc: string;
  readonly deliveryDesc: string;
  readonly yourDetails: string;
  readonly fullName: string;
  readonly phone: string;
  readonly phoneHint: string;
  readonly phoneHelp: string;
  readonly address: string;
  readonly city: string;
  readonly chooseCity: string;
  readonly area: string;
  readonly street: string;
  readonly building: string;
  readonly apt: string;
  readonly deliveryNotes: string;
  readonly zoneInfo: string;
  readonly outsideZone: string;
  readonly outsideZoneBody: string;
  readonly switchPickup: string;
  readonly belowMin: string;
  readonly belowMinBody: string;
  readonly addItems: string;
  readonly payment: string;
  readonly cash: string;
  readonly cashPickup: string;
  readonly cashDelivery: string;
  readonly card: string;
  readonly comingSoon: string;
  readonly cardSoon: string;
  readonly reviewCta: string;
  readonly review: string;
  readonly receive: string;
  readonly pickupAt: string;
  readonly deliverTo: string;
  readonly customer: string;
  readonly sendInfo: string;
  readonly sendRequest: string;
  readonly sending: string;
  readonly changedTitle: string;
  readonly changedBody: string;
  readonly priceTitle: string;
  readonly priceBody: string;
  readonly soldOutCart: string;
  readonly gotIt: string;
  readonly offline: string;
  readonly offlineBody: string;
  readonly serverError: string;
  readonly serverBody: string;
  readonly rateLimited: string;
  readonly rateBody: string;
  readonly duplicate: string;
  readonly duplicateBody: string;
  readonly retry: string;
  readonly today: string;
  readonly tomorrow: string;
  readonly min: string;
  readonly stepDetails: string;
  readonly stepPayment: string;
  readonly stepReview: string;
  readonly payAtPickup: string;
  readonly payOnDelivery: string;
  readonly restaurantConfirms: string;
  // Phase E: received / status / cancel / WhatsApp copy, from the approved
  // string table; demoNotice is the one execution-clarification string.
  readonly received: string;
  readonly receivedBody: string;
  readonly continueWa: string;
  readonly trackStatus: string;
  readonly waFallback: string;
  readonly waWeb: string;
  readonly copyMsg: string;
  readonly copied: string;
  readonly msgPreview: string;
  readonly waiting: string;
  readonly waitingBody: string;
  readonly expiresIn: string;
  readonly accepted: string;
  readonly acceptedBody: string;
  readonly preparing: string;
  readonly preparingBody: string;
  readonly readyPickup: string;
  readonly readyPickupBody: string;
  readonly readyDelivery: string;
  readonly readyDeliveryBody: string;
  readonly completed: string;
  readonly completedBody: string;
  readonly rejected: string;
  readonly rejectedBody: string;
  readonly expired: string;
  readonly expiredBody: string;
  readonly cancelled: string;
  readonly cancelledBody: string;
  readonly cancelRequest: string;
  readonly cancelTitle: string;
  readonly cancelBody: string;
  readonly keep: string;
  readonly yesCancel: string;
  readonly openChat: string;
  readonly orderAgain: string;
  readonly stReceived: string;
  readonly stWaiting: string;
  readonly stAccepted: string;
  readonly stPreparing: string;
  readonly stReady: string;
  readonly stCompleted: string;
  readonly viewStatus: string;
  readonly demoNotice: string;
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
