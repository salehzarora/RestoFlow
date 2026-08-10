/// GLOBAL-BRAND-SHARED-V6 — the shared components, hardened where V2–V5 proved
/// the failure modes.
///
/// V6 is consolidation, not another redesign. Every claim here is about a widget
/// in `packages/design_system` that MORE THAN ONE app renders, so a defect found
/// once is a defect fixed everywhere.
///
/// The instrumentation note that made this whole program possible, repeated
/// because it is the single most useful thing learned: a RenderFlex overflow is
/// reported during PAINT through [FlutterError.onError] and does NOT reach
/// `tester.takeException()` in this harness. A matrix built on `takeException`
/// is green whatever the layout does — it reads as coverage while proving
/// nothing. Every width/scale assertion below captures the real channel, and
/// every fix in this file was RED-proved through it before being written.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

// ── harness ────────────────────────────────────────────────────────────────

/// Runs [body] and returns every RenderFlex overflow the renderer reported.
///
/// Restored BEFORE the caller's expectation: the binding asserts it owns the
/// hook by then, and leaving the override installed turns every later failure in
/// the file into an opaque "did not complete".
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };
  await body();
  FlutterError.onError = previous;
  return overflows;
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  double scale = 1.0,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: restoflowBaseTheme(brightness: brightness),
  builder: (context, child) => MediaQuery.withClampedTextScaling(
    minScaleFactor: scale,
    maxScaleFactor: scale,
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// The readiness strip as the Dashboard's setup centre really builds it: four
/// stats with localized-length labels, a long headline and a trailing action.
Widget _readinessStrip({bool ready = false}) => RestoflowReadinessStrip(
  ready: ready,
  readyLabel: 'Branch ready for service',
  pendingLabel: 'Finishing branch setup',
  percent: 75,
  trailing: IconButton(
    onPressed: () {},
    icon: const Icon(Icons.refresh),
    visualDensity: VisualDensity.compact,
  ),
  stats: const [
    RestoflowReadinessStat(
      icon: Icons.restaurant_menu_outlined,
      label: 'Menu',
      done: 12,
      total: 18,
    ),
    RestoflowReadinessStat(
      icon: Icons.devices_outlined,
      label: 'Devices',
      done: 2,
      total: 3,
    ),
    RestoflowReadinessStat(
      icon: Icons.print_outlined,
      label: 'Printers',
      done: 1,
      total: 2,
    ),
    RestoflowReadinessStat(
      icon: Icons.badge_outlined,
      label: 'Staff',
      done: 4,
      total: 5,
    ),
  ],
);

const _widths = [1280.0, 834.0, 700.0, 540.0, 430.0, 390.0];

/// A design-system widget owns no strings, so LOCALE is not the axis that can
/// break it — DIRECTION is. Testing direction keeps this suite honest about
/// what the layer under test actually decides, and keeps `design_system` free
/// of the l10n dependency it deliberately does not have.
const _directions = TextDirection.values;

void main() {
  // =========================================================================
  // A. SHARED-READINESS-STRIP-TEXTSCALE-001
  // =========================================================================
  group('A. the readiness strip survives a doubled text scale', () {
    // 700 x 2x is the exact reproducer recorded when this was deferred out of
    // V2.2: an owner on a tablet with large text saw ~27px of striped bar
    // across their setup checklist.
    testWidgets('700px / 2x — the deferred reproducer', (tester) async {
      _size(tester, const Size(700, 4000));
      final overflows = await _overflowsDuring(() async {
        await tester.pumpWidget(_host(_readinessStrip(), scale: 2.0));
        await tester.pumpAndSettle();
      });
      expect(
        overflows,
        isEmpty,
        reason: 'the readiness strip must reflow at a doubled text scale',
      );
    });

    for (final width in _widths) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()}px / ${scale}x', (tester) async {
          _size(tester, Size(width, scale > 1 ? 6000 : 3000));
          final overflows = await _overflowsDuring(() async {
            await tester.pumpWidget(_host(_readinessStrip(), scale: scale));
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);
        });
      }
    }

    for (final direction in _directions) {
      testWidgets('700px / 2x / ${direction.name}', (tester) async {
        _size(tester, const Size(700, 6000));
        final overflows = await _overflowsDuring(() async {
          await tester.pumpWidget(
            _host(_readinessStrip(), direction: direction, scale: 2.0),
          );
          await tester.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }

    testWidgets('every statistic and the percent survive the reflow', (
      tester,
    ) async {
      // The fix must not have bought its space by dropping information: a
      // readiness checklist that hides a count is worse than one that wraps.
      _size(tester, const Size(700, 6000));
      await tester.pumpWidget(_host(_readinessStrip(), scale: 2.0));
      await tester.pumpAndSettle();
      for (final label in ['Menu', 'Devices', 'Printers', 'Staff']) {
        expect(find.text(label), findsOneWidget, reason: '$label went missing');
      }
      for (final count in ['12/18', '2/3', '1/2', '4/5']) {
        expect(find.text(count), findsOneWidget, reason: '$count went missing');
      }
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Finishing branch setup'), findsOneWidget);
    });
  });

  // =========================================================================
  // B. STEP TILE at high text scale
  // =========================================================================
  group('B. the step tile at high text scale', () {
    Widget steps({int count = 3}) => Column(
      children: [
        for (var i = 0; i < count; i++)
          RestoflowStepTile(
            index: i + 1,
            title: 'Pair the counter point-of-sale device with this branch',
            description:
                'Open the POS on the device, enter the enrollment code shown '
                'here, and approve the pairing from the devices list.',
          ),
      ],
    );

    for (final width in [700.0, 430.0, 390.0]) {
      for (final direction in _directions) {
        testWidgets('${width.toInt()}px / ${direction.name} / 2x', (
          tester,
        ) async {
          _size(tester, Size(width, 8000));
          final overflows = await _overflowsDuring(() async {
            await tester.pumpWidget(
              _host(steps(), direction: direction, scale: 2.0),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('the badge never clips the number it exists to show', (
      tester,
    ) async {
      // NOT a size comparison on the rendered Text: a fixed-size Container
      // clamps its child and `getSize` returns the CLAMPED value, so a clipped
      // digit measures exactly like a fitting one. That is precisely how this
      // defect stayed invisible — it never raised a RenderFlex overflow either.
      // The natural size is computed independently and compared to the box.
      for (final index in [1, 10]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          _size(tester, const Size(700, 3000));
          await tester.pumpWidget(
            _host(
              RestoflowStepTile(index: index, title: 'Step', description: 'd'),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();

          final digit = find.text('$index');
          expect(digit, findsOneWidget);
          final style = tester.widget<Text>(digit).style;
          final natural = TextPainter(
            text: TextSpan(text: '$index', style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
          final badge = tester.getSize(
            find.ancestor(of: digit, matching: find.byType(Container)).first,
          );
          expect(
            badge.width,
            greaterThanOrEqualTo(natural.width),
            reason: 'index $index at ${scale}x is wider than its badge',
          );
          expect(
            badge.height,
            greaterThanOrEqualTo(natural.height),
            reason: 'index $index at ${scale}x is taller than its badge',
          );
        }
      }
    });
    testWidgets('the title never collides with the index badge', (
      tester,
    ) async {
      _size(tester, const Size(430, 6000));
      await tester.pumpWidget(_host(steps(count: 1), scale: 2.0));
      await tester.pumpAndSettle();
      final badge = tester.getRect(
        find
            .ancestor(of: find.text('1'), matching: find.byType(Container))
            .first,
      );
      final title = tester.getRect(
        find.textContaining('Pair the counter').first,
      );
      expect(
        title.left,
        greaterThanOrEqualTo(badge.right - 1),
        reason: 'the label must start after the indicator, never over it',
      );
    });
  });

  // =========================================================================
  // C. SHARED HOST ROWS — the pattern V2–V5 kept finding
  // =========================================================================
  group('C. shared rows bound their trailing clusters', () {
    testWidgets('a section card header with a long title and an action', (
      tester,
    ) async {
      _size(tester, const Size(430, 4000));
      final overflows = await _overflowsDuring(() async {
        await tester.pumpWidget(
          _host(
            RestoflowSectionCard(
              title: 'Recent orders across every branch in this organization',
              subtitle: 'Newest first, on the currently selected window',
              action: TextButton(
                onPressed: () {},
                child: const Text('View all'),
              ),
              children: const [SizedBox(height: 40)],
            ),
            scale: 2.0,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(overflows, isEmpty);
    });

    // THE WIDEST-IMPACT FIND OF V6.
    //
    // A notice banner with an action overflowed at 390px at ORDINARY text
    // scale — a shipping defect on every phone-width surface that tells
    // someone what to do next, not a large-text edge case. Measured boundary
    // before the fix (first failing scale per width): 1280 never, 834 never,
    // 700 at 2.0, 540 at 1.5, 430 at 1.15, 390 at 1.0.
    for (final width in [1280.0, 834.0, 700.0, 540.0, 430.0, 390.0]) {
      for (final scale in [1.0, 1.15, 1.3, 1.5, 2.0]) {
        testWidgets('notice banner + action ${width.toInt()}px / ${scale}x', (
          tester,
        ) async {
          _size(tester, Size(width, 4000));
          final overflows = await _overflowsDuring(() async {
            await tester.pumpWidget(
              _host(
                RestoflowNoticeBanner(
                  tone: RestoflowTone.warning,
                  title: 'No kitchen display is configured yet',
                  body:
                      'Create a kitchen display device so cooking tickets '
                      'reach the pass.',
                  action: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Create kitchen display'),
                  ),
                ),
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
          });
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('the banner action survives the vertical fallback', (
      tester,
    ) async {
      // Stacking must not have hidden the very control the banner exists to
      // offer, and it must still fire.
      var taps = 0;
      _size(tester, const Size(390, 2000));
      await tester.pumpWidget(
        _host(
          RestoflowNoticeBanner(
            tone: RestoflowTone.warning,
            body: 'Create a kitchen display device.',
            action: OutlinedButton(
              onPressed: () => taps++,
              child: const Text('Create kitchen display'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create kitchen display'), findsOneWidget);
      await tester.tap(find.text('Create kitchen display'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
    testWidgets('a metric card with a long label, value and delta', (
      tester,
    ) async {
      _size(tester, const Size(390, 4000));
      final overflows = await _overflowsDuring(() async {
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 180,
              child: RestoflowMetricCard(
                style: RestoflowMetricCardStyle.kpi,
                label: 'Average order value across the window',
                value: '₪1,234.56',
                icon: Icons.trending_up,
                delta: RestoflowMetricDelta(
                  label: '12% vs the previous ninety days',
                  positive: true,
                ),
              ),
            ),
            scale: 2.0,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(overflows, isEmpty);
    });

    testWidgets('a status pill with a long label inside a narrow row', (
      tester,
    ) async {
      // The pill is already internally resilient (Flexible + wrap + ellipsis);
      // this pins that a HOST giving it a tight box still cannot break it.
      _size(tester, const Size(390, 2000));
      final overflows = await _overflowsDuring(() async {
        await tester.pumpWidget(
          _host(
            Row(
              children: [
                const Expanded(child: Text('Kitchen ticket')),
                Flexible(
                  child: RestoflowStatusPill(
                    label: 'Pending acknowledgement from the kitchen',
                    tone: RestoflowTone.warning,
                    icon: Icons.schedule,
                  ),
                ),
              ],
            ),
            scale: 2.0,
          ),
        );
        await tester.pumpAndSettle();
      });
      expect(overflows, isEmpty);
    });
  });

  // =========================================================================
  // D. SEMANTIC COLOUR CONTRACT — pinned against future brand revaluation
  // =========================================================================
  group('D. semantics never collapse into the brand', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name}: four states, and neither brand hue', () {
        final semantic = RestoflowSemanticColors.of(brightness);
        final brand = RestoflowBrandPalette.of(brightness);

        final states = {
          semantic.success,
          semantic.warning,
          semantic.danger,
          semantic.info,
        };
        expect(
          states.length,
          4,
          reason: 'two states sharing a colour is an unreadable board',
        );
        for (final state in states) {
          expect(
            state,
            isNot(brand.primaryNavy),
            reason: 'a brand revaluation must not repaint an operational state',
          );
          expect(state, isNot(brand.accentOrange));
        }
        // The attention accent is the brand orange BY DESIGN (KDS V5) — that is
        // an identity decision, not an operational state, and it must stay
        // distinct from all four states.
        expect(semantic.accent, brand.accentOrange);
        for (final state in states) {
          expect(semantic.accent, isNot(state));
        }
      });
    }
  });

  // =========================================================================
  // E. ACCESSIBILITY — touch targets, focus, and never colour alone
  // =========================================================================
  group('E. shared interactions stay reachable', () {
    testWidgets('a tappable readiness stat keeps a usable target', (
      tester,
    ) async {
      _size(tester, const Size(1280, 2000));
      await tester.pumpWidget(
        _host(
          RestoflowReadinessStrip(
            ready: false,
            readyLabel: 'ready',
            pendingLabel: 'pending',
            percent: 40,
            stats: [
              RestoflowReadinessStat(
                icon: Icons.devices_outlined,
                label: 'Devices',
                done: 1,
                total: 3,
                onTap: () {},
                tapKey: const Key('stat-devices'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(const Key('stat-devices')));
      expect(
        size.height,
        greaterThanOrEqualTo(44.0),
        reason: 'a stat that navigates must be comfortably tappable',
      );
    });

    testWidgets('a status pill communicates by TEXT, not colour alone', (
      tester,
    ) async {
      // Colour-blind and forced-colour users read the label; the tone is an
      // accelerator, never the message.
      _size(tester, const Size(700, 1200));
      await tester.pumpWidget(
        _host(
          const Row(
            children: [
              RestoflowStatusPill(label: 'Paid', tone: RestoflowTone.success),
              SizedBox(width: 8),
              RestoflowStatusPill(label: 'Unpaid', tone: RestoflowTone.neutral),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Unpaid'), findsOneWidget);
    });

    testWidgets('a tappable metric card takes keyboard focus', (tester) async {
      _size(tester, const Size(700, 1200));
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: RestoflowMetricCard(
              style: RestoflowMetricCardStyle.kpi,
              label: 'Unpaid orders',
              value: '2',
              icon: Icons.pending_actions_outlined,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        primaryFocus?.hasPrimaryFocus,
        isTrue,
        reason: 'a card that navigates must be reachable without a pointer',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });
}
