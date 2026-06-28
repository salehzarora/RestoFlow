/// A small, platform-agnostic model of a printable document (RF-118 fix).
///
/// Both the on-screen preview and the isolated browser print are built from a
/// [PrintDocument], so the printed page contains ONLY the receipt/ticket lines —
/// never the Flutter app canvas behind the modal. [documentToHtml] is a pure,
/// web-safe function (no `dart:html`) so it is unit-testable and can be rendered
/// into an isolated browser window. Money-free for kitchen tickets
/// (SECURITY T-003).
enum PrintLineKind { title, center, keyValue, item, sub, rule, note }

class PrintLine {
  PrintLine.title(this.left)
    : kind = PrintLineKind.title,
      right = null,
      emphasised = false;
  PrintLine.center(this.left)
    : kind = PrintLineKind.center,
      right = null,
      emphasised = false;
  PrintLine.kv(this.left, this.right, {this.emphasised = false})
    : kind = PrintLineKind.keyValue;
  PrintLine.item(this.left, this.right, {this.emphasised = false})
    : kind = PrintLineKind.item;
  PrintLine.sub(this.left)
    : kind = PrintLineKind.sub,
      right = null,
      emphasised = false;
  PrintLine.note(this.left)
    : kind = PrintLineKind.note,
      right = null,
      emphasised = false;
  PrintLine.rule()
    : kind = PrintLineKind.rule,
      left = null,
      right = null,
      emphasised = false;

  final PrintLineKind kind;
  final String? left;
  final String? right;
  final bool emphasised;
}

class PrintDocument {
  PrintDocument({required this.title, required this.lines});

  /// The print window/tab title (data, not chrome).
  final String title;
  final List<PrintLine> lines;
}

/// Escapes text for safe embedding in HTML (data values only — no scripts).
String _escape(String? raw) {
  if (raw == null) return '';
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

const String _css = '''
@page { margin: 10mm; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; color: #111;
  font-family: ui-monospace, 'Courier New', monospace; }
.paper { max-width: 320px; margin: 0 auto; padding: 8px; }
.t { text-align: center; font-weight: 800; font-size: 16px; margin-bottom: 4px; }
.c { text-align: center; font-weight: 700; margin: 2px 0; }
.kv, .it { display: flex; justify-content: space-between; gap: 8px;
  margin: 4px 0; font-size: 14px; }
.kv .b { font-weight: 800; }
.it .q { font-size: 22px; font-weight: 900; }
.s { font-size: 13px; color: #444; margin: 0 0 2px 14px; }
.n { text-align: center; font-size: 11px; color: #555; margin: 2px 0; }
.r { border-top: 1px dashed #999; margin: 6px 0; }
''';

/// Renders [doc] into a self-contained, print-friendly HTML page. The page
/// auto-focuses + prints itself on load and closes after printing, so the
/// browser print preview shows ONLY this document.
String documentToHtml(PrintDocument doc) {
  final body = StringBuffer();
  for (final line in doc.lines) {
    switch (line.kind) {
      case PrintLineKind.title:
        body.writeln('<div class="t">${_escape(line.left)}</div>');
      case PrintLineKind.center:
        body.writeln('<div class="c">${_escape(line.left)}</div>');
      case PrintLineKind.keyValue:
        body.writeln(
          '<div class="kv"><span>${_escape(line.left)}</span>'
          '<span class="${line.emphasised ? 'b' : ''}">'
          '${_escape(line.right)}</span></div>',
        );
      case PrintLineKind.item:
        body.writeln(
          '<div class="it"><span>${_escape(line.left)}</span>'
          '<span class="${line.emphasised ? 'q' : ''}">'
          '${_escape(line.right)}</span></div>',
        );
      case PrintLineKind.sub:
        body.writeln('<div class="s">${_escape(line.left)}</div>');
      case PrintLineKind.note:
        body.writeln('<div class="n">${_escape(line.left)}</div>');
      case PrintLineKind.rule:
        body.writeln('<div class="r"></div>');
    }
  }
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<title>${_escape(doc.title)}</title><style>$_css</style></head>'
      '<body><div class="paper">$body</div>'
      '<script>window.onload=function(){window.focus();window.print();};'
      'window.onafterprint=function(){window.close();};</script>'
      '</body></html>';
}
