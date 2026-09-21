/**
 * UI-SESSION FLAGS - the ONE module in the storefront permitted to touch a
 * browser store, and the only store it may touch.
 *
 * SCOPE, deliberately tiny and closed:
 *   - Two boolean UI flags, per tenant slug, for the CURRENT TAB SESSION only.
 *   - The session store only. No long-lived store, no database, no cookie.
 *   - The stored value is the single character "1" and nothing else; the
 *     ABSENCE of the key is the only representation of false. There is no JSON
 *     payload and no generic get/set, so nothing else can be smuggled through.
 *
 * WHAT MAY NEVER BE STORED HERE: customer names, phone numbers or addresses, a
 * checkout draft, request or status details, payment data, order notes, tokens
 * or secrets, and analytics of any kind. Cart persistence is Phase C/D work
 * under its own approved contract and does not belong in this module.
 *
 * FAILURE MODES, all handled: the store does not exist during the static
 * prerender, and merely READING the global throws in some privacy
 * configurations rather than returning undefined. Every path is wrapped, and
 * every failure degrades to "flag not set" - the first-visit state, which is
 * always safe to show.
 *
 * Approved by DESIGN_HANDOFF.md:27, INTERACTIONS.md:10 and
 * COMPONENT_INVENTORY.md:9.
 */
import { isValidSlug } from '@/theme/sanitize';

/** Namespaced and versioned, so no future key can collide with one of these. */
const NAMESPACE = 'sf:v1:';

/** The only two flags that exist. Adding a third is a contract change. */
type Flag = 'seen' | 'announcement-dismissed';

/**
 * Conservative ceiling. The longest legal key is
 * `sf:v1:announcement-dismissed:` (29 characters) plus the 63-character maximum
 * slug that isValidSlug admits, i.e. 92. Anything longer did not come from a
 * resolved slug, so it is refused rather than written.
 */
const MAX_KEY_LENGTH = 96;

/** The stored truth value. Absence of the key is the only "false". */
const TRUE_VALUE = '1';

/**
 * The session store, or null when it is unavailable. The property ACCESS is
 * inside the try on purpose: it throws, not merely returns undefined, when site
 * data is blocked.
 */
function store(): Storage | null {
  try {
    const found = (globalThis as { sessionStorage?: Storage }).sessionStorage;
    return found ?? null;
  } catch {
    return null;
  }
}

/** A key, or null when the slug is not one this app resolved. */
function keyFor(flag: Flag, slug: string): string | null {
  if (!isValidSlug(slug)) return null;
  const key = `${NAMESPACE}${flag}:${slug}`;
  return key.length > MAX_KEY_LENGTH ? null : key;
}

function readFlag(flag: Flag, slug: string): boolean {
  const key = keyFor(flag, slug);
  if (key === null) return false;
  const found = store();
  if (found === null) return false;
  try {
    return found.getItem(key) === TRUE_VALUE;
  } catch {
    return false;
  }
}

function writeFlag(flag: Flag, slug: string): void {
  const key = keyFor(flag, slug);
  if (key === null) return;
  const found = store();
  if (found === null) return;
  try {
    found.setItem(key, TRUE_VALUE);
  } catch {
    /* Quota, or writes refused. The flag simply does not persist. */
  }
}

/** Has this tab already been past the intro for this storefront? */
export function hasSeenIntro(slug: string): boolean {
  return readFlag('seen', slug);
}

/** Record that this tab has reached this storefront's home screen. */
export function markIntroSeen(slug: string): void {
  writeFlag('seen', slug);
}

/** Has the visitor dismissed this storefront's announcement in this tab? */
export function isAnnouncementDismissed(slug: string): boolean {
  return readFlag('announcement-dismissed', slug);
}

/** Record the announcement dismissal for the rest of this tab session. */
export function markAnnouncementDismissed(slug: string): void {
  writeFlag('announcement-dismissed', slug);
}
