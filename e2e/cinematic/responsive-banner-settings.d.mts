export const responsiveBannerKeys: readonly string[];
export function responsiveBannerFixture<T extends { appearance: Record<string, unknown> }>(document: T): { document: T; materializedNullKeys: string[] };
export function legacyBannerDocument<T>(document: T): T;
export function legacyBannerMenu<T>(envelope: T): T;
