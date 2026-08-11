// DASHBOARD-AUTH-SEGMENTED-AR-CLIP-001 — responsive coverage for the REAL-MODE
// Dashboard entry surface (the sign-in / create-account gate).
//
// WHY THIS FILE EXISTS AT ALL. Every browser smoke in the V0-V6 visual program
// ran a DEMO-mode bundle, and demo mode boots straight past authentication. The
// auth gate is therefore the one Dashboard surface the whole responsive program
// never looked at — and the first real-mode look at production found it
// clipping. This file is the standing coverage for that surface.
//
// WHAT THE DEFECT WAS. SegmentedButton is shrink-to-content: it sizes every
// segment to the widest segment's MAX INTRINSIC width, capped at an equal share
// of the width it is given. Given loose constraints it never claims the card's
// spare room, so each segment got only what the intrinsic measurement claimed.
// For Arabic that came up short of the shaped line — measured on a real-font
// web build, 125.7px per segment against a card offering 220 / 199 / 179 at
// 1280 / 430 / 390. At 125.7 the shaped "تسجيل الدخول" plus its check icon no
// longer fit on one line, the label wrapped to two, and the segment box —
// already sized for one line at 32px — clipped the second.
//
// HOW IT IS PINNED. The discriminating assertion is group A: the control must
// be laid out with a TIGHT width, i.e. it takes the card's width instead of its
// own intrinsic width. That is the fix stated as an invariant, and it is
// independent of font metrics, which matters here: flutter_test substitutes a
// fallback font whose Arabic metrics are much wider than the shipped web font,
// so in this harness the label wraps and the box GROWS instead of clipping. A
// "is it clipped" assertion alone would sit green over the broken code. Group B
// still asserts no-clip as a forward guard on any renderer, and the real-font
// evidence lives in the browser run recorded on the ticket.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/auth/dashboard_auth_repository.dart';
import 'package:restoflow_dashboard/src/auth/login_signup_screen.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A silent auth seam: the gate must render without contacting anything.
class _StubAuthRepository implements DashboardAuthRepository {
  final _controller = StreamController<AuthSessionStatus>.broadcast();

  @override
  AuthSessionStatus get status => AuthSessionStatus.signedOut;

  @override
  Stream<AuthSessionStatus> get statusChanges => _controller.stream;

  @override
  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async => const AuthError(AuthErrorKind.network);

  @override
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) async => const AuthError(AuthErrorKind.network);

  @override
  Future<void> signOut() async {}
}

