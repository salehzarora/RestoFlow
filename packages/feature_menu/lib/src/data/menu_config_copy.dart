/// OPS-043 Phase 4 — "Copy settings from existing item".
///
/// The owner picks a source item and its CONFIGURATION is copied into the
/// editor as a LOCAL DRAFT: base price, Kitchen setup rows, modifier groups,
/// options, price deltas, selection rules and the kitchen-count / classifier
/// metadata. Nothing is written anywhere until the operator presses the normal
/// Save button (D7) — Apply performs ZERO writes, and cancelling leaves both
/// the source and the target exactly as they were.
///
/// IDENTITY IS NEVER COPIED (D6/D7): name, description, image, category, ids,
/// SKU, availability, tags, item type, analytics, legacy Sizes/Types and the
/// Phase-3 hidden attributes all stay with their own item. What is copied is
/// only the configuration the kitchen and the POS actually consume.
///
/// THE ID PROBLEM. `modifier_options.kitchen_meat.classifier_option_id` and
/// `attributes.prep_components[].classifier_option_id` point at ANOTHER OPTION
/// OF THE SAME ITEM (the Cheese option that splits the size option's meat
/// pieces). A copy that carried those ids verbatim would point the new item at
/// the SOURCE item's options — and `resolveTrustedMeatClassifier` /
/// `resolveTrustedPrepClassifiers` strip a foreign id on sight, so the split
/// would vanish silently, with no error and nothing on screen to notice. The
/// draft therefore keeps each option's SOURCE id ([CopiedOptionDraft.sourceOptionId])
/// purely as a remap key, and the flush below rewrites every classifier to the
/// NEW option's server-minted id once it exists. A source id must never reach a
/// target row, not even transiently: pass one writes the metadata WITHOUT
/// classifier keys, and pass two adds them back remapped.
library;

import 'package:restoflow_domain/restoflow_domain.dart';

import '../models/menu_item.dart';
import '../models/menu_snapshot.dart';
import '../models/menu_write_failure.dart';
import 'menu_writer.dart';

/// The wire keys of the classifier triple, shared by `kitchen_meat` and a
/// `prep_components` row (both are read by `KitchenMeat.tryFromJson` /
/// `KitchenPrepComponent.tryFromJson`, which type-check them strictly).
const String kCopyClassifierOptionIdKey = 'classifier_option_id';
const String kCopyClassifierOptionNameKey = 'classifier_option_name';

/// One modifier option in the copied draft.
///
/// [sourceOptionId] is bookkeeping, never data: it is the remap key that turns
/// a source classifier link into a target one, and it is never sent to any
/// writer. [createdId] is filled in as the flush creates the real row, so a
/// retry after a mid-save failure RESUMES instead of creating a second copy.
class CopiedOptionDraft {
  CopiedOptionDraft({
    required this.sourceOptionId,
    required this.name,
    required this.priceDeltaMinor,
    required this.displayOrder,
    required this.isActive,
    this.kitchenMeat,
  });

  /// The id of the option this one was copied from. NEVER persisted — the
  /// remap key only.
  final String sourceOptionId;

  final String name;
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;

  /// The copied kitchen-count metadata (`{quantity, unit}` plus, possibly, a
  /// classifier link that still names a SOURCE option). Null = no count.
  final Map<String, dynamic>? kitchenMeat;

  /// Set once the real row exists (its server-minted id).
  String? createdId;

  /// Set once the second pass has written this option's remapped classifier.
  bool classifierFlushed = false;

  /// The source option id this option's kitchen count is classified by, or ''.
  String get classifierSourceOptionId {
    final value = kitchenMeat?[kCopyClassifierOptionIdKey];
    return value is String ? value.trim() : '';
  }

  bool get carriesClassifier => classifierSourceOptionId.isNotEmpty;

  /// The metadata as written on the FIRST pass: the count itself, with every
  /// classifier key removed. A target row therefore never holds a source id,
  /// not even between the two passes.
  Map<String, dynamic>? get kitchenMeatWithoutClassifier {
    final meat = kitchenMeat;
    if (meat == null) return null;
    return <String, dynamic>{...meat}
      ..remove(kCopyClassifierOptionIdKey)
      ..remove(kCopyClassifierOptionNameKey);
  }

