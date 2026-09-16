// CANVASKIT-A2.1 — serve the CanvasKit engine from this origin, once, under a
// path addressed by the ENGINE REVISION.
//
// This is a Flutter bootstrap TEMPLATE. Flutter regenerates the real
// flutter_bootstrap.js from it on every `flutter build web`; the three {{...}}
// tokens are substituted by the SDK. Nothing here edits a generated or minified
// loader.
//
// WHY A REVISION IN THE PATH
// A2 pointed every role at a bare "/canvaskit/". That removed a discriminator
// the default already had: the SDK's own fallback is
// https://www.gstatic.com/flutter-canvaskit/<engineRevision>/, so the engine
// revision is part of the default URL. With a bare path, a browser still holding
// a cached /canvaskit/canvaskit.wasm from an older engine would pair those bytes
// with a newer main.dart.js after an SDK upgrade. Addressing the directory by
// revision makes an upgrade a NEW url, so stale bytes are simply never requested.
//
// WHERE THE REVISION COMES FROM
// The build-config token below assigns _flutter.buildConfig, which the SDK
// populates with the engineRevision of the build that produced THIS file. It is
// read at run time from that object - never hardcoded, never copied from a
// document, and never a Flutter marketing version (3.44.2 is not a cache key:
// several SDK builds can share one, and it does not identify the engine bytes).
//
// NO SILENT FALLBACK
// If the revision is missing or malformed this throws. It must not quietly fall
// back to an unversioned path or to the gstatic CDN: either would hide exactly
// the defect this change exists to prevent. The pattern also rejects "/" and
// ".." so the value can never escape the intended directory.
//
// WHAT IS DELIBERATELY UNCHANGED
// The serviceWorkerSettings block is the SDK default, kept verbatim: this change
// must not introduce, remove or rescope a service worker. There is no
// onEntrypointLoaded callback, which would stop `config` reaching the engine
// initializer. No renderer flag and no --no-web-resources-cdn shortcut is used;
// the four `flutter build web` command lines are untouched.
{{flutter_js}}
{{flutter_build_config}}
(function () {
  var cfg = window._flutter && window._flutter.buildConfig;
  var rev = cfg && cfg.engineRevision;
  if (typeof rev !== 'string' || !/^[0-9a-fA-F]{7,64}$/.test(rev)) {
    throw new Error(
      'CANVASKIT-A2.1: buildConfig.engineRevision is missing or malformed (' + rev + '). ' +
      'Refusing to fall back to an unversioned path or to the CanvasKit CDN.'
    );
  }
  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: '/canvaskit/' + rev + '/'
    },
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}}
    }
  });
})();
