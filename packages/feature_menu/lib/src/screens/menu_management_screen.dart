import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../models/menu_scope.dart';
import '../models/menu_snapshot.dart';
import '../state/menu_providers.dart';
import '../widgets/menu_badges.dart';
import '../widgets/menu_category_list.dart';
import '../widgets/menu_components.dart';
import '../widgets/menu_entity_forms.dart';
import '../widgets/menu_item_list.dart';
import '../widgets/menu_state_views.dart';
import 'item_editor_screen.dart';

/// The owner menu management surface (RF-111): a polished page header + a
/// search/filter toolbar over a responsive master/detail (categories + items),
/// with an in-place item editor. All navigation is internal state (no GoRouter /
/// pushed routes) so the whole tree stays under the feature ProviderScope
/// overrides. Read/write run against the injected seam (demo store today).
class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});

  static const double _wideBreakpoint = RestoflowBreakpoints.wide;

  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  MenuEditorTarget? _editing;
  String? _selectedCategoryId;
  bool _narrowShowItems = false;
  String _query = '';
  MenuActiveFilter _filter = MenuActiveFilter.all;

  void _openEditor(MenuEditorTarget target) =>
      setState(() => _editing = target);

  void _closeEditor() => setState(() => _editing = null);

  void _selectCategory(String id) => setState(() {
    _selectedCategoryId = id;
    _narrowShowItems = true;
  });

  Future<void> _addCategory() async {
    final l10n = AppLocalizations.of(context);
    if (await showCategoryFormDialog(context) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.menuSavedSnack)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshotAsync = ref.watch(menuSnapshotProvider);
    final scope = ref.watch(menuScopeProvider);

    return snapshotAsync.when(
      loading: () => const MenuLoadingView(),
      error: (error, _) => MenuStateView(
        icon: Icons.error_outline,
        title: l10n.menuLoadError,
        body: l10n.menuLoadErrorBody,
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(menuSnapshotProvider),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.menuRetry),
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
        return _surface(context, l10n, snapshot, scope);
      },
    );
  }

  Widget _surface(
    BuildContext context,
    AppLocalizations l10n,
    MenuSnapshot snapshot,
    MenuScope scope,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            RestoflowSpacing.lg,
            RestoflowSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MenuPageHeader(
                title: l10n.menuManagementTitle,
                subtitle: l10n.menuManagementSubtitle,
                trailing: MenuScopeChip(branchId: scope.branchId),
              ),
              const SizedBox(height: RestoflowSpacing.lg),
              MenuToolbar(
                query: _query,
                onQueryChanged: (value) => setState(() => _query = value),
                filter: _filter,
                onFilterChanged: (value) => setState(() => _filter = value),
                trailing: FilledButton.icon(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.menuAddCategory),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              RestoflowSpacing.lg,
              0,
              RestoflowSpacing.lg,
              RestoflowSpacing.lg,
            ),
            child: MenuSurfacePanel(
              child: _MasterDetail(
                snapshot: snapshot,
                scope: scope,
                query: _query,
                filter: _filter,
                selectedCategoryId: _resolveSelected(snapshot),
                narrowShowItems: _narrowShowItems,
                onSelectCategory: _selectCategory,
                onBackToCategories: () =>
                    setState(() => _narrowShowItems = false),
                onOpenEditor: _openEditor,
              ),
            ),
          ),
        ),
      ],
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
    required this.query,
    required this.filter,
    required this.selectedCategoryId,
    required this.narrowShowItems,
    required this.onSelectCategory,
    required this.onBackToCategories,
    required this.onOpenEditor,
  });

  final MenuSnapshot snapshot;
  final MenuScope scope;
  final String query;
  final MenuActiveFilter filter;
  final String? selectedCategoryId;
  final bool narrowShowItems;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onBackToCategories;
  final ValueChanged<MenuEditorTarget> onOpenEditor;

  Widget _itemsPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoryId = selectedCategoryId;
    if (categoryId == null) {
      return MenuStateView(
        icon: Icons.touch_app_outlined,
        title: l10n.menuSelectCategoryHint,
      );
    }
    return MenuItemList(
      snapshot: snapshot,
      categoryId: categoryId,
      scope: scope,
      query: query,
      filter: filter,
      onOpenEditor: onOpenEditor,
    );
  }

  Widget _categoryList() {
    return MenuCategoryList(
      snapshot: snapshot,
      selectedCategoryId: selectedCategoryId,
      query: query,
      filter: filter,
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
              SizedBox(
                width: RestoflowPanelWidths.masterPane,
                child: _categoryList(),
              ),
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
