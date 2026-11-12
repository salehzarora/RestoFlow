/** Lossless public locale copy at the server/client boundary. No dictionary values live here. */
import type { StorefrontMessages } from './storefront';

// One stable, exhaustive key order avoids repeating all property names in each
// document and RSC payload. Round-trip tests cover every key in every locale.
const keys = [
  "menuHeading", "discoverMenu", "suggestItem", "suggestionEmpty", "menuEyebrow", "menuCaption",
  "heroEyebrow", "findUs", "yourChoices", "welcome", "explore", "poweredBy", "langLabel", "search",
  "openNow", "closed", "paused", "closesAt", "opensAt", "opensOn", "closedNow", "closedBodyOn",
  "closedBodyNoHours", "weekday0", "weekday1", "weekday2", "weekday3", "weekday4", "weekday5",
  "weekday6", "pickup", "delivery", "pickupOff", "deliveryOff", "fromFee", "hours", "back", "close",
  "unknownTitle", "unknownBody", "prevCategory", "nextCategory", "orderNow", `from`, "addShort",
  "viewAll", "pickupShort", "mostOrdered", "last30", "chefPicks", "chefPick", "rankN", "soldOut",
  "badgeNew", "badgeDeal", "unavailableNow", "viewCart", "items", "item", "cart", "subtotal", "tax",
  "total", "checkout", "emptyCart", "closedTitle", "closedBody", "pausedTitle", "pausedBody",
  "emptyMenu", "emptyMenuBody", "orderingClosed", "orderingPaused", "orderingOfflineTitle",
  "orderingOfflineBody", "callRestaurant", "menuLabel", "compactMenuLabel", "searchPh", "noResults",
  "tryOther", "required", "optional", "chooseOne", "upTo", "included", "notes", "notesHint",
  "addToCart", "updateItem", "chooseToContinue", "requiredError", "maxReached", "decrease", "increase",
  "clearSearch", "edit", "remove", "deliveryFee", "emptyCartBody", "browseMenu", "howReceive",
  "pickupDesc", "deliveryDesc", "yourDetails", "fullName", "phone", "phoneError", "address", "city",
  "chooseCity", "area", "street", "building", "apt", "deliveryNotes", "zoneInfo", "outsideZone",
  "outsideZoneBody", "switchPickup", "belowMin", "belowMinBody", "addItems", "payment", "cash",
  "cashPickup", "cashDelivery", "card", "comingSoon", "cardSoon", "reviewCta", "review", "receive",
  "pickupAt", "deliverTo", "customer", "sendInfo", "sendRequest", "sending", "changedTitle",
  "changedBody", "priceTitle", "priceBody", "soldOutCart", "gotIt", "offline", "offlineBody",
  "serverError", "serverBody", "rateLimited", "rateBody", "duplicate", "duplicateBody", "retry",
  "today", "tomorrow", "min", "stepDetails", "stepPayment", "stepReview", "payAtPickup",
  "payOnDelivery", "restaurantConfirms", "received", "receivedBody", "continueWa", "trackStatus",
  "waFallback", "waWeb", "copyMsg", "copied", "msgPreview", "waiting", "waitingBody", "expiresIn",
  "accepted", "acceptedBody", "preparing", "preparingBody", "readyPickup", "readyPickupBody",
  "readyDelivery", "readyDeliveryBody", "completed", "completedBody", "rejected", "rejectedBody",
  "expired", "expiredBody", "cancelled", "cancelledBody", "cancelRequest", "cancelTitle", "cancelBody",
  "keep", "yesCancel", "openChat", "orderAgain", "stReceived", "stWaiting", "stAccepted", "stPreparing",
  "stReady", "stCompleted", "viewStatus", "demoNotice", "languageNames",
] as const satisfies readonly (keyof StorefrontMessages)[];

// Adding a dictionary key without updating the wire order is a type error.
export type StorefrontMessageValues = Exclude<keyof StorefrontMessages, typeof keys[number]> extends never
  ? readonly StorefrontMessages[keyof StorefrontMessages][] : never;

export function packStorefrontMessages(messages: StorefrontMessages): StorefrontMessageValues {
  return keys.map(key => messages[key]);
}

export function unpackStorefrontMessages(values: StorefrontMessageValues): StorefrontMessages {
  if (values.length !== keys.length) throw new Error('Storefront message values are incomplete');
  return Object.fromEntries(keys.map((key, index) => [key, values[index]])) as unknown as StorefrontMessages;
}
