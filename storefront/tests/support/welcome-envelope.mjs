/** Explicit v12 synthetic projection. Historical envelope factories stay exact. */
export function withWelcomeMedia(envelope) {
  if (envelope?.ok !== true || !envelope.restaurant) throw new TypeError('welcome fixture requires a successful historical envelope');
  return { ...envelope, restaurant: { ...envelope.restaurant, welcome_media_type: null, welcome_video: null } };
}
