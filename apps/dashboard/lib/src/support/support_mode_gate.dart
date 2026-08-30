/// ADMIN-126B — the support-mode entry gate and its permanent banner.
///
/// When a live support session exists, this short-circuits the ordinary
/// membership gate: a platform operator holds NO membership, so
/// `resolveAuthGateState` would (correctly) send them to onboarding. Instead
/// the Dashboard is handed a SYNTHESIZED scope for the tenant being supported,
/// and every read then flows through the ordinary code path.
///
/// The synthesized scope is a CLIENT-SIDE CONVENIENCE AND NOTHING MORE. It is
/// never sent anywhere and grants nothing: the server decides what a support
/// session may read (fifteen named RPCs) and refuses every write regardless of
/// what this object claims. If a future change made the client lie here, the
/// server would still say no — which is the property that makes support mode
/// safe rather than merely tidy.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'platform_support.dart';
import 'support_mode_scope.dart';

/// The scope handed to the Dashboard while supporting [session].
///
/// `org_owner` is chosen because the Dashboard uses the role only to decide
/// which SURFACES to offer; the server, which decides what may actually be
/// read or written, never sees this value.
MembershipContext supportMembershipFor(PlatformSupportSession session) =>
    MembershipContext(
      id: 'support:${session.id}',
      organizationId: session.organizationId,
      organizationName: session.organizationName,
      restaurantId: session.restaurantId,
      restaurantName: session.restaurantName,
      branchId: null,
      branchName: null,
      role: MembershipRole.orgOwner,
      status: 'active',
    );

/// Resolves support mode once at boot, then keeps it honest.
class SupportModeGate extends StatefulWidget {
  const SupportModeGate({
    required this.repository,
    required this.handoffToken,
    required this.onSupport,
    required this.child,
    this.clock,
    super.key,
  });

  final PlatformSupportRepository repository;

  /// The one-time handoff taken from the launch URL, if any. Already stripped
  /// from the address bar by the caller.
  final String? handoffToken;

  /// Builds the Dashboard for a live support session.
  final Widget Function(BuildContext context, PlatformSupportSession session)
  onSupport;

  /// The ordinary tenant Dashboard, used whenever no support session is live.
  /// This is the common case and it is completely unchanged.
  final Widget child;

  /// Injectable for tests; production uses the wall clock.
  final DateTime Function()? clock;

  @override
  State<SupportModeGate> createState() => _SupportModeGateState();
}

class _SupportModeGateState extends State<SupportModeGate> {
  late Future<PlatformSupportSession?> _future;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<PlatformSupportSession?> _resolve() async {
    final token = widget.handoffToken;
    if (token != null && token.isNotEmpty) {
      // Spend the handoff. Whether it succeeds or not, we then ask the server
      // what is actually live — the exchange response is a courtesy, the status
      // read is the truth.
      await widget.repository.exchange(token);
    }
    return widget.repository.current();
  }

  Future<void> _end() async {
    await widget.repository.end();
    if (!mounted) return;
    setState(() => _ended = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ended) return const SupportSessionClosedView();
    return FutureBuilder<PlatformSupportSession?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Only ever brief, and only when a handoff is being spent.
          return widget.handoffToken == null
              ? widget.child
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        final session = snapshot.data;
        if (session == null) {
          // No live session: the ordinary tenant Dashboard, untouched. A
          // platform operator who lands here with a dead handoff sees exactly
          // what any member-less account sees.
          return widget.handoffToken == null
              ? widget.child
              : const SupportSessionClosedView();
        }
        return SupportModeScaffold(
          session: session,
          clock: widget.clock,
          onEnd: _end,
          child: widget.onSupport(context, session),
        );
      },
    );
  }
}

/// Wraps the Dashboard in a banner that cannot be scrolled away from.
///
/// The banner is deliberately fixed above the content rather than placed inside
/// it: someone glancing at this screen — including the restaurant's own staff,
/// standing behind the operator — must be able to tell at any moment that they
/// are not looking at their own session.
class SupportModeScaffold extends StatefulWidget {
  const SupportModeScaffold({
    required this.session,
    required this.onEnd,
    required this.child,
    this.clock,
    super.key,
  });

