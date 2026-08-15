/// DEVICE-THEME-COLOR-PICKER-032 — the VISUAL color chooser behind the custom
/// device theme.
///
/// POS-CUSTOM-DEVICE-THEME-010 shipped the custom pair as two `#RRGGBB` text
/// fields. That asks a restaurant owner to know what a hex code is. This sheet
/// replaces the typing with sight: a curated palette to start from, a
/// saturation/value field, a hue rail and a lighter/darker shade strip — all
/// driven by touch, all previewed live.
///
/// APPEARANCE ONLY, and deliberately narrow: it returns a [Color] and knows
/// nothing about persistence, themes, or the device pair. The stored format is
/// untouched — [PosDeviceThemeController] still writes the same
/// `custom:RRGGBB:RRGGBB` wire through the same per-device key.
///
/// Manual hex entry survives under «متقدم / Advanced», collapsed by default,
/// keeping the exact validation contract of the fields it replaces
/// ([posParseHexColor], the localized invalid-format error, and a disabled
/// confirm while the text does not parse). Nothing here REQUIRES it: the
/// visual controls alone always yield a valid color.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../design/pos_color_utils.dart';
import '../design/pos_visual_tokens.dart';

/// The one-tap starting points: a spread of hues that read as restaurant
/// identity colors rather than a web-safe grid. Order runs dark → light so the
/// row itself reads as a gradient. Includes both shipped defaults (navy /
/// ember) so "put it back roughly how it was" is a single tap.
const List<Color> kPosColorPickerPalette = <Color>[
  Color(0xFF16263B), // navy (default primary)
  Color(0xFF1A3D34), // forest
  Color(0xFF3B2A44), // aubergine
  Color(0xFF2B2F36), // charcoal
  Color(0xFF2C5F8A), // sky
  Color(0xFF146B6B), // teal
  Color(0xFF4E5B31), // olive
  Color(0xFFA62B2B), // crimson
  Color(0xFF8C4A2F), // clay
  Color(0xFFD9642B), // ember (default secondary)
  Color(0xFFD89A2B), // saffron
  Color(0xFFF2EFE8), // cream
];

/// The lighter → darker steps offered beside the field, as HSV *value* stops.
/// Value only: hue and saturation stay exactly where the owner put them, so
/// the strip reads as "the same color, lighter or darker".
const List<double> kPosColorPickerShadeStops = <double>[
  1.0,
  0.82,
  0.64,
  0.46,
  0.28,
];

/// Opens the visual picker and resolves to the chosen color, or `null` when
/// the owner cancels or dismisses the sheet.
Future<Color?> showPosColorPicker(
  BuildContext context, {
  required Color initial,
  required String title,
}) => showModalBottomSheet<Color>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PosColorPickerSheet(initial: initial, title: title),
);

/// The picker body. Public so tests can pump it directly without a route.
class PosColorPickerSheet extends StatefulWidget {
  const PosColorPickerSheet({
    super.key,
    required this.initial,
    required this.title,
  });

  /// The color the sheet opens on — the swatch the owner tapped.
  final Color initial;

  /// Which color is being chosen, e.g. «اللون الأساسي». Reuses the existing
  /// custom-theme field labels; this sheet adds no naming of its own.
  final String title;

  @override
  State<PosColorPickerSheet> createState() => _PosColorPickerSheetState();
}

class _PosColorPickerSheetState extends State<PosColorPickerSheet> {
  /// HSV — not Color — is the source of truth. A round-trip through Color
  /// loses hue whenever saturation or value reaches zero, which would snap the
  /// rail to red the moment someone dragged to the black edge.
  late HSVColor _hsv;

  final TextEditingController _hexCtl = TextEditingController();

  /// The advanced hex field mirrors [_hsv]; this guards the write-back so the
  /// mirror never feeds its own lossy re-parse into the source of truth.
  bool _syncingHex = false;

