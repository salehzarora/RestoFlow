import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_copy.dart';

// BIZBOT-STOREFRONT-VISUAL-PARITY-001: presentation adapted from the POS
// picker. No POS state, imports, settings, or persistence are shared.
Color? storefrontParseColor(String? value) =>
    value != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)
    ? Color(0xff000000 | int.parse(value.substring(1), radix: 16))
    : null;

String storefrontFormatColor(Color value) =>
    '#${(value.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

Color _ink(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

enum StorefrontColorRole { background, accent, text, buttonText }

/// A local sample of the four draft colors, with inherited ink when omitted.
/// It makes no claims about scene images, glass, or final Storefront layout.
class StorefrontColorSample {
  const StorefrontColorSample({
    this.background = '#13322a',
    this.accent = '#e07b2c',
    this.text,
    this.buttonText,
  });
  final String background, accent;
  final String? text, buttonText;

  Color color(StorefrontColorRole role) => switch (role) {
    StorefrontColorRole.background =>
      storefrontParseColor(background) ?? const Color(0xff13322a),
    StorefrontColorRole.accent =>
      storefrontParseColor(accent) ?? const Color(0xffe07b2c),
    StorefrontColorRole.text =>
      storefrontParseColor(text) ?? _ink(color(StorefrontColorRole.background)),
    StorefrontColorRole.buttonText =>
      storefrontParseColor(buttonText) ??
          _ink(color(StorefrontColorRole.accent)),
  };

  StorefrontColorSample withColor(StorefrontColorRole role, String? hex) =>
      StorefrontColorSample(
        background: role == StorefrontColorRole.background ? hex! : background,
        accent: role == StorefrontColorRole.accent ? hex! : accent,
        text: role == StorefrontColorRole.text ? hex : text,
        buttonText: role == StorefrontColorRole.buttonText ? hex : buttonText,
      );
}

/// Null result means Cancel; a non-null result with null HEX means inherit.
class StorefrontColorChoice {
  const StorefrontColorChoice(this.hex);
  final String? hex;
}

/// Keeps the existing HEX field and its stable key/controller under Advanced.
/// The visual sheet owns a separate draft until Apply returns a choice.
class StorefrontColorControl extends StatefulWidget {
  const StorefrontColorControl({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.role,
    required this.sample,
    required this.enabled,
    required this.onChanged,
    required this.advancedField,
    this.resetHex,
  });
  final String id, label;
  final String? value, resetHex;
  final StorefrontColorRole role;
  final StorefrontColorSample sample;
  final bool enabled;
  final ValueChanged<String?> onChanged;
  final Widget advancedField;

  @override
  State<StorefrontColorControl> createState() => _ColorControlState();
}

class _ColorControlState extends State<StorefrontColorControl> {
  bool _advanced = false;

  Future<void> _choose() async {
    // Capture the callback belonging to this editor identity before the await.
    // Its caller also checks binding generation before accepting the draft.
    final changed = widget.onChanged;
    final result = await showModalBottomSheet<StorefrontColorChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StorefrontColorPickerSheet(
        title: widget.label,
        initialHex: widget.value,
        resetHex: widget.resetHex,
        role: widget.role,
        sample: widget.sample,
      ),
    );
    if (mounted && widget.enabled && result != null) changed(result.hex);
  }

  @override
  Widget build(BuildContext context) {
    final copy = (String key) =>
        storefrontContentCopy(AppLocalizations.of(context), key);
    final color =
        storefrontParseColor(widget.value) ?? widget.sample.color(widget.role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          key: Key('${widget.id}-picker'),
          onPressed: widget.enabled ? _choose : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
          child: Row(
            children: [
              _Swatch(color: color),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.label)),
              const Icon(Icons.palette_outlined),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: Key('${widget.id}-advanced'),
            onPressed: () => setState(() => _advanced = !_advanced),
            icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
            label: Text(copy('colorAdvanced')),
          ),
        ),
        if (_advanced) widget.advancedField,
        if (!_advanced &&
            widget.value != null &&
            storefrontParseColor(widget.value) == null)
          Text(
            copy('appearanceHexInvalid'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class StorefrontColorPickerSheet extends StatefulWidget {
  const StorefrontColorPickerSheet({
    super.key,
    required this.title,
    required this.initialHex,
    required this.role,
    required this.sample,
    this.resetHex,
  });
  final String title;
  final String? initialHex, resetHex;
  final StorefrontColorRole role;
  final StorefrontColorSample sample;

  @override
  State<StorefrontColorPickerSheet> createState() => _PickerState();
}

class _PickerState extends State<StorefrontColorPickerSheet> {
  late HSVColor _hsv;
  late final Color _current;
  final _hex = TextEditingController();
  final _hexFocus = FocusNode();
  final _advancedKey = GlobalKey();
  bool _advanced = false, _inherited = false;
  String c(String key) =>
      storefrontContentCopy(AppLocalizations.of(context), key);

  @override
  void initState() {
    super.initState();
    _current =
        storefrontParseColor(widget.initialHex) ??
        widget.sample.color(widget.role);
    _hsv = HSVColor.fromColor(_current);
    _inherited = widget.initialHex == null && widget.resetHex == null;
    _hex.text = storefrontFormatColor(_current);
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();
  bool get _invalid => storefrontParseColor(_hex.text) == null;
  String? get _choice => _inherited ? null : storefrontFormatColor(_color);

  void _setHsv(HSVColor hsv, {bool inherited = false}) {
    setState(() {
      // Keep hue in HSV even at grey/black; RGB round trips lose it.
      _hsv = hsv;
      _inherited = inherited;
      final text = storefrontFormatColor(_color);
      _hex.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _restore() {
    final reset = storefrontParseColor(widget.resetHex);
    final inherited = widget.sample.withColor(widget.role, widget.resetHex);
    _setHsv(
      HSVColor.fromColor(reset ?? inherited.color(widget.role)),
      inherited: widget.resetHex == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    final theme = Theme.of(context);
    final sample = widget.sample.withColor(widget.role, _choice);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: (size.height * .85 - insets.bottom).clamp(180, 800),
          ),
          child: Column(
            key: const Key('storefront-color-picker'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _labeledSwatch('colorCurrent', _current),
                          ),
                          Expanded(child: _labeledSwatch('colorNew', _color)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        key: const Key('storefront-color-live-preview'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: sample.color(StorefrontColorRole.background),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              c('colorPreview'),
                              style: TextStyle(
                                color: sample.color(StorefrontColorRole.text),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: sample.color(StorefrontColorRole.accent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  c('colorPreviewButton'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: sample.color(
                                      StorefrontColorRole.buttonText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(c('colorField')),
                      const SizedBox(height: 8),
                      Center(
                        child: SizedBox(
                          width: size.height < 700 ? 168 : 228,
                          child: _SaturationValueField(
                            hsv: _hsv,
                            onChanged: _setHsv,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(c('colorHue')),
                      _HueRail(hsv: _hsv, onChanged: _setHsv),
                      TextButton(
                        key: const Key('storefront-color-restore'),
                        onPressed: _restore,
                        child: Text(
                          c(
                            widget.resetHex == null
                                ? 'colorInherit'
                                : 'colorRestore',
                          ),
                        ),
                      ),
                      if (_inherited)
                        Text(
                          c('colorInherited'),
                          key: const Key('storefront-color-inherited'),
                        ),
                      TextButton.icon(
                        key: const Key('storefront-color-advanced'),
                        onPressed: () {
                          setState(() => _advanced = !_advanced);
                          if (!_advanced) {
                            _hexFocus.unfocus();
                            _setHsv(_hsv, inherited: _inherited);
                          } else {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final target = _advancedKey.currentContext;
                              if (target != null)
                                Scrollable.ensureVisible(target);
                            });
                          }
                        },
                        icon: Icon(
                          _advanced ? Icons.expand_less : Icons.expand_more,
                        ),
                        label: Text(c('colorAdvanced')),
                      ),
                      if (_advanced)
                        Padding(
                          key: _advancedKey,
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            key: const Key('storefront-color-hex'),
                            controller: _hex,
                            focusNode: _hexFocus,
                            textDirection: TextDirection.ltr,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              label: const Text(
                                '#RRGGBB',
                                textDirection: TextDirection.ltr,
                              ),
                              errorText: _invalid
                                  ? c('appearanceHexInvalid')
                                  : null,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) => setState(() {
                              final parsed = storefrontParseColor(value);
                              if (parsed == null) return;
                              _inherited = false;
                              if (parsed.toARGB32() != _color.toARGB32()) {
                                _hsv = HSVColor.fromColor(parsed);
                              }
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const Key('storefront-color-apply'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: _invalid
                            ? null
                            : () => Navigator.of(
                                context,
                              ).pop(StorefrontColorChoice(_choice)),
                        child: Text(c('colorApply')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('storefront-color-cancel'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(88, 48),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(c('colorCancel')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledSwatch(String label, Color color) => Row(
    children: [
      _Swatch(key: Key('storefront-$label-swatch'), color: color),
      const SizedBox(width: 8),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c(label)),
            Text(
              storefrontFormatColor(color),
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}

/// The saturation (x) / value (y) field at the current hue.
class _KeyboardInstrument extends StatefulWidget {
  const _KeyboardInstrument({
    required this.hsv,
    required this.onChanged,
    required this.hueOnly,
    required this.child,
  });
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final bool hueOnly;
  final Widget child;
  @override
  State<_KeyboardInstrument> createState() => _KeyboardInstrumentState();
}

class _KeyboardInstrumentState extends State<_KeyboardInstrument> {
  bool _focused = false;
  late HSVColor _value = widget.hsv;

  @override
  void didUpdateWidget(covariant _KeyboardInstrument oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.hsv;
  }

  HSVColor _next(double horizontal, double vertical) {
    final hsv = _value;
    return widget.hueOnly
        ? hsv.withHue((hsv.hue + horizontal * 3 + vertical * 3).clamp(0, 360))
        : hsv
              .withSaturation((hsv.saturation + horizontal * .01).clamp(0, 1))
              .withValue((hsv.value + vertical * .01).clamp(0, 1));
  }

  void _adjust(double horizontal, double vertical) {
    // Two key events can arrive before the next frame. Accumulate both axes
    // against the latest value instead of overwriting the first adjustment.
    _value = _next(horizontal, vertical);
    widget.onChanged(_value);
  }

  String _describe(HSVColor hsv) => widget.hueOnly
      ? '${hsv.hue.round()}°'
      : '${(hsv.saturation * 100).round()}%, ${(hsv.value * 100).round()}%';

  @override
  Widget build(BuildContext context) => Focus(
    key: Key(
      widget.hueOnly
          ? 'storefront-color-hue-focus'
          : 'storefront-color-sv-focus',
    ),
    onFocusChange: (focused) => setState(() => _focused = focused),
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      // Physical direction matches the spatial paint in both LTR and RTL.
      if (key == LogicalKeyboardKey.arrowRight) {
        _adjust(1, 0);
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _adjust(-1, 0);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _adjust(0, 1);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _adjust(0, -1);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: Semantics(
      slider: true,
      value: _describe(widget.hsv),
      increasedValue: _describe(_next(1, 0)),
      decreasedValue: _describe(_next(-1, 0)),
      onIncrease: () => _adjust(1, 0),
      onDecrease: () => _adjust(-1, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            width: 3,
            color: _focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: widget.child),
      ),
    ),
  );
}

class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({required this.hsv, required this.onChanged});

  final HSVColor hsv;

  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 8;
        final height = width;
        void emit(Offset local) => onChanged(
          hsv
              .withSaturation((local.dx / width).clamp(0.0, 1.0))
              .withValue((1 - local.dy / height).clamp(0.0, 1.0)),
        );
        return Semantics(
          label: storefrontContentCopy(
            AppLocalizations.of(context),
            'colorField',
          ),
          child: _KeyboardInstrument(
            hsv: hsv,
            onChanged: onChanged,
            hueOnly: false,
            child: _EagerPanArea(
              onPoint: emit,
              child: SizedBox(
                key: const Key('storefront-color-sv-field'),
                width: width,
                height: height,
                // clipBehavior none so a marker parked on an edge is never
                // half-eaten by the rounded corner.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CustomPaint(
                        size: Size(width, height),
                        painter: _SvFieldPainter(hsv.hue),
                      ),
                    ),
                    Positioned(
                      // Physical left/top on purpose: a color field is a
                      // spatial instrument, not a text run — mirroring it in
                      // ar/he would move the marker away from the color.
                      left: hsv.saturation * width - _SelectionMarker.size / 2,
                      top: (1 - hsv.value) * height - _SelectionMarker.size / 2,
                      child: const _SelectionMarker(
                        key: Key('storefront-color-sv-marker'),
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
        final width = constraints.maxWidth - 8;
        void emit(Offset local) =>
            onChanged(hsv.withHue(((local.dx / width).clamp(0.0, 1.0)) * 360));
        return Semantics(
          label: storefrontContentCopy(
            AppLocalizations.of(context),
            'colorHue',
          ),
          child: _KeyboardInstrument(
            hsv: hsv,
            onChanged: onChanged,
            hueOnly: true,
            child: _EagerPanArea(
              onPoint: emit,
              // Padding inside the gesture area, not around it: the rail reads
              // as 28dp but the finger gets the full 44.
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  key: const Key('storefront-color-hue-rail'),
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
                        left: hsv.hue / 360 * width - _SelectionMarker.size / 2,
                        top: (_height - _SelectionMarker.size) / 2,
                        child: const _SelectionMarker(
                          key: Key('storefront-color-hue-marker'),
                        ),
                      ),
                    ],
                  ),
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

  /// Pinned, because both instruments centre the marker with `- size / 2`.
  /// Letting the rings decide the size drifts that centre off the colour the
  /// marker names (the nested border/padding measured 23dp, not 26).
  static const double size = 26;

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x8A000000), width: 1.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(1.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: Colors.white, width: 3),
            ),
          ),
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