  final PlatformSupportSession session;
  final Future<void> Function() onEnd;
  final Widget child;
  final DateTime Function()? clock;

  @override
  State<SupportModeScaffold> createState() => _SupportModeScaffoldState();
}

class _SupportModeScaffoldState extends State<SupportModeScaffold> {
  bool _expired = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _expired = widget.session.remaining(_now) == Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    // This build runs ONCE per session, not once per second. The countdown owns
    // its own ticker inside [_SupportBanner]; if the seconds were held here,
    // every tick would mark the element holding the whole Dashboard dirty —
    // the exact shape of the one-second whole-shell rebuild that PERF-110 had
    // to hunt down in the kiosk.
    return Directionality(
      textDirection: Directionality.of(context),
      child: Column(
        children: [
          _SupportBanner(
            session: widget.session,
            clock: widget.clock,
            onEnd: widget.onEnd,
            onExpired: () {
              if (mounted && !_expired) setState(() => _expired = true);
            },
          ),
          // Once the clock runs out the content below is stale by definition —
          // every server read is already failing — so it is replaced rather
          // than left on screen looking live.
          Expanded(
            child: _expired
                ? const SupportSessionClosedView()
                // The marker the shell reads to drop the surfaces this session
                // cannot read anyway. Presentation only — see the scope's own
                // doc comment.
                : SupportModeScope(active: true, child: widget.child),
          ),
        ],
      ),
    );
  }
}

/// The banner itself, and the only thing that repaints each second.
class _SupportBanner extends StatefulWidget {
  const _SupportBanner({
    required this.session,
    required this.onEnd,
    required this.onExpired,
    this.clock,
  });

  final PlatformSupportSession session;
  final Future<void> Function() onEnd;
  final VoidCallback onExpired;
  final DateTime Function()? clock;

  @override
  State<_SupportBanner> createState() => _SupportBannerState();
}

class _SupportBannerState extends State<_SupportBanner> {
  Timer? _tick;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    if (widget.session.remaining(_now) == Duration.zero) return;
    // A countdown only; expiry itself is re-checked by the server on every
    // read, so a stopped timer cannot extend anyone's access by a second.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (widget.session.remaining(_now) == Duration.zero) {
        _tick?.cancel();
        widget.onExpired();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final left = widget.session.remaining(_now);
    final expired = left == Duration.zero;

    return Material(
      color: expired
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.lg,
            vertical: RestoflowSpacing.sm,
          ),
          // A Wrap hands its children UNBOUNDED width, so every text here is
          // given the banner's own width to wrap inside. Without that, a long
          // label (or a long tenant name, which is tenant data and can be
          // anything) runs off the edge on a phone instead of taking a second
          // line.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              Widget bounded(Widget child) => ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              );
              return Wrap(
                spacing: RestoflowSpacing.md,
                runSpacing: RestoflowSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  bounded(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.support_agent,
                          size: RestoflowIconSizes.md,
                        ),
                        const SizedBox(width: RestoflowSpacing.sm),
                        Flexible(
                          child: Text(
                            l10n.supportModeBanner,
                            key: const Key('support-mode-banner'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  bounded(
                    Text(
                      widget.session.targetLabel,
                      key: const Key('support-mode-target'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  bounded(
                    Text(
                      expired
                          ? l10n.supportModeExpired
                          : l10n.supportModeExpiresIn(_mmss(left)),
                      key: const Key('support-mode-expiry'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  bounded(
                    TextButton.icon(
                      key: const Key('support-mode-end'),
                      onPressed: () => unawaited(widget.onEnd()),
                      icon: const Icon(
                        Icons.logout,
                        size: RestoflowIconSizes.sm,
                      ),
                      label: Text(l10n.supportModeEnd),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The safe screen for an ended, expired or never-valid support session.
///
/// It offers no retry: a spent handoff cannot be spent again, and pretending
/// otherwise would send the operator round a loop. The way back is a new
/// session from the platform console.
class SupportSessionClosedView extends StatelessWidget {
  const SupportSessionClosedView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: RestoflowStateView(
          key: const Key('support-session-closed'),
          icon: Icons.lock_clock,
          tone: RestoflowTone.neutral,
          title: l10n.supportModeClosedTitle,
          message: l10n.supportModeClosedBody,
        ),
      ),
    );
  }
}
