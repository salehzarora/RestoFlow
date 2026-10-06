import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
    this.onLocalUnpair,
    this.onRecovered,
    this.staffOnlyRepair = false,
    this.isWeb = kIsWeb,
    super.key,
  });
  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext> onRestored;
  final Widget Function(GlobalKey<NavigatorState>, TransitionBuilder) buildApp;
  final VoidCallback? onLocalUnpair;
  final VoidCallback? onRecovered;
  final bool staffOnlyRepair;
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
        if (!mounted) return;
        setState(() => _navigatorKey = GlobalKey<NavigatorState>());
        widget.onInvalidSession();
      },
      onRestored: widget.onRestored,
      onRecovered: widget.onRecovered,
      staffOnlyRepair: widget.staffOnlyRepair,
      onLocalUnpair: () {
        if (!mounted) return;
        final message = AppLocalizations.of(context).deviceUnpairedSnack;
        setState(() => _navigatorKey = GlobalKey<NavigatorState>());
        widget.onLocalUnpair?.call();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final navigatorContext = _navigatorKey.currentContext;
          if (navigatorContext != null) {
            ScaffoldMessenger.maybeOf(
              navigatorContext,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
        });
      },
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
    this.onLocalUnpair,
    this.onRecovered,
    this.staffOnlyRepair = false,
    this.isWeb = kIsWeb,
    required this.child,
    super.key,
  });

  final DeviceSessionHeartbeatManager? manager;
  final VoidCallback onInvalidSession;
  final ValueChanged<DeviceContext>? onRestored;
  final GlobalKey<NavigatorState>? navigatorKey;
  final VoidCallback? onLocalUnpair;
  final VoidCallback? onRecovered;
  final bool staffOnlyRepair;
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
  // Offline changes the displayed verdict, but does not discharge a cold
  // restore's obligation to publish the next authoritative context to its gate.
  bool _restoreRecoveryPending = false;
  bool _blocked = false;
  bool _repairing = false;
  StreamSubscription<bool>? _blockSubscription;
  DeviceContext? _blockedContext;
  bool _scheduled = false;
  int _unavailableCount = 0;

  void _invalidate() {
    if (!mounted) return;
    _scheduler!.replaceSession(active: false);
    setState(() {
      _unavailable = false;
      _restoreUnavailable = false;
      _restoreRecoveryPending = false;
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
      recoveryRequired: () =>
          manager is DeviceSessionRecoveryManager &&
          (manager as DeviceSessionRecoveryManager).protectedCallsBlocked,
    );
    if (manager is DeviceSessionRecoveryManager) {
      final recovery = manager as DeviceSessionRecoveryManager;
      _blocked = recovery.protectedCallsBlocked;
      _blockedContext = _blocked ? manager.activeDevice : null;
      _blockSubscription = recovery.protectedCallBlockChanges.listen((blocked) {
        if (!mounted) return;
        final previous = _blocked;
        final previousContext = _blockedContext;
        setState(() => _blocked = blocked);
        if (blocked) _blockedContext = manager.activeDevice;
        _scheduler?.refreshRecoveryState();
        if (previous && !blocked && previousContext != null) {
          // Pair/unpair also change the guard. Only recovery of the SAME live
          // session resumes its existing outbox, after repository publication.
          scheduleMicrotask(() {
            if (!mounted || _blocked || _repairing) return;
            final current = manager.activeDevice;
            if (current != null &&
                current.deviceId == previousContext.deviceId &&
                current.deviceSessionId == previousContext.deviceSessionId) {
              widget.onRecovered?.call();
            }
          });
        }
      });
    }
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
          _restoreRecoveryPending = true;
          _unavailableCount = _countUnavailable();
        });
      } else {
        final active = change.context != null;
        // Re-publication during restore is not another scheduling transition.
        // In particular an old server must not create an unsupported/restore loop.
        if (active != _scheduled) {
          _scheduled = active;
          _scheduler!.replaceSession(active: active);
        }
        if (active && !_blocked && _unavailable) {
          setState(() {
            _unavailable = false;
            _restoreUnavailable = false;
            _unavailableCount = 0;
          });
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
    _blockSubscription?.cancel();
    _scheduler?.dispose();
    _unavailable = false;
    _restoreUnavailable = false;
    _restoreRecoveryPending = false;
    _blocked = false;
    _blockedContext = null;
    _scheduled = false;
    _unavailableCount = 0;
    _connect();
  }

  void _onResult(DeviceHeartbeatResult result) {
    if (!mounted) return;
    switch (result) {
      case DeviceHeartbeatResult.active:
        final restore = _restoreRecoveryPending;
        setState(() {
          _unavailable = false;
          _restoreUnavailable = false;
          _restoreRecoveryPending = false;
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
          _restoreUnavailable = false;
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
    _blockSubscription?.cancel();
    _scheduler?.dispose();
    super.dispose();
  }

  void _localUnpair() {
    if (!mounted) return;
    _scheduler?.replaceSession(active: false);
    setState(() {
      _scheduled = false;
      _unavailable = false;
      _restoreUnavailable = false;
      _restoreRecoveryPending = false;
      _unavailableCount = 0;
      _repairing = false;
    });
    widget.onLocalUnpair?.call();
  }

  @override
  Widget build(BuildContext context) => _RecoveryProgress(
    count: _unavailableCount,
    onLocalUnpair: _localUnpair,
    child: Column(
      children: [
        // Own layout space above the navigator: no cart, checkout, or kitchen
        // control can be obscured by the retry notice, including on a phone.
        if ((_unavailable || _restoreUnavailable || _blocked || _repairing) &&
            (widget.manager?.activeDevice != null || _repairing))
          SafeArea(
            bottom: false,
            child: DeviceSessionUnavailableView(
              compact: true,
              staffOnlyRepair: widget.staffOnlyRepair,
              onRetry: _retry,
              repairManager: widget.manager is DeviceSessionLocalRepairManager
                  ? widget.manager as DeviceSessionLocalRepairManager
                  : null,
              onRepairState: (repairing) {
                if (mounted) setState(() => _repairing = repairing);
              },
              dialogContext: () =>
                  widget.navigatorKey?.currentContext ?? context,
            ),
          ),
        Expanded(
          key: const ValueKey('device-session-navigator'),
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: constraints.biggest),
              child: widget.child,
            ),
          ),
        ),
      ],
    ),
  );
}

