/// PRINT-LAYOUT-001 — a typed print MEDIA profile.
///
/// It replaces the scattered hardcoded `576` / `48 columns` / `feed 3` constants
/// (which forced every printer onto 80mm output regardless of the real media)
/// with ONE typed value threaded per printer endpoint. The raster/ESC-POS
/// pipeline reads geometry + typography from here so a 50mm label renders at its
/// real width and paginates to its real height instead of overrunning.
///
/// Three profiles ship:
///  * [continuous80] — the BACKWARD-COMPATIBLE default (an 80mm CONTINUOUS roll):
///    576 dots wide, 48 columns, NO pagination, feed 3, scale 1.0, no margins.
///    Any endpoint with no explicit selection resolves to this, so existing
///    installs stay byte-identical.
///  * [label50x50] / [label80x80] — FIXED square thermal labels. Both paginate to
///    the label height so content never runs off the bottom, and both carry safe
///    top/bottom/side margins. 80×80 uses its extra room for larger type; 50×50
///    prioritizes legibility with compact spacing.
enum MediaProfileId { continuous80, label50x50, label80x80 }

class MediaProfile {
  const MediaProfile({
    required this.id,
    required this.widthDots,
    required this.columns,
    required this.mediaHeightDots,
    this.safeLeftDots = 0,
    this.safeRightDots = 0,
    this.safeTopDots = 0,
    this.safeBottomDots = 0,
    this.fontScale = 1.0,
    this.lineSpacing = 1.3,
    this.feedLines = 3,
  }) : assert(widthDots > 0 && widthDots % 8 == 0, 'widthDots must be a positive multiple of 8'),
       assert(mediaHeightDots >= 0),
       assert(columns > 0),
       assert(safeLeftDots >= 0 && safeRightDots >= 0),
       assert(safeTopDots >= 0 && safeBottomDots >= 0),
       assert(fontScale > 0),
       assert(lineSpacing > 0),
       assert(feedLines >= 0),
       assert(
         safeLeftDots + safeRightDots < widthDots,
         'side margins must leave printable width',
       );

  /// Stable identity — also the persisted key (see [idKey] / [fromId]).
  final MediaProfileId id;

  /// The printable RASTER width in dots (a multiple of 8). The generated bitmap
  /// is exactly this wide — never an 80mm canvas scaled down for a narrow head.
  final int widthDots;

  /// ESC/POS monospace text columns for the ASCII text path.
  final int columns;

  /// Physical printable HEIGHT in dots. `0` == a continuous roll (no page bound;
  /// never paginates). A positive value == a fixed medium that must paginate.
  final int mediaHeightDots;

  final int safeLeftDots;
  final int safeRightDots;
  final int safeTopDots;
  final int safeBottomDots;

  /// Multiplier applied to the base font size (80×80 uses its extra room).
  final double fontScale;

  /// Line-height multiplier (compact for 50×50, roomier for 80×80).
  final double lineSpacing;

  /// Line feeds emitted before the cut (a fixed medium ejects less than a roll).
  final int feedLines;

  /// True when this is a FIXED-size medium that must paginate to [mediaHeightDots].
  bool get paginates => mediaHeightDots > 0;

  /// Bytes per raster row (`ceil(widthDots / 8)`).
  int get widthBytes => (widthDots + 7) ~/ 8;

  /// The printable width in dots between the safe left/right margins.
  int get printableWidthDots => widthDots - safeLeftDots - safeRightDots;

  /// The printable height in dots between the safe top/bottom margins; `0` when
  /// continuous (no page bound).
  int get printableHeightDots =>
      paginates ? mediaHeightDots - safeTopDots - safeBottomDots : 0;

  /// The BACKWARD-COMPATIBLE default: an 80mm continuous roll — 576 dots, 48
  /// columns, feed 3, no pagination, no margins, scale 1.0. Byte-identical to the
  /// pre-PRINT-LAYOUT-001 output, so an unconfigured endpoint never changes.
  static const MediaProfile continuous80 = MediaProfile(
    id: MediaProfileId.continuous80,
    widthDots: 576,
    columns: 48,
    mediaHeightDots: 0,
  );

  /// 80mm × 80mm fixed label (80mm @ 8 dots/mm = 640). Uses the extra room for a
  /// clearer hierarchy (larger type) and paginates so nothing runs off the label.
  static const MediaProfile label80x80 = MediaProfile(
    id: MediaProfileId.label80x80,
    widthDots: 576,
    columns: 48,
    mediaHeightDots: 640,
    safeLeftDots: 8,
    safeRightDots: 8,
    safeTopDots: 16,
    safeBottomDots: 24,
    fontScale: 1.12,
    lineSpacing: 1.36,
    feedLines: 2,
  );

  /// 50mm × 50mm fixed label (50mm @ 8 dots/mm = 400). Uses the established narrow
  /// head width (384 dots = 48mm printable, a proven multiple of 8) — legibility
  /// over decoration, compact readable spacing, paginated (never clipped).
  static const MediaProfile label50x50 = MediaProfile(
    id: MediaProfileId.label50x50,
    widthDots: 384,
    columns: 32,
    mediaHeightDots: 400,
    safeLeftDots: 8,
    safeRightDots: 8,
    safeTopDots: 12,
    safeBottomDots: 20,
    fontScale: 1.0,
    lineSpacing: 1.26,
    feedLines: 2,
  );

  /// The two operator-selectable fixed labels (the settings dropdown). The
  /// continuous-80 default is the resolved fallback, not a manual selection.
  static const List<MediaProfile> selectable = <MediaProfile>[
    label50x50,
    label80x80,
  ];

  /// Every known profile, including the continuous default.
  static const List<MediaProfile> all = <MediaProfile>[
    continuous80,
    label50x50,
    label80x80,
  ];

  /// The persisted key for this profile.
  String get idKey => id.name;

  /// Resolve a persisted key to a profile. An unknown or absent key resolves to
  /// the BACKWARD-COMPATIBLE [continuous80] default — a saved config that predates
  /// media profiles keeps its exact prior output.
  static MediaProfile fromId(String? id) {
    switch (id) {
      case 'label50x50':
        return label50x50;
      case 'label80x80':
        return label80x80;
      case 'continuous80':
        return continuous80;
      default:
        return continuous80;
    }
  }
}
