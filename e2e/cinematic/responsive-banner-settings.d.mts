export const responsiveBannerKeys: readonly string[];
export function responsiveBannerFixture<T extends { appearance: Record<string, unknown> }>(document: T): { document: T; materializedNullKeys: string[] };
export function legacyBannerDocument<T>(document: T): T;
export function legacyBannerMenu<T>(envelope: T): T;
export function responsiveBannerReady(expected: { height: number; focus: string }, actual: Record<string, unknown> | null | undefined): boolean;
export function dashboardImageHash(request: { url: string; method: string; resourceType: string; headers: Record<string, string> }): string;
export function dashboardImageBytesMatch(hash: string, status: number, bytes: Uint8Array): boolean;
export function dashboardMediaReady(requests: number, verified: number, checks: boolean[]): boolean;
