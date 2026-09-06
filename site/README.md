# BIZBOT | بِزبط — public marketing website

The public, customer-facing site for **bizbot.systems**. It is deliberately
separate from the product web apps (Dashboard / POS / KDS / Kiosk live on
`app.bizbot.systems`, built by `tools/vercel_build_web.sh` from the repo root):
its own Vercel project, its own root directory (`site/`), no Flutter, no
Supabase, no shared runtime.

## What is in here

| Path | Role |
|---|---|
| `src/locales/{ar,en,he}.json` | All copy, one file per language. Arabic is the default (`/`), English at `/en`, Hebrew at `/he`. Edit copy here only. |
| `src/site.config.json` | Public contact values and links (sales/support mailboxes, app URL, optional phone / WhatsApp / social URLs — empty values are simply not rendered). |
| `src/render.mjs` | HTML renderer (sections, device mockups, SEO tags, JSON-LD). Pure function of locale + config. |
| `src/styles.css` / `src/main.js` | Styles (brand tokens, device frames, RTL/LTR via logical properties, motion) and the progressive-enhancement script (tabs, mobile menu, reveal-on-scroll, video autoplay-in-view, form submission). |
| `src/icons.mjs` | Inline SVG icon set. |
| `public/assets/brand/` | Official BIZBOT symbol + Arabic / English wordmarks (derived from the owner masters in `tools/brand/masters/bizbot`, same pipeline as the apps) plus reverse (white-ink) wordmarks for dark surfaces. |
| `public/assets/shots/` | Real product screenshots (owner's `WEBPICS`), Android status bar cropped, exported as responsive WebP. |
| `public/assets/video/` | Kiosk attract-screen video (H.264, muted, 540 px) + poster. |
| `public/assets/fonts/` | Self-hosted OFL fonts: Rubik (Latin/Arabic/Hebrew, body), Alexandria (Arabic display), Inter (English display) — the same families the product apps ship. |
| `public/assets/og/` | Open Graph images per locale. |
| `api/lead.js` → `lib/lead.mjs` | The demo-request endpoint (Vercel Node function). |
| `scripts/build.mjs` | Zero-dependency static build → `dist/`. |
| `scripts/dev.mjs` | Local preview with the API mounted in-process. |
| `tests/` | `node --test`: build output invariants + endpoint behaviour. |

## Run locally

```sh
cd site
node scripts/build.mjs        # → dist/
node scripts/dev.mjs 8787     # http://localhost:8787  (/en, /he)
node --test tests/*.test.mjs
```

No `npm install` is needed (there are no dependencies). Node ≥ 20.

## Deployment (Vercel)

Project **`bizbot-site`** (separate from `resto-flow`), **Root Directory = `site`**.
`vercel.json` in this folder carries everything: build command, output directory,
`ignoreCommand` (skip builds when nothing under `site/` changed), security headers
(CSP without inline scripts/styles), immutable caching for `/assets`, the
`www → apex` redirect, and redirects that keep the product routes alive on the
brand root (`/pos`, `/kds`, `/kiosk`, `/dashboard`, `/app`, `/login`, `/auth/*`
→ `https://app.bizbot.systems/...`).

### Environment variables (names only — never commit values)

| Name | Required | Purpose |
|---|---|---|
| `RESEND_API_KEY` | to send | Resend API key with **sending** access for `bizbot.systems` (domain already verified in Resend). Without it the endpoint answers `503 not_configured` and the page shows the direct e-mail fallback. |
| `LEAD_TO` | no | Recipient of demo requests (default `sales@bizbot.systems`). |
| `LEAD_FROM` | no | Verified sender (default `BIZBOT <leads@bizbot.systems>`). |

### The lead form

`POST /api/lead` (JSON) → validates (name, business, phone, e-mail, business
type, branches, notes ≤ 1500 chars), drops bots (honeypot field, minimum fill
time, small per-instance rate limit), then e-mails the lead through Resend with
the lead's address as `Reply-To`. Nothing is stored server-side; no cookies, no
third-party scripts.

## Brand rules honoured

Official BIZBOT symbol (`c2355a92-43d1-42a2-8dbf-aa13e0121514`), the owner's
Arabic and English wordmarks, the identity-board palette (Charcoal `#1F2937`,
Emerald `#059669`, Mint `#A7F3D0`, Light Neutral `#F4F6F5`). No VEYRO anywhere;
`tests/build.test.mjs` fails the build if it ever reappears.
