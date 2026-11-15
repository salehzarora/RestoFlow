export const BANNER_PUBLIC_FIELDS: readonly string[];
export function bannerPublicProjection(envelope: unknown): Record<string, any>;
export function bannerHtmlProjection(html: string, previousPaths: string[]): Record<string, any>;
export function safeRegenerationErrors(text: string): Record<string, any>[];
