export type Principal = { email: string; password: string; orgId: string; restaurantId: string; branchId: string; slug: string; authUserId: string };
export type LocalFixture = { apiUrl: string; anonKey: string; ownerA: Principal; ownerB: Principal };
export type LocalReply = { status: number; ok: boolean; data: Record<string, any>; bytes: Buffer; contentType: string | null };
export const API_URL: string;
export const DASHBOARD_URL: string;
export function readFixture(): LocalFixture;
export function scope(owner: Principal): { p_organization_id: string; p_restaurant_id: string };
export function rpc(fixture: LocalFixture, token: string | null, name: string, args: Record<string, unknown>): Promise<LocalReply>;
export function readInvariants(fixture: LocalFixture, token: string, owner?: Principal): Promise<Record<string, unknown>>;