  /// «متقدم» starts collapsed — the whole point is that hex is optional.
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtl.text = posFormatHexColor(widget.initial);
    _hexCtl.addListener(_onHexEdited);
  }

  @override
  void dispose() {
    _hexCtl.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  /// The confirm gate — identical in spirit to the editor's old Apply gate:
  /// the typed hex must parse. Unreachable through the visual controls alone,
  /// which can only ever produce a valid color.
  Color? get _hexColor => posParseHexColor(_hexCtl.text);

  bool get _hexInvalid => _hexCtl.text.trim().isNotEmpty && _hexColor == null;

  void _setHsv(HSVColor next) {
    setState(
      () => _hsv = HSVColor.fromAHSV(1, next.hue, next.saturation, next.value),
    );
    final text = posFormatHexColor(_color);
    if (_hexCtl.text.toUpperCase() == text) return;
    _syncingHex = true;
    _hexCtl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncingHex = false;
  }

  void _setColor(Color color) => _setHsv(HSVColor.fromColor(color));

  void _onHexEdited() {
    if (_syncingHex) return;
    final parsed = _hexColor;
    // Unparseable text leaves the visual controls exactly where they were —
    // the owner still sees the color the sheet would return, and confirm is
    // disabled until the text agrees with it again.
    setState(() {
      if (parsed != null) _hsv = HSVColor.fromColor(parsed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = _color;
    // The pilot tablet is 1024x600 in landscape: a full-height field would
    // push everything below the fold. Give the field less room there, and
    // pin the actions outside the scroll view so «اختيار اللون» is NEVER
    // something you have to go looking for.
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final fieldHeight = viewportHeight < 700 ? 116.0 : 168.0;

    return SafeArea(
      child: Padding(
        // The advanced hex field can raise the keyboard; keep the actions
        // reachable instead of buried under it.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        // heightFactor 1 shrink-wraps the sheet to its content, so a short
        // picker does not claim 85% of a tall phone; the max-height cap only
        // bites on short (tablet-landscape) viewports, where it scrolls.
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: viewportHeight * 0.85,
            ),
            child: Column(
              key: const Key('pos-color-picker'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RestoflowSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(theme, l10n, color),
                        const SizedBox(height: RestoflowSpacing.md),
                        _caption(theme, l10n.posColorPickerQuickColors),
                        const SizedBox(height: RestoflowSpacing.xs),
                        _palette(color),
                        const SizedBox(height: RestoflowSpacing.md),
                        _caption(theme, l10n.posColorPickerField),
                        const SizedBox(height: RestoflowSpacing.xs),
                        _SaturationValueField(
                          hsv: _hsv,
                          height: fieldHeight,
                          onChanged: _setHsv,
                        ),
                        const SizedBox(height: RestoflowSpacing.md),
                        _caption(theme, l10n.posColorPickerHue),
                        const SizedBox(height: RestoflowSpacing.xs),
                        _HueRail(hsv: _hsv, onChanged: _setHsv),
                        const SizedBox(height: RestoflowSpacing.md),
                        _caption(theme, l10n.posColorPickerShade),
                        const SizedBox(height: RestoflowSpacing.xs),
                        _shadeStrip(),
                        const SizedBox(height: RestoflowSpacing.sm),
                        _advanced(theme, l10n),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    RestoflowSpacing.lg,
                    RestoflowSpacing.sm,
                    RestoflowSpacing.lg,
                    RestoflowSpacing.lg,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kRestoflowHairline)),
                  ),
                  child: _actions(l10n),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _caption(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  /// Title plus the live answer: a big swatch of what confirming would return,
  /// with the hex demoted to quiet secondary information beside it.
  Widget _header(ThemeData theme, AppLocalizations l10n, Color color) => Row(
    children: [
      Container(
        key: const Key('pos-color-picker-preview'),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(RestoflowRadii.md),
          border: Border.all(color: kRestoflowHairline),
        ),
      ),
      const SizedBox(width: RestoflowSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: RestoflowSpacing.xxs),
            // Informational only — never the way in. Hex is Latin, so it gets
            // a fixed LTR run inside ar/he.
            Text(
              posFormatHexColor(color),
              key: const Key('pos-color-picker-hex-readout'),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: kPosMoneyFontFamily,
                fontFamilyFallback: kPosMoneyFontFallbacks,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _palette(Color current) => Wrap(
    spacing: RestoflowSpacing.sm,
    runSpacing: RestoflowSpacing.sm,
    children: [
      for (final swatch in kPosColorPickerPalette)
        _PickerSwatch(
          key: Key(
            'pos-color-picker-swatch-${posFormatHexColor(swatch).substring(1)}',
          ),
          color: swatch,
          selected: swatch.toARGB32() == current.toARGB32(),
          onTap: () => _setColor(swatch),
        ),
    ],
  );

  /// Lighter → darker at the current hue and saturation.
  Widget _shadeStrip() => Row(
    key: const Key('pos-color-picker-shades'),
    children: [
      for (var i = 0; i < kPosColorPickerShadeStops.length; i++) ...[
        if (i > 0) const SizedBox(width: RestoflowSpacing.sm),
        Expanded(
          child: _ShadeStep(
            key: Key('pos-color-picker-shade-$i'),
            color: _hsv.withValue(kPosColorPickerShadeStops[i]).toColor(),
            onTap: () => _setHsv(_hsv.withValue(kPosColorPickerShadeStops[i])),
          ),
        ),
      ],
    ],
  );

  Widget _advanced(ThemeData theme, AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('pos-color-picker-advanced-toggle'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => setState(() => _advancedOpen = !_advancedOpen),
          icon: Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more),
          label: Text(l10n.posColorPickerAdvanced),
        ),
      ),
      if (_advancedOpen)
        Padding(
          padding: const EdgeInsets.only(top: RestoflowSpacing.xs),
          child: TextField(
            key: const Key('pos-color-picker-hex'),
            controller: _hexCtl,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 7,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
            ],
            style: const TextStyle(
              fontFamily: kPosMoneyFontFamily,
              fontFamilyFallback: kPosMoneyFontFallbacks,
            ),
            decoration: InputDecoration(
              labelText: l10n.posDeviceThemeCustomHexHint,
              hintText: l10n.posDeviceThemeCustomHexHint,
              counterText: '',
              isDense: true,
              errorText: _hexInvalid
                  ? l10n.posDeviceThemeCustomInvalidHex
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
    ],
  );

  Widget _actions(AppLocalizations l10n) => Row(
    children: [
      Expanded(
        child: FilledButton(
          key: const Key('pos-color-picker-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _hexColor == null
              ? null
              : () => Navigator.of(context).pop(_color),
          child: Text(l10n.posColorPickerConfirm),
        ),
      ),
      const SizedBox(width: RestoflowSpacing.sm),
      TextButton(
        key: const Key('pos-color-picker-cancel'),
        style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.posDeviceThemeCustomCancel),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// One palette tile. 44dp square (the sheet's touch-target floor) with a check
/// in the readable ink when it is the current color.
class _PickerSwatch extends StatelessWidget {
  const _PickerSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.md),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(RestoflowRadii.md),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : kRestoflowHairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 20, color: posReadableInkOn(color))
              : null,
        ),
      ),
    );
  }
}

/// One lighter/darker step. Not a persistent selection (the field marker and
/// the header preview already say where you are) — a nudge you can take.
class _ShadeStep extends StatelessWidget {
  const _ShadeStep({super.key, required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RestoflowRadii.sm),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(RestoflowRadii.sm),
            border: Border.all(color: kRestoflowHairline),
          ),
        ),
      ),
    );
  }
}

