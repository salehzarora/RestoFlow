import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show PairingPanelRequest;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show pairingLinkForDeviceType;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// LIVE-OPS-001 — the Dashboard's QR pairing panel presenter (the `feature_admin`
/// [PairingPanelPresenter] seam). Shown after a device enrollment code is issued:
/// a LOCALLY-rendered QR + a copyable hosted link (`{origin}/pos?pair=CODE` or
/// `/kds`, origin-derived) + the manual code, so staff can point a tablet straight
/// at the pairing screen with the code prefilled.
///
/// OFFLINE only — `qr_flutter` is a pure-Dart `qr` encoder + `CustomPaint`; there
/// is NO external QR API and NO network. The code is short-lived, single-use and
/// rate-limited server-side, so it is not a durable secret; it is never logged.
/// The operator STILL taps "Pair" on the device — this is prefill only, never an
/// auto-redeem. [base] defaults to the current web origin ([Uri.base]); tests
/// inject a fixed origin.
Future<void> showDevicePairingPanel(
  BuildContext context,
  PairingPanelRequest request, {
  Uri? base,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DevicePairingPanel(request: request, base: base),
);

/// The pairing panel dialog body (public for widget tests).
class DevicePairingPanel extends StatefulWidget {
  const DevicePairingPanel({required this.request, this.base, super.key});

  final PairingPanelRequest request;
  final Uri? base;

  @override
  State<DevicePairingPanel> createState() => _DevicePairingPanelState();
}

class _DevicePairingPanelState extends State<DevicePairingPanel> {
  bool _linkCopied = false;
  bool _codeCopied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final req = widget.request;
    // Origin-derived link; null for an unknown device type -> manual code only.
    final link = pairingLinkForDeviceType(
      base: widget.base ?? Uri.base,
      code: req.code,
      deviceType: req.deviceType,
    );
    final typeLabel = switch (req.deviceType.trim().toLowerCase()) {
      'pos' => l10n.adminDeviceTypePos,
      'kds' => l10n.adminDeviceTypeKds,
      _ => req.deviceType,
    };
    return AlertDialog(
      icon: Icon(Icons.qr_code_2, color: scheme.primary),
      title: Text(l10n.pairingPanelTitle, textAlign: TextAlign.center),
      // A FIXED-width, vertically-scrollable body: AlertDialog would otherwise
      // try to intrinsic-size an unbounded scroll view (which the QR/scroll do
      // not support) and assert during layout.
      content: SizedBox(
        width: RestoflowPanelWidths.dialog,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                req.deviceLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                typeLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              if (link != null) ...[
                // A light card keeps the QR scannable in any theme.
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(RestoflowSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(RestoflowRadii.md),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: QrImageView(
                      key: const Key('pairing-qr'),
                      data: link.toString(),
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                      semanticsLabel: l10n.pairingPanelScanLabel,
                    ),
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.sm),
                Text(
                  l10n.pairingPanelInstructions,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: RestoflowSpacing.lg),
                _CopyRow(
                  key: const Key('pairing-link'),
                  label: l10n.pairingPanelLinkLabel,
                  value: link.toString(),
                  copyTooltip: l10n.pairingPanelCopyLink,
                  copied: _linkCopied,
                  onCopy: () =>
                      _copy(link.toString(), () => _linkCopied = true),
                ),
              ] else ...[
                // Unknown device type: no app route, so NO link/QR — manual only.
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: RestoflowIconSizes.sm,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: RestoflowSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.pairingPanelManualOnly,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: RestoflowSpacing.md),
              _CopyRow(
                key: const Key('pairing-code'),
                label: l10n.pairingPanelCodeLabel,
                value: req.code,
                mono: true,
                copyTooltip: l10n.adminCopy,
                copied: _codeCopied,
                onCopy: () => _copy(req.code, () => _codeCopied = true),
              ),
              const SizedBox(height: RestoflowSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: RestoflowSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.adminShownOnce,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RestoflowSpacing.sm),
              Text(
                l10n.adminCodeExpiresNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.adminDone),
        ),
      ],
    );
  }

  Future<void> _copy(String text, void Function() mark) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(mark);
  }
}

/// A labelled value box with a copy affordance (the pairing link or the code).
class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.copyTooltip,
    required this.copied,
    required this.onCopy,
    this.mono = false,
    super.key,
  });

  final String label;
  final String value;
  final String copyTooltip;
  final bool copied;
  final VoidCallback onCopy;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: RestoflowSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RestoflowSpacing.md,
            vertical: RestoflowSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: mono
                      ? theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: copyTooltip,
                icon: Icon(copied ? Icons.check : Icons.copy_outlined),
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
