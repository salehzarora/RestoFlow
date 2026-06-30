import 'package:flutter/material.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';

/// The visual tone of a [DemoNoticeBanner] (RF-140; mirrors the admin
/// `PlatformNoticeBanner`).
enum DemoNoticeTone {
  /// The demo-data notice (informational).
  info,

  /// The real-mode "live · limited" notice (cautionary).
  caution,
}

/// A full-width notice banner keeping the dashboard honest about its data
/// source: an [DemoNoticeTone.info] tone for the demo-data notice and a
/// [DemoNoticeTone.caution] tone for the real-mode "live · limited" notice
/// (RF-140). Pure presentation — [message] is localized chrome.
class DemoNoticeBanner extends StatelessWidget {
  const DemoNoticeBanner({
    required this.message,
    this.tone = DemoNoticeTone.info,
    super.key,
  });

  final String message;
  final DemoNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caution = tone == DemoNoticeTone.caution;
    final bg = caution ? scheme.secondaryContainer : scheme.tertiaryContainer;
    final fg = caution
        ? scheme.onSecondaryContainer
        : scheme.onTertiaryContainer;
    final icon = caution ? Icons.bolt_outlined : Icons.info_outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RestoflowSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: RestoflowSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
