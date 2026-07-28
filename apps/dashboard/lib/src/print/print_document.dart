/// A small, platform-agnostic model of a printable document (ORDERS-HISTORY-001).
///
/// Dashboard-local copy of the POS/KDS print model so the Dashboard reprint
/// center can render a receipt / kitchen-ticket PREVIEW and print it from the
/// browser WITHOUT depending on the POS/KDS apps (the Dashboard has no hardware
/// print path — real hardware reprint stays a POS/KDS paired-device capability).
/// Both the on-screen preview and the isolated browser print are built from a
/// [PrintDocument], so the printed page contains ONLY the receipt/ticket lines —
/// never the Flutter app canvas behind the modal. [documentToHtml] is a pure,
/// web-safe function (no `dart:html`) so it is unit-testable. No money is
/// invented here — values are passed in already formatted (and the kitchen
/// ticket carries no money at all).
enum PrintLineKind {
  title,
  center,
  keyValue,
  item,
  sub,
  rule,
  note,
  headerImage,
}

class PrintLine {
  PrintLine.title(this.left)
    : kind = PrintLineKind.title,
      right = null,
      emphasised = false,
      imageUrl = null;
  PrintLine.center(this.left)
    : kind = PrintLineKind.center,
      right = null,
      emphasised = false,
      imageUrl = null;
  PrintLine.kv(this.left, this.right, {this.emphasised = false})
    : kind = PrintLineKind.keyValue,
      imageUrl = null;
  PrintLine.item(this.left, this.right, {this.emphasised = false})
    : kind = PrintLineKind.item,
      imageUrl = null;
  PrintLine.sub(this.left)
    : kind = PrintLineKind.sub,
      right = null,
      emphasised = false,
      imageUrl = null;
  PrintLine.note(this.left)
    : kind = PrintLineKind.note,
      right = null,
      emphasised = false,
      imageUrl = null;
  PrintLine.rule()
    : kind = PrintLineKind.rule,
      left = null,
      right = null,
      emphasised = false,
      imageUrl = null;
  // PRINT-BRANDING-LOGO-001: a centered customer-receipt logo (browser <img>
  // from a transient signed URL — never persisted). Customer-receipt only; the
  // kitchen-ticket builder never emits it.
  PrintLine.headerImage(this.imageUrl)
    : kind = PrintLineKind.headerImage,
      left = null,
      right = null,
      emphasised = false;

  final PrintLineKind kind;
  final String? left;
  final String? right;
  final bool emphasised;

  /// PRINT-BRANDING-LOGO-001: the logo image URL for a [headerImage] line.
  final String? imageUrl;
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
.paper { max-width: 300px; margin: 0 auto; padding: 8px; }
.t { text-align: center; font-weight: 800; font-size: 15px; margin-bottom: 4px; }
.c { text-align: center; font-weight: 700; margin: 2px 0; }
.kv, .it { display: flex; justify-content: space-between; gap: 8px;
  margin: 2px 0; font-size: 13px; }
.kv .b { font-weight: 800; }
.it .q { font-size: 18px; font-weight: 900; }
.s { font-size: 12px; color: #444; margin: 0 0 2px 14px; }
.n { text-align: center; font-size: 11px; color: #555; margin: 2px 0; }
.r { border-top: 1px dashed #999; margin: 6px 0; }
.logo { text-align: center; margin: 2px 0 6px; }
.logo img { display: inline-block; max-width: 60%; max-height: 120px;
  height: auto; width: auto; }
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
      case PrintLineKind.headerImage:
        final url = line.imageUrl;
        if (url != null && url.isNotEmpty) {
          // PRINT-BRANDING-LOGO-001 (§9): the signed URL may fail to download or
          // decode in the browser AFTER the HTML is issued. A fixed, escaped
          // onerror removes the WHOLE .logo wrapper (image + its reserved
          // vertical spacing) so no broken-image icon or blank gap remains — the
          // title then becomes the first visible header. Not generic script exec.
          body.writeln(
            '<div class="logo"><img alt="" src="${_escape(url)}"$_logoOnError />'
            '</div>',
          );
        }
    }
  }
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<title>${_escape(doc.title)}</title><style>$_css</style></head>'
      '<body><div class="paper">$body</div>'
      '<script>$_logoSweepAndPrintJs</script>'
      '</body></html>';
}

/// PRINT-BRANDING-LOGO-001 (§9): a FIXED (no interpolation → no injection) image
/// error handler that removes the entire `.logo` wrapper when the browser fails
/// to load/decode the receipt logo, leaving text-only output with no blank gap.
const String _logoOnError =
    ' onerror="var w=this.parentNode;'
    'if(w&&w.parentNode){w.parentNode.removeChild(w);}"';

/// Before printing, sweep any `.logo` whose image failed to render
/// (`naturalWidth===0`, e.g. an error that beat the inline handler) and remove
/// the wrapper, so a broken image + its spacing never reach the printed page.
const String _logoSweepAndPrintJs =
    'window.onload=function(){'
    'var ls=document.querySelectorAll(".logo");'
    'for(var i=0;i<ls.length;i++){var im=ls[i].querySelector("img");'
    'if(!im||im.naturalWidth===0){'
    'if(ls[i].parentNode){ls[i].parentNode.removeChild(ls[i]);}}}'
    'window.focus();window.print();};'
    'window.onafterprint=function(){window.close();};';
