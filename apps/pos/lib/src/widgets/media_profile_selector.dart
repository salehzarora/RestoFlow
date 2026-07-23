import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_printing/restoflow_printing.dart' show MediaProfileId;

/// PRINT-LAYOUT-001A: the per-printer MEDIA-SIZE selector shown in the POS
/// network + Bluetooth printer settings. It offers the two fixed labels (50×50,
/// 80×80) plus the backward-compatible 80 mm continuous roll — the default an
/// unconfigured printer resolves to, so an existing install is never silently
/// converted to a paginated label. Purely local hardware config; money-free.
///
/// A continuous 80 mm ROLL and a fixed 80×80 LABEL are DISTINCT options here
/// (they map to different typed profiles): the roll never paginates, the label
/// does.
class MediaProfileSelector extends StatelessWidget {
  const MediaProfileSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.fieldKey,
  });

  /// The currently-selected profile id.
  final MediaProfileId value;

  /// Called with the newly-picked profile id.
  final ValueChanged<MediaProfileId> onChanged;

  final bool enabled;

  /// Optional key for the dropdown field (so tests can target it).
  final Key? fieldKey;

  /// The localized label for [id] — the SINGLE source, reused by tests.
  static String labelFor(AppLocalizations l10n, MediaProfileId id) =>
      switch (id) {
        MediaProfileId.continuous80 => l10n.posPrinterMediaSizeContinuous,
        MediaProfileId.label50x50 => l10n.posPrinterMediaSize50,
        MediaProfileId.label80x80 => l10n.posPrinterMediaSize80,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: RestoflowSpacing.sm),
      child: DropdownButtonFormField<MediaProfileId>(
        key: fieldKey,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.posPrinterMediaSizeLabel,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final id in MediaProfileId.values)
            DropdownMenuItem<MediaProfileId>(
              value: id,
              child: Text(labelFor(l10n, id)),
            ),
        ],
        onChanged: enabled
            ? (v) {
                if (v != null) onChanged(v);
              }
            : null,
      ),
    );
  }
}