// The mounted cold-start gate also observes automatic heartbeat verdicts.
// Rebuilding this value leaves the navigator and cart state intact.
class _RecoveryProgress extends InheritedWidget {
  const _RecoveryProgress({
    required this.count,
    required this.onLocalUnpair,
    required super.child,
  });
  final int count;
  final VoidCallback onLocalUnpair;
  @override
  bool updateShouldNotify(_RecoveryProgress oldWidget) =>
      count != oldWidget.count;
}

/// Retryable unknown state. Kiosk local repair is revealed only to staff by a
/// deliberate five-second title hold; the customer never sees it by default.
class DeviceSessionUnavailableView extends StatefulWidget {
  const DeviceSessionUnavailableView({
    required this.onRetry,
    this.compact = false,
    this.staffOnlyRepair = false,
    this.repairManager,
    this.onRepaired,
    this.onRepairState,
    this.dialogContext,
    super.key,
  });
  final VoidCallback onRetry;
  final bool compact;
  final bool staffOnlyRepair;
  final DeviceSessionLocalRepairManager? repairManager;
  final VoidCallback? onRepaired;
  final ValueChanged<bool>? onRepairState;
  final BuildContext Function()? dialogContext;

  @override
  State<DeviceSessionUnavailableView> createState() => _UnavailableViewState();
}

class _UnavailableViewState extends State<DeviceSessionUnavailableView> {
  bool _staffRevealed = false;
  bool _confirming = false;
  bool _repairing = false;
  bool _repairFailed = false;

  Future<void> _repair() async {
    final manager = widget.repairManager;
    if (manager == null ||
        manager.consecutiveUnavailable < 3 ||
        _repairing ||
        _confirming)
      return;
    final l10n = AppLocalizations.of(context);
    final rootRepair = context
        .getInheritedWidgetOfExactType<_RecoveryProgress>()
        ?.onLocalUnpair;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: widget.dialogContext?.call() ?? context,
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
    if (mounted) setState(() => _confirming = false);
    // A heartbeat can recover the device while the confirmation is open.
    if (!mounted ||
        confirmed != true ||
        !identical(manager, widget.repairManager) ||
        manager.consecutiveUnavailable < 3)
      return;
    setState(() {
      _repairing = true;
      _repairFailed = false;
    });
    widget.onRepairState?.call(true);
    try {
      await manager.clearLocalPairing();
      if (!mounted) return;
      widget.onRepaired?.call();
      rootRepair?.call();
    } catch (_) {
      if (mounted) setState(() => _repairFailed = true);
    } finally {
      if (mounted) {
        setState(() => _repairing = false);
        widget.onRepairState?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = context
        .dependOnInheritedWidgetOfExactType<_RecoveryProgress>();
    final count =
        progress?.count ?? widget.repairManager?.consecutiveUnavailable ?? 0;
    final canRepair =
        widget.repairManager != null &&
        count >= 3 &&
        (!widget.staffOnlyRepair || _staffRevealed);
    final title = RawGestureDetector(
      key: const Key('device-session-unavailable-title'),
      gestures: widget.staffOnlyRepair
          ? {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(seconds: 5),
                    ),
                    (instance) => instance.onLongPress = () {
                      if (mounted) setState(() => _staffRevealed = true);
                    },
                  ),
            }
          : const {},
      child: Text(
        l10n.pinLoginUnavailable,
        maxLines: widget.compact ? 2 : null,
        overflow: widget.compact ? TextOverflow.ellipsis : null,
        textAlign: widget.compact ? TextAlign.start : TextAlign.center,
      ),
    );
    final retry = widget.compact
        ? IconButton(
            key: const Key('device-session-retry'),
            onPressed: _repairing ? null : widget.onRetry,
            icon: Icon(Icons.refresh, semanticLabel: l10n.authTryAgain),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          )
        : FilledButton(
            key: const Key('device-session-retry'),
            onPressed: _repairing ? null : widget.onRetry,
            child: Text(l10n.authTryAgain),
          );
    final repair = widget.compact
        ? IconButton(
            key: const Key('device-session-repair'),
            onPressed: _repairing || _confirming ? null : _repair,
            icon: Icon(Icons.link_off, semanticLabel: l10n.deviceUnpairAction),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          )
        : TextButton(
            key: const Key('device-session-repair'),
            onPressed: _repairing || _confirming ? null : _repair,
            child: Text(l10n.deviceUnpairAction),
          );
    final contents = Padding(
      padding: EdgeInsets.all(widget.compact ? 8 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.compact)
            Row(
              children: [
                Expanded(child: title),
                retry,
                if (canRepair) repair,
              ],
            )
          else ...[
            title,
            const SizedBox(height: 24),
            retry,
            if (canRepair) repair,
          ],
          if (_repairFailed)
            Text(
              l10n.pinLoginUnavailable,
              key: const Key('device-session-repair-error'),
            ),
        ],
      ),
    );
    return widget.compact
        ? Material(elevation: 2, child: contents)
        : Scaffold(body: Center(child: contents));
  }
}
