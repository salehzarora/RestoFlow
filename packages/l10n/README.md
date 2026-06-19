# restoflow_l10n

Localization package - **shell only** for RF-011.

The **full** localization framework (ar/he/en ARB resources, message delegates,
and RTL/LTR scaffolding per **DECISION D-014**) is owned by ticket **RF-020**.

## Public surface (RF-011 scaffold)
- `kSupportedLocales` - the neutral list of target locales (`ar`, `he`, `en`).

## Deferred
Everything else (ARB files, generated message lookups, `LocalizationsDelegate`s,
directionality helpers) lands in **RF-020**.
