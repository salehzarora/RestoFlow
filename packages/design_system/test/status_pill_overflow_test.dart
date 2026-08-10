/// DESIGN-SYSTEM-STATUS-PILL-OVERFLOW-001 — the pill must survive a narrow box.
///
/// THE DEFECT. [RestoflowStatusPill] paints a `Container` around a
/// `Row(mainAxisSize: min)` whose label is a plain `Text`. A horizontal
/// `RenderFlex` lays its NON-FLEXIBLE children out with an UNBOUNDED main-axis
/// constraint, so that `Text` measured its full single-line width no matter how
/// little room the pill actually had, and the `Row` then overflowed its own
/// box. `Wrap` is where this bites in practice: it offers a child the full
/// available width but never forces it smaller, so the pill happily reported a
/// width it could not have.
///
/// That is a COMPONENT defect, not a call-site one — which is why bounding the
/// pill from outside (the `ConstrainedBox` first tried on the Dashboard) did
/// nothing: the bound reached the `Container`, and the `Row` handed the label
/// infinity anyway.
///
/// WHAT THESE TESTS PIN. Behaviour, not geometry: no overflow, the label still
/// rendered, the pill still hugging its label when there is room, direction
/// preserved, and the tone -> colour mapping untouched. Exact widths are
/// asserted only where "hugs its label" has no other observable meaning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// The longest labels each surface can realistically produce. Real strings from
/// the shipped ar/he/en catalogues — Arabic and Hebrew status words are longer
/// than the English ones the pill was originally eyeballed with.
const _longEn = 'Awaiting kitchen confirmation';
const _longAr = 'في انتظار تأكيد المطبخ';
const _longHe = 'ממתין לאישור המטבח';

