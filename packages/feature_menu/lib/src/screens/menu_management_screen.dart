import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../state/menu_providers.dart';
import '../widgets/menu_category_list.dart';
import '../widgets/menu_item_list.dart';
import '../widgets/menu_state_views.dart';
import 'item_editor_screen.dart';

/// The owner menu management surface (RF-111): a responsive master/detail of
/// categories + items, with an in-place item editor. All navigation is internal
/// state (no GoRouter / pushed routes) so the whole tree stays under the feature
/// ProviderScope overrides. Read/write run against the injected seam (demo store
/// today; real online wiring deferred to the auth/org-context bridge).
class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  static const double _wideBreakpoint = 900;

  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  MenuEditorTarget? _editing;
  String? _selectedCategoryId;
  bool _narrowShowItems = false;

  void _openEditor(MenuEditorTarget target) =>
      setState(() => _editing = target);

  void _closeEditor() => setState(() => _editing = null);

  void _selectCategory(String id) => setState(() {
    _selectedCategoryId = id;
    _narrowShowItems = true;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(menuSnapshotProvider);
    final scope = ref.watch(menuScopeProvider);

    return snapshotAsync.when(
      loading: () => const MenuLoadingView(),
      error: (error, _) => MenuMessageView(
        icon: Icons.error_outline,
        message: l10n.menuLoadError,
        action: FilledButton(
          onPressed: () => ref.invalidate(menuSnapshotProvider),
          child: Text(l10n.menuRetry),
        ),
      ),
      data: (snapshot) {
        final editing = _editing;
        if (editing != null) {
          return ItemEditorView(
            snapshot: snapshot,
            scope: scope,
            target: editing,
            onClose: _closeEditor,
          );
        }
        return _MasterDetail(
          snapshot: snapshot,
          scope: scope,
          selectedCategoryId: _resolveSelected(snapshot),
          narrowShowItems: _narrowShowItems,
          onSelectCategory: _selectCategory,
          onBackToCategories: () => setState(() => _narrowShowItems = false),
          onOpenEditor: _openEditor,
        );
      },
    );
  }

  String? _resolveSelected(MenuSnapshot snapshot) {
    final categories = snapshot.visibleCategories();
    if (categories.any((c) => c.id == _selectedCategoryId)) {
      return _selectedCategoryId;
    }
    return categories.isEmpty ? null : categories.first.id;
  }
}

class _MasterDetail extends StatelessWidget {
  const _MasterDetail({
    required this.snapshot,
    required this.scope,
    required this.selectedCategoryId,
    required this.narrowShowItems,
    required this.onSelectCategory,
    required this.onBackToCategories,
    required this.onOpenEditor,
  });

  final MenuSnapshot snapshot;
  final MenuScope scope;
  final String? selectedCategoryId;
  final bool narrowShowItems;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onBackToCategories;
  final ValueChanged<MenuEditorTarget> onOpenEditor;

  Widget _itemsPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoryId = selectedCategoryId;
    if (categoryId == null) {
      return MenuMessageView(
        icon: Icons.touch_app_outlined,
        message: l10n.menuSelectCategoryHint,
      );
    }
    return MenuItemList(
      snapshot: snapshot,
      categoryId: categoryId,
      scope: scope,
      onOpenEditor: onOpenEditor,
    );
  }

  Widget _categoryList() {
    return MenuCategoryList(
      snapshot: snapshot,
      selectedCategoryId: selectedCategoryId,
      onSelect: onSelectCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= MenuManagementScreen._wideBreakpoint;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _categoryList()),
              const VerticalDivider(width: 1),
              Expanded(child: _itemsPanel(context)),
            ],
          );
        }
        if (narrowShowItems && selectedCategoryId != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onBackToCategories,
                  icon: const BackButtonIcon(),
                  label: Text(
                    AppLocalizations.of(context).menuCategoriesHeading,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _itemsPanel(context)),
            ],
          );
        }
        return _categoryList();
      },
    );
  }
}
