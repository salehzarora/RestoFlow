/**
 * The tenant runtime boundary.
 *
 * These types are the ONLY shape the UI may read. The fixture (UI-001) and the
 * live adapter (STOREFRONT-READ-001, src/source/live) both produce them, so no
 * component learns where data came from.
 *
 * Money rule (RestoFlow D-007, restated by the design handoff): amounts are
 * INTEGER MINOR UNITS. There is no floating-point money anywhere in this
 * package, and a formatter is the only place a decimal point appears. The tax
 * rate is an INTEGER number of basis points for the same reason.
 */

/** An integer number of agorot. Never a float, never a formatted string. */
export type Minor = number;

/** An integer number of basis points (1800 = 18%). Never a float. */
export type BasisPoints = number;

export type Preset = 'dark' | 'light';

export type ServiceState = 'open' | 'closed' | 'paused';

export interface TenantBrand {
  /** Raw tenant input; the theme layer sanitises before use. */
  readonly primary: string;
  readonly accent: string;
  /** Logo asset URL, or null for the initial-tile fallback. */
  readonly logo: string | null;
}

export interface TenantHours {
  /**
   * 24-hour `HH:MM` of TODAY's window (the current one when open, else the
   * next one starting today); empty when no window starts today or the
   * restaurant published none.
   */
  readonly opens: string;
  readonly closes: string;
  /**
   * The next opening instant (ISO 8601 with offset) when closed, or null when
   * open now / no window within 7 days / unknown (fixture). The only forward
   * pointer across days: a time in `opens` never describes another day.
   */
  readonly nextOpen: string | null;
  /**
   * `nextOpen` expressed on the restaurant's own wall clock (weekday 0 = Sunday
   * .. 6 = Saturday, `HH:MM`), computed ON THE SERVER by the adapter so the UI
   * renders it from the dictionary without any date arithmetic or Intl call of
   * its own; null whenever `nextOpen` is null or cannot be expressed.
   */
  readonly nextOpenAt: NextOpenAt | null;
  /** The IANA zone the hours are expressed in (informational). */
  readonly timezone: string;
}

export interface NextOpenAt {
  readonly weekday: number;
  readonly time: string;
}

export interface TenantService {
  readonly state: ServiceState;
  readonly pickupEnabled: boolean;
  readonly deliveryEnabled: boolean;
  /** Lowest delivery fee across zones, in minor units. */
  readonly deliveryFromMinor: Minor;
  /**
   * Whether this storefront accepts requests at all. False for every LIVE
   * tenant in STOREFRONT-READ-001 (browse-only): the flow shows the reason on
   * every progression control and never constructs a gateway. The fixture
   * tenant stays true so the accepted UI-001 demo keeps working.
   */
  readonly orderingEnabled: boolean;
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
  /**
   * Hero image URL, or null: a live tenant that published no hero renders the
   * brand-colour panel without a photo (owner decision D11). Video is deferred
   * out of UI-001 by approved decision 8.
   */
  readonly heroImage: string | null;
  readonly currency: 'ILS';
}

/** A delivery zone. Fixture-only data in this slice (no zone storage exists). */
export interface DeliveryZone {
  readonly id: string;
  readonly name: string;
  /** Delivery fee in minor units, or null when the zone is NOT served. */
  readonly feeMinor: Minor | null;
  /** Minimum order subtotal in minor units, or null when not served. */
  readonly minimumMinor: Minor | null;
}

/**
 * Everything a route needs to render one storefront, from either source. The
 * modifier groups, the zones, the tax rate and the menu version travel WITH the
 * view so the client islands read them through props/context instead of
 * importing the fixture (packet §4.5, exact import sites).
 */
export interface StorefrontResolution {
  /**
   * Which source produced this resolution. The client runtimes honour the
   * `?fx=` demo scenario tokens ONLY for `fixture`; a live tenant's pages
   * ignore them entirely (independent review, STOREFRONT-READ-001 C5).
   */
  readonly source: 'fixture' | 'live';
  readonly view: HomeView;
  readonly preset: Preset;
  readonly groups: readonly ModifierGroup[];
  readonly zones: readonly DeliveryZone[];
  readonly taxRateBp: BasisPoints;
  /** The cart key: a persisted cart for another version is discarded. */
  readonly menuVersion: string;
}