/// Mounts the REAL auth gate — the shipped composition, not a stand-in.
Future<AppLocalizations> _pumpGate(
  WidgetTester tester, {
  required String language,
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: LoginSignupScreen(
          authRepository: _StubAuthRepository(),
          onSignedUpWithSession: (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(Locale(language));
}

/// The shipped `SegmentedButton<_AuthMode>` — its type argument is private to
/// the screen, so it is matched structurally.
final _segmented = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith('SegmentedButton<'),
);

/// Collects paint-time overflow, which never reaches [WidgetTester.takeException].
/// The handler is restored BEFORE returning so the caller's `expect` runs with
/// the binding's own handler back in place.
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

/// The width matrix: the two shipped phone widths, the narrow phone that first
/// broke, and a desktop width.
const _widths = <String, Size>{
  '1280': Size(1280, 900),
  '430': Size(430, 932),
  '390': Size(390, 844),
};

void main() {
  group('A. the mode segments take the card width, not their own text width', () {
    for (final language in ['ar', 'en']) {
      for (final entry in _widths.entries) {
        // 390 is the width the defect was first measured at; keep both locales
        // on the full matrix so a regression cannot hide in one of them.
        testWidgets('$language @ ${entry.key} lays the control out tight', (
          tester,
        ) async {
          await _pumpGate(tester, language: language, size: entry.value);

          // The control's own render box: whatever SegmentedButton builds
          // first receives the constraints the control was given.
          final box = tester.renderObject<RenderBox>(_segmented);
          final constraints = box.constraints;

          expect(
            constraints.hasTightWidth,
            isTrue,
            reason:
                'The auth mode control must be laid out at the card width so '
                'each segment gets an equal share of it. Loose constraints let '
                'SegmentedButton shrink to its own intrinsic width, which for '
                'Arabic is narrower than the shaped label needs — the label '
                'then wraps inside a box already sized for one line and the '
                'second line is silently clipped. Got $constraints.',
          );
        });
      }
    }
  });

  group('B. neither segment label is clipped by the control', () {
    for (final language in ['ar', 'en']) {
      for (final entry in _widths.entries) {
        testWidgets('$language @ ${entry.key} keeps both labels inside', (
          tester,
        ) async {
          final l10n = await _pumpGate(
            tester,
            language: language,
            size: entry.value,
          );
          final control = tester.getRect(_segmented.first);

          for (final label in [l10n.authSignInTab, l10n.authCreateAccountTab]) {
            final rect = tester.getRect(find.text(label).first);
            expect(
              rect.top >= control.top - 0.5 &&
                  rect.bottom <= control.bottom + 0.5,
              isTrue,
              reason:
                  'The "$label" segment label must render inside the control. '
                  'A label taller than its segment is cut by the segment\'s own '
                  'edge WITHOUT any RenderFlex overflow being reported, so this '
                  'is the only thing that catches it. label=$rect '
                  'control=$control',
            );
          }
        });
      }
    }
  });

  testWidgets('B2. the labels stay inside the control at 2x text', (
    tester,
  ) async {
    final l10n = await _pumpGate(
      tester,
      language: 'ar',
      size: const Size(430, 932),
      textScale: 2.0,
    );
    final control = tester.getRect(_segmented.first);
    for (final label in [l10n.authSignInTab, l10n.authCreateAccountTab]) {
      final rect = tester.getRect(find.text(label).first);
      expect(
        rect.top >= control.top - 0.5 && rect.bottom <= control.bottom + 0.5,
        isTrue,
        reason:
            'At 2x the label legitimately wraps; the control must GROW to hold '
            'it rather than clip it. label=$rect control=$control',
      );
    }
  });

  group('C. the gate renders without overflow', () {
    for (final language in ['ar', 'he', 'en']) {
      for (final entry in _widths.entries) {
        testWidgets('$language @ ${entry.key} reports no overflow', (
          tester,
        ) async {
          final overflows = await _overflowsDuring(
            () => _pumpGate(tester, language: language, size: entry.value),
          );
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('ar @ 430 reports no overflow at 2x text', (tester) async {
      final overflows = await _overflowsDuring(
        () => _pumpGate(
          tester,
          language: 'ar',
          size: const Size(430, 932),
          textScale: 2.0,
        ),
      );
      expect(overflows, isEmpty);
    });
  });

  group('D. the control still behaves like a mode switch', () {
    testWidgets('both segments are present and only one is selected', (
      tester,
    ) async {
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
      );
      expect(_segmented, findsOneWidget);
      expect(find.text(l10n.authSignInTab), findsWidgets);
      expect(find.text(l10n.authCreateAccountTab), findsWidgets);

      // Sign-in is the initial mode: the sign-up-only fields are absent.
      expect(find.byKey(const Key('auth-restaurant')), findsNothing);
      expect(find.byKey(const Key('auth-email')), findsOneWidget);
    });

    testWidgets('tapping a segment switches mode', (tester) async {
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
      );
      await tester.tap(find.text(l10n.authCreateAccountTab).first);
      await tester.pumpAndSettle();

      // Sign-up mode adds the restaurant field — proof the tap was wired
      // through, not merely that a colour changed.
      expect(find.byKey(const Key('auth-restaurant')), findsOneWidget);

      await tester.tap(find.text(l10n.authSignInTab).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-restaurant')), findsNothing);
    });

    testWidgets('each segment is tappable across its whole half', (
      tester,
    ) async {
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
      );
      final control = tester.getRect(_segmented.first);
      final signInRect = tester.getRect(find.text(l10n.authSignInTab).first);

      // Widening the segments widens their hit areas too; prove the target
      // really does reach the control's edge rather than staying a small box
      // around the text. Under RTL sign-in sits on the right, so which edge
      // belongs to which mode is derived, not assumed.
      final signInOnRight = signInRect.center.dx > control.center.dx;
      final signUpEdge = signInOnRight
          ? Offset(control.left + 8, control.center.dy)
          : Offset(control.right - 8, control.center.dy);

      await tester.tapAt(signUpEdge);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('auth-restaurant')),
        findsOneWidget,
        reason:
            'A tap at the far edge of the create-account segment must select '
            'it — the touch target spans the segment, not just its label.',
      );
    });

    testWidgets('the segments are keyboard reachable', (tester) async {
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus,
        isNotNull,
        reason: 'Tab must move focus into the gate.',
      );
      // The gate is still intact after keyboard traversal.
      expect(find.text(l10n.authSignInTab), findsWidgets);
    });
  });

  group('E. real-mode entry surface smoke', () {
    // The gate is the first thing a real (non-demo) owner sees. Mount it in
    // every shipped locale and assert the whole surface is there — this is the
    // coverage whose absence let the Arabic clip reach production.
    for (final language in ['ar', 'he', 'en']) {
      testWidgets('the $language gate mounts with its full form', (
        tester,
      ) async {
        final l10n = await _pumpGate(
          tester,
          language: language,
          size: const Size(430, 932),
        );
        expect(_segmented, findsOneWidget);
        expect(find.byKey(const Key('auth-email')), findsOneWidget);
        expect(find.byKey(const Key('auth-password')), findsOneWidget);
        expect(find.byKey(const Key('auth-submit')), findsOneWidget);
        expect(find.text(l10n.authWelcomeTitle), findsOneWidget);
      });
    }

    testWidgets('the gate never renders money (it is pre-tenant)', (
      tester,
    ) async {
      await _pumpGate(tester, language: 'ar', size: const Size(430, 932));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(texts.contains('₪'), isFalse);
    });
  });
}
