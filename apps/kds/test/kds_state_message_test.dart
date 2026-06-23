import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_kds/main.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// RF-102: the loading/error/reauth states keep their icons/spinner AND now show
/// a localized message. Driven with a fake sync source (no Supabase/session).
class _FakeKdsSyncSource implements KdsSyncSource {
  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();
  KdsSyncState _state = KdsSyncState.initial;

  void emit(KdsSyncState s) {
    _state = s;
    _controller.add(s);
  }

  @override
  KdsSyncState get state => _state;

  @override
  Stream<KdsSyncState> get states => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

void main() {
  testWidgets(
    'reauthRequired keeps the lock icon and adds a localized message',
    (tester) async {
      final source = _FakeKdsSyncSource();
      addTearDown(source.dispose);

      await tester.pumpWidget(KdsApp(source: source));
      await tester.pump();
      source.emit(const KdsSyncState(status: KdsSyncStatus.reauthRequired));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Sign-in required'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('error keeps the error icon and adds a localized message', (
    tester,
  ) async {
    final source = _FakeKdsSyncSource();
    addTearDown(source.dispose);

    await tester.pumpWidget(KdsApp(source: source));
    await tester.pump();
    source.emit(const KdsSyncState(status: KdsSyncStatus.error));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text("Couldn't load tickets"), findsOneWidget);
  });
}
