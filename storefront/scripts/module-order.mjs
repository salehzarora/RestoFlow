// The locked home module order.
//
// SOURCE OF TRUTH for the eight named modules:
//   BIZBOT_STOREFRONT_DESIGN_HANDOFF/OPEN_QUESTIONS.md:23 - "This release ships
//   a fixed order (announce -> hero -> service -> categories -> promo ->
//   popular -> sections -> story)."
// 'compact', 'notice' and 'footer' are NOT named by the handoff. Their
// positions are this implementation's and are pinned here so they cannot drift.
//
// WHY THIS FILE EXISTS: the previous guarantee was a monotonic indexOf() scan
// over RAW component source, so five of its twelve tokens resolved to JSDoc
// prose or import lines. Moving PromoBanner below Popular, or the announcement
// below the rail, violated the locked order and the whole suite stayed green.
// Everything below anchors to real markup and demands EXACTLY ONE occurrence.
export const LOCKED_MODULE_ORDER = Object.freeze([
  'announce', 'compact', 'hero', 'service', 'notice',
  'categories', 'promo', 'popular', 'sections', 'story', 'footer',
]);

/** Comments removed: these rules are about CODE and MARKUP, not prose. */
export const stripComments = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/.*/gm, '$1 ');

/**
 * Every data-sf-module value in DOCUMENT order, consecutive repeats collapsed
 * (the category sections are one module, emitted once per category).
 */
export function renderedModuleOrder(html) {
  const seen = [];
  for (const m of html.matchAll(/\sdata-sf-module="([a-z]+)"/g)) {
    if (seen[seen.length - 1] !== m[1]) seen.push(m[1]);
  }
  return seen;
}

/** problems[] - empty only when `observed` IS the locked order minus absences. */
export function checkModuleOrder(observed, { mandatory = [] } = {}) {
  const problems = [];
  if (observed.length === 0) problems.push('no data-sf-module element was found at all');
  for (const name of observed) {
    if (!LOCKED_MODULE_ORDER.includes(name)) problems.push(`unknown module "${name}"`);
  }
  const expected = LOCKED_MODULE_ORDER.filter((n) => observed.includes(n));
  if (expected.join(' -> ') !== observed.join(' -> ')) {
    problems.push(`order is [${observed.join(' -> ')}]; locked order is [${expected.join(' -> ')}]`);
  }
  for (const name of mandatory) {
    if (!observed.includes(name)) problems.push(`mandatory module "${name}" is missing`);
  }
  return problems;
}

/**
 * Source-order check. Each anchor must occur EXACTLY ONCE in the
 * comment-stripped file and the occurrences must be strictly increasing.
 *
 * "Exactly once" is the whole point: it is what kills the reviewed defect at
 * the root. A token that also matches an import list, a prop declaration or a
 * JSDoc line has a count > 1 and fails LOUDLY instead of silently resolving to
 * the wrong occurrence.
 */
export function anchorOrder(source, anchors) {
  const text = stripComments(source);
  const problems = [];
  let previousAt = -1;
  let previousName = null;
  for (const [name, anchor] of anchors) {
    const count = text.split(anchor).length - 1;
    if (count !== 1) {
      problems.push(`${name}: anchor ${JSON.stringify(anchor)} occurs ${count}x, expected exactly 1`);
      continue;
    }
    const at = text.indexOf(anchor);
    if (at < previousAt) problems.push(`${name} must be authored after ${previousName}`);
    previousAt = at;
    previousName = name;
  }
  return problems;
}

/** The JSX anchors. Every one is a real element or a rendered child slot. */
export const CHROME_ANCHORS = Object.freeze([
  ['announce', 'data-sf-module="announce"'],
  ['compact', 'data-sf-module="compact"'],
  ['hero', '{hero}'],
  ['service', '{service}'],
  ['notice', '{notice}'],
  ['categories', 'data-sf-module="categories"'],
]);

export const PAGE_ANCHORS = Object.freeze([
  ['chrome', '<HomeChrome'],
  ['promo', '<PromoBanner'],
  ['popular', '<PopularSection'],
  ['sections', '<MenuSection'],
  ['story', '<StoryCard'],
  ['footer', '<SiteFooter'],
]);
