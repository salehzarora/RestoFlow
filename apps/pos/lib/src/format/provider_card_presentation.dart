/// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — the localized words of the card view
/// (execution packet §7.1).
///
/// Every state is a title AND a body AND an icon, never a colour alone. No
/// provider text, reference or return code is ever shown: the server's closed
/// tokens select a localized sentence, and anything unknown falls back to the
/// generic sentence of its state.
library;

import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart'
    show RestoflowTone;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/provider_card_attempt.dart';
import '../state/provider_card_controller.dart'
    show ProviderCardBusy, ProviderCardNote;

/// One state of the card view, as shown.
@immutable
class ProviderCardPresentation {
  const ProviderCardPresentation({
    required this.title,
    required this.body,
    required this.tone,
    required this.icon,
  });

  final String title;
  final String body;
  final RestoflowTone tone;
  final IconData icon;
}

/// The view of [a]'s derived phase.
ProviderCardPresentation presentProviderCardAttempt(
  AppLocalizations l10n,
  ProviderCardAttempt a,
) {
  ProviderCardPresentation p(
    String title,
    String body,
    RestoflowTone tone,
    IconData icon,
  ) => ProviderCardPresentation(
    title: title,
    body: body,
    tone: tone,
    icon: icon,
  );
  if (a.safetyStop != null && a.phase == ProviderCardPhase.reconciliation) {
    return p(
      l10n.posCardReconcileTitle,
      l10n.posCardSafetyStopBody,
      RestoflowTone.danger,
      Icons.gpp_maybe_outlined,
    );
  }
  return switch (a.phase) {
    ProviderCardPhase.notSent => p(
      l10n.posCardNotSentTitle,
      l10n.posCardNotSentBody,
      RestoflowTone.warning,
      Icons.cloud_off_outlined,
    ),
    ProviderCardPhase.authRequired => p(
      l10n.posCardSignInTitle,
      l10n.posCardSignInBody,
      RestoflowTone.warning,
      Icons.lock_outline,
    ),
    ProviderCardPhase.notApplied => p(
      l10n.posCardNotAppliedTitle,
      l10n.posCardNotAppliedBody,
      RestoflowTone.danger,
      Icons.block,
    ),
    ProviderCardPhase.refused => p(
      l10n.posCardRefusedTitle,
      providerCardStartRefusalText(l10n, a.startRefusal),
      RestoflowTone.warning,
      Icons.block,
    ),
    ProviderCardPhase.uncertain => p(
      l10n.posCardUncertainTitle,
      l10n.posCardUncertainBody,
      RestoflowTone.warning,
      Icons.help_outline,
    ),
    ProviderCardPhase.notFound => p(
      l10n.posCardNotFoundTitle,
      l10n.posCardNotFoundBody,
      RestoflowTone.info,
      Icons.search_off,
    ),
    ProviderCardPhase.waiting => p(
      l10n.posCardWaitingTitle,
      l10n.posCardWaitingBody,
      RestoflowTone.info,
      Icons.point_of_sale,
    ),
    ProviderCardPhase.released => p(
      l10n.posCardReleasedTitle,
      l10n.posCardReleasedBody,
      RestoflowTone.warning,
      Icons.cancel_schedule_send_outlined,
    ),
    ProviderCardPhase.approvedRecording => p(
      l10n.posCardApprovedTitle,
      l10n.posCardApprovedBody,
      RestoflowTone.info,
      Icons.hourglass_top,
    ),
    ProviderCardPhase.recordingUnconfirmed => p(
      l10n.posCardRecordingUnconfirmedTitle,
      l10n.posCardRecordingUnconfirmedBody,
      RestoflowTone.warning,
      Icons.sync_problem,
    ),
    ProviderCardPhase.recordingRefused => p(
      l10n.posCardRecordingRefusedTitle,
      l10n.posCardRecordingRefusedBody,
      RestoflowTone.warning,
      Icons.supervisor_account_outlined,
    ),
    ProviderCardPhase.managerMustSend => p(
      l10n.posCardManagerMustSendTitle,
      l10n.posCardManagerMustSendBody,
      RestoflowTone.warning,
      Icons.supervisor_account_outlined,
    ),
    ProviderCardPhase.resumeRefused => p(
      l10n.posCardResumeRefusedTitle,
      switch (a.resumeDenied) {
        'resume_stale' => l10n.posCardResumeStaleBody,
        'resume_limit' => l10n.posCardResumeLimitBody,
        _ => l10n.posCardResumeRefusedBody,
      },
      RestoflowTone.warning,
      Icons.report_outlined,
    ),
    ProviderCardPhase.recorded => p(
      l10n.posCardRecordedTitle,
      l10n.posCardRecordedBody,
      RestoflowTone.success,
      Icons.check_circle_outline,
    ),
    ProviderCardPhase.declined => p(
      l10n.posCardDeclinedTitle,
      l10n.posCardDeclinedBody,
      RestoflowTone.danger,
      Icons.credit_card_off_outlined,
    ),
    ProviderCardPhase.freed => p(
      l10n.posCardFreedTitle,
      l10n.posCardFreedBody,
      RestoflowTone.info,
      Icons.lock_open_outlined,
    ),
    ProviderCardPhase.resolved => p(
      l10n.posCardResolvedTitle,
      l10n.posCardResolvedBody,
      RestoflowTone.info,
      Icons.assignment_turned_in_outlined,
    ),
    ProviderCardPhase.reconciliation => p(
      l10n.posCardReconcileTitle,
      (a.server?.resumeCount ?? 0) >= kProviderCardMaxResumes
          ? l10n.posCardResumeLimitBody
          : l10n.posCardReconcileBody,
      RestoflowTone.danger,
      Icons.gpp_maybe_outlined,
    ),
    ProviderCardPhase.testWaiting => p(
      l10n.posCardTestWaitingTitle,
      l10n.posCardTestWaitingBody,
      RestoflowTone.info,
      Icons.science_outlined,
    ),
    ProviderCardPhase.testReleased => p(
      l10n.posCardTestReleasedTitle,
      l10n.posCardTestReleasedBody,
      RestoflowTone.info,
      Icons.science_outlined,
    ),
    ProviderCardPhase.testApproved => p(
      l10n.posCardTestApprovedTitle,
      l10n.posCardTestApprovedBody,
      RestoflowTone.info,
      Icons.science_outlined,
    ),
    ProviderCardPhase.testDeclined => p(
      l10n.posCardTestDeclinedTitle,
      l10n.posCardTestDeclinedBody,
      RestoflowTone.info,
      Icons.science_outlined,
    ),
    ProviderCardPhase.testClosed => p(
      l10n.posCardTestClosedTitle,
      l10n.posCardTestClosedBody,
      RestoflowTone.info,
      Icons.science_outlined,
    ),
    ProviderCardPhase.closed => p(
      l10n.posCardRefusedTitle,
      l10n.posCardRefusedGeneric,
      RestoflowTone.neutral,
      Icons.close,
    ),
  };
}

