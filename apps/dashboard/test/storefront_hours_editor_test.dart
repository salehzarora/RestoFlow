import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/opening_hours_editor.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_models.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STOREFRONT-PUBLISH-001 — the opening hours editor: a PURE model editor
/// that emits exactly the validator grammar (weekday 0 = Sunday, up to three
/// windows a day, overnight windows said so, open == close flagged, exception
/// dates "closed all day" or one window — never `closed: false` — and the caps).

/// Holds the editor's value like the section does, and records every emit.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    required this.emitted,
    this.timezone,
    this.pickTime,
    this.pickDate,
  });

  final OpeningHours initial;
  final List<OpeningHours> emitted;
  final String? timezone;
  final StorefrontTimePicker? pickTime;
  final StorefrontDatePicker? pickDate;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late OpeningHours _value = widget.initial;

  @override
  Widget build(BuildContext context) => OpeningHoursEditor(
    value: _value,
    timezone: widget.timezone,
    pickTime: widget.pickTime,
    pickDate: widget.pickDate,
    onChanged: (h) {
      widget.emitted.add(h);
      setState(() => _value = h);
    },
  );
}

/// Scripted picker answers (in order).
class _Picks {
  _Picks(this.answers);

  final List<String?> answers;
  final List<String?> initials = [];

