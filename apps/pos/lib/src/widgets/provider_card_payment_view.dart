/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the card attempt view inside the payment
/// sheet (execution packet §7).
///
/// It shows ONE attempt as the controller knows it — the state as a title, a
/// body and an icon (never colour alone) in a live region — and offers only the
/// next safe actions of that state. While it is visible and the app is in the
/// foreground it holds a lease on automatic status checks; disposing it,
/// covering its route or pausing the app releases the lease and stops the
/// timer (the journal keeps the attempt). "Paid" is never shown before the
/// authoritative recording.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/provider_card_attempt.dart';
import '../format/money_format.dart';
import '../format/provider_card_presentation.dart';
import '../state/provider_card_controller.dart';

class ProviderCardPaymentView extends ConsumerStatefulWidget {
  const ProviderCardPaymentView({
    required this.attemptId,
    required this.onTakeAnotherWay,
    required this.onRecorded,
    required this.onDone,
    required this.onClose,
    super.key,
  });

  final String attemptId;

  /// Leave the card view for the tender form (only offered where no charge can
  /// exist).
  final VoidCallback onTakeAnotherWay;

  /// Called ONCE per view when the attempt is recorded; [armed] is true only
  /// when this device's own recording reply reserved the one automatic receipt.
  final void Function(bool armed) onRecorded;

  /// The one authoritative success edge (recorded).
  final VoidCallback onDone;

  /// Close the sheet; the attempt is kept.
  final VoidCallback onClose;

  @override
  ConsumerState<ProviderCardPaymentView> createState() =>
      _ProviderCardPaymentViewState();
}