/**
 * What the storefront can be asked for. The seam is ASYNC because the live
 * source is a network read; the fixture resolves on a microtask.
 */
export interface StorefrontSource {
  readonly kind: 'fixture' | 'live';
  /** Null means "no such published storefront" - the Unknown screen's trigger. */
  getStorefront(slug: string): Promise<StorefrontResolution | null>;
  /** Slugs that must be statically pre-rendered. Empty for a live source. */
  staticSlugs(): readonly string[];
}

/** The fixture's synchronous tenant lookup (fixtures.ts); the scenario layer reads it. */
export interface FixtureTenantSource {
  readonly kind: 'fixture';
  getTenant(slug: string): Tenant | null;
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
  /**
   * 24-grid outlined SVG path. NEVER tenant text: the fixture authors it and the
   * live adapter resolves it from the icon-key REGISTRY (src/source/live/icons.ts).
   */
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
  /**
   * Modifier groups this item offers, in display order. Empty for an item that
   * is ordered as-is; `hasOptions` is exactly `groupIds.length > 0`.
   */
  readonly groupIds: readonly string[];
}

/**
 * One choice inside a modifier group.
 *
 * `priceDeltaMinor` is an INTEGER number of agorot added to the item's base
 * price when the option is selected. Zero is the common case and renders as the
 * approved "included" copy (or as nothing at all in a removal group).
 */
export interface ModifierOption {
  readonly id: string;
  readonly name: string;
  readonly priceDeltaMinor: Minor;
}

/**
 * A modifier group, exactly as the approved prototype models it
 * (prototype/storefront-data.js GROUPS).
 *
 * `required` means AT LEAST ONE selection - the prototype's own rule is
 * `required && selections.length === 0` is unmet, for single and multi alike.
 * `single` replaces the selection; a multi group accumulates up to `max`.
 * `removal` marks a group whose options take things OFF the item: its zero
 * deltas render blank rather than as "included".
 */
export interface ModifierGroup {
  readonly id: string;
  readonly name: string;
  readonly required: boolean;
  readonly single: boolean;
  /** Only meaningful for a multi group. Absent means unbounded. */
  readonly max?: number;
  readonly removal?: boolean;
  readonly options: readonly ModifierOption[];
}

/** Selected option ids, keyed by group id. */
export type ModifierSelections = Readonly<Record<string, readonly string[]>>;

/**
 * One configured line in the cart.
 *
 * This is the PERSISTED shape (see src/cart/cartStorage.ts). It carries ids and
 * primitives only - never a resolved name, price or image, because those come
 * from the menu and must not be trusted from storage.
 */
export interface CartLine {
  readonly lineId: string;
  readonly itemId: string;
  /** 1..20, integer. */
  readonly qty: number;
  readonly selections: ModifierSelections;
  /** Kitchen note, at most 140 characters after sanitising. */
  readonly note: string;
}

/** The persisted cart. `schema` is checked on every read. */
export interface CartState {
  readonly schema: 1;
  readonly slug: string;
  readonly menuVersion: string;
  readonly lines: readonly CartLine[];
}

export interface AnnouncementModule {
  readonly text: string;
}

export interface CampaignModule {
  readonly title: string;
  /** Empty when the tenant has no second line; the hero then omits the row. */
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
   * backend concern; the live adapter never claims it.
   */
  readonly popular: { readonly enabled: boolean; readonly ready: boolean };
}

/**
 * A PRESENTATIONAL cart summary. Phase B rendered the dock and the wide aside
 * from this shape; nothing renders it since Phase D and it carries no visitor
 * data. Kept so the fixture's evidence assertions still have their subject.
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
  /** The configured rate in basis points, rendered as its own line. Configuration, not law. */
  readonly taxRateBp: BasisPoints;
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