  /// The metadata as written on the SECOND pass: the same count, with the
  /// classifier pointing at the NEW option. An id with no entry in [remap]
  /// yields the unclassified form rather than a foreign link — the count is
  /// kept, the (unresolvable) split is not invented.
  Map<String, dynamic>? kitchenMeatRemapped(Map<String, String> remap) {
    final meat = kitchenMeat;
    if (meat == null) return null;
    final newId = remap[classifierSourceOptionId];
    if (newId == null || newId.isEmpty) return kitchenMeatWithoutClassifier;
    return <String, dynamic>{...meat, kCopyClassifierOptionIdKey: newId};
  }
}

/// One modifier group in the copied draft, with its options.
class CopiedGroupDraft {
  CopiedGroupDraft({
    required this.sourceModifierId,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.isRequired,
    required this.displayOrder,
    required this.isActive,
    required this.allowQuantity,
    required this.maxQuantity,
    required this.options,
  });

  /// Bookkeeping only — never persisted.
  final String sourceModifierId;

  final String name;
  final String selectionType;
  final int minSelect;
  final int? maxSelect;
  final bool isRequired;
  final int displayOrder;
  final bool isActive;
  final bool allowQuantity;
  final int? maxQuantity;
  final List<CopiedOptionDraft> options;

  /// Set once the real group row exists.
  String? createdId;
}

/// The whole copied configuration, held by the item editor until Save.
class MenuCopiedConfig {
  MenuCopiedConfig({
    required this.sourceItemId,
    required this.sourceItemName,
    required this.basePriceMinor,
    required this.currencyCode,
    required this.groups,
    required this.prepComponents,
  });

  /// The source, for the "Copied from X" summary and to exclude it from the
  /// picker. Purely presentational — the copy holds no live link to it, so
  /// editing the source afterwards changes nothing here.
  final String sourceItemId;
  final String sourceItemName;

  /// D5: the source's base price, prefilled into the editable price field.
  final int basePriceMinor;
  final String currencyCode;

  final List<CopiedGroupDraft> groups;

  /// Kitchen setup rows in WIRE shape (`{name, quantity, unit}` plus a
  /// classifier pair when the source had one). Their classifier ids are source
  /// ids and are remapped on the second pass, exactly like the options'.
  final List<Map<String, Object?>> prepComponents;

  int get groupCount => groups.length;

  int get optionCount =>
      groups.fold(0, (total, group) => total + group.options.length);

  int get kitchenCountOptionCount => groups.fold(
    0,
    (total, group) =>
        total + group.options.where((o) => o.kitchenMeat != null).length,
  );

  /// How many classifier links must be remapped on Save (options + prep rows).
  int get classifierLinkCount =>
      groups.fold(
        0,
        (total, group) =>
            total + group.options.where((o) => o.carriesClassifier).length,
      ) +
      prepComponents.where(rowCarriesCopyClassifier).length;

  bool get isEmpty => groups.isEmpty && prepComponents.isEmpty;

  /// Every option in flush order (groups in order, options in order).
  Iterable<({CopiedGroupDraft group, CopiedOptionDraft option})>
  get allOptions sync* {
    for (final group in groups) {
      for (final option in group.options) {
        yield (group: group, option: option);
      }
    }
  }

  /// The oldOptionId -> newOptionId map built from what the flush has created
  /// so far. Only options that really exist contribute an entry.
  Map<String, String> get remap => <String, String>{
    for (final entry in allOptions)
      if (entry.option.createdId != null)
        entry.option.sourceOptionId: entry.option.createdId!,
  };

  /// The copied name of the option a SOURCE id names, or null when the id names
  /// no option of this draft. Names are copied verbatim, so this is also the
  /// name the NEW option will carry — which is what a classifier label needs.
  String? optionNameBySourceId(String sourceOptionId) {
    if (sourceOptionId.isEmpty) return null;
    for (final entry in allOptions) {
      if (entry.option.sourceOptionId == sourceOptionId)
        return entry.option.name;
    }
    return null;
  }
}

