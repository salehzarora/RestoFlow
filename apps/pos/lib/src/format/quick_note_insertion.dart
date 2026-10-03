/// POS-QUICK-NOTES-124 — the one place that decides how a quick-note phrase is
/// joined onto the item note.
///
/// The rules live here, not in the sheet, because they are the part that can be
/// got subtly wrong: the composed note is ORDINARY TEXT, so it must be exactly
/// what a careful person would have typed. There is no preset id, no marker
/// token and no hidden metadata in it.
///
/// POS-QUICK-NOTE-CHIPS-001: a tap no longer writes into the field. The sheet
/// keeps tapped phrases as removable chips, and when it confirms it folds them
/// onto the typed text with THIS function (`composeQuickNote`), so the note is
/// byte-identical to typing that text and then tapping the same chips under
/// the pre-chip sheet. Whether a chip may be added is decided against the same
/// 140-character contract (`canAddQuickNote`).
///
/// Two consequences are deliberate:
///
///  * **No truncation, ever.** A programmatic write bypasses the field's own
///    `maxLength`, so the candidate is measured against the SAME 140-character
///    contract before it is applied. A preset that would not fit is REFUSED
///    whole. Half a note ("no onions, extra cri") reaches the kitchen as an
///    instruction, and a cut-off instruction is worse than none.
///  * **No duplicate detection.** This function appends twice if asked twice.
///    Preset text may itself contain commas and line breaks, so any "is it
///    already there?" heuristic on TEXT would be unreliable exactly when it
///    mattered; a plain, predictable append is safer than a clever one. (The
///    sheet now prevents adding the same preset twice by its id, which needs
///    no text heuristic.)
library;

/// The note contract shared by the POS item-note field and every quick-note
/// insertion. A chip may never produce a note the cashier could not have typed.
const int kPosItemNoteMaxLength = 140;

/// Trailing punctuation after which a `, ` separator would read as doubled
/// (`No onions,, Extra crispy`). Arabic comma/semicolon are included because
/// tenant preset text is ar/he/en (D-014) and a cashier typing Arabic ends a
/// clause with `،`, not `,`.
const Set<String> _clauseEnders = <String>{',', '،', ';', '؛'};

/// The canonical separator between two notes on one line.
const String _separator = ', ';

/// What joining one phrase onto a note produces, or why it was refused.
class QuickNoteInsertion {
  const QuickNoteInsertion._(this.text, this.refusedForLength);

  /// The phrase joins to give [text], verbatim.
  const QuickNoteInsertion.applied(String text) : this._(text, false);

  /// Refused: the composed note would exceed the length limit. Nothing is
  /// joined and nothing is trimmed.
  const QuickNoteInsertion.refused() : this._(null, true);

  /// The exact composed text, or null when [refusedForLength].
  final String? text;

  /// True when the only reason nothing happened is the length contract.
  final bool refusedForLength;

  bool get isApplied => text != null;
}

/// Composes [presetText] onto [currentText] under the rules in the library doc.
///
/// [currentText] is the note so far — the cashier's typed text with any earlier
/// phrases already joined on (see `composeQuickNote`) — taken verbatim: its
/// internal spacing, casing and punctuation are the cashier's and are never
/// normalized. Only the trailing whitespace run is inspected, to decide the
/// separator.
///
/// [presetText] is trimmed on the outside only: the server already stores it
/// that way, so trimming here just makes a malformed row harmless rather than
/// pasting stray spaces into a kitchen instruction.
QuickNoteInsertion buildQuickNoteInsertion(
  String currentText,
  String presetText, {
  int maxLength = kPosItemNoteMaxLength,
}) {
  final preset = presetText.trim();
  if (preset.isEmpty) {
    // Nothing to add. Not a refusal — the note is simply unchanged.
    return QuickNoteInsertion.applied(currentText);
  }

  // The text without its trailing whitespace run, and the run itself. Splitting
  // here (rather than trimming outright) is what lets a deliberate line break
  // survive: "No onions\n" + "Extra crispy" must stay on two lines.
  final core = currentText.replaceFirst(RegExp(r'\s+$'), '');
  final trailing = currentText.substring(core.length);

  final String candidate;
  if (core.isEmpty) {
    // Empty or whitespace-only: the preset IS the note. Any whitespace the
    // cashier left behind is not content.
    candidate = preset;
  } else if (trailing.contains('\n')) {
    // The cashier ended a line on purpose. Keep their break exactly and start
    // the preset on the new line — no comma, no extra space.
    candidate = '$currentText$preset';
  } else if (_clauseEnders.contains(core[core.length - 1])) {
    // They already punctuated the clause. Honour THEIR mark and add exactly one
    // space, rather than appending a second separator after it.
    candidate = '$core $preset';
  } else {
    candidate = '$core$_separator$preset';
  }

  if (candidate.length > maxLength) return const QuickNoteInsertion.refused();
  return QuickNoteInsertion.applied(candidate);
}
