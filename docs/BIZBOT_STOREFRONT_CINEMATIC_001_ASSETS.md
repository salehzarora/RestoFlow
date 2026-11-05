# Cinematic Preview image inventory

Historical inventory below. On 2026-11-04 the 20 product files were preserved
unchanged in [the PR379 reference archive](visual-references/PR379-cinematic-preview/README.md).
The current visual-parity review profile uses byte-identical copies of the
recorded public source photographs instead; cover, logo and texture stay in
their original application paths. See [current Preview provenance](STOREFRONT_VISUAL_PARITY_PREVIEW.md).

Public source snapshot: 2026-11-03. Original URLs are retained in the preview catalog/runtime snapshot. Prepared images are derivatives only; no hosted menu image was replaced.

| Product | Asset | Treatment |
|---|---|---|
| golden pops | `8ee6e82d-7a09-4b54-8e41-42ccfa4e12e2.webp` | AI background extraction, optimized; fine detail reconstructed |
| maps monster | `b2d952db-ad93-4259-958c-58b6c200d895.webp` | AI background extraction, optimized; fine detail reconstructed |
| Cup Map x Cheesy Fries | `338bd2c8-07a8-49d9-9648-4b2e8c6646cf.webp` | AI background extraction, optimized; fine detail reconstructed |
| map x | `4afa95e4-ca37-4e21-9c11-75913fbd6302.webp` | AI background extraction, optimized; fine detail reconstructed |
| كلاسيك برجر | `8a7b43d0-5011-4376-bd5a-8cb518db81e1.webp` | AI background extraction, optimized; fine detail reconstructed |
| 🇮🇹 إيطاليانو برجر | `1094c5e8-111a-45fa-9727-4262d347c248.webp` | AI background extraction, optimized; fine detail reconstructed |
| Cup Map Volcano Cheesy Fries | `3a0bd3b4-4800-49a0-a718-1b1dba5da64a.webp` | AI background extraction, optimized; fine detail reconstructed |
| map vlcano cheesy fries | `43fa2239-6034-4a2b-b4aa-1082533f6f09.webp` | AI background extraction, optimized; fine detail reconstructed |
| cup golden | `69631efa-d00e-4b6f-82a3-7a4b49a6806d.webp` | AI background extraction, optimized; fine detail reconstructed |
| برجر عربي | `a3064d51-5096-4e8e-9d2e-4d486d9dea90.webp` | AI background extraction, optimized; fine detail reconstructed |
| 🌶️ مكسيكاني برجر | `26c3e4b9-27db-415a-8dae-4633b3106f62.webp` | AI background extraction, optimized; fine detail reconstructed; paper wrapper removed |
| سماش برجر | `e2339127-1541-4ea3-8089-a36364c6de66.webp` | AI background extraction, optimized; fine detail reconstructed; paper wrapper removed |
| برجر كرسبي | `1047d262-2c4b-4f3b-9989-d74d881af724.webp` | AI background extraction, optimized; fine detail reconstructed |
| Cola | `ecffd581-67d4-47d9-9669-489db9f81d12.webp` | Original transparent image, optimized |
| Cola zero | `98b27b08-4f06-4a3c-8c51-33b9d598360e.webp` | AI background extraction, optimized; fine detail reconstructed |
| Fanta | `f199fe04-a3f3-44f6-b9e3-603a624effd3.webp` | AI background extraction, optimized; fine detail reconstructed |
| Sprite | `7b98ae51-eed3-4e4d-b5cb-818327ed0d60.webp` | Original transparent image, optimized |
| Sprite zero | `c25346fb-2d35-4910-b511-081f60b88583.webp` | Original transparent image, optimized |
| XL | `1e4fd530-2c70-49a7-af17-1e355c6d40cf.webp` | Original transparent image, optimized |
| ماء | `f8e87534-a26d-4f8e-a179-5d19ac07d723.webp` | AI background extraction, optimized; fine detail reconstructed |

All assets live under `storefront/public/cinematic-preview/`. The 23 files include
20 products, the proposed cover, original logo and supplied menu texture. Each
stays below 256 KB; product alpha transparency is preserved. Total: 2,999,504
bytes; largest asset: 233,102 bytes.

The independent menu texture is the user's supplied `Warm Charcoal Smoke Texture.png`
(887 × 1774, 1,545,385 bytes), preserved unchanged outside the application.
Original SHA-256: `ae188cac206be1bb90822f99ad1129433d871091c645d425e433d8324d83c231`.
Its optimized `menu-background.webp` derivative is 12,432 bytes at the same
dimensions, SHA-256 `8111815f8503d23e91b8465388e65afb84b9fe1f9bb9b213d38a8c374b81a308`.
No image generation was used for this texture. See
[background implementation](BIZBOT_STOREFRONT_CINEMATIC_001_BACKGROUND.md).

Background-extraction prompt brief: remove only the table, condiment bottles and photographic backdrop; retain actual food proportions/ingredients/angle and integral serving containers; output real alpha; no invented products. Built-in imagegen was used. Some fine texture and branding were reconstructed from360×480 originals; these candidates need final asset approval, particularly cup/water labels and wrapper lettering.

Reusable components consume published `item.image`, `tenant.heroImage` and the
optional menu background without a Maps-specific asset map. Final production
selection goes through the existing dashboard media pipeline after approval.
