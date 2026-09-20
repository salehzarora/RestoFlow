/**
 * Inline SVG icons, 24-grid, 2px stroke, round caps and joins, OUTLINED ONLY —
 * the icon language the design handoff specifies. There is no icon font and no
 * icon image file, so nothing here costs a network request.
 */

function Icon({ d, label }: { d: string; label?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      aria-hidden={label === undefined ? 'true' : undefined}
      aria-label={label}
      role={label === undefined ? undefined : 'img'}
      focusable="false"
    >
      <path d={d} />
    </svg>
  );
}

export function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <circle cx="11" cy="11" r="7" />
      <path d="M20 20l-3.5-3.5" />
    </svg>
  );
}

/** Storefront — the pickup service. */
export function StoreIcon() {
  return <Icon d="M4 9.5L5.2 5h13.6L20 9.5M4 9.5h16M4 9.5v9a1.5 1.5 0 001.5 1.5h13a1.5 1.5 0 001.5-1.5v-9M9.5 20v-5h5v5" />;
}

/** Scooter — the delivery service. */
export function DeliveryIcon() {
  return <Icon d="M6.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM18.5 18.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM9 16h7M16 16l-2-9h-3M6.5 13.5V10h4" />;
}

/** Chevron pointing along the reading direction; flipped in RTL by CSS. */
export function ChevronIcon() {
  return <Icon d="M9 5l7 7-7 7" />;
}

export function CheckIcon() {
  return <Icon d="M4.5 12.5l5 5 10-11" />;
}
