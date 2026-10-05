import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
    this.isWeb = kIsWeb,
    super.key,
  });
  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext> onRestored;
  final Widget Function(GlobalKey<NavigatorState>, TransitionBuilder) buildApp;
  final bool isWeb;
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
      navigatorKey: _navigatorKey,
      isWeb: widget.isWeb,
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
    this.navigatorKey,
    this.isWeb = kIsWeb,
    required this.child,
    super.key,
  });

  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext>? onRestored;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool isWeb;
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
  bool _scheduled = false;
  int _unavailableCount = 0;

  void _invalidate() {
    _scheduler!.replaceSession(active: false);
    setState(() {
      _unavailable = false;
      _restoreUnavailable = false;
      _unavailableCount = 0;
      _scheduled = false;
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
      if (change.invalidSession) {
        _invalidate();
      } else if (change.unavailable) {
        if (!_scheduled) {
          _scheduled = true;
          _scheduler!.replaceSession(active: true);
        }
        setState(() {
          _unavailable = true;
          _restoreUnavailable = true;
          _unavailableCount = _countUnavailable();
        });
      } else {
        _scheduled = change.context != null;
        _scheduler!.replaceSession(active: _scheduled);
        if (change.context != null && _unavailable) {
          final wasRestoreUnavailable = _restoreUnavailable;
          setState(() {
            _unavailable = false;
            _restoreUnavailable = false;
            _unavailableCount = 0;
          });
          if (wasRestoreUnavailable) widget.onRestored?.call(change.context!);
        }
      }
    });
    _scheduled = manager.activeDevice != null;
    _scheduler!.replaceSession(active: _scheduled);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _scheduler!.setForeground(_isForeground(lifecycle));
  }

  bool _isForeground(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      (widget.isWeb && state == AppLifecycleState.inactive);

  int _countUnavailable() => switch (widget.manager) {
    final DeviceSessionLocalRepairManager manager =>
      manager.consecutiveUnavailable,
    _ => _unavailableCount + 1,
  };

  @override
  void didUpdateWidget(DeviceSessionHeartbeatScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.manager, widget.manager)) return;
    _subscription?.cancel();
    _scheduler?.dispose();
    _unavailable = false;
    _restoreUnavailable = false;
    _unavailableCount = 0;
    _connect();
  }

  void _onResult(DeviceHeartbeatResult result) {
    if (!mounted) return;
    switch (result) {
      case DeviceHeartbeatResult.active:
        final restore = _restoreUnavailable;
        setState(() {
          _unavailable = false;
          _restoreUnavailable = false;
          _unavailableCount = 0;
        });
        if (restore && widget.manager?.activeDevice != null) {
          widget.onRestored?.call(widget.manager!.activeDevice!);
        }
      case DeviceHeartbeatResult.unsupported:
        // Compatibility is not new authority to reopen an unknown session.
        break;
      case DeviceHeartbeatResult.unavailable:
        setState(() {
          _unavailable = true;
          _unavailableCount = _countUnavailable();
        });
      case DeviceHeartbeatResult.invalidSession:
        _invalidate();
      case DeviceHeartbeatResult.offline:
        setState(() {
          _unavailable = false;
          _unavailableCount = 0;
        });
        break;
      case DeviceHeartbeatResult.superseded:
        break;
    }
  }

  void _retry() => _scheduler?.request();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _scheduler?.setForeground(
        _isForeground(state),
        resume: state == AppLifecycleState.resumed,
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scheduler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RecoveryProgress(
    count: _unavailableCount,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Unknown evidence never disables the navigator or bounded offline work.
        widget.child,
        if (_unavailable && widget.manager?.activeDevice != null)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: DeviceSessionUnavailableView(
                  compact: true,
                  onRetry: _retry,
                  repairManager:
                      _unavailableCount >= 3 &&
                          widget.manager is DeviceSessionLocalRepairManager
                      ? widget.manager as DeviceSessionLocalRepairManager
                      : null,
                  onRepaired: _invalidate,
                  dialogContext: () =>
                      widget.navigatorKey?.currentContext ?? context,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

// The mounted cold-start gate also observes automatic heartbeat verdicts.
// Rebuilding this inherited value leaves the navigator and cart state intact.
class _RecoveryProgress extends InheritedWidget {
  const _RecoveryProgress({required this.count, required super.child});
  final int count;
  @override
  bool updateShouldNotify(_RecoveryProgress oldWidget) =>
      count != oldWidget.count;
}

/// Retryable unknown server state; deliberately distinct from activation and
/// network-offline screens. Never exposes a raw error or session credential.
class DeviceSessionUnavailableView extends StatelessWidget {
  const DeviceSessionUnavailableView({
    required this.onRetry,
    this.compact = false,
    this.repairManager,
    this.onRepaired,
    this.dialogContext,
    super.key,
  });
  final VoidCallback onRetry;
  final bool compact;
  final DeviceSessionLocalRepairManager? repairManager;
  final VoidCallback? onRepaired;
  final BuildContext Function()? dialogContext;

  Future<void> _repair(BuildContext context) async {
    final manager = repairManager;
    if (manager == null || manager.consecutiveUnavailable < 3) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: dialogContext?.call() ?? context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deviceUnpairAction),
        content: Text(l10n.deviceUnpairWarning),
        actions: [
          TextButton(
            key: const Key('device-session-repair-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.deviceUnpairCancel),
          ),
          FilledButton(
            key: const Key('device-session-repair-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deviceUnpairConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await manager.clearLocalPairing();
    onRepaired?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = context
        .dependOnInheritedWidgetOfExactType<_RecoveryProgress>();
    final unavailableCount =
        progress?.count ?? repairManager?.consecutiveUnavailable ?? 0;
    final contents = Padding(
      padding: const EdgeInsets.all(16),
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
          if (repairManager != null && unavailableCount >= 3)
            TextButton(
              key: const Key('device-session-repair'),
              onPressed: () => _repair(context),
              child: Text(l10n.deviceUnpairAction),
            ),
        ],
      ),
    );
    return compact
        ? Material(elevation: 8, child: contents)
        : Scaffold(body: Center(child: contents));
  }
}
