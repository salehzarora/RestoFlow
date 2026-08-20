import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'src/design/kiosk_theme.dart';
import 'src/screens/kiosk_shell.dart';
import 'src/state/kiosk_flow_controller.dart';

/// KIOSK-001 Phase 1 — RestoFlow customer self-service kiosk.
///
/// FIXTURE-ONLY build: the approved V2 visual/interaction foundation at the
/// canonical 1080×1920 portrait frame. There is NO backend of any kind here —
/// no Supabase client, no device pairing, no PIN sessions, no order submit,
/// no printer. Those arrive phase by phase (see the KIOSK-001 Phase 0 plan).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kiosk posture: portrait only, immersive fullscreen. Keep-screen-on is
  // applied on Android in MainActivity (FLAG_KEEP_SCREEN_ON).
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const ProviderScope(child: KioskApp()));
}

class KioskApp extends ConsumerWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(kioskFlowProvider.select((s) => s.lang));
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).kioskStart,
      debugShowCheckedModeBanner: false,
      theme: kioskTheme(),
      locale: Locale(lang),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      localeResolutionCallback: restoflowResolveLocale,
      home: const KioskTicker(child: KioskShell()),
    );
  }
}

/// Production clock: forwards one [KioskFlowController.tick] per second. All
/// timer behavior lives in the controller so tests drive time by calling
/// tick() directly — this widget is the only wall-clock coupling.
class KioskTicker extends ConsumerStatefulWidget {
  const KioskTicker({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<KioskTicker> createState() => _KioskTickerState();
}

class _KioskTickerState extends ConsumerState<KioskTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(kioskFlowProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
