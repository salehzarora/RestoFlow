@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kiosk/src/data/kiosk_fixtures.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_shell.dart';
import 'package:restoflow_kiosk/src/state/kiosk_flow_controller.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// KIOSK-001 Phase 1 — LOCAL screenshot generator (repo convention: the
/// `**/test/goldens/` output directory is gitignored; this is a review tool,
/// not a CI regression suite — the committed regression guard is the
/// structural assertions in the other suites). Run explicitly with:
///   flutter test test/kiosk_screenshots_test.dart \
///     --dart-define=KIOSK_SCREENSHOTS=true --update-goldens
/// which writes canonical 1080×1920 PNGs under test/goldens/kiosk_v2/.
const bool _enabled = bool.fromEnvironment('KIOSK_SCREENSHOTS');

Future<void> _loadRealFonts() async {
  final dir = Directory('assets/fonts').existsSync()
      ? 'assets/fonts'
      : 'apps/kiosk/assets/fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Anton', ['Anton-Regular.ttf']);
  await load('Rubik', [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-SemiBold.ttf',
    'Rubik-Bold.ttf',
    'Rubik-ExtraBold.ttf',
    'Rubik-Black.ttf',
  ]);
  await load('Roboto', ['Rubik-Regular.ttf']);

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
      );
      await loader.load();
    }
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, String lang) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(kioskFlowProvider.notifier).setLanguage(lang);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: Locale(ref.watch(kioskFlowProvider.select((s) => s.lang))),
          debugShowCheckedModeBanner: false,
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: const KioskShell(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  // Decode every fixture image up front — Image.asset never resolves inside
  // the test event loop without runAsync, and the screenshots exist to show
  // the real photography treatment.
  final context = tester.element(find.byType(KioskShell));
  await tester.runAsync(() async {
    for (final asset in [
      ...kioskAttractAssets,
      for (final c in kioskFixtureMenu) ...[
        if (c.thumbAsset != null) c.thumbAsset!,
        for (final it in c.items)
          if (it.imageAsset != null) it.imageAsset!,
      ],
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

Future<void> _shot(WidgetTester tester, String name) async {
  // Multiple frames: the first starts any screen/sheet transition, the rest
  // advance it to completion before capture.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
  await expectLater(
    find.byType(KioskShell),
    matchesGoldenFile('goldens/kiosk_v2/$name.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (_enabled) await _loadRealFonts();
  });

  testWidgets('attract ar', skip: !_enabled, (tester) async {
    await _pump(tester, 'ar');
    await _shot(tester, 'attract_ar');
  });

  testWidgets('service ar', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    c.read(kioskFlowProvider.notifier).startFromAttract();
    await _shot(tester, 'service_ar');
  });

  testWidgets('tables ar busy', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    final n = c.read(kioskFlowProvider.notifier);
    n.startFromAttract();
    n.pickService(KioskServiceType.dineIn);
    n.toggleTable('T4');
    await _shot(tester, 'tables_ar');
  });

  for (final lang in ['ar', 'he', 'en']) {
    testWidgets('menu $lang', skip: !_enabled, (tester) async {
      final c = await _pump(tester, lang);
      final n = c.read(kioskFlowProvider.notifier);
      n.startFromAttract();
      n.pickService(KioskServiceType.takeaway);
      await _shot(tester, 'menu_$lang');
    });
  }

  testWidgets('item sheet ar', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    final n = c.read(kioskFlowProvider.notifier);
    n.startFromAttract();
    n.pickService(KioskServiceType.takeaway);
    n.openItem('b1');
    await _shot(tester, 'item_ar');
  });

  testWidgets('cart ar', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    final n = c.read(kioskFlowProvider.notifier);
    n.startFromAttract();
    n.pickService(KioskServiceType.dineIn);
    n.toggleTable('T4');
    n.confirmTable();
    n.openItem('b1');
    n.toggleOption('weight', 'w240');
    n.submitDraft();
    n.openItem('s1');
    n.toggleOption('sauce', 'sc3');
    n.submitDraft();
    n.openCart();
    await _shot(tester, 'cart_ar');
  });

  testWidgets('confirmation ar', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    final n = c.read(kioskFlowProvider.notifier);
    n.startFromAttract();
    n.pickService(KioskServiceType.dineIn);
    n.toggleTable('T4');
    n.confirmTable();
    n.openItem('b1');
    n.toggleOption('weight', 'w240');
    n.submitDraft();
    n.setCustomerName('Sami');
    n.placeOrder();
    await _shot(tester, 'confirm_ar');
  });

  testWidgets('pin gate', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'ar');
    final n = c.read(kioskFlowProvider.notifier);
    n.staffTap();
    n.staffTap();
    n.staffTap();
    await _shot(tester, 'pin_ar');
  });

  testWidgets('settings', skip: !_enabled, (tester) async {
    final c = await _pump(tester, 'en');
    final n = c.read(kioskFlowProvider.notifier);
    n.staffTap();
    n.staffTap();
    n.staffTap();
    for (final d in ['2', '4', '6', '8']) {
      n.pinPress(d);
    }
    await _shot(tester, 'settings_en');
  });
}
