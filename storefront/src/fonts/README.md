# Rubik, self-hosted

Three variable woff2 subsets (Latin, Arabic, Hebrew), each covering the whole
400-900 weight range, vendored because `font-src 'self'` forbids gstatic.

## Why five `localFont` calls and two "sets"

The written acceptance limit is **at most two font PRELOADS per route**, and
the pinned `next/font/local` (Next 16.3.5, Turbopack) decides `preload` per
`localFont()` call, for all of that call's files, with no per-file
`unicode-range` and no per-file preload. So each subset is its own call - and
its own font family, because the loader names the family after the export
(`rubikLatin`, `rubikArabic`, ...) and ignores a custom `font-family`
declaration when it writes the `.variable` class. The three families are
composed in `storefront.module.css`:

```
--font: var(--sf-font-latin), var(--sf-font-arabic), var(--sf-font-hebrew),
        'Segoe UI', Tahoma, sans-serif;
```

Font matching walks that list per character; each `@font-face` carries the
subset's blocks as `unicode-range`, so a family whose range excludes the
character is skipped without a download. There is deliberately NO
metric-adjusted `local()` fallback face (next/font's `adjustFontFallback` is
off on every call): a `local()` face costs ~150 ms of the first layout on the
throttled lab (Chromium matches it against the installed font collection),
and with this design's fixed line-heights the swap shift measured 0 without
one (G-FONTS, the lab protocol; PERF_PROTOCOL_AND_TRACE.md).

## Which files are preloaded where

| Root | Preloaded (2) | On demand |
|---|---|---|
| `/`, `/ar`, `/en` | Latin, Arabic | Hebrew (carries `₪` U+20AA, fetched for the first price) |
| `/he` | Latin, Hebrew (+ `₪`) | Arabic (the tenant's content, fetched when it is laid out) |

Latin is preloaded everywhere: it owns the space, the digits and the
punctuation, and a late swap of those moves every line. Which subset owns
which characters is its script's Unicode blocks (Latin: Basic Latin, Latin-1,
Latin Extended-A, the spacing modifiers and combining marks the file carries,
General Punctuation, `€`, `™`, `−`, `∕`; Arabic: Arabic + Arabic Presentation
Forms; Hebrew: Hebrew, `₪`, Alphabetic Presentation Forms) - disjoint, so
the shared glyphs (space, hyphen, "A", combining marks) belong to Latin
alone; a character in a block the file lacks falls to the next family as it
always did. The files' exact coverage was read from their `cmap` tables
(`U+0020-007E, U+00A0-00FF, …` / `U+060C…U+FD3F` / `U+05B0…U+FB4B`) and is a
subset of those blocks.

The `*-lazy` calls are the same files with `preload: false`; a root imports
exactly the three calls it needs (`rubik-preload-arabic.ts` or
`rubik-preload-hebrew.ts`) so the font manifest lists two preloads for it and
no more. Two toolchain facts decide WHERE a set is bound: sibling root
layouts share one chunk group, so a set imported by a root layout is linked
into every root's documents (proven by a build); and the not-found boundary
is part of every route's client tree, so the 404 document's own set
(`rubik-unknown.ts`) holds only Latin and the two on-demand subsets. The sets
are therefore bound in each root's `s/[slug]/layout.tsx` (a wrapper element)
and handed to `RequestScreen` by each root's `r/[ref]/page.tsx`. A file that is declared but not preloaded is not a removed
language: it is fetched the moment its characters appear.
