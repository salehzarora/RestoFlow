import 'package:flutter/material.dart';

import '../tokens.dart';

/// A large on-screen numeric keypad for touch surfaces (design-polish sprint):
/// PIN sign-in and cash-tendered entry, where an OS keyboard is absent
/// (desktop POS) or covers half the screen (tablets).
///
/// Purely additive input: it emits digits/backspace via callbacks so the
/// backing [TextField] (which keeps its test Key and `enterText`
/// compatibility) stays the single source of truth. Digits are ASCII '0'-'9'
/// (PIN/amount wire formats are ASCII; glyph localization is out of scope).
/// RTL-safe: a numeric grid has no reading direction; the backspace icon
/// auto-mirrors.
class RestoflowNumericKeypad extends StatelessWidget {
  const RestoflowNumericKeypad({
    required this.onDigit,
    required this.onBackspace,
    this.trailingKey,
    this.enabled = true,
    this.buttonHeight = 56,
    super.key,
  });

  /// Called with '0'..'9' when a digit key is tapped.
  final ValueChanged<String> onDigit;

  /// Removes the last character.
  final VoidCallback onBackspace;

  /// Optional bottom-start key (e.g. a decimal separator for cash entry).
  /// Null renders an empty slot.
  final Widget? trailingKey;

  final bool enabled;
  final double buttonHeight;

  Widget _digit(BuildContext context, String d) {
    return SizedBox(
      height: buttonHeight,
      child: FilledButton.tonal(
        key: Key('keypad-$d'),
        onPressed: enabled ? () => onDigit(d) : null,
        style: FilledButton.styleFrom(
          textStyle: Theme.of(context).textTheme.titleLarge,
          padding: EdgeInsets.zero,
        ),
        child: Text(d),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> cells) => Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: RestoflowSpacing.sm),
          Expanded(child: cells[i]),
        ],
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([
          for (final d in ['1', '2', '3']) _digit(context, d),
        ]),
        const SizedBox(height: RestoflowSpacing.sm),
        row([
          for (final d in ['4', '5', '6']) _digit(context, d),
        ]),
        const SizedBox(height: RestoflowSpacing.sm),
        row([
          for (final d in ['7', '8', '9']) _digit(context, d),
        ]),
        const SizedBox(height: RestoflowSpacing.sm),
        row([
          SizedBox(
            height: buttonHeight,
            child: trailingKey ?? const SizedBox(),
          ),
          _digit(context, '0'),
          SizedBox(
            height: buttonHeight,
            child: OutlinedButton(
              key: const Key('keypad-backspace'),
              onPressed: enabled ? onBackspace : null,
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: const Icon(
                Icons.backspace_outlined,
                size: RestoflowIconSizes.lg,
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
