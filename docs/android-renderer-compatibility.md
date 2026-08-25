# Android Renderer Compatibility — POS + Kiosk ship with Impeller disabled

> **Status**: active production policy since **PERF-112** (2026-08-23), owner-accepted.
> Owner of this rule: the two `<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false"/>` entries in
> [apps/pos/android/app/src/main/AndroidManifest.xml](../apps/pos/android/app/src/main/AndroidManifest.xml) and
> [apps/kiosk/android/app/src/main/AndroidManifest.xml](../apps/kiosk/android/app/src/main/AndroidManifest.xml).

## What was observed

- **Device**: Acer Iconia Tab A16, 16" 1920×1200 — Allwinner A733 (2×Cortex-A76 + 6×Cortex-A55) with an
  Imagination **PowerVR BXM-4-64 MC1** GPU, Android 15.
- **Symptom**: severe, *Flutter-only* jank and intermittent freezes in POS and Kiosk; UI that "looks like it
  refreshes continuously"; panels visually "entering each other" (stale/ghosted overlapping frames). YouTube
  and ordinary Android apps on the same tablet are smooth (video uses dedicated decode/composition paths, so
  that smoothness says nothing about GPU rendering of a Flutter scene).
- Two 11" tablets running the identical APKs behave normally.

## The evidence (same device, same app, one variable)

| Build | Renderer | Owner verdict on the Acer |
|---|---|---|
| PERF-110 (`db2235fe`) — all rebuild/decode/layout optimizations, Impeller default (ON → Vulkan) | Impeller/Vulkan | no meaningful improvement |
| PERF-111 (`75195e04`) — byte-identical Dart, ONLY `EnableImpeller=false` added | Skia/OpenGL ES | **"Skia test: MUCH BETTER"** |

PERF-110's application-level fixes (kiosk per-second whole-shell rebuild, decode caps, repaint isolation,
POS portrait posture, watch narrowing) are real and retained — they reduce work on every device — but the
dominant remaining cause on this hardware was the renderer path.

This matches active Flutter engine reports for the PowerVR BXM / B-Series class: significant FPS loss under
Impeller vs Impeller-disabled, and stale/ghosted/repeated frames on the Vulkan path while OpenGL/Skia renders
correctly (see flutter/flutter issues **#181315**, **#189767**, **#191457**).

## Current policy

- **`com.restoflow.pos` and `com.restoflow.kiosk` ship with `EnableImpeller=false`** (legacy Skia/OpenGL) on
  Android. These are operational restaurant surfaces: stability and correctness on the owner's real hardware
  outrank renderer modernization.
- **KDS is unchanged** (no flag): it was not reported affected and gets no unproven workaround.
- This is a deployment-time opt-out supported by Flutter 3.44 on Android; no runtime GPU detection, no
  device-specific flavors, no separate app IDs.
- **Do not generalize**: this does not claim every PowerVR device is broken — it pins a proven-safe renderer
  for the device class we actually operate on.

## Building a field-diagnostics APK

The PERF-110 diagnostics (device metrics + rolling frame timings in the staff Device Settings of POS and
Kiosk) are disabled at compile time in normal production builds: `RESTOFLOW_PERF_DIAGNOSTICS` is a
compile-time constant defaulting to false, so the frame recorder never starts (dead code) and the staff
Device Settings entry can never appear. To produce a diagnostics build, add one define to the ordinary
release command:

```
flutter build apk --release --build-name=<x.y.z> --build-number=<N> \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=$RESTOFLOW_SUPABASE_URL \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=$RESTOFLOW_SUPABASE_ANON_KEY \
  --dart-define=RESTOFLOW_PERF_DIAGNOSTICS=true
```

Everything the diagnostics show stays on the device; nothing is logged, persisted or sent.

## When to revisit

Re-evaluate only after BOTH:

1. a Flutter/engine upgrade whose release notes or the issues above indicate the PowerVR BXM/B-Series
   problems are fixed, **and**
2. a controlled same-device A/B on the Acer A16 (one build with the flag removed vs one with it kept, exactly
   as PERF-111 did) that the owner judges at least as smooth.

Until then, removing the flag is a regression on known production hardware.
