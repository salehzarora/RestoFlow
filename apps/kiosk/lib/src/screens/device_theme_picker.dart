import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/kiosk_theme.dart';
import '../widgets/kiosk_chrome.dart';

/// KIOSK-001-107 §8 — the CUSTOM two-color editor for the global device
/// theme. Mirrors the POS visual-picker concept (curated palette +
/// saturation/value field + hue rail + shade strip + live swatch + optional
/// strict-hex advanced input) without importing any `apps/pos` source. The
/// dialog works on a LOCAL draft only: nothing leaks into the live UI (or
/// even the appearance draft) until Apply returns the encoded wire.
class KioskDeviceThemeCustomDialog extends StatefulWidget {
  const KioskDeviceThemeCustomDialog({super.key, required this.initial});

  /// The pair the editor opens with (current draft resolution).
  final KioskThemePair initial;

  @override
  State<KioskDeviceThemeCustomDialog> createState() =>
      _KioskDeviceThemeCustomDialogState();
}

class _KioskDeviceThemeCustomDialogState
    extends State<KioskDeviceThemeCustomDialog> {
  late Color _primary = widget.initial.primary;
  late Color _action = widget.initial.action;
  bool _editingAction = false;

  KioskThemePair get _draftPair =>
      KioskThemePair.custom(primary: _primary, action: _action);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editing = _editingAction ? _action : _primary;
    return Dialog(
      backgroundColor: KioskColors.sheetBottom,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.kioskUiThemeCustomTitle,
                style: KioskType.body(28, FontWeight.w800),
              ),
              const SizedBox(height: 16),
              // Which of the two roles is being edited (shape+check, never
              // color-only).
              Row(
                children: [
                  Expanded(
                    child: _RoleTile(
                      key: const Key('kiosk-uitheme-role-primary'),
                      label: l10n.kioskUiThemePrimaryLabel,
                      color: _primary,
                      selected: !_editingAction,
                      onTap: () => setState(() => _editingAction = false),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _RoleTile(
                      key: const Key('kiosk-uitheme-role-action'),
                      label: l10n.kioskUiThemeActionLabel,
                      color: _action,
                      selected: _editingAction,
                      onTap: () => setState(() => _editingAction = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              KioskColorField(
                key: ValueKey('field-${_editingAction ? 'action' : 'primary'}'),
                value: editing,
                onChanged: (c) => setState(() {
                  if (_editingAction) {
                    _action = c;
                  } else {
                    _primary = c;
                  }
                }),
              ),
              const SizedBox(height: 18),
              _DraftPreview(pair: _draftPair, l10n: l10n),
              const SizedBox(height: 18),
              Row(
                children: [
                  KioskAccentPill(
                    key: const Key('kiosk-uitheme-apply'),
                    onTap: () => Navigator.of(context).pop(_draftPair.wire),
                    height: 72,
                    horizontalPadding: 38,
                    child: Text(
                      l10n.kioskUiThemeApply,
                      style: KioskType.body(
                        21,
                        FontWeight.w800,
                        color: KioskColors.onAction,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  TextButton(
                    key: const Key('kiosk-uitheme-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.kioskCancel,
                      style: KioskType.body(
                        20,
                        FontWeight.w600,
                        color: KioskColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KioskPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KioskColors.glass(.05),
        border: Border.all(
          color: selected ? KioskColors.ring : KioskColors.glass(.16),
          width: selected ? 3 : 1.5,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: KioskType.body(18, FontWeight.w700),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, color: KioskColors.ring, size: 26),
        ],
      ),
    ),
  );
}

/// The compact live preview: canvas + one structural chip + one action CTA +
/// an action ring + readable copy — all rendered from the DRAFT pair.
class _DraftPreview extends StatelessWidget {
  const _DraftPreview({required this.pair, required this.l10n});
  final KioskThemePair pair;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => KioskThemePreview(pair: pair);
}

/// Shared draft-pair preview (also used by the settings section).
class KioskThemePreview extends StatelessWidget {
  const KioskThemePreview({super.key, required this.pair});
  final KioskThemePair pair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('kiosk-uitheme-preview'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pair.structuralCanvasTop, pair.structuralCanvasBottom],
        ),
        border: Border.all(color: pair.structuralBorder, width: 1.5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Structural panel chip + primary swatch.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pair.structuralPanel,
                border: Border.all(color: pair.structuralBorderHi),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.kioskUiThemePreviewBody,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KioskType.body(16, FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 18,
                    width: 84,
                    decoration: BoxDecoration(
                      color: pair.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Action CTA + ring mark.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [pair.actionHi, pair.actionDeep],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(color: pair.actionGlow, blurRadius: 12),
                  ],
                ),
                child: Text(
                  l10n.kioskUiThemePreviewAction,
                  style: KioskType.body(
                    16,
                    FontWeight.w800,
                    color: pair.onAction,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: pair.actionRing, width: 3),
                ),
                child: Center(
                  child: Text(
                    '4',
                    style: KioskType.body(
                      15,
                      FontWeight.w800,
                      color: pair.actionSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The visual color field: curated palette + SV square + hue rail + shade
// strip + advanced strict-hex input.
// ---------------------------------------------------------------------------

const List<Color> _kCuratedField = [
  Color(0xFF16263B), // midnight navy
  Color(0xFF1E4D3B), // forest
  Color(0xFF44264A), // aubergine
  Color(0xFF33312C), // charcoal
  Color(0xFF5C1E2E), // burgundy
  Color(0xFF14343B), // deep teal
  Color(0xFFF97316), // ember
  Color(0xFFC65A4B), // brick
  Color(0xFFD89A2B), // gold
  Color(0xFF4E8B7A), // mint leaf
  Color(0xFF60A5FA), // sky
  Color(0xFFF4EBDD), // cream
];

class KioskColorField extends StatefulWidget {
  const KioskColorField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<KioskColorField> createState() => _KioskColorFieldState();
}

class _KioskColorFieldState extends State<KioskColorField> {
  late HSVColor _hsv = HSVColor.fromColor(widget.value);
  late final TextEditingController _hex = TextEditingController(
    text: kioskFormatWireHex(widget.value),
  );
  bool _hexError = false;

  void _emit(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexError = false;
      _hex.text = kioskFormatWireHex(hsv.toColor());
    });
    widget.onChanged(hsv.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = _hsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Curated quick palette.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final swatch in _kCuratedField)
              KioskPressable(
                onTap: () => _emit(HSVColor.fromColor(swatch)),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: swatch.toARGB32() == current.toARGB32()
                          ? KioskColors.ring
                          : Colors.white24,
                      width: swatch.toARGB32() == current.toARGB32() ? 3 : 1.5,
                    ),
                  ),
                  child: swatch.toARGB32() == current.toARGB32()
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: kioskReadableInkOn(swatch),
                        )
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Saturation/value field.
        SizedBox(
          key: const Key('kiosk-uitheme-sv-field'),
          height: 190,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _pickSv(d.localPosition, constraints.biggest),
              onPanUpdate: (d) => _pickSv(d.localPosition, constraints.biggest),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  size: constraints.biggest,
                  painter: _SvPainter(_hsv),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Hue rail.
        SizedBox(
          key: const Key('kiosk-uitheme-hue-rail'),
          height: 30,
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => _pickHue(d.localPosition, constraints.biggest),
              onPanUpdate: (d) =>
                  _pickHue(d.localPosition, constraints.biggest),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: CustomPaint(
                  size: constraints.biggest,
                  painter: _HuePainter(_hsv.hue),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Lighter/darker shade strip of the CURRENT color.
        Row(
          children: [
            for (final t in const [-.4, -.25, -.12, 0.0, .12, .25, .4])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: KioskPressable(
                    onTap: () => _emit(
                      HSVColor.fromColor(
                        t == 0
                            ? current
                            : Color.lerp(
                                current,
                                t < 0 ? Colors.black : Colors.white,
                                t.abs(),
                              )!,
                      ),
                    ),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: t == 0
                            ? current
                            : Color.lerp(
                                current,
                                t < 0 ? Colors.black : Colors.white,
                                t.abs(),
                              ),
                        borderRadius: BorderRadius.circular(8),
                        border: t == 0
                            ? Border.all(color: Colors.white70, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Advanced strict-hex input + live swatch.
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('kiosk-uitheme-hex'),
                controller: _hex,
                style: KioskType.body(19, FontWeight.w600),
                decoration: InputDecoration(
                  labelText: l10n.kioskUiThemeAdvancedHex,
                  errorText: _hexError ? l10n.kioskAppearanceHexHint : null,
                  isDense: true,
                ),
                onSubmitted: _applyHex,
                onEditingComplete: () => _applyHex(_hex.text),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _applyHex(String raw) {
    final parsed = kioskParseWireHex(raw);
    if (parsed == null) {
      setState(() => _hexError = true);
      return;
    }
    _emit(HSVColor.fromColor(parsed));
  }

  void _pickSv(Offset position, Size size) {
    final s = (position.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (position.dy / size.height).clamp(0.0, 1.0);
    _emit(_hsv.withSaturation(s).withValue(v));
  }

  void _pickHue(Offset position, Size size) {
    final h = (position.dx / size.width).clamp(0.0, 1.0) * 360.0;
    _emit(_hsv.withHue(h.clamp(0.0, 359.999)));
  }
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    // Selection thumb (shape cue, not color-only).
    final thumb = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      thumb,
      12,
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      thumb,
      11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      thumb,
      13,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SvPainter oldDelegate) => oldDelegate.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var h = 0; h <= 360; h += 30)
              HSVColor.fromAHSV(
                1,
                h.toDouble().clamp(0, 359.999),
                1,
                1,
              ).toColor(),
          ],
        ).createShader(rect),
    );
    final x = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: 10,
          height: size.height + 6,
        ),
        const Radius.circular(5),
      ),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) => oldDelegate.hue != hue;
}
