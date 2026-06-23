import 'dart:convert';
import 'dart:typed_data';

import '../print_document.dart';

/// Deterministic JSON (de)serialization for the RF-070 [PrintDocument] (RF-071).
///
/// The spool persists the RENDER-NEUTRAL document (A4), not raw ESC/POS bytes,
/// so it can re-render via the RF-070 adapter at print time (e.g. a reconciled
/// receipt number, PRINTERS §12). Round-trip preserves rendering exactly. The
/// raster payload is carried as base64; its dimensions are validated on decode.
class PrintDocumentCodec {
  const PrintDocumentCodec();

  /// Encode to a compact, deterministic JSON string.
  String encode(PrintDocument document) => jsonEncode(toMap(document));

  /// Decode from a JSON string produced by [encode].
  PrintDocument decode(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const FormatException('PrintDocument JSON must be an object');
    }
    return fromMap(decoded.map((k, v) => MapEntry(k.toString(), v)));
  }

  Map<String, dynamic> toMap(PrintDocument document) => {
    'localeTag': document.localeTag,
    'lines': document.lines.map(_lineToMap).toList(),
  };

  PrintDocument fromMap(Map<String, dynamic> map) {
    final rawLines = map['lines'];
    if (rawLines is! List) {
      throw const FormatException('PrintDocument.lines must be an array');
    }
    final lines = <PrintLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) {
        throw const FormatException('each print line must be an object');
      }
      lines.add(_lineFromMap(raw.map((k, v) => MapEntry(k.toString(), v))));
    }
    final locale = map['localeTag'];
    return PrintDocument(lines, localeTag: locale is String ? locale : null);
  }

  Map<String, dynamic> _lineToMap(PrintLine line) {
    switch (line) {
      case PrintTextLine():
        return {
          'type': 'text',
          'text': line.text,
          'alignment': line.alignment.name,
          'emphasis': line.emphasis.name,
          'direction': line.direction.name,
        };
      case PrintFeedLine():
        return {'type': 'feed', 'lines': line.lines};
      case PrintCutLine():
        return {'type': 'cut'};
      case PrintDrawerKickLine():
        return {'type': 'drawerKick'};
      case PrintRasterImageLine():
        return {
          'type': 'raster',
          'data': base64Encode(line.data),
          'widthBytes': line.widthBytes,
          'heightDots': line.heightDots,
        };
    }
  }

  PrintLine _lineFromMap(Map<String, dynamic> map) {
    final type = map['type'];
    switch (type) {
      case 'text':
        return PrintTextLine(
          map['text'] is String ? map['text'] as String : '',
          alignment: _enumByName(
            PrintAlignment.values,
            map['alignment'],
            PrintAlignment.left,
          ),
          emphasis: _enumByName(
            TextEmphasis.values,
            map['emphasis'],
            TextEmphasis.normal,
          ),
          direction: _enumByName(
            PrintTextDirection.values,
            map['direction'],
            PrintTextDirection.ltr,
          ),
        );
      case 'feed':
        final n = map['lines'];
        return PrintFeedLine(n is int ? n : 1);
      case 'cut':
        return const PrintCutLine();
      case 'drawerKick':
        return const PrintDrawerKickLine();
      case 'raster':
        final data = base64Decode(map['data'] as String);
        final widthBytes = map['widthBytes'];
        final heightDots = map['heightDots'];
        if (widthBytes is! int || heightDots is! int) {
          throw const FormatException('raster width/height must be integers');
        }
        if (widthBytes <= 0 || heightDots <= 0) {
          throw const FormatException('raster dimensions must be positive');
        }
        if (data.length != widthBytes * heightDots) {
          throw const FormatException(
            'raster data length must equal widthBytes * heightDots',
          );
        }
        return PrintRasterImageLine(
          data: Uint8List.fromList(data),
          widthBytes: widthBytes,
          heightDots: heightDots,
        );
      default:
        throw FormatException('unknown print line type: $type');
    }
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
