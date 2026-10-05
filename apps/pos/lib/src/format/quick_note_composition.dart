/// POS-QUICK-NOTE-CHIPS-001 — removable quick-note chips, one plain note.
///
/// Since this ticket a quick-note tap no longer writes into the item-note
/// field. The options sheet keeps the tapped presets as removable chips and the
/// field keeps only what the cashier typed. The note the sheet hands the cart
/// is still ONE plain string, built here when the sheet confirms:
///
///   the typed text first, then each chip label in tap order, folded with the
///   UNCHANGED [buildQuickNoteInsertion].
///
/// That fold is exactly what the field held before this ticket after the
/// cashier typed the same text and then tapped the same chips, so separators,
/// Arabic and Latin clause enders, a kept line break and trim-to-null are the
/// same bytes the receipt, kitchen ticket, KDS and sync payload always got. No
/// preset id, marker or structure ever leaves the sheet: downstream nothing
/// parses a note, so anything else would print literally.
///
/// The functions here are pure (no Flutter), so every rule is pinned by plain
/// tests.
library;

import 'quick_note_insertion.dart';

/// A cap the fold can never reach. Composition only folds; whether a chip may
/// be added is decided up front by [canAddQuickNote] against the real limit.
const int _uncapped = 1 << 30;

/// The widest separator the fold can put between the typed text and the first
/// chip (`', '`). Reserving it keeps the typed text's own budget exact without
/// knowing what the cashier will type next.
const int _separatorReserve = 2;

/// The confirmed note before trimming: [freeText] (the field, verbatim) with
/// every label in [labels] folded on in order.
///
/// With no labels the result IS [freeText], so a sheet without chips returns
/// exactly what it returned before this ticket. A blank label adds nothing,
/// as a blank preset always has.
String composeQuickNote(String freeText, List<String> labels) {
  var acc = freeText;
  for (final label in labels) {
    acc = buildQuickNoteInsertion(acc, label, maxLength: _uncapped).text!;
  }
  return acc;
}

/// How many characters the cashier may still type while [labels] are chips.
///
/// No chips leaves the whole [maxLength], so the field is configured exactly
/// as before this ticket. With chips the separator in front of the first chip
/// is reserved, which guarantees `composeQuickNote(F, labels).length <=
/// maxLength` for any `F.length <= budget`: the fold adds at most that
/// separator in front of `composeQuickNote('', labels)`.
///
/// May be zero or negative for a label set that leaves no room; callers never
/// let that set exist (see [canAddQuickNote] and [splitTrailingQuickNotes]).
int quickNoteFreeTextBudget(
  List<String> labels, {
  int maxLength = kPosItemNoteMaxLength,
}) {
  final chips = composeQuickNote('', labels);
  if (chips.isEmpty) return maxLength;
  return maxLength - _separatorReserve - chips.length;
}

/// Whether [newLabel] may join [labels] as a chip while the field holds
/// [freeText]. A refusal is whole, like the pre-chip tap: nothing is added and
/// nothing is truncated.
///
/// All three must hold:
///  * the composed note stays within [maxLength] (the pre-chip measure);
///  * at least one character of typing room is left (a text field cannot be
///    given a zero length limit);
///  * the text already typed fits the new, smaller typing budget, so the field
///    is never put over its own limit.
///
/// The last two make this up to two characters stricter than the pre-chip
/// tap: the typing budget always reserves the widest separator, so a tap whose
/// note would still just fit (typed text ending in a space, a comma or a line
/// break, which take a narrower separator) can be refused, and chips alone
/// stop at 137 characters. That is the price of one fixed field limit, which
/// lets Flutter's own limiter handle every keyboard's composing text.
bool canAddQuickNote({
  required String freeText,
  required List<String> labels,
  required String newLabel,
  int maxLength = kPosItemNoteMaxLength,
}) {
  final next = <String>[...labels, newLabel];
  if (composeQuickNote(freeText, next).length > maxLength) return false;
  final budget = quickNoteFreeTextBudget(next, maxLength: maxLength);
  if (budget < 1) return false;
  return freeText.length <= budget;
}

/// Splits a stored note back into typed text and chips when a cart line is
/// reopened, so a phrase added by mistake can still be removed in one tap.
///
/// Only phrases at the END of [note] that EXACTLY (case-sensitively) equal a
/// current label come back as chips, each label at most once, and only when
/// recomposing gives back [note] byte for byte. Anything else — a renamed or
/// deleted preset, a phrase typed in another case, a phrase in the middle, a
/// note that would not fit the typing budget — stays plain text, which is the
/// pre-chip behaviour. Saving a reopened line untouched therefore never
/// changes its note.
///
/// Longer labels are tried first, so `Sauce, on side` wins over `on side`.
/// Returns indexes into [labels], in note order.
({String freeText, List<int> labelIndexes}) splitTrailingQuickNotes(
  String note,
  List<String> labels, {
  int maxLength = kPosItemNoteMaxLength,
}) {
  final unchanged = (freeText: note, labelIndexes: const <int>[]);
  if (note.isEmpty || labels.isEmpty || note.length > maxLength) {
    return unchanged;
  }

  final candidates =
      <int>[
        for (var i = 0; i < labels.length; i++)
          if (labels[i].trim().isNotEmpty) i,
      ]..sort((a, b) {
        final ta = labels[a].trim();
        final tb = labels[b].trim();
        final byLength = tb.length.compareTo(ta.length);
        if (byLength != 0) return byLength;
        final byText = ta.compareTo(tb);
        if (byText != 0) return byText;
        return a.compareTo(b);
      });

  var rest = note;
  final taken = <int>[];
  final takenTexts = <String>{};
  var progressed = true;
  while (rest.isNotEmpty && progressed) {
    progressed = false;
    for (final i in candidates) {
      final text = labels[i].trim();
      if (takenTexts.contains(text) || !rest.endsWith(text)) continue;
      final head = rest.substring(0, rest.length - text.length);
      final previous = _statesBefore(head).where(
        (p) =>
            buildQuickNoteInsertion(p, text, maxLength: _uncapped).text == rest,
      );
      if (previous.isEmpty) continue;
      taken.insert(0, i);
      takenTexts.add(text);
      rest = previous.first;
      progressed = true;
      break;
    }
  }

  if (taken.isEmpty) return unchanged;
  final takenLabels = <String>[for (final i in taken) labels[i]];
  if (composeQuickNote(rest, takenLabels) != note) return unchanged;
  final budget = quickNoteFreeTextBudget(takenLabels, maxLength: maxLength);
  if (budget < 1 || rest.length > budget) return unchanged;
  return (freeText: rest, labelIndexes: List<int>.unmodifiable(taken));
}

/// The texts the field could have held just before a label was folded on,
/// leaving [head] in front of it. Each is only a candidate: the caller keeps
/// one only if folding the label onto it reproduces the note exactly.
Iterable<String> _statesBefore(String head) sync* {
  if (head.isEmpty) {
    yield '';
    return;
  }
  final core = head.replaceFirst(RegExp(r'\s+$'), '');
  if (core.isNotEmpty && head.substring(core.length).contains('\n')) {
    yield head;
  }
  if (head.endsWith(', ')) {
    yield head.substring(0, head.length - 2);
  }
  if (head.endsWith(' ')) {
    yield head.substring(0, head.length - 1);
  }
}
