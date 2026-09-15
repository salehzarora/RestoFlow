# BIZBOT Storefront - static-export infrastructure shell

STOREFRONT-INFRA-001B. This is an **infrastructure placeholder**, not the
Storefront product. It exists to prove the deployment contract end to end before
any customer-facing surface is built.

What it is:

- A Next.js App Router project built with `output: 'export'` to static
  HTML/CSS/JS in `out/`.
- Four routes: `/` (Arabic), `/ar`, `/en`, `/he`, each emitting the correct
  `<html lang>` and `<html dir>` in the served HTML, before hydration.
- One shared presentation component, so locale copy cannot drift.

What it deliberately is not:

- No BFF, server action, request-time API, middleware or proxy.
- No Supabase client, credential, environment variable or real menu data.
- No cart, order, payment or messaging behaviour.
- Not the evolving restaurant experience design, which is iterated separately.

Crossing between `/ar`, `/en` and `/he` is a full document load: they are
separate root layouts. That is expected for this shell and implies nothing about
future cart persistence.

`storefront/scripts/` and `storefront/tests/` are support code. The deployment
filter never scans them, which is why they may use Node built-ins while the
application source may not.
