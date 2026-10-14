import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/online_order_inbox.dart';
import '../format/money_format.dart';
import '../media/pos_media_image.dart';
import '../state/online_order_inbox_controller.dart';
import '../state/pos_menu_provider.dart';
import '../state/pos_offline_state.dart';

/// One visible entry owns lifecycle signals; polling itself lives only in the
/// singleton controller. The compact variant shares the existing navbar row.
class OnlineOrderInboxButton extends ConsumerStatefulWidget {
  const OnlineOrderInboxButton({super.key, this.compact = false});
  final bool compact;
  @override
  ConsumerState<OnlineOrderInboxButton> createState() => _InboxButtonState();
}

class _InboxButtonState extends ConsumerState<OnlineOrderInboxButton>
    with WidgetsBindingObserver {
  bool _opening = false;
  OnlineOrderInboxController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller = ref.read(onlineOrderInboxControllerProvider.notifier);
      if (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _controller!.onResume();
      } else {
        _controller!.onPaused();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller?.onResume();
    } else {
      _controller?.onPaused();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.onPaused();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      unawaited(
        ref.read(onlineOrderInboxControllerProvider.notifier).refresh(),
      );
      await OnlineOrderInboxSheet.show(context);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(onlineOrderInboxControllerProvider);
    final count = state.pendingCountAt(
      ref.read(onlineOrderInboxControllerProvider.notifier).now(),
    );
    final icon = Badge(
      isLabelVisible: count > 0,
      label: Text(l10n.posOnlineInboxCount(count, state.hasMore ? '+' : '')),
      child: const Icon(Icons.shopping_bag_outlined),
    );
    if (widget.compact) {
      return IconButton(
        key: const Key('online-inbox-button'),
        tooltip: l10n.posOnlineInboxTitle,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _open,
        icon: Semantics(
          label: '${l10n.posOnlineInboxTitle}, $count',
          child: icon,
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${l10n.posOnlineInboxTitle}, $count',
      child: TextButton.icon(
        key: const Key('online-inbox-button'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: _open,
        icon: icon,
        label: Text(
          l10n.posOnlineInboxTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class OnlineOrderInboxSheet extends ConsumerWidget {
  const OnlineOrderInboxSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 1200),
    builder: (_) => const OnlineOrderInboxSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(onlineOrderInboxIdentityProvider);
    // Recreate local selection and text controllers on every authority change.
    return _InboxContent(key: ValueKey(identity));
  }
}

class _InboxContent extends ConsumerStatefulWidget {
  const _InboxContent({super.key});
  @override
  ConsumerState<_InboxContent> createState() => _InboxContentState();
}

class _InboxContentState extends ConsumerState<_InboxContent> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(onlineOrderInboxControllerProvider);
    final controller = ref.read(onlineOrderInboxControllerProvider.notifier);
    final selected = state.requests
        .where((r) => r.id == _selectedId)
        .firstOrNull;
    final height = max(
      120.0,
      MediaQuery.sizeOf(context).height * .9 -
          MediaQuery.viewInsetsOf(context).bottom,
    );
    return SafeArea(
      child: SizedBox(
        key: const Key('online-inbox-sheet'),
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * .5),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.posOnlineInboxTitle,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            key: const Key('online-inbox-refresh'),
                            tooltip: l10n.posOnlineInboxRefresh,
                            onPressed: state.loading || state.deciding
                                ? null
                                : () => state.intent != null
                                      ? controller.recoverDecision()
                                      : controller.refresh(),
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (state.loading || state.deciding)
                        LinearProgressIndicator(
                          semanticsLabel: state.deciding
                              ? l10n.posOnlineInboxChecking
                              : l10n.posOnlineInboxLoading,
                        ),
                      if (state.uncertain)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.posOnlineInboxUncertain,
                            key: const Key('online-inbox-uncertain'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        )
                      else if (state.failure != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _failureText(l10n, state.failure!),
                            key: const Key('online-inbox-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (state.intent != null && !state.deciding)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            key: const Key('online-inbox-recover'),
                            onPressed: controller.recoverDecision,
                            icon: const Icon(Icons.sync),
                            label: Text(l10n.posOnlineInboxRecover),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final wide =
                        bounds.maxWidth >= 840 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.6;
                    final list = _requestList(context, state, controller);
                    final detail = selected == null
                        ? Center(child: Text(l10n.posOnlineInboxSelect))
                        : _RequestDetail(
                            key: ValueKey(selected.id),
                            request: selected,
                            state: state,
                            onBack: wide
                                ? null
                                : () => setState(() => _selectedId = null),
                          );
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: list),
                          const VerticalDivider(width: 24),
                          Expanded(child: detail),
                        ],
                      );
                    }
                    return selected == null ? list : detail;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestList(
    BuildContext context,
    OnlineOrderInboxState state,
    OnlineOrderInboxController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state.requests.isEmpty) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Text(
            state.loading
                ? l10n.posOnlineInboxLoading
                : state.failure != null
                ? _failureText(l10n, state.failure!)
                : l10n.posOnlineInboxEmpty,
            key: const Key('online-inbox-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      key: const Key('online-inbox-requests'),
      itemCount: state.requests.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == state.requests.length) {
          return TextButton(
            onPressed: state.loading || state.intent != null
                ? null
                : () => controller.refresh(loadMore: true),
            child: Text(l10n.posOnlineInboxMore),
          );
        }
        final request = state.requests[index];
        final theme = Theme.of(context);
        final selected = request.id == _selectedId;
        return Material(
          key: ValueKey('online-request-${request.id}'),
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _selectedId = request.id),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RequestArrival(request: request, now: controller.now()),
                  const SizedBox(height: 10),
                  Text(
                    request.customerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.posMenuItemCount(_itemCount(request)),
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    request.items
                        .map((item) => '${item.quantity} × ${item.name}')
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 8,
                    children: [
                      for (final item in request.items.take(3))
                        _OrderThumbnail(item: item, size: 46),
                      Text(
                        MoneyFormatter.formatMinor(
                          request.grandTotalMinor,
                          request.currencyCode,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestDetail extends ConsumerStatefulWidget {
  const _RequestDetail({
    super.key,
    required this.request,
    required this.state,
    this.onBack,
  });
  final OnlineOrderRequest request;
  final OnlineOrderInboxState state;
  final VoidCallback? onBack;
  @override
  ConsumerState<_RequestDetail> createState() => _RequestDetailState();
}

class _RequestDetailState extends ConsumerState<_RequestDetail> {
  final _reason = TextEditingController();
  bool _rejecting = false;
  @override
  void dispose() {
    _reason.clear();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = widget.request;
    final state = widget.state;
    final controller = ref.read(onlineOrderInboxControllerProvider.notifier);
    final offline =
        ref.watch(posOfflineModeProvider).phase != PosOfflinePhase.online;
    final expired =
        request.expiredAt(controller.now()) ||
        request.status == OnlineOrderStatus.expired;
    final enabled =
        !offline &&
        !expired &&
        state.intent == null &&
        request.status == OnlineOrderStatus.pending &&
        state.failure != OnlineInboxFailure.invalidSession &&
        state.failure != OnlineInboxFailure.permissionDenied;
    final validReason =
        _reason.text.trim().isNotEmpty &&
        _reason.text.trim().runes.length <= 240 &&
        !RegExp(r'[\x00-\x1F\x7F]').hasMatch(_reason.text);
    String money(int minor) =>
        MoneyFormatter.formatMinor(minor, request.currencyCode);
    return SingleChildScrollView(
      key: const Key('online-inbox-details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onBack != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(l10n.posOnlineInboxBack),
              ),
            ),
          _RequestArrival(request: request, now: controller.now()),
          const SizedBox(height: 12),
          Text(
            request.customerName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(request.customerPhone),
          ),
          const SizedBox(height: 8),
          Text(
            expired
                ? l10n.posOnlineInboxExpired
                : l10n.posOnlineInboxExpires(
                    max(
                      0,
                      request.expiresAt.difference(controller.now()).inMinutes,
                    ),
                  ),
          ),
          const Divider(height: 24),
          Text(
            l10n.posMenuItemCount(_itemCount(request)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final item in request.items) ...[
            _RequestItem(item: item, currencyCode: request.currencyCode),
            const SizedBox(height: 12),
          ],
          if (request.notes?.isNotEmpty == true) ...[
            _NotePanel(
              label: l10n.posOnlineInboxNotes,
              notes: request.notes!,
              key: const Key('online-inbox-order-notes'),
            ),
            const SizedBox(height: 16),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _total(l10n.posCartSubtotal, money(request.subtotalMinor)),
                  _total(l10n.posTaxLabel, money(request.taxTotalMinor)),
                  const Divider(height: 20),
                  DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    child: _total(
                      l10n.posGrandTotal,
                      money(request.grandTotalMinor),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (offline) Text(l10n.posOnlineInboxConnection),
          if (_rejecting) ...[
            TextField(
              key: const Key('online-inbox-rejection-reason'),
              controller: _reason,
              maxLength: 240,
              enabled: enabled,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.posOnlineInboxReason,
                hintText: l10n.posOnlineInboxReasonHint,
              ),
            ),
            const SizedBox(height: 8),
          ],
          LayoutBuilder(
            builder: (context, bounds) {
              final actionWidth =
                  bounds.maxWidth < 360 ||
                      MediaQuery.textScalerOf(context).scale(1) >= 1.6
                  ? bounds.maxWidth
                  : (bounds.maxWidth - 12) / 2;
              final style = ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(actionWidth, 56)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: actionWidth,
                    child: FilledButton.icon(
                      key: const Key('online-inbox-accept'),
                      style: style,
                      onPressed: enabled
                          ? () => controller.decide(
                              request.id,
                              OnlineOrderDecision.accept,
                            )
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text(l10n.posOnlineInboxAccept),
                    ),
                  ),
                  SizedBox(
                    width: actionWidth,
                    child: OutlinedButton.icon(
                      key: const Key('online-inbox-reject'),
                      style: style,
                      onPressed: !enabled || (_rejecting && !validReason)
                          ? null
                          : () {
                              if (!_rejecting) {
                                setState(() => _rejecting = true);
                              } else {
                                unawaited(
                                  controller.decide(
                                    request.id,
                                    OnlineOrderDecision.reject,
                                    reason: _reason.text,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.close),
                      label: Text(l10n.posOnlineInboxReject),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _total(String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      children: [Text(label), Text(amount)],
    ),
  );
}

int _itemCount(OnlineOrderRequest request) =>
    request.items.fold(0, (count, item) => count + item.quantity);

class _RequestArrival extends StatelessWidget {
  const _RequestArrival({required this.request, required this.now});
  final OnlineOrderRequest request;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final expired =
        request.expiredAt(now) || request.status == OnlineOrderStatus.expired;
    final pending = !expired && request.status == OnlineOrderStatus.pending;
    final localCreated = request.createdAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final arrival = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(localCreated),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          key: ValueKey('online-inbox-status-${request.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: pending
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            expired
                ? l10n.posOnlineInboxExpired
                : request.status == OnlineOrderStatus.accepted
                ? l10n.posOrderStatusSubmitted
                : request.status == OnlineOrderStatus.rejected
                ? l10n.posOrderRejectedTitle
                : l10n.posOrderPendingTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              color: pending
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$arrival · ${l10n.posOnlineInboxAge(_age(now, request.createdAt))}',
          key: ValueKey('online-inbox-arrival-${request.id}'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Images are decoration only. Every textual and monetary field below comes
/// from the submitted snapshot; the current menu contributes only its photo.
class _RequestItem extends StatelessWidget {
  const _RequestItem({required this.item, required this.currencyCode});
  final OnlineOrderItem item;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    String money(int minor) => MoneyFormatter.formatMinor(minor, currencyCode);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OrderThumbnail(item: item, size: 72),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${item.quantity} × ${item.name}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.posCartQtyUnit(
                          item.quantity,
                          money(item.unitPriceMinor),
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        money(item.lineTotalMinor),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final option in item.modifiers)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${option.quantity} × ${option.name} · ${money(option.priceMinor)}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            if (item.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              _NotePanel(
                label: l10n.posModifierItemNoteLabel,
                notes: item.notes!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotePanel extends StatelessWidget {
  const _NotePanel({super.key, required this.label, required this.notes});
  final String label;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
          start: BorderSide(color: theme.colorScheme.secondary, width: 3),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(notes),
          ],
        ),
      ),
    );
  }
}

class _OrderThumbnail extends ConsumerWidget {
  const _OrderThumbnail({required this.item, required this.size});
  final OnlineOrderItem item;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuse the authenticated, scope-bound POS menu and its already resolved
    // URLs. Never look up by name or accept an image URL from the request.
    final menu = ref.watch(posMenuProvider).asData?.value;
    final menuItem = menu?.items
        .where((m) => m.id == item.menuItemId)
        .firstOrNull;
    final category = menuItem == null
        ? null
        : menu?.categoryOf(menuItem.categoryId);
    final colors = Theme.of(context).colorScheme;
    Widget fallback() => ColoredBox(
      key: ValueKey('online-inbox-image-fallback-${item.menuItemId}'),
      color:
          category?.color.withValues(alpha: .12) ??
          colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          category?.icon ?? Icons.restaurant_menu,
          color: category?.color ?? colors.onSurfaceVariant,
        ),
      ),
    );
    final url = menuItem?.imageUrl;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: url == null || url.isEmpty
              ? fallback()
              : Image(
                  key: ValueKey('online-inbox-image-${item.menuItemId}'),
                  image: ResizeImage.resizeIfNeeded(
                    (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
                    null,
                    posMediaImageProvider(url),
                  ),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback(),
                ),
        ),
      ),
    );
  }
}

int _age(DateTime now, DateTime created) =>
    max(0, now.difference(created).inMinutes);

String _failureText(AppLocalizations l10n, OnlineInboxFailure failure) =>
    switch (failure) {
      OnlineInboxFailure.unavailable => l10n.posOnlineInboxUnavailable,
      OnlineInboxFailure.transport => l10n.posOnlineInboxConnection,
      OnlineInboxFailure.invalidSession ||
      OnlineInboxFailure.permissionDenied => l10n.posOnlineInboxSession,
      OnlineInboxFailure.requestExpired => l10n.posOnlineInboxExpired,
      OnlineInboxFailure.shiftRequired => l10n.posOnlineInboxShift,
      OnlineInboxFailure.quoteChanged => l10n.posOnlineInboxQuoteChanged,
      OnlineInboxFailure.itemUnavailable ||
      OnlineInboxFailure.modifierSelectionInvalid =>
        l10n.posOnlineInboxItemUnavailable,
      OnlineInboxFailure.decisionConflict ||
      OnlineInboxFailure.notFound => l10n.posOnlineInboxConflict,
      _ => l10n.posOnlineInboxError,
    };
