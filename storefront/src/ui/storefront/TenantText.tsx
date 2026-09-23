/**
 * TENANT-AUTHORED TEXT, bidi-isolated WITHOUT moving structure.
 *
 * THE DEFECT THIS EXISTS TO PREVENT. `dir="auto"` resolves an element's
 * direction from the first strong character of its content. Put it on a
 * BLOCK-level box and that box's `text-align: start` then resolves against its
 * OWN direction, so the text jumps to the opposite edge from every
 * direction-fixed neighbour - the accent rule beside a heading, the price row
 * under a card name, the fact pills under a story block, the sibling rows in a
 * footer. Menu content is single-language in MVP
 * (CONTENT_AND_LOCALIZATION.md:3), so Arabic copy on an English page is the
 * DESIGNED case, not an edge case, and the split is plainly visible.
 *
 * THE RULE. The structural element keeps the page direction and owns the
 * layout; only the tenant-authored RUN is isolated, on an inner inline span.
 * That is what the approved prototype does (Storefront.dc.html:140/:142) and
 * what CONTENT_AND_LOCALIZATION.md:223 prescribes - `dir="auto"` is for inline
 * mixed runs, while :211 lists text alignment as mirroring from the ROOT dir.
 *
 * A `<span>` is inline, so it adds no box of its own: line-clamping, ellipsis
 * truncation and the surrounding typography are all unaffected.
 *
 * `lang` is deliberately NOT set here: this release has no per-tenant content
 * locale to read, and inventing one would be a guess about data that does not
 * exist yet.
 */
import type { ReactNode } from 'react';

export function TenantText({ children }: { children: ReactNode }) {
  return <span dir="auto">{children}</span>;
}