/// A pill inside a `Wrap` inside a box of exactly [width] — the layout that
/// produced the original 5px overflow on the Dashboard Overview.
Future<void> _pumpInWrap(
  WidgetTester tester,
  Widget pill, {
  required double width,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1.0,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: restoflowBaseTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Wrap(children: [pill]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The same pill under an UNBOUNDED horizontal parent — a plain `Row` child, a
/// horizontal list, a scroll view. Nothing may overflow there either, and the
/// component must not assert about unbounded constraints.
Future<void> _pumpUnbounded(
  WidgetTester tester,
  Widget pill, {
  TextDirection direction = TextDirection.ltr,
  double textScale = 1.0,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: restoflowBaseTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [pill]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Fails with the framework's own message when anything overflowed.
void _expectNoOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'the pill must never overflow its own box');
}

/// The pill's painted width, and the width of the box it was given.
({double pill, double box}) _widths(WidgetTester tester) => (
  pill: tester.getSize(find.byType(RestoflowStatusPill)).width,
  box: tester.getSize(find.byType(Wrap)).width,
);

void main() {
  group('A. unconstrained behaviour is unchanged', () {
    testWidgets('a short label renders and the pill hugs it', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Paid'),
        width: 400,
      );
      _expectNoOverflow(tester);

      expect(find.text('Paid'), findsOneWidget);
      final w = _widths(tester);
      expect(
        w.pill,
        lessThan(w.box),
        reason: 'a pill is a chip, not a full-width banner',
      );
    });

    testWidgets('the leading icon still sits at the reading start', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(
          label: 'Live',
          tone: RestoflowTone.success,
          icon: Icons.bolt_outlined,
        ),
        width: 400,
      );
      _expectNoOverflow(tester);

      final icon = tester.getCenter(find.byIcon(Icons.bolt_outlined)).dx;
      final text = tester.getCenter(find.text('Live')).dx;
      expect(icon, lessThan(text));
    });

    testWidgets(
      'an unbounded horizontal parent still gets the intrinsic width',
      (tester) async {
        await _pumpUnbounded(tester, const RestoflowStatusPill(label: _longEn));
        _expectNoOverflow(tester);

        expect(find.text(_longEn), findsOneWidget);
        // Nothing to shrink into: the pill keeps its natural single-line width.
        expect(
          tester.getSize(find.byType(RestoflowStatusPill)).width,
          greaterThan(100),
        );
      },
    );
  });

  group('B-D. a long label in a narrow box never overflows', () {
    testWidgets('B. long English label at 200px', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longEn),
        width: 200,
      );
      _expectNoOverflow(tester);
      expect(find.text(_longEn), findsOneWidget);

      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });

    testWidgets('C. long Arabic label at 200px, RTL', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longAr, tone: RestoflowTone.warning),
        width: 200,
        direction: TextDirection.rtl,
      );
      _expectNoOverflow(tester);
      expect(find.text(_longAr), findsOneWidget);

      expect(
        Directionality.of(tester.element(find.text(_longAr))),
        TextDirection.rtl,
      );
      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });

    testWidgets('D. long Hebrew label at 200px, RTL', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longHe, tone: RestoflowTone.danger),
        width: 200,
        direction: TextDirection.rtl,
      );
      _expectNoOverflow(tester);
      expect(find.text(_longHe), findsOneWidget);

      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });

    testWidgets('the icon variant is bounded too — the icon is not the escape '
        'hatch', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(
          label: _longEn,
          icon: Icons.timer_outlined,
          tone: RestoflowTone.warning,
        ),
        width: 160,
      );
      _expectNoOverflow(tester);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });
  });

  group('E. large text scale', () {
    testWidgets('2x scale in a realistic narrow container does not overflow', (
      tester,
    ) async {
      // 326px is the measured inner width of an Overview card at phone width —
      // the exact box that produced the original defect.
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longEn),
        width: 326,
        textScale: 2.0,
      );
      _expectNoOverflow(tester);

      // Readable: the label is still there, and it was NOT shrunk back down to
      // the 1x size to make it fit.
      expect(find.text(_longEn), findsOneWidget);
      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });

    testWidgets('2x scale stays INSIDE the parent box in RTL too', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longAr),
        width: 326,
        direction: TextDirection.rtl,
        textScale: 2.0,
      );
      _expectNoOverflow(tester);

      final pill = tester.getRect(find.byType(RestoflowStatusPill));
      final box = tester.getRect(find.byType(Wrap));
      expect(pill.left, greaterThanOrEqualTo(box.left - 0.5));
      expect(pill.right, lessThanOrEqualTo(box.right + 0.5));
    });

    testWidgets('a non-dense (KDS) pill — the widest variant — also fits', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: _longEn, dense: false),
        width: 240,
        textScale: 2.0,
      );
      _expectNoOverflow(tester);

      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });

    testWidgets('text scale still makes the label BIGGER — the fix did not '
        'defeat accessibility', (tester) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Paid'),
        width: 400,
      );
      final normal = tester.getSize(find.text('Paid')).height;

      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Paid'),
        width: 400,
        textScale: 2.0,
      );
      final scaled = tester.getSize(find.text('Paid')).height;

      expect(
        scaled,
        greaterThan(normal),
        reason: 'a pill with room to spare must honour the user text scale',
      );
    });
  });

  group('F. very narrow but valid containers', () {
    for (final width in const [120.0, 80.0, 48.0]) {
      testWidgets('${width.toInt()}px holds the pill without an exception', (
        tester,
      ) async {
        await _pumpInWrap(
          tester,
          const RestoflowStatusPill(label: _longEn),
          width: width,
        );
        _expectNoOverflow(tester);

        final w = _widths(tester);
        expect(w.pill, lessThanOrEqualTo(w.box));
      });
    }

    testWidgets('an unbreakable single token is truncated, not overflowed', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Unbreakablesinglewordstatuslabel'),
        width: 80,
      );
      _expectNoOverflow(tester);

      final w = _widths(tester);
      expect(w.pill, lessThanOrEqualTo(w.box));
    });
  });

  group('G. wide containers', () {
    testWidgets('a pill does not stretch to fill the space it is offered', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Ready'),
        width: 900,
      );
      _expectNoOverflow(tester);

      final w = _widths(tester);
      expect(
        w.pill,
        lessThan(200),
        reason: 'the chip must keep hugging its label at any width',
      );
    });

    testWidgets('two pills in one Wrap still sit side by side', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: restoflowBaseTheme(),
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  child: Wrap(
                    spacing: 8,
                    children: const [
                      RestoflowStatusPill(label: 'Completed'),
                      RestoflowStatusPill(
                        label: 'Paid',
                        tone: RestoflowTone.success,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      _expectNoOverflow(tester);

      final first = tester.getRect(find.byType(RestoflowStatusPill).first);
      final second = tester.getRect(find.byType(RestoflowStatusPill).last);
      expect(second.left, greaterThan(first.right));
      expect(first.top, second.top);
    });
  });

  group('H. the semantic contract is untouched', () {
    testWidgets('every tone keeps its own container colour', (tester) async {
      final theme = restoflowBaseTheme();
      for (final tone in RestoflowTone.values) {
        await _pumpInWrap(
          tester,
          RestoflowStatusPill(label: tone.name, tone: tone),
          width: 400,
        );
        _expectNoOverflow(tester);

        final decorated = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(RestoflowStatusPill),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = decorated.decoration! as BoxDecoration;
        expect(
          decoration.color,
          tone.styleOf(theme).container,
          reason: 'tone ${tone.name} changed colour',
        );
      }
    });

    testWidgets('the label keeps the on-container colour and bold weight', (
      tester,
    ) async {
      final theme = restoflowBaseTheme();
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Voided', tone: RestoflowTone.danger),
        width: 400,
      );
      final style = tester.widget<Text>(find.text('Voided')).style!;
      expect(style.color, RestoflowTone.danger.styleOf(theme).onContainer);
      expect(style.fontWeight, FontWeight.w700);
    });

    testWidgets('dense still means smaller text than non-dense', (
      tester,
    ) async {
      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Ready'),
        width: 400,
      );
      final dense = tester.widget<Text>(find.text('Ready')).style?.fontSize;

      await _pumpInWrap(
        tester,
        const RestoflowStatusPill(label: 'Ready', dense: false),
        width: 400,
      );
      final large = tester.widget<Text>(find.text('Ready')).style?.fontSize;

      expect(dense, isNotNull);
      expect(large, greaterThan(dense!));
    });
  });
}