class _ProviderCardPaymentViewState
    extends ConsumerState<ProviderCardPaymentView>
    with WidgetsBindingObserver {
  ProviderCardLease? _lease;
  bool _routeCurrent = true;
  bool _recordedHandled = false;
  bool _receiptUnknown = false;

  ProviderCardController get _controller =>
      ref.read(providerCardControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Automatic checks run only while this view is visible: its route on top
    // and the app in the foreground (packet §10). Attaching touches controller
    // state, which a build may not do: after the frame.
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLease());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncLease();

  /// Holds the lease exactly while this view is visible.
  void _syncLease() {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (foreground && _routeCurrent) {
      _lease ??= _controller.attachForeground(widget.attemptId);
    } else {
      _lease?.release();
      _lease = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lease?.release();
    _lease = null;
    super.dispose();
  }

  /// Runs once per view, after the frame: consuming the receipt reservation
  /// changes controller state, which a build may not do.
  void _handleRecorded() {
    if (_recordedHandled) return;
    _recordedHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final armed = _controller.consumeReceipt(widget.attemptId);
      setState(() => _receiptUnknown = !armed);
      widget.onRecorded(armed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(providerCardControllerProvider);
    final a = state.byId(widget.attemptId);
    if (a == null) return const SizedBox.shrink();
    final phase = a.phase;
    if (phase == ProviderCardPhase.recorded) _handleRecorded();
    final busy = state.busy[a.attemptId];
    final note = state.notes[a.attemptId];
    final idle = busy == null;
    final preparing = providerCardPreparing(a, busy);
    final shown = preparing
        ? presentProviderCardPreparing(l10n)
        : presentProviderCardAttempt(l10n, a);
    final test = a.mode == ProviderCardMode.test;
    final facts = a.server;

    Widget primary(String key, String label, IconData icon, VoidCallback act) =>
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: Key(key),
            onPressed: idle ? act : null,
            icon: Icon(icon),
            label: Text(label),
            style: RestoflowButtonStyles.big(context),
          ),
        );
    Widget secondary(
      String key,
      String label,
      IconData icon,
      VoidCallback act,
    ) => SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: Key(key),
        onPressed: idle ? act : null,
        icon: Icon(icon),
        label: Text(label),
        style: RestoflowButtonStyles.big(context),
      ),
    );
    Widget quiet(String key, String label, VoidCallback act) => SizedBox(
      width: double.infinity,
      child: TextButton(
        key: Key(key),
        onPressed: idle ? act : null,
        child: Text(label),
      ),
    );

    final check = secondary(
      'card-check-status-button',
      l10n.posPaymentCheckStatus,
      Icons.search,
      () => _controller.checkStatus(a.attemptId),
    );
    final closeLater = quiet(
      'card-close-button',
      l10n.posPaymentCloseResumeLater,
      widget.onClose,
    );
    final close = quiet('card-close-button', l10n.posCardClose, widget.onClose);
    // Leaves for the tender form: when no set-aside is needed or it was
    // stored, never hiding an attempt that is still open (packet §7.3).
    Future<void> leave() async {
      final closed = a.mayBeSetAside
          ? await _controller.setAside(a.attemptId)
          : true;
      if (mounted && (closed || !a.isOpen)) widget.onTakeAnotherWay();
    }

    final otherWay = secondary(
      'card-other-method-button',
      l10n.posCardOtherMethod,
      Icons.payments_outlined,
      leave,
    );
    final releasable =
        facts != null &&
        facts.resolution == null &&
        (facts.state == 'sent' || facts.state == 'unknown');
    final release = secondary(
      'card-release-button',
      l10n.posCardRelease,
      Icons.cancel_outlined,
      () => _controller.release(a.attemptId),
    );
    final resumable =
        facts != null &&
        facts.recoverable == true &&
        (facts.resumeCount ?? kProviderCardMaxResumes) <
            kProviderCardMaxResumes;
    final resume = primary(
      'card-resume-button',
      l10n.posCardResume,
      Icons.supervisor_account,
      () => _controller.resumeRecording(a.attemptId),
    );
    final backToPayment = secondary(
      'card-back-to-payment-button',
      l10n.posCardBackToPayment,
      Icons.arrow_back,
      leave,
    );

    final actions = <Widget>[
      // Preparing offers nothing (packet §7.1): the request is in flight.
      if (!preparing)
        ...switch (phase) {
          ProviderCardPhase.notSent => [
            primary(
              'card-send-again-button',
              l10n.posCardSendAgain,
              Icons.send,
              () => _controller.retryStart(a.attemptId),
            ),
            secondary(
              'card-cancel-request-button',
              l10n.posCardCancelRequest,
              Icons.close,
              leave,
            ),
            close,
          ],
          ProviderCardPhase.authRequired => [
            primary(
              'card-send-again-button',
              l10n.posCardSendAgain,
              Icons.send,
              () => _controller.retryStart(a.attemptId),
            ),
            otherWay,
            close,
          ],
          ProviderCardPhase.notApplied ||
          ProviderCardPhase.refused ||
          ProviderCardPhase.declined ||
          ProviderCardPhase.freed ||
          ProviderCardPhase.resolved ||
          ProviderCardPhase.closed => [otherWay, close],
          ProviderCardPhase.uncertain => [check, closeLater],
          ProviderCardPhase.notFound => [check, otherWay, closeLater],
          ProviderCardPhase.waiting => [
            check,
            if (releasable) release,
            closeLater,
          ],
          ProviderCardPhase.released => [check, closeLater],
          ProviderCardPhase.approvedRecording ||
          ProviderCardPhase.recordingUnconfirmed => [
            primary(
              'card-resend-recording-button',
              l10n.posCardResendRecording,
              Icons.sync,
              () => _controller.resendRecording(a.attemptId),
            ),
            check,
            closeLater,
          ],
          ProviderCardPhase.recordingRefused => [resume, check, closeLater],
          ProviderCardPhase.managerMustSend => [
            primary(
              'card-manager-send-button',
              l10n.posCardManagerSend,
              Icons.supervisor_account,
              () => _controller.managerSend(a.attemptId),
            ),
            check,
            closeLater,
          ],
          ProviderCardPhase.resumeRefused => [
            check,
            if (resumable) resume,
            closeLater,
          ],
          ProviderCardPhase.recorded => [
            primary(
              'card-done-button',
              l10n.posPaymentDone,
              Icons.check,
              widget.onDone,
            ),
          ],
          ProviderCardPhase.reconciliation => [check, closeLater],
          // An unresolved TEST attempt is the restricted recovery surface of
          // its order on this till: no way back to the tender form and no
          // set-aside until it is final, whatever the lab toggle (correction
          // packet §4). A cancel the provider confirmed is not final either.
          ProviderCardPhase.testWaiting => [
            check,
            if (releasable) release,
            closeLater,
          ],
          ProviderCardPhase.testReleased => [check, closeLater],
          ProviderCardPhase.testApproved ||
          ProviderCardPhase.testDeclined ||
          ProviderCardPhase.testClosed => [check, backToPayment, close],
        },
    ];

    final resumeCount = facts?.resumeCount;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          RestoflowSpacing.lg,
          0,
          RestoflowSpacing.lg,
          RestoflowSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const Key('card-attempt-view'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale, color: theme.colorScheme.primary),
                const SizedBox(width: RestoflowSpacing.sm),
                Expanded(
                  child: Text(
                    test
                        ? l10n.posCardAttemptTestTitle
                        : l10n.posCardAttemptTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (test) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              RestoflowNoticeBanner(
                key: const Key('card-test-badge'),
                tone: RestoflowTone.info,
                icon: Icons.science_outlined,
                body: l10n.posCardTestBadge,
              ),
              // D9 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-D9-SAFETY-COPY-001):
              // beside the TEST notice, on every TEST attempt, never on LIVE.
              // Its wording is conditional, so it stays true while this view
              // shows a final TEST result. It describes the existing
              // restriction and changes no action, timer or state.
              const SizedBox(height: RestoflowSpacing.xs),
              Text(
                l10n.posCardTestOrderHoldSafety,
                key: const Key('card-test-hold-safety'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.posAmountDue,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  MoneyFormatter.formatMinor(a.amountMinor, a.currencyCode),
                  key: const Key('card-attempt-amount'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RestoflowSpacing.md),
            Semantics(
              liveRegion: true,
              child: RestoflowNoticeBanner(
                key: Key(
                  preparing
                      ? 'card-state-preparing'
                      : 'card-state-${phase.name}',
                ),
                tone: shown.tone,
                icon: shown.icon,
                title: shown.title,
                body: shown.body,
              ),
            ),
            if (busy != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Row(
                key: const Key('card-busy-note'),
                children: [
                  const RestoflowInlineSpinner(),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(child: Text(providerCardBusyText(l10n, busy))),
                ],
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                providerCardNoteText(l10n, note),
                key: Key('card-note-${note.name}'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (resumeCount != null &&
                (phase == ProviderCardPhase.recordingRefused ||
                    phase == ProviderCardPhase.resumeRefused ||
                    phase == ProviderCardPhase.reconciliation)) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                l10n.posCardResumesUsed(resumeCount, kProviderCardMaxResumes),
                key: const Key('card-resumes-used'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (phase == ProviderCardPhase.recorded && _receiptUnknown) ...[
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                l10n.posPaymentReceiptUnknown,
                key: const Key('card-receipt-unknown'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: RestoflowSpacing.md),
            for (final (i, action) in actions.indexed) ...[
              if (i > 0) const SizedBox(height: RestoflowSpacing.sm),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
