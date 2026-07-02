import 'package:flutter/material.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A typed, safe PIN sign-in error for [PinLoginScreen] messaging (the host
/// maps its transport/auth failures to one of these; no raw provider text).
enum PinLoginError { wrongPin, locked, network, unavailable }

/// The shared POS/KDS staff PIN sign-in screen (DECISION D-006: a personal
/// employee identity + a PIN-based fast session, valid only on a paired,
/// authorized device).
///
/// MONEY-FREE by design (a kitchen device renders it too — SECURITY T-003).
/// Flow: load the branch staff from the token-proven [staffRepository] → tap a
/// name → enter the PIN (obscured, digits only, never echoed or logged) →
/// [onStartSession]. A wrong PIN / lockout / network problem shows a safe,
/// localized message; nothing is ever faked — no session means no entry.
class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({
    required this.staffRepository,
    required this.onStartSession,
    this.surface,
    this.appBarActions = const <Widget>[],
    super.key,
  });

  final DeviceStaffRepository staffRepository;

  /// The hosting surface (POS/KDS). Drives the no-staff guidance wording —
  /// which roles can sign in here. Null => the generic fallback body.
  final AppSurface? surface;

  /// Host-provided app-bar actions (sprint I: the language switcher must be
  /// reachable on EVERY page, including the PIN screen).
  final List<Widget> appBarActions;

  /// Starts the PIN session; returns null on success (the host rebuilds past
  /// this screen) or a typed error to show.
  final Future<PinLoginError?> Function(String employeeProfileId, String pin)
  onStartSession;

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  /// PIN wire format: 4-8 ASCII digits (matches the keypad's '0'-'9' output).
  static const int _maxPinLength = 8;

  late Future<Result<List<DeviceStaffMember>, DeviceStaffFailure>> _staff =
      widget.staffRepository.listStaff();
  DeviceStaffMember? _selected;
  final _pin = TextEditingController();
  PinLoginError? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
    _staff = widget.staffRepository.listStaff();
    _selected = null;
    _error = null;
  });

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null || _busy) return;
    final pin = _pin.text;
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin)) {
      setState(() => _error = PinLoginError.wrongPin);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onStartSession(selected.employeeProfileId, pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _pin.clear();
    });
    // On success the host swaps this screen out; nothing more to do here.
  }

  /// Appends a keypad digit to the SAME controller the [TextField] edits —
  /// the field stays the single source of truth (and `enterText`-compatible).
  void _keypadDigit(String digit) {
    if (_busy || _pin.text.length >= _maxPinLength) return;
    final next = _pin.text + digit;
    _pin.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _keypadBackspace() {
    if (_busy || _pin.text.isEmpty) return;
    final next = _pin.text.substring(0, _pin.text.length - 1);
    _pin.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pinLoginTitle),
        actions: widget.appBarActions,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: RestoflowPanelWidths.formPanel,
          ),
          child:
              FutureBuilder<
                Result<List<DeviceStaffMember>, DeviceStaffFailure>
              >(
                future: _staff,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    // Exactly ONE spinner (loading-state test contract).
                    return const Center(child: CircularProgressIndicator());
                  }
                  return snap.data!.fold(
                    (staff) => _selected == null
                        ? _staffPicker(context, staff)
                        : _pinEntry(context, _selected!),
                    (failure) => _loadFailure(context, failure),
                  );
                },
              ),
        ),
      ),
    );
  }

  Widget _loadFailure(BuildContext context, DeviceStaffFailure failure) {
    final l10n = AppLocalizations.of(context);
    final message = switch (failure) {
      DeviceStaffFailure.invalidSession => l10n.pinLoginSessionInvalid,
      DeviceStaffFailure.network ||
      DeviceStaffFailure.unknown => l10n.pinLoginLoadError,
    };
    return Padding(
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RestoflowNoticeBanner(
            tone: RestoflowTone.danger,
            icon: Icons.wifi_off_outlined,
            body: message,
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.authTryAgain),
          ),
        ],
      ),
    );
  }

  Widget _staffPicker(BuildContext context, List<DeviceStaffMember> staff) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (staff.isEmpty) {
      return _emptyStaff(context);
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      children: [
        Text(
          l10n.pinLoginPickName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: RestoflowSpacing.lg),
        for (final member in staff)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              bottom: RestoflowSpacing.sm,
            ),
            child: _StaffTile(
              member: member,
              roleLabel: _roleLabel(l10n, member.role),
              onTap: () => setState(() {
                _selected = member;
                _error = null;
                _pin.clear();
              }),
            ),
          ),
      ],
    );
  }

  /// Action-oriented, surface-specific guidance: WHO can sign in on this
  /// device (cashier vs kitchen staff) and exactly where PINs come from.
  /// Still money-free (a kitchen device renders this too — T-003), and
  /// never a fake/auto-created member.
  Widget _emptyStaff(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final body = switch (widget.surface) {
      AppSurface.pos => l10n.pinLoginEmptyBodyPos,
      AppSurface.kds => l10n.pinLoginEmptyBodyKds,
      _ => l10n.pinLoginEmptyBody,
    };
    // A Column (not a lazy list) so every setup step is always built, and the
    // whole state stays scrollable on short viewports.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // RestoflowStateView presentation, composed inline so the setup
          // steps card sits between the message and the retry action.
          Container(
            width: RestoflowIconSizes.hero,
            height: RestoflowIconSizes.hero,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.badge_outlined,
              size: RestoflowIconSizes.xl,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          Text(
            l10n.pinLoginEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(RestoflowSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(RestoflowRadii.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.checklist_outlined,
                      size: RestoflowIconSizes.md,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.pinLoginStepsTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RestoflowSpacing.xs),
                // The step strings carry their own localized numbering
                // ('1. Open the Dashboard' …) — no extra number chrome.
                for (final step in [
                  l10n.pinLoginStep1,
                  l10n.pinLoginStep2,
                  l10n.pinLoginStep3,
                  l10n.pinLoginStep4,
                  l10n.pinLoginStep5,
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: RestoflowSpacing.xs,
                    ),
                    child: Text(step, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.authTryAgain),
          ),
        ],
      ),
    );
  }

  Widget _pinEntry(BuildContext context, DeviceStaffMember member) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final errorText = switch (_error) {
      null => null,
      PinLoginError.wrongPin => l10n.pinLoginWrongPin,
      PinLoginError.locked => l10n.pinLoginLocked,
      PinLoginError.network => l10n.pinLoginNetworkError,
      PinLoginError.unavailable => l10n.pinLoginUnavailable,
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RestoflowSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            member.displayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: RestoflowSpacing.xs),
          Text(
            _roleLabel(l10n, member.role),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          TextField(
            key: const Key('pin-input'),
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: _maxPinLength,
            textAlign: TextAlign.center,
            // Bigger obscured dots; no letterSpacing (Arabic-safe).
            style: theme.textTheme.headlineSmall,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.pinFieldLabel,
              counterText: '',
              errorText: errorText,
            ),
          ),
          const SizedBox(height: RestoflowSpacing.md),
          // Touch-first on-screen keypad (desktop POS has no soft keyboard;
          // tablet keyboards cover half the screen). Additive input only —
          // the TextField above stays the single source of truth.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: RestoflowNumericKeypad(
                onDigit: _keypadDigit,
                onBackspace: _keypadBackspace,
                enabled: !_busy,
                buttonHeight: 48,
              ),
            ),
          ),
          const SizedBox(height: RestoflowSpacing.lg),
          FilledButton(
            key: const Key('pin-submit'),
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const RestoflowInlineSpinner()
                : Text(l10n.pinLoginSubmit),
          ),
          const SizedBox(height: RestoflowSpacing.sm),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _selected = null;
                    _error = null;
                    _pin.clear();
                  }),
            child: Text(l10n.pinLoginBack),
          ),
        ],
      ),
    );
  }

  /// Maps the wire role to the existing localized role labels (no money, no
  /// new vocabulary).
  static String _roleLabel(AppLocalizations l10n, String wire) =>
      switch (wire) {
        'cashier' => l10n.authRoleCashier,
        'kitchen_staff' => l10n.authRoleKitchenStaff,
        'manager' => l10n.authRoleManager,
        'restaurant_owner' => l10n.authRoleRestaurantOwner,
        'org_owner' => l10n.authRoleOwner,
        'accountant' => l10n.authRoleAccountant,
        _ => wire,
      };
}

/// One large touch-first staff tile: an initials avatar (derived from the
/// display-name DATA, not copy), the name, the role as a status pill, and a
/// chevron affordance (auto-mirrors under RTL). The whole tile is the tap
/// target (well above the 56dp minimum) and keeps the stable
/// `pin-staff-<employeeProfileId>` key on the tappable.
class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.member,
    required this.roleLabel,
    required this.onTap,
  });

  final DeviceStaffMember member;
  final String roleLabel;
  final VoidCallback onTap;

  /// First grapheme of up to two name parts, uppercased (a no-op for
  /// Arabic/Hebrew). Pure data derivation — never localized copy.
  static String _initials(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return '$first$second'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RestoflowRadii.lg),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        key: Key('pin-staff-${member.employeeProfileId}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  _initials(member.displayName),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: RestoflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: RestoflowSpacing.xs),
                    RestoflowStatusPill(label: roleLabel),
                  ],
                ),
              ),
              const SizedBox(width: RestoflowSpacing.sm),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
