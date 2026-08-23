import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceStaffMember;
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/kiosk_theme.dart';
import '../state/kiosk_flow_controller.dart';
import '../state/kiosk_staff_access.dart';
import '../widgets/kiosk_chrome.dart';

/// KIOSK-001-102 §5 — the REAL staff gate behind the discreet ••• target.
///
/// The SAME employee PIN system as every staff surface: pick your name from
/// the token-proven `list_device_staff` projection, enter your employee PIN,
/// and the server verifies it (`start_pin_session` — bcrypt, lockout and
/// rate limits authoritative). The typed PIN lives only in this widget's
/// state for the duration of the attempt — never logged, never persisted.
/// Success opens Device Settings; leaving settings relocks (full reset).
class KioskStaffPinSheet extends ConsumerStatefulWidget {
  const KioskStaffPinSheet({super.key});

  @override
  ConsumerState<KioskStaffPinSheet> createState() => _KioskStaffPinSheetState();
}

class _KioskStaffPinSheetState extends ConsumerState<KioskStaffPinSheet> {
  List<DeviceStaffMember>? _staff;
  bool _staffFailed = false;
  String? _selectedId;
  String _entry = '';
  bool _busy = false;
  String? _errorKey; // 'wrong' | 'locked' | 'network'

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final access = ref.read(kioskStaffAccessProvider);
    if (access == null) return;
    setState(() {
      _staff = null;
      _staffFailed = false;
    });
    final result = await access.listStaff();
    if (!mounted) return;
    result.fold(
      (members) => setState(() {
        _staff = members;
        if (members.length == 1) _selectedId = members.single.employeeProfileId;
      }),
      (_) => setState(() => _staffFailed = true),
    );
  }

  Future<void> _press(String digit) async {
    if (_busy || _selectedId == null) return;
    final entry = _entry + digit;
    if (entry.length < 4) {
      setState(() {
        _entry = entry;
        _errorKey = null;
      });
      return;
    }
    setState(() {
      _entry = entry;
      _busy = true;
      _errorKey = null;
    });
    final access = ref.read(kioskStaffAccessProvider);
    final sessionId = ref.read(kioskDeviceContextProvider)?.deviceSessionId;
    if (access == null || sessionId == null) {
      setState(() {
        _busy = false;
        _entry = '';
        _errorKey = 'network';
      });
      return;
    }
    final error = await access.verifyPin(
      deviceSessionId: sessionId,
      employeeProfileId: _selectedId!,
      pin: entry,
    );
    if (!mounted) return;
    if (error == null) {
      ref.read(kioskFlowProvider.notifier).enterSettingsAfterStaffAuth();
      return;
    }
    setState(() {
      _busy = false;
      _entry = '';
      _errorKey = switch (error) {
        KioskStaffPinError.wrongPin => 'wrong',
        KioskStaffPinError.locked => 'locked',
        _ => 'network',
      };
    });
  }

  void _backspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(kioskFlowProvider.notifier);
    final staff = _staff;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: controller.closeStaffPinSheet,
            child: const ColoredBox(color: KioskColors.scrimDeep),
          ),
        ),
        Center(
          child: Container(
            width: 640,
            padding: const EdgeInsets.fromLTRB(44, 40, 44, 36),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [KioskColors.sheetTop, KioskColors.pinCardBottom],
              ),
              border: Border.all(color: KioskColors.glass(.14), width: 1.5),
              borderRadius: BorderRadius.circular(40),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x8C000000),
                  offset: Offset(0, 40),
                  blurRadius: 90,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.kioskStaffAccess,
                  style: KioskType.body(34, FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.kioskStaffPinPrompt,
                  textAlign: TextAlign.center,
                  style: KioskType.body(
                    20,
                    FontWeight.w500,
                    color: KioskColors.textMuted,
                  ),
                ),
                const SizedBox(height: 22),
                // --- staff picker (token-proven projection) ---
                if (staff == null && !_staffFailed)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        color: KioskColors.accentTop,
                      ),
                    ),
                  )
                else if (_staffFailed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        Text(
                          l10n.kioskStaffPinNetwork,
                          style: KioskType.body(
                            20,
                            FontWeight.w600,
                            color: KioskColors.dangerSoft,
                          ),
                        ),
                        const SizedBox(height: 12),
                        KioskAccentPill(
                          key: const Key('kiosk-staff-retry'),
                          onTap: _loadStaff,
                          height: 72,
                          horizontalPadding: 40,
                          child: Text(
                            l10n.kioskSubmitRetry,
                            style: KioskType.body(
                              22,
                              FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    l10n.kioskStaffChooseName,
                    style: KioskType.body(
                      21,
                      FontWeight.w700,
                      color: KioskColors.textSoft,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final member in staff!)
                        KioskPressable(
                          key: Key('kiosk-staff-${member.employeeProfileId}'),
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                  _selectedId = member.employeeProfileId;
                                  _entry = '';
                                  _errorKey = null;
                                }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              gradient: _selectedId == member.employeeProfileId
                                  ? kioskAccentGradient
                                  : null,
                              color: _selectedId == member.employeeProfileId
                                  ? null
                                  : KioskColors.glass(.06),
                              border: Border.all(
                                color: _selectedId == member.employeeProfileId
                                    ? Colors.transparent
                                    : KioskColors.glass(.16),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              member.displayName,
                              style: KioskType.body(21, FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  // --- dots ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _entry.length
                                ? KioskColors.accentTop
                                : KioskColors.glass(.12),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: _busy
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: KioskColors.accentTop,
                            ),
                          )
                        : _errorKey == null
                        ? const SizedBox.shrink()
                        : Text(
                            switch (_errorKey!) {
                              'wrong' => l10n.kioskStaffPinWrong,
                              'locked' => l10n.kioskActivationErrorLocked,
                              _ => l10n.kioskStaffPinNetwork,
                            },
                            key: const Key('kiosk-staff-pin-error'),
                            style: KioskType.body(
                              19,
                              FontWeight.w700,
                              color: KioskColors.dangerSoft,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  // --- keypad ---
                  SizedBox(
                    width: 420,
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.55,
                      children: [
                        for (final d in [
                          '1',
                          '2',
                          '3',
                          '4',
                          '5',
                          '6',
                          '7',
                          '8',
                          '9',
                        ])
                          _StaffKey(label: d, onTap: () => _press(d)),
                        const SizedBox.shrink(),
                        _StaffKey(label: '0', onTap: () => _press('0')),
                        _StaffKey(
                          icon: Icons.backspace_outlined,
                          onTap: _backspace,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                KioskPressable(
                  onTap: controller.closeStaffPinSheet,
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                    key: const Key('kiosk-staff-cancel'),
                    style:
                        KioskType.body(
                          21,
                          FontWeight.w700,
                          color: KioskColors.textMuted,
                        ).copyWith(
                          decoration: TextDecoration.underline,
                          decorationColor: KioskColors.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StaffKey extends StatelessWidget {
  const _StaffKey({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: KioskColors.glass(.06),
        border: Border.all(color: KioskColors.glass(.14), width: 1.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: label != null
            ? Text(label!, style: KioskType.body(30, FontWeight.w800))
            : Icon(icon, size: 30, color: KioskColors.textSoft),
      ),
    ),
  );
}