/// The saturation (x) / value (y) field at the current hue.
class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({
    required this.hsv,
    required this.height,
    required this.onChanged,
  });

  final HSVColor hsv;

  /// Shorter on tablet-landscape viewports so the rest of the picker stays
  /// above the fold; the gesture maths reads this, never a constant.
  final double height;

  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void emit(Offset local) => onChanged(
          hsv
              .withSaturation((local.dx / width).clamp(0.0, 1.0))
              .withValue((1 - local.dy / height).clamp(0.0, 1.0)),
        );
        return Semantics(
          label: AppLocalizations.of(context).posColorPickerField,
          child: _EagerPanArea(
            onPoint: emit,
            child: SizedBox(
              key: const Key('pos-color-picker-sv-field'),
              width: width,
              height: height,
              // clipBehavior none so a marker parked on an edge is never
              // half-eaten by the rounded corner.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(RestoflowRadii.md),
                    child: CustomPaint(
                      size: Size(width, height),
                      painter: _SvFieldPainter(hsv.hue),
                    ),
                  ),
                  Positioned(
                    // Physical left/top on purpose: a color field is a
                    // spatial instrument, not a text run — mirroring it in
                    // ar/he would move the marker away from the color.
                    left: hsv.saturation * width - 13,
                    top: (1 - hsv.value) * height - 13,
                    child: const _SelectionMarker(
                      key: Key('pos-color-picker-sv-marker'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The hue rail: full spectrum, thumb at the current hue.
class _HueRail extends StatelessWidget {
  const _HueRail({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const double _height = 28;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void emit(Offset local) =>
            onChanged(hsv.withHue(((local.dx / width).clamp(0.0, 1.0)) * 360));
        return Semantics(
          label: AppLocalizations.of(context).posColorPickerHue,
          child: _EagerPanArea(
            onPoint: emit,
            // Padding inside the gesture area, not around it: the rail reads
            // as 28dp but the finger gets the full 44.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                key: const Key('pos-color-picker-hue-rail'),
                width: width,
                height: _height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(_height / 2),
                      child: CustomPaint(
                        size: Size(width, _height),
                        painter: const _HueRailPainter(),
                      ),
                    ),
                    Positioned(
                      left: hsv.hue / 360 * width - 13,
                      top: _height / 2 - 13,
                      child: const _SelectionMarker(
                        key: Key('pos-color-picker-hue-marker'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The marker used by both instruments: a white ring inside a dark ring, so it
/// stays visible over white, over black, and over every hue in between —
/// the accessibility floor this ticket asks to preserve.
class _SelectionMarker extends StatelessWidget {
  const _SelectionMarker({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.transparent,
      border: Border.fromBorderSide(
        BorderSide(color: Color(0x8A000000), width: 1.5),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(1.5),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    ),
  );
}

/// Wraps an instrument in a pan recognizer that claims the pointer on DOWN.
///
/// The sheet scrolls vertically; a plain pan loses the arena to the enclosing
/// scrollable at 18dp of vertical slop (a pan needs 36), so dragging down the
/// value axis would scroll the sheet instead of darkening the color. Claiming
/// eagerly is the same fix the dashboard floor editor uses for arrange-mode
/// tile drags.
class _EagerPanArea extends StatelessWidget {
  const _EagerPanArea({required this.onPoint, required this.child});

  final ValueChanged<Offset> onPoint;
  final Widget child;

  void _emit(BuildContext context, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    onPoint(box.globalToLocal(global));
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _EagerPanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
            _EagerPanGestureRecognizer.new,
            // Plain statements, not a cascade: `..onDown = (d) => _emit(...)`
            // parses the NEXT `..` as a cascade on _emit's void result.
            (recognizer) {
              recognizer.onDown = (d) => _emit(context, d.globalPosition);
              recognizer.onStart = (d) => _emit(context, d.globalPosition);
              recognizer.onUpdate = (d) => _emit(context, d.globalPosition);
            },
          ),
    },
    child: child,
  );
}

/// A pan recognizer that claims the pointer the moment it goes down, so an
/// instrument drag ALWAYS beats the enclosing vertical scrollable.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

// ---------------------------------------------------------------------------
// Painters
// ---------------------------------------------------------------------------

/// White → hue across x, transparent → black down y. The classic field: every
/// tone of one hue reachable in a single gesture.
class _SvFieldPainter extends CustomPainter {
  const _SvFieldPainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pure = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, pure],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SvFieldPainter oldDelegate) => oldDelegate.hue != hue;
}

/// The full spectrum, left (0°) to right (360°).
class _HueRailPainter extends CustomPainter {
  const _HueRailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            for (var h = 0; h <= 360; h += 30)
              HSVColor.fromAHSV(1, h % 360 * 1.0, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HueRailPainter oldDelegate) => false;
}
