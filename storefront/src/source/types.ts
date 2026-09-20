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

/** Presentation settings a restaurant controls; never customer controls. */
export type CardMode = 'list' | 'grid';
export type MotionMode = 'calm' | 'full' | 'lively';

/** The optional home modules. Their ORDER is fixed in UI-001 and is not data. */
export type OptionalModule = 'announce' | 'promo' | 'popular' | 'story';

export interface Category {
  readonly id: string;
  readonly name: string;
  /** Representative photo, or null to fall back to the outlined icon. */
  readonly image: string | null;
  /** 24-grid outlined SVG path, assignable per restaurant from the dashboard. */
  readonly iconPath: string;
  readonly blurb: string | null;
}

export type ItemBadge = 'new' | 'deal';

export interface MenuItem {
  readonly id: string;
  readonly categoryId: string;
  readonly name: string;
  readonly description: string;
  readonly priceMinor: Minor;
  readonly image: string | null;
  /** Featured items render as the large card at the top of their section. */
  readonly featured: boolean;
  /** Signature items are the ones eligible for the popular rail. */
  readonly signature: boolean;
  readonly badge: ItemBadge | null;
  readonly soldOut: boolean;
  /** True when the item has option groups, so its price is a STARTING price. */
  readonly hasOptions: boolean;
}

export interface AnnouncementModule {
  readonly text: string;
}

export interface CampaignModule {
  readonly title: string;
  readonly subline: string;
}

export interface PromoModule {
  readonly kicker: string;
  readonly title: string;
  readonly body: string;
  readonly image: string;
  readonly priceMinor: Minor;
  readonly itemId: string;
}

export interface StoryModule {
  readonly kicker: string;
  readonly title: string;
  readonly body: string;
  readonly image: string;
  /** Owner-written statements about their own operation, never platform stats. */
  readonly facts: readonly string[];
}

export interface HomeModules {
  readonly announcement: AnnouncementModule | null;
  readonly campaign: CampaignModule;
  readonly promo: PromoModule | null;
  readonly story: StoryModule | null;
  /**
   * `ready` governs the popular rail's TRUTH, not its styling: false removes
   * every rank claim and relabels the rail. The threshold that decides it is a
   * backend concern and is fixture-driven in UI-001.
   */
  readonly popular: { readonly enabled: boolean; readonly ready: boolean };
}

/**
 * A PRESENTATIONAL cart summary. Phase B renders the dock and the wide aside
 * from this shape; there is no store, no persistence and no mutation anywhere.
 * Real cart behaviour arrives in its own phase.
 */
export interface CartLineView {
  readonly lineId: string;
  readonly name: string;
  readonly image: string | null;
  readonly quantity: number;
  readonly lineTotalMinor: Minor;
  readonly optionSummary: string;
}

export interface CartView {
  readonly lines: readonly CartLineView[];
  readonly itemCount: number;
  readonly subtotalMinor: Minor;
  readonly taxMinor: Minor;
  readonly totalMinor: Minor;
  /** The configured rate, rendered as its own line. Configuration, not law. */
  readonly taxRate: number;
}

export interface HomeView {
  readonly tenant: Tenant;
  readonly modules: HomeModules;
  readonly categories: readonly Category[];
  readonly items: readonly MenuItem[];
  readonly cardMode: CardMode;
  readonly motion: MotionMode;
  readonly cart: CartView;
}
