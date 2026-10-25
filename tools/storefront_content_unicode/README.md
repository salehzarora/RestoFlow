# Storefront content Unicode15.1

Contract: `docs/BIZBOT_STOREFRONT_CONTENT_CONTRACT_001.md` §2. No ICU,
`Intl.Segmenter`, locale regex, runtime download, normalization or dependency.

`vendor/` contains the exact official public Unicode15.1 data and conformance
files, plus Unicode's permission notice. `provenance.json` pins their original
HTTPS URLs, byte sizes and SHA-256. The versioned files were obtained from
unicode.org; the license URL is unversioned and its exact retrieved bytes are
pinned independently. Preserve notices with generated derivatives.

Run the existing pinned Node24 executable with `generate.mjs` to regenerate
the TS ranges, Dart/SQL helpers and all1,187 official grapheme vectors offline;
`generate.mjs --check` compares deterministic generated output without writing.
Every vendor hash is verified before generation. Templates are owned source,
not downloaded executable code. Unicode revision updates require contract review.

The three implementations apply UAX29r43 GB3–GB13/GB999, including GB9c Indic,
GB11 emoji-ZWJ, RI parity, algorithmic Hangul, controls/Prepend/SpacingMark.
All offsets are scalar codepoints; malformed UTF16 is rejected. Editor selections
map exact code-unit boundaries to codepoints without rounding. Headline/token
rules use the contract's explicit whitespace set, not linguistic word boundaries.

`contentTextValid` / `app.storefront_content_text_v1` check **already normalized**
storage/wire text. RPC input normalization must reject controls before exact
edge trimming and blank→null. Required-field null rejection is a separate layer.
`heroFormatValid` checks offsets; the enclosing DTO/RPC must additionally bind
format.text byte-exactly to the saved headline and reject an all-null format
object instead of inventing formatting. An absent format is valid.

Generated Dart is for the Flutter Dashboard only. No POS, KDS or print change.
The SQL fragment is for the separately reviewed additive migration and only
defines immutable, revoked helper functions; it is not a migration runner.
