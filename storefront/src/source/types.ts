/**
 * The tenant runtime boundary.
 *
 * These types are the ONLY shape the UI may read. A real adapter (Phase D+)
 * must satisfy the same interface, so no component learns where data came from.
 *
 * Money rule (RestoFlow D-007, restated by the design handoff): amounts are
 * INTEGER MINOR UNITS. There is no floating-point money anywhere in this
 * package, and a formatter is the only place a decimal point appears.
 */

/** An integer number of agorot. Never a float, never a formatted string. */
export type Minor = number;

export type Preset = 'dark' | 'light';

export type ServiceState = 'open' | 'closed' | 'paused';

export interface TenantBrand {
  /** Raw tenant input; the theme layer sanitises before use. */
  readonly primary: string;
  readonly accent: string;
  /** Logo asset path, or null for the initial-tile fallback. */
  readonly logo: string | null;
}

export interface TenantHours {
  /** 24-hour `HH:MM`. */
  readonly opens: string;
  readonly closes: string;
}

export interface TenantService {
  readonly state: ServiceState;
  readonly pickupEnabled: boolean;
  readonly deliveryEnabled: boolean;
  /** Lowest delivery fee across zones, in minor units. */
  readonly deliveryFromMinor: Minor;
}

export interface Tenant {
  readonly slug: string;
  readonly displayName: string;
  readonly tagline: string;
  readonly city: string;
  readonly address: string;
  readonly phone: string;
  readonly brand: TenantBrand;
  readonly hours: TenantHours;
  readonly service: TenantService;
  /** Hero image path. Video is deferred out of UI-001 by approved decision 8. */
  readonly heroImage: string;
  readonly currency: 'ILS';
}

/**
 * What the storefront can be asked for. Phase A only needs tenant lookup; the
 * menu/cart members arrive with their own phases rather than being stubbed here
 * as empty shapes nobody can trust.
 */
export interface StorefrontSource {
  readonly kind: 'fixture' | 'live';
  /** Null means "no such published storefront" — the Unknown screen's trigger. */
  getTenant(slug: string): Tenant | null;
  /** Slugs that must be statically pre-rendered. Empty for a live source. */
  staticSlugs(): readonly string[];
}