/// Whether a wire `prep_components` row carries a classifier link.
bool rowCarriesCopyClassifier(Map<String, Object?> row) {
  final value = row[kCopyClassifierOptionIdKey];
  return value is String && value.trim().isNotEmpty;
}

/// Builds the draft from a source item and the loaded [snapshot].
///
/// TENANCY: the snapshot is the ALREADY-SCOPED read of the active
/// organization + restaurant (`MenuManagementRepository.load(scope)`), and this
/// function queries nothing — so a source outside the active restaurant is
/// unreachable here by construction, the same argument the classifier boundary
/// makes about option ids.
///
/// Classifier links are resolved against the SOURCE item's own options BEFORE
/// they are copied (`resolveTrustedMeatClassifier` /
/// `resolveTrustedPrepClassifiers`). A dangling or foreign link on the source is
/// therefore dropped here rather than copied into something unremappable: every
/// classifier id that survives into the draft is, by construction, the id of an
/// option that is also being copied — so the remap on Save is total.
MenuCopiedConfig buildMenuCopiedConfig({
  required MenuSnapshot snapshot,
  required MenuItem source,
}) {
  final groups = snapshot.modifiersForItem(source.id);
  final optionNamesById = <String, String>{
    for (final group in groups)
      for (final option in snapshot.optionsForModifier(group.id))
        option.id: option.name,
  };

  final copiedGroups = <CopiedGroupDraft>[
    for (final group in groups)
      CopiedGroupDraft(
        sourceModifierId: group.id,
        name: group.name,
        selectionType: group.selectionType,
        minSelect: group.minSelect,
        maxSelect: group.maxSelect,
        isRequired: group.isRequired,
        displayOrder: group.displayOrder,
        isActive: group.isActive,
        allowQuantity: group.allowQuantity,
        maxQuantity: group.maxQuantity,
        options: <CopiedOptionDraft>[
          for (final option in snapshot.optionsForModifier(group.id))
            CopiedOptionDraft(
              sourceOptionId: option.id,
              name: option.name,
              priceDeltaMinor: option.priceDeltaMinor,
              displayOrder: option.displayOrder,
              isActive: option.isActive,
              // Trust boundary FIRST: a link the source itself could not
              // justify is dropped now, so it can never become an unremappable
              // id on the copy.
              kitchenMeat: _meatToWire(
                resolveTrustedMeatClassifier(
                  KitchenMeat.tryFromJson(option.kitchenMeat),
                  optionNamesById: optionNamesById,
                  selfOptionId: option.id,
                ),
              ),
            ),
        ],
      ),
  ];

  final prepRows = <Map<String, Object?>>[
    for (final component in resolveTrustedPrepClassifiers(
      source.prepComponents,
      optionNamesById,
    ))
      component.toJson(),
  ];

  return MenuCopiedConfig(
    sourceItemId: source.id,
    sourceItemName: source.name,
    basePriceMinor: source.basePriceMinor,
    currencyCode: source.currencyCode,
    groups: copiedGroups,
    prepComponents: prepRows,
  );
}

Map<String, dynamic>? _meatToWire(KitchenMeat? meat) {
  if (meat == null) return null;
  return <String, dynamic>{...meat.toJson()};
}

/// Which step of the flush a failure happened in — so the operator is told
/// exactly how far the (deliberately NON-atomic) sequence got.
enum MenuCopyFlushStage { groups, options, classifiers, prepComponents }

/// The honest outcome of a flush attempt.
class MenuCopyFlushReport {
  const MenuCopyFlushReport({
    required this.ok,
    required this.groupsCreated,
    required this.optionsCreated,
    required this.classifiersLinked,
    this.failure,
    this.failedStage,
    this.failedEntityName,
  });

  final bool ok;
  final int groupsCreated;
  final int optionsCreated;
  final int classifiersLinked;

