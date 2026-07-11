import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/admin/timezone_catalog.dart';
import 'package:restoflow_dashboard/src/admin/timezone_picker.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// TIMEZONE-GLOBAL-001 — the searchable global timezone picker: shows the
/// current zone, opens a searchable dialog over the full catalog, selects a
/// canonical IANA id, supports "leave unchanged", and is RTL-safe.
Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

const _options = [
  TimezoneOption(id: 'Asia/Jerusalem', offsetMinutes: 180),
  TimezoneOption(id: 'Asia/Gaza', offsetMinutes: 180),
  TimezoneOption(id: 'Asia/Hebron', offsetMinutes: 180),
  TimezoneOption(id: 'Europe/London', offsetMinutes: 60),
  TimezoneOption(id: 'America/New_York', offsetMinutes: -240),
  TimezoneOption(id: 'Asia/Tokyo', offsetMinutes: 540),
];

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: restoflowLocalizationsDelegates,
  supportedLocales: kSupportedLocales,
  home: Scaffold(body: child),
);

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('P1 shows the current branch timezone as a friendly label', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: 'Asia/Jerusalem',
          selected: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Israel — Jerusalem'), findsOneWidget);
    expect(find.text('Asia/Jerusalem'), findsWidgets); // id shown as subtitle
  });

  testWidgets('P2 shows "Not set" when there is no current or selected zone', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: null,
          selected: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.timezonePickerNotSet), findsOneWidget);
  });

  testWidgets('P3 opening the field lists the global catalog options', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: null,
          selected: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timezone-picker-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('timezone-option-Asia/Jerusalem')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('timezone-option-Europe/London')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('timezone-option-Asia/Tokyo')), findsOneWidget);
    // "leave unchanged" is offered.
    expect(find.byKey(const Key('timezone-leave-unchanged')), findsOneWidget);
  });

  testWidgets('P4 searching filters the catalog by city', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: null,
          selected: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('timezone-search')), 'tokyo');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timezone-option-Asia/Tokyo')), findsOneWidget);
    expect(
      find.byKey(const Key('timezone-option-Europe/London')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('timezone-option-Asia/Jerusalem')),
      findsNothing,
    );
  });

  testWidgets('P5 selecting a zone reports its canonical IANA id', (
    tester,
  ) async {
    _wide(tester);
    final l10n = await _en();
    String? picked = 'UNSET';
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: null,
          selected: null,
          onChanged: (v) => picked = v,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timezone-option-Asia/Jerusalem')));
    await tester.pumpAndSettle();
    expect(picked, 'Asia/Jerusalem');
    expect(find.byKey(const Key('timezone-picker-dialog')), findsNothing);
  });

  testWidgets('P6 "leave unchanged" reports null', (tester) async {
    _wide(tester);
    final l10n = await _en();
    String? picked = 'UNSET';
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: 'Asia/Jerusalem',
          selected: null,
          onChanged: (v) => picked = v,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timezone-leave-unchanged')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('P7 a no-match search shows the empty state', (tester) async {
    _wide(tester);
    final l10n = await _en();
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: l10n,
          options: _options,
          currentTimezone: null,
          selected: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('timezone-search')),
      'zzzznowhere',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timezone-no-results')), findsOneWidget);
  });

  testWidgets('P8 RTL (Arabic) renders the dialog right-to-left', (
    tester,
  ) async {
    _wide(tester);
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    await tester.pumpWidget(
      _wrap(
        TimezonePickerField(
          l10n: ar,
          options: _options,
          currentTimezone: 'Asia/Jerusalem',
          selected: null,
          onChanged: (_) {},
        ),
        locale: const Locale('ar'),
      ),
    );
    await tester.pumpAndSettle();
    // Arabic curated label on the field.
    expect(find.text('إسرائيل — القدس'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-branch-timezone')));
    await tester.pumpAndSettle();
    final dir = Directionality.of(
      tester.element(find.byKey(const Key('timezone-picker-dialog'))),
    );
    expect(dir, TextDirection.rtl);
    expect(find.text(ar.timezonePickerSearchHint), findsOneWidget);
  });
}
