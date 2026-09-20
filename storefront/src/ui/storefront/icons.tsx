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

/** Paper plane - the announcement strip's accent glyph. */
export function SendIcon() {
  return <Icon d="M21 3L10.5 13.5M21 3l-6.8 18-3.7-7.5L3 10l18-7z" />;
}

/** Clock - the service strip's hours cell. */
export function ClockIcon() {
  return <Icon d="M12 7v5l3 2M12 21a9 9 0 100-18 9 9 0 000 18z" />;
}

/** Hamburger - scrolls to the first menu section (a designed stand-in). */
export function MenuIcon() {
  return <Icon d="M4 7h16M4 12h16M4 17h16" />;
}

/** Flame - the popular section's accent tile. */
export function FlameIcon() {
  return <Icon d="M12 22a6 6 0 006-6c0-4-3-5.5-3.5-9C13 9 12 10.5 12 12c-1-1-1.5-2.5-1.5-4C8 10 6 12.7 6 16a6 6 0 006 6z" />;
}

export function PlusIcon() {
  return <Icon d="M12 5v14M5 12h14" />;
}

export function CloseIcon() {
  return <Icon d="M6 6l12 12M18 6L6 18" />;
}

/** Warning triangle - the closed/paused notice. */
export function AlertIcon() {
  return <Icon d="M12 9v4.5M12 17h.01M10.3 4.3L2.6 18a2 2 0 001.7 3h15.4a2 2 0 001.7-3L13.7 4.3a2 2 0 00-3.4 0z" />;
}

/** Dotted map motif drawn once behind the hero. Decorative. */
export function MapMotif() {
  return (
    <svg viewBox="0 0 190 120" aria-hidden="true" focusable="false" preserveAspectRatio="none">
      <path d="M2 96C36 92 52 66 78 58c26-8 40 6 62-10 12-9 20-24 46-36" />
      <path d="M22 118C52 108 62 88 92 84c28-4 44 10 64-6" />
    </svg>
  );
}