/// Whether [a] is being started by this device right now and no earlier
/// `start` of it may have executed (the one in flight may have): the
/// "preparing" state (packet §7.1), shown instead of the derived phase while
/// that request is in flight. In memory only: after a restart the record shows
/// its own state (in doubt: Check status); after a rebuild the new controller
/// world keeps showing this until the earlier world's start ends, then shows
/// what it stored.
bool providerCardPreparing(ProviderCardAttempt a, ProviderCardBusy? busy) =>
    busy == ProviderCardBusy.starting &&
    !a.startMayHaveExecuted &&
    switch (a.phase) {
      ProviderCardPhase.notSent ||
      ProviderCardPhase.authRequired ||
      ProviderCardPhase.uncertain => true,
      _ => false,
    };

/// The words of the preparing state.
ProviderCardPresentation presentProviderCardPreparing(AppLocalizations l10n) =>
    ProviderCardPresentation(
      title: l10n.posCardPreparingTitle,
      body: l10n.posCardPreparingBody,
      tone: RestoflowTone.info,
      icon: Icons.send_outlined,
    );

/// The sentence for a closed `start` refusal (packet §6). Unknown or absent
/// tokens use the generic sentence.
String providerCardStartRefusalText(
  AppLocalizations l10n,
  ProviderCardStartRefusal? r,
) {
  if (r == null) return l10n.posCardRefusedGeneric;
  return switch ((r.error, r.detail)) {
    ('card_payments_disabled', _) => l10n.posCardRefusedDisabled,
    ('payment_in_progress', _) => l10n.posCardRefusedInProgress,
    ('order_already_settled', _) => l10n.posCardRefusedSettled,
    ('order_not_chargeable', _) => l10n.posCardRefusedNotChargeable,
    ('amount_mismatch', _) => l10n.posCardRefusedOrderChanged,
    ('conflict', null) => l10n.posCardRefusedOrderChanged,
    ('precondition_failed', 'ineligible_order_state') =>
      l10n.posCardRefusedOrderChanged,
    ('precondition_failed', 'max_live_amount_exceeded') ||
    (
      'precondition_failed',
      'max_test_amount_exceeded',
    ) => l10n.posCardRefusedLimit,
    ('precondition_failed', 'currency_not_supported') =>
      l10n.posCardRefusedCurrency,
    ('precondition_failed', 'no_open_shift') ||
    ('precondition_failed', 'no_active_drawer') => l10n.posPaymentNoOpenShift,
    ('permission_denied', _) => l10n.posCardRefusedRole,
    _ => l10n.posCardRefusedGeneric,
  };
}

/// The sentence for a transient note.
String providerCardNoteText(
  AppLocalizations l10n,
  ProviderCardNote note,
) => switch (note) {
  ProviderCardNote.notSent => l10n.posCardNoteNotSent,
  ProviderCardNote.signInAgain => l10n.posCardNoteSignIn,
  ProviderCardNote.refusedBeforeProcessing => l10n.posCardNoteRefused,
  ProviderCardNote.unavailable => l10n.posCardNoteUnavailable,
  ProviderCardNote.pollLimit => l10n.posCardNotePollLimit,
  ProviderCardNote.autoChecksPaused => l10n.posCardNoteAutoPaused,
  ProviderCardNote.releaseNotConfirmed => l10n.posCardNoteReleaseNotConfirmed,
  ProviderCardNote.saveFailed => l10n.posCardNoteSaveFailed,
  ProviderCardNote.managerRequired => l10n.posCardNoteManagerRequired,
  ProviderCardNote.managerProofUnavailable => l10n.posCardNoteManagerProof,
  ProviderCardNote.notRecoverable => l10n.posCardNoteNotRecoverable,
  ProviderCardNote.roleCannot => l10n.posCardNoteRole,
  ProviderCardNote.terminalUnavailable => l10n.posCardTerminalUnavailableNote,
  ProviderCardNote.postureUnknown => l10n.posCardNotePostureUnknown,
};

/// The sentence while a request is in flight.
String providerCardBusyText(AppLocalizations l10n, ProviderCardBusy busy) =>
    switch (busy) {
      ProviderCardBusy.starting => l10n.posCardNoteStarting,
      ProviderCardBusy.checking => l10n.posCardNoteChecking,
      ProviderCardBusy.releasing => l10n.posCardNoteReleasing,
      ProviderCardBusy.recording ||
      ProviderCardBusy.resuming => l10n.posCardNoteRecording,
    };
