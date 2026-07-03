import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/modifier_templates.dart';
import '../models/menu_write_failure.dart';
import '../state/menu_providers.dart';
import 'menu_l10n.dart';

/// The one-line picker summary for a [template]: its selection shape
/// ("Required · choose 1" / "Optional · multi-select" / "Optional · choose up
/// to 1") joined with the option count.
String _summaryOf(AppLocalizations l10n, ModifierTemplate template) {
  final String shape;
  if (template.selectionType == 'multiple') {
    shape = l10n.menuTemplateOptionalMulti;
  } else if (template.isRequired) {
    shape = l10n.menuTemplateRequiredSingle;
  } else {
    shape = l10n.menuTemplateOptionalSingle;
  }
  return '$shape · ${l10n.menuTemplateOptionCount(template.options.length)}';
}

/// Opens the modifier template picker for the item being edited and, when the
/// owner picks one, APPLIES it: creates one modifier group + its options
/// through the SAME write path the manual forms use (copy-on-attach over the
/// existing per-item RPCs — frozen D-031 stays intact; demo store and real RPC
/// writer both work). The created rows are ordinary per-item modifiers the
/// owner edits/deletes with the existing UI.
///
/// Group/option NAMES are resolved from the CALLER's l10n at apply time and
/// inserted as tenant DATA in the active locale (an Arabic-default dashboard
/// seeds Arabic names).
///
/// Failure handling is honest: the writes run sequentially and STOP on the
/// first failure, surfacing the existing localized failure message. There is
/// no rollback pretense — rows created before the failure remain visible for
/// manual cleanup, and the snackbar says so (menuTemplateApplyPartial).
Future<void> showModifierTemplatePicker(
  BuildContext context, {
  required String menuItemId,
}) async {
  // The write controller MUST be read from the CALLER's context: showDialog
  // builds under the ROOT navigator, ABOVE the menu feature's nested
  // ProviderScope, where the menu seams throw UnimplementedError (the
  // documented real-mode "Save stuck forever" regression — see
  // menu_entity_forms.dart). The dialog below performs no provider lookups.
  final controller = ProviderScope.containerOf(
    context,
  ).read(menuWriteControllerProvider);
  // Captured BEFORE the awaits: no BuildContext use across async gaps.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);

  final template = await showDialog<ModifierTemplate>(
    context: context,
    builder: (_) => const _ModifierTemplatePickerDialog(),
  );
  if (template == null) return;

  // 1. Create the group — the exact call the manual modifier form makes.
  final groupOutcome = await controller.upsertModifier(
    menuItemId: menuItemId,
    name: template.name(l10n),
    selectionType: template.selectionType,
    minSelect: template.minSelect,
    maxSelect: template.maxSelect,
    isRequired: template.isRequired,
  );
  String? groupId;
  MenuWriteFailure? groupFailure;
  groupOutcome.fold((result) => groupId = result.id, (f) => groupFailure = f);
  if (groupFailure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.menuWriteFailureText(groupFailure!))),
    );
    return;
  }

  // 2. Create the options sequentially against the created group; stop on the
  // first failure (already-created rows stay — said honestly, never rolled
  // back silently). displayOrder = recipe order.
  for (var i = 0; i < template.options.length; i++) {
    final option = template.options[i];
    final outcome = await controller.upsertModifierOption(
      modifierId: groupId!,
      name: option.name(l10n),
      priceDeltaMinor: option.priceDeltaMinor,
      displayOrder: i,
    );
    MenuWriteFailure? optionFailure;
    outcome.fold((_) {}, (f) => optionFailure = f);
    if (optionFailure != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.menuWriteFailureText(optionFailure!)}\n'
            '${l10n.menuTemplateApplyPartial}',
          ),
        ),
      );
      return;
    }
  }

  // Full success — the snapshot already refreshes via the write controller
  // (same as manual add); mirror the manual save feedback.
  messenger.showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
}

/// The template list dialog. Pops with the picked [ModifierTemplate] (or null
/// on cancel). Performs NO provider lookups (it renders above the nested
/// feature ProviderScope) and applies nothing itself.
class _ModifierTemplatePickerDialog extends StatelessWidget {
  const _ModifierTemplatePickerDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.menuTemplatePickerTitle),
      contentPadding: const EdgeInsetsDirectional.only(
        top: RestoflowSpacing.sm,
        bottom: RestoflowSpacing.sm,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final template in kMenuModifierTemplates)
                ListTile(
                  key: ValueKey('menu-template-${template.id}'),
                  leading: const Icon(Icons.layers_outlined),
                  title: Text(template.name(l10n)),
                  subtitle: Text(_summaryOf(l10n, template)),
                  onTap: () => Navigator.of(context).pop(template),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.menuCancelAction),
        ),
      ],
    );
  }
}
