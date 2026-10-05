import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Owns the Navigator's actual key. An explicit rejection replaces protected
/// routes (including dialogs); a retryable unknown state keeps them mounted.
class DeviceSessionAppHost extends StatefulWidget {
  const DeviceSessionAppHost({
    required this.manager,
    required this.onInvalidSession,
    required this.onRestored,
    required this.buildApp,
    super.key,
  });
  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext> onRestored;
  final Widget Function(GlobalKey<NavigatorState>, TransitionBuilder) buildApp;
  @override
  State<DeviceSessionAppHost> createState() => _DeviceSessionAppHostState();
}

class _DeviceSessionAppHostState extends State<DeviceSessionAppHost> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => widget.buildApp(
    _navigatorKey,
    (context, child) => DeviceSessionHeartbeatScope(
      manager: widget.manager,
      onInvalidSession: () {
        setState(() => _navigatorKey = GlobalKey<NavigatorState>());
        widget.onInvalidSession();
      },
      onRestored: widget.onRestored,
      child: child!,
    ),
  );
}

/// Lives above the app navigator (including dialogs) and the human PIN gates.
/// A paused app sends no periodic heartbeats. Resume and pairing transitions
/// request an immediate, single-flight check without extending any PIN window.
class DeviceSessionHeartbeatScope extends StatefulWidget {
  const DeviceSessionHeartbeatScope({
    required this.manager,
    required this.onInvalidSession,
    this.onRestored,
    required this.child,
    super.key,
  });

  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext>? onRestored;
  final Widget child;

  @override
  State<DeviceSessionHeartbeatScope> createState() => _HeartbeatScopeState();
}

class _HeartbeatScopeState extends State<DeviceSessionHeartbeatScope>
    with WidgetsBindingObserver {
  DeviceSessionHeartbeatScheduler? _scheduler;
  StreamSubscription<DeviceSessionChange>? _subscription;
  bool _unavailable = false;
  bool _restoreUnavailable = false;
  bool _restoreInFlight = false;
  String? _restoreType;

  void _invalidate() {
    _scheduler!.replaceSession(active: false);
    setState(() {
      _unavailable = false;
      _restoreUnavailable = false;
    });
    widget.onInvalidSession();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void _connect() {
    final manager = widget.manager;
    if (manager == null) return;
    _scheduler = DeviceSessionHeartbeatScheduler(
      heartbeat: manager.heartbeat,
      onResult: _onResult,
    );
    _subscription = manager.sessionChanges.listen((change) {
      if (!mounted) return;
      _scheduler!.replaceSession(active: change.context != null);
      if (change.invalidSession) {
        _invalidate();
      } else if (change.unavailable) {
        setState(() {
          _unavailable = true;
          _restoreUnavailable = true;
          _restoreType = change.expectedDeviceType;
        });
      } else if (change.context != null && _unavailable) {
        final wasRestoreUnavailable = _restoreUnavailable;
        setState(() {
          _unavailable = false;
          _restoreUnavailable = false;
        });
        if (wasRestoreUnavailable) widget.onRestored?.call(change.context!);
      }
    });
    _scheduler!.replaceSession(active: manager.activeDevice != null);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _scheduler!.setForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  void didUpdateWidget(DeviceSessionHeartbeatScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.manager, widget.manager)) return;
    _subscription?.cancel();
    _scheduler?.dispose();
    _unavailable = false;
    _restoreUnavailable = false;
    _connect();
  }

  void _onResult(DeviceHeartbeatResult result) {
    if (!mounted) return;
    switch (result) {
      case DeviceHeartbeatResult.active:
        if (_unavailable) setState(() => _unavailable = false);
      case DeviceHeartbeatResult.unsupported:
        // Compatibility is not new authority to reopen an unknown session.
        break;
      case DeviceHeartbeatResult.unavailable:
        if (!_unavailable) setState(() => _unavailable = true);
      case DeviceHeartbeatResult.invalidSession:
        _invalidate();
      case DeviceHeartbeatResult.offline:
      case DeviceHeartbeatResult.superseded:
        // Offline neither revokes a pairing nor overrides a prior unknown
        // verdict. POS's existing bounded offline PIN policy remains in force.
        break;
    }
  }

  Future<void> _retry() async {
    if (!_restoreUnavailable) {
      _scheduler?.request();
      return;
    }
    final Object? manager = widget.manager;
    final type = _restoreType;
    if (_restoreInFlight ||
        manager is! DeviceSessionOutcomeManager ||
        type == null)
      return;
    _restoreInFlight = true;
    try {
      final outcome = await manager.restoreOutcome(expectedDeviceType: type);
      if (mounted &&
          identical(manager, widget.manager) &&
          _restoreUnavailable &&
          outcome is DeviceSessionRestoreRejected) {
        _invalidate();
      }
    } catch (_) {
      // A failed retry proves no authority and destroys no local state.
    } finally {
      _restoreInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _scheduler?.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scheduler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Keep the cart and durable outbox composition mounted. Their shared
      // guarded transport also refuses new protected RPCs while unavailable.
      Offstage(
        offstage: _unavailable,
        child: TickerMode(enabled: !_unavailable, child: widget.child),
      ),
      if (_unavailable) DeviceSessionUnavailableView(onRetry: _retry),
    ],
  );
}

/// Retryable unknown server state; deliberately distinct from activation and
/// network-offline screens. Never exposes a raw error or session credential.
class DeviceSessionUnavailableView extends StatelessWidget {
  const DeviceSessionUnavailableView({required this.onRetry, super.key});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.pinLoginUnavailable, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('device-session-retry'),
              onPressed: onRetry,
              child: Text(l10n.authTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
