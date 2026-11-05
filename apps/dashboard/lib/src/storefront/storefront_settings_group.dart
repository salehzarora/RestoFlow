import 'package:flutter/material.dart';

/// Presentation only: closing a group retains controllers, pending operations
/// and retry identities in its mounted child. It never saves or reloads.
class StorefrontSettingsGroup extends StatefulWidget {
  const StorefrontSettingsGroup({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    super.key,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<StorefrontSettingsGroup> createState() =>
      _StorefrontSettingsGroupState();
}

class _StorefrontSettingsGroupState extends State<StorefrontSettingsGroup> {
  late bool _expanded = widget.initiallyExpanded;
  final _controller = ExpansibleController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ExpansionTile(
      controller: _controller,
      title: Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      maintainState: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      collapsedShape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      children: [ExcludeFocus(excluding: !_expanded, child: widget.child)],
    ),
  );
}