  Future<String?> call(BuildContext context, String? initial) async {
    initials.add(initial);
    return answers.removeAt(0);
  }
}

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void main() {
  late List<OpeningHours> emitted;

  setUp(() => emitted = []);

  Future<void> pump(
    WidgetTester tester, {
    OpeningHours initial = OpeningHours.empty,
    String? timezone = 'Asia/Jerusalem',
    _Picks? times,
    _Picks? dates,
    String locale = 'en',
  }) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        locale: Locale(locale),
        home: Scaffold(
          body: SingleChildScrollView(
            child: _Host(
              initial: initial,
              emitted: emitted,
              timezone: timezone,
              pickTime: times?.call,
              pickDate: dates?.call,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seven weekdays (Sunday first), all closed, with the timezone', (
    tester,
  ) async {
    final l10n = await _l10n('en');
    await pump(tester);
    for (var dow = 0; dow < 7; dow++) {
      expect(find.byKey(Key('storefront-hours-day-$dow')), findsOneWidget);
      expect(find.byKey(Key('storefront-hours-closed-$dow')), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text(l10n.storefrontHoursSunday)).dy,
      lessThan(tester.getTopLeft(find.text(l10n.storefrontHoursMonday)).dy),
    );
    expect(
      find.text(l10n.storefrontHoursTimezone('Asia/Jerusalem')),
      findsOneWidget,
    );
    expect(find.text(l10n.storefrontHoursExceptionsEmpty), findsOneWidget);
  });

  testWidgets('no timezone yet is said so', (tester) async {
    final l10n = await _l10n('en');
    await pump(tester, timezone: null);
    expect(find.text(l10n.storefrontHoursNoTimezone), findsOneWidget);
  });

  testWidgets('add a window emits {dow, open, close} with a JSON integer dow', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('storefront-hours-add-1')));
    await tester.pumpAndSettle();
    expect(emitted.last.toJson(), {
      'weekly': [
        {'dow': 1, 'open': '09:00', 'close': '17:00'},
      ],
      'exceptions': <Object?>[],
    });
    expect(OpeningHours.isValidJson(emitted.last.toJson()), isTrue);
    expect(find.byKey(const Key('storefront-hours-closed-1')), findsNothing);
    expect(find.byKey(const Key('storefront-hours-open-1-0')), findsOneWidget);
  });

  testWidgets('a close earlier than open crosses midnight and says so', (
    tester,
  ) async {
    final times = _Picks(['02:00']);
    await pump(
      tester,
      initial: const OpeningHours(
        weekly: [WeeklyWindow(dow: 5, open: '18:00', close: '23:00')],
      ),
      times: times,
    );
    expect(
      find.byKey(const Key('storefront-hours-overnight-5-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('storefront-hours-close-5-0')));
    await tester.pumpAndSettle();
    expect(times.initials, ['23:00']);
    expect(emitted.last.weekly.single.close, '02:00');
    expect(emitted.last.weekly.single.crossesMidnight, isTrue);
    expect(emitted.last.isValid, isTrue);
    expect(
      find.byKey(const Key('storefront-hours-overnight-5-0')),
      findsOneWidget,
    );
  });

  testWidgets('open == close is flagged and makes the model invalid', (
    tester,
  ) async {
    final l10n = await _l10n('en');
    await pump(
      tester,
      initial: const OpeningHours(
        weekly: [WeeklyWindow(dow: 0, open: '09:00', close: '17:00')],
      ),
      times: _Picks(['09:00']),
    );
    await tester.tap(find.byKey(const Key('storefront-hours-close-0-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storefront-hours-error-0-0')), findsOneWidget);
    expect(find.text(l10n.storefrontHoursOpenEqualsClose), findsOneWidget);
    expect(emitted.last.isValid, isFalse);
    expect(OpeningHours.isValidJson(emitted.last.toJson()), isFalse);
  });

  testWidgets('three windows per day at most (7 x 3 = the 21 cap)', (
    tester,
  ) async {
    final l10n = await _l10n('en');
    await pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('storefront-hours-add-2')));
      await tester.pumpAndSettle();
    }
    expect(emitted.last.windowsFor(2), hasLength(3));
    // DASH-2: three presses never produce an identical window.
    expect(emitted.last.windowsFor(2).toSet(), hasLength(3));
    expect(emitted.last.overlaps(), isEmpty);
    final add = tester.widget<TextButton>(
      find.byKey(const Key('storefront-hours-add-2')),
    );
    expect(add.onPressed, isNull);
    expect(find.text(l10n.storefrontHoursDayCap(3)), findsOneWidget);
    expect(OpeningHours.maxWindowsPerDay * 7, OpeningHours.maxWeekly);
  });

  testWidgets('DASH-2: "Add hours" seeds after the day\'s last close — never '
      'a second identical 09:00-17:00', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('storefront-hours-add-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storefront-hours-add-1')));
    await tester.pumpAndSettle();
    expect(emitted.last.windowsFor(1), const [
      WeeklyWindow(dow: 1, open: '09:00', close: '17:00'),
      WeeklyWindow(dow: 1, open: '18:00', close: '22:00'),
    ]);
    expect(find.byKey(const Key('storefront-hours-duplicate-1')), findsNothing);
    expect(find.byKey(const Key('storefront-hours-overlap-1')), findsNothing);
  });

  testWidgets('C9 / DASH-2: ADVISORY warnings for a duplicate, a same-day '
      'overlap and an overnight window running into the next day (Saturday '
      'into Sunday)', (tester) async {
    final l10n = await _l10n('en');
    const hours = OpeningHours(
      weekly: [
        WeeklyWindow(dow: 1, open: '09:00', close: '17:00'),
        WeeklyWindow(dow: 1, open: '09:00', close: '17:00'),
        WeeklyWindow(dow: 2, open: '09:00', close: '12:00'),
        WeeklyWindow(dow: 2, open: '10:00', close: '23:00'),
        WeeklyWindow(dow: 6, open: '20:00', close: '03:00'),
        WeeklyWindow(dow: 0, open: '01:00', close: '11:00'),
      ],
    );
    await pump(tester, initial: hours);
    Text text(String key) => tester.widget<Text>(find.byKey(Key(key)));
    expect(
      text('storefront-hours-duplicate-1').data,
      l10n.storefrontHoursDuplicateWarning,
    );
    expect(
      text('storefront-hours-overlap-2').data,
      l10n.storefrontHoursOverlapWarning,
    );
    expect(
      text('storefront-hours-spill-6').data,
      l10n.storefrontHoursSpillWarning(l10n.storefrontHoursSunday),
    );
    // Only where they apply.
    for (final key in [
      'storefront-hours-overlap-1',
      'storefront-hours-duplicate-2',
      'storefront-hours-spill-0',
      'storefront-hours-overlap-0',
      'storefront-hours-overlap-6',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    // Advisory: the value is still valid, nothing was changed or blocked.
    expect(hours.isValid, isTrue);
    expect(emitted, isEmpty);
    expect(find.byKey(const Key('storefront-hours-error-1-1')), findsNothing);
  });

  testWidgets('a clean split shift and an overnight window into a closed day '
      'get no warning', (tester) async {
    await pump(
      tester,
      initial: const OpeningHours(
        weekly: [
          WeeklyWindow(dow: 0, open: '08:00', close: '12:00'),
          WeeklyWindow(dow: 0, open: '12:00', close: '16:00'),
          WeeklyWindow(dow: 0, open: '18:00', close: '02:00'),
        ],
      ),
    );
    final warnings = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          RegExp(
            r'^storefront-hours-(overlap|duplicate|spill)-',
          ).hasMatch(k.value);
    });
    expect(warnings, findsNothing);
  });

  testWidgets('in Hebrew the spill warning names the next day in Hebrew', (
    tester,
  ) async {
    final he = await _l10n('he');
    await pump(
      tester,
      locale: 'he',
      initial: const OpeningHours(
        weekly: [
          WeeklyWindow(dow: 3, open: '22:00', close: '04:00'),
          WeeklyWindow(dow: 4, open: '03:00', close: '09:00'),
        ],
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('storefront-hours-spill-3')))
          .data,
      he.storefrontHoursSpillWarning(he.storefrontHoursThursday),
    );
  });

  testWidgets('remove a window; the other days keep their order', (
    tester,
  ) async {
    await pump(
      tester,
      initial: const OpeningHours(
        weekly: [
          WeeklyWindow(dow: 0, open: '08:00', close: '12:00'),
          WeeklyWindow(dow: 0, open: '14:00', close: '20:00'),
          WeeklyWindow(dow: 3, open: '10:00', close: '22:00'),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('storefront-hours-remove-0-0')));
    await tester.pumpAndSettle();
    expect(emitted.last.weekly, const [
      WeeklyWindow(dow: 0, open: '14:00', close: '20:00'),
      WeeklyWindow(dow: 3, open: '10:00', close: '22:00'),
    ]);
  });

  testWidgets(
    'exception dates: closed all day, or ONE window without a closed key',
    (tester) async {
      final dates = _Picks(['2026-12-25']);
      final times = _Picks(['10:00']);
      await pump(tester, dates: dates, times: times);
      await tester.tap(find.byKey(const Key('storefront-hours-add-exception')));
      await tester.pumpAndSettle();
      expect(emitted.last.toJson()['exceptions'], [
        {'date': '2026-12-25', 'closed': true},
      ]);

      await tester.tap(
        find.byKey(const Key('storefront-hours-exception-window-0')),
      );
      await tester.pumpAndSettle();
      final window = (emitted.last.toJson()['exceptions']! as List).single;
      expect(window, {'date': '2026-12-25', 'open': '09:00', 'close': '17:00'});
      expect((window as Map).containsKey('closed'), isFalse);

      await tester.tap(find.byKey(const Key('storefront-hours-open-x0')));
      await tester.pumpAndSettle();
      expect(emitted.last.exceptions.single.open, '10:00');

      // Back to closed: never `closed: false`, never open/close with closed.
      await tester.tap(
        find.byKey(const Key('storefront-hours-exception-closed-0')),
      );
      await tester.pumpAndSettle();
      expect(emitted.last.toJson()['exceptions'], [
        {'date': '2026-12-25', 'closed': true},
      ]);
      expect(OpeningHours.isValidJson(emitted.last.toJson()), isTrue);

      await tester.tap(
        find.byKey(const Key('storefront-hours-exception-remove-0')),
      );
      await tester.pumpAndSettle();
      expect(emitted.last.exceptions, isEmpty);
    },
  );

  testWidgets('a duplicate exception date is refused with a note', (
    tester,
  ) async {
    await pump(
      tester,
      initial: const OpeningHours(
        exceptions: [HoursException.closed('2026-12-25')],
      ),
      dates: _Picks(['2026-12-25']),
    );
    await tester.tap(find.byKey(const Key('storefront-hours-add-exception')));
    await tester.pumpAndSettle();
    expect(emitted, isEmpty);
    expect(
      find.byKey(const Key('storefront-hours-exception-duplicate')),
      findsOneWidget,
    );
  });

  testWidgets('at 62 exception dates the add button is disabled', (
    tester,
  ) async {
    final l10n = await _l10n('en');
    final many = [
      for (var i = 0; i < OpeningHours.maxExceptions; i++)
        HoursException.closed(
          '2027-${(i ~/ 28 + 1).toString().padLeft(2, '0')}-'
          '${(i % 28 + 1).toString().padLeft(2, '0')}',
        ),
    ];
    await pump(tester, initial: OpeningHours(exceptions: many));
    final add = tester.widget<TextButton>(
      find.byKey(const Key('storefront-hours-add-exception')),
    );
    expect(add.onPressed, isNull);
    expect(
      find.text(l10n.storefrontHoursExceptionsCap(OpeningHours.maxExceptions)),
      findsOneWidget,
    );
  });

  testWidgets('in Arabic the day names are localized and times stay LTR', (
    tester,
  ) async {
    final ar = await _l10n('ar');
    await pump(
      tester,
      locale: 'ar',
      initial: const OpeningHours(
        weekly: [WeeklyWindow(dow: 6, open: '09:30', close: '23:15')],
      ),
    );
    expect(find.text(ar.storefrontHoursSaturday), findsOneWidget);
    expect(
      Directionality.of(
        tester.element(find.byKey(const Key('storefront-hours-day-6'))),
      ),
      TextDirection.rtl,
    );
    final time = tester.widget<Text>(find.text('09:30'));
    expect(time.textDirection, TextDirection.ltr);
  });
}