  /// Null on success.
  final MenuWriteFailure? failure;
  final MenuCopyFlushStage? failedStage;

  /// The name of the group/option the failure happened on, for the message.
  final String? failedEntityName;
}

/// The three writes the flush performs, isolated behind a seam so this pipeline
/// stays unit-testable and the data layer never reaches into Riverpod.
abstract class MenuCopyWriteSink {
  /// Creates ONE modifier group on the target item.
  Future<MenuWriteOutcome> createGroup(CopiedGroupDraft group);

  /// Creates ([id] null) or updates an option of [modifierId]. [kitchenMeat] is
  /// passed verbatim — the caller decides whether it carries a classifier.
  Future<MenuWriteOutcome> upsertOption({
    String? id,
    required String modifierId,
    required CopiedOptionDraft option,
    required Map<String, dynamic>? kitchenMeat,
  });

  /// Re-sends the target item's FULL state (the Phase-3 no-wipe payload — every
  /// other field carried through) with the Kitchen setup rows' classifier ids
  /// resolved through [remap].
  ///
  /// The PAYLOAD is built by the caller, not here, and from the rows the
  /// operator is actually looking at: the copied Kitchen setup lands in the
  /// ordinary editable prep card, so by the time Save runs the operator may
  /// have renamed a row, changed a quantity, added one or deleted one. Handing
  /// this pipeline a snapshot of the source's rows instead would quietly
  /// overwrite those edits with the original.
  Future<MenuWriteOutcome> rewritePrepClassifiers(Map<String, String> remap);
}

