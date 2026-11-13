export const responsiveBannerKeys: readonly string[];
export function responsiveBannerFixture<T extends { appearance: Record<string, unknown> }>(document: T): { document: T; materializedNullKeys: string[] };
export function legacyBannerDocument<T>(document: T): T;
export function legacyBannerMenu<T>(envelope: T): T;
export function responsiveBannerReady(expected: { height: number; focus: string }, actual: Record<string, unknown> | null | undefined): boolean;