/// Persists a copied draft onto an ALREADY-CREATED target item.
///
/// NOT ATOMIC, and never pretends to be: the per-entity RPCs are the only write
/// path (D-031), so this is a sequence of ordinary calls that stops on the first
/// failure and reports exactly how far it got. Nothing is rolled back — saying
/// so is the honest behaviour the template apply established.
///
/// It IS resumable. Every created id is recorded on the draft, so pressing Save
/// again after a failure continues from where it stopped instead of creating a
/// second set of groups — the one thing a blind retry would get catastrophically
/// wrong.
///
/// Order (the classifier remap depends on it):
///  1. every group -> its new id;
///  2. every option, kitchen counts WITHOUT classifier keys -> its new id,
///     which completes the oldOptionId -> newOptionId map;
///  3. re-upsert the options whose count is classified, now with the NEW id;
///  4. rewrite the item's `prep_components` with the NEW ids.
///
/// Steps 3 and 4 run only when something is actually classified.
Future<MenuCopyFlushReport> flushMenuCopiedConfig({
  required MenuCopiedConfig config,
  required MenuCopyWriteSink sink,
  void Function(int done, int total)? onProgress,
}) async {
  var prepClassifiersWritten = false;
  var done = 0;
  final total = menuCopyFlushCallCount(config);

  void step() {
    done++;
    onProgress?.call(done, total);
  }

  // CUMULATIVE, not per-attempt. A resume after a failure creates only what was
  // still missing, so counting this call's writes would tell the operator
  // "copied 0 groups" at the exact moment the copy finally completed. What they
  // need is what EXISTS now, which is what the draft's created ids record.
  int groupsCreated() => config.groups.where((g) => g.createdId != null).length;
  int optionsCreated() =>
      config.allOptions.where((e) => e.option.createdId != null).length;
  int classifiersLinked() =>
      config.allOptions.where((e) => e.option.classifierFlushed).length +
      (prepClassifiersWritten
          ? config.prepComponents.where(rowCarriesCopyClassifier).length
          : 0);

  MenuCopyFlushReport fail(
    MenuCopyFlushStage stage,
    MenuWriteFailure failure,
    String name,
  ) => MenuCopyFlushReport(
    ok: false,
    groupsCreated: groupsCreated(),
    optionsCreated: optionsCreated(),
    classifiersLinked: classifiersLinked(),
    failure: failure,
    failedStage: stage,
    failedEntityName: name,
  );

  // 1. Groups.
  for (final group in config.groups) {
    if (group.createdId != null) continue;
    final outcome = await sink.createGroup(group);
    MenuWriteFailure? groupFailure;
    outcome.fold(
      (result) => group.createdId = result.id,
      (f) => groupFailure = f,
    );
    final failedGroup = groupFailure;
    if (failedGroup != null) {
      return fail(MenuCopyFlushStage.groups, failedGroup, group.name);
    }
    step();
  }

  // 2. Options — kitchen counts WITHOUT classifier keys, so no target row ever
  // holds a source id even if the run stops here.
  for (final entry in config.allOptions) {
    final option = entry.option;
    if (option.createdId != null) continue;
    final outcome = await sink.upsertOption(
      modifierId: entry.group.createdId!,
      option: option,
      kitchenMeat: option.kitchenMeatWithoutClassifier,
    );
    MenuWriteFailure? optionFailure;
    outcome.fold(
      (result) => option.createdId = result.id,
      (f) => optionFailure = f,
    );
    final failedOption = optionFailure;
    if (failedOption != null) {
      return fail(MenuCopyFlushStage.options, failedOption, option.name);
    }
    step();
  }

  // 3. Second pass: the classifier links, now resolvable.
  final remap = config.remap;
  for (final entry in config.allOptions) {
    final option = entry.option;
    if (!option.carriesClassifier || option.classifierFlushed) continue;
    final outcome = await sink.upsertOption(
      id: option.createdId,
      modifierId: entry.group.createdId!,
      option: option,
      kitchenMeat: option.kitchenMeatRemapped(remap),
    );
    MenuWriteFailure? linkFailure;
    outcome.fold(
      (_) => option.classifierFlushed = true,
      (f) => linkFailure = f,
    );
    final failedLink = linkFailure;
    if (failedLink != null) {
      return fail(MenuCopyFlushStage.classifiers, failedLink, option.name);
    }
    step();
  }

  // 4. The item's own prep rows, with their classifier ids remapped.
  if (config.prepComponents.any(rowCarriesCopyClassifier)) {
    final outcome = await sink.rewritePrepClassifiers(remap);
    MenuWriteFailure? prepFailure;
    outcome.fold((_) {}, (f) => prepFailure = f);
    final failedPrep = prepFailure;
    if (failedPrep != null) {
      return fail(
        MenuCopyFlushStage.prepComponents,
        failedPrep,
        config.sourceItemName,
      );
    }
    prepClassifiersWritten = true;
    step();
  }

  return MenuCopyFlushReport(
    ok: true,
    groupsCreated: groupsCreated(),
    optionsCreated: optionsCreated(),
    classifiersLinked: classifiersLinked(),
  );
}

/// How many writes a full flush of [config] performs (for the progress note).
int menuCopyFlushCallCount(MenuCopiedConfig config) {
  var calls = config.groupCount + config.optionCount;
  calls += config.allOptions.where((e) => e.option.carriesClassifier).length;
  if (config.prepComponents.any(rowCarriesCopyClassifier)) calls++;
  return calls;
}

/// Rewrites `prep_components` classifier ids through [remap].
///
/// A row whose id has no mapping loses its classifier PAIR entirely rather than
/// keeping a foreign id — the resource keeps its ordinary unsplit line, which is
/// exactly what the trust boundary would have forced at read time anyway.
List<Map<String, Object?>> remapPrepComponents(
  List<Map<String, Object?>> rows,
  Map<String, String> remap,
) {
  final out = <Map<String, Object?>>[];
  for (final row in rows) {
    final copy = Map<String, Object?>.of(row);
    if (!rowCarriesCopyClassifier(row)) {
      out.add(copy);
      continue;
    }
    final oldId = (row[kCopyClassifierOptionIdKey]! as String).trim();
    final newId = remap[oldId];
    if (newId == null || newId.isEmpty) {
      copy
        ..remove(kCopyClassifierOptionIdKey)
        ..remove(kCopyClassifierOptionNameKey);
    } else {
      copy[kCopyClassifierOptionIdKey] = newId;
    }
    out.add(copy);
  }
  return out;
}
