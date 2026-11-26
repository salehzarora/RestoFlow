import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import '../data/customer_phone.dart';
import '../data/order_submission.dart'
    show kCustomerNameMaxLength, normalizeCustomerName;
import '../pos_palette.dart';
import '../state/order_setup_controller.dart';
import '../state/pos_customer_suggestions.dart';

/// Optional order fields. Typing is local; only an explicit tap applies a match.
class CustomerSuggestionFields extends ConsumerStatefulWidget {
  const CustomerSuggestionFields({super.key});

  @override
  ConsumerState<CustomerSuggestionFields> createState() =>
      _CustomerSuggestionFieldsState();
}

class _CustomerSuggestionFieldsState
    extends ConsumerState<CustomerSuggestionFields> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  Timer? _timer;
  int _generation = 0;
  String? _resultScope;
  List<PosCustomerSuggestion> _matches = const [];

  @override
  void initState() {
    super.initState();
    final setup = ref.read(orderSetupControllerProvider);
    _name = TextEditingController(text: setup.customerName ?? '');
    _phone = TextEditingController(text: setup.customerPhoneInput);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    _generation++;
    _resultScope = null;
    if (_matches.isNotEmpty) setState(() => _matches = const []);
  }

  void _typed(String input, {required bool byPhone}) {
    final controller = ref.read(orderSetupControllerProvider.notifier);
    if (byPhone) {
      controller.setCustomerPhone(input);
    } else {
      controller.setCustomerName(input);
    }
    _dismiss();
    final prefix = posCustomerSuggestionPrefix(input, byPhone: byPhone);
    final scope = ref.read(posCustomerSuggestionsScopeProvider);
    if (prefix == null || scope == null) return;
    final generation = _generation;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      if (!_stillCurrent(generation, scope)) return;
      try {
        final lookup = ref.read(posCustomerSuggestionsLookupProvider);
        final matches = await lookup(prefix, byPhone: byPhone);
        if (_stillCurrent(generation, scope) && matches.isNotEmpty) {
          setState(() {
            _resultScope = scope;
            _matches = matches.take(5).toList(growable: false);
          });
        }
      } on Exception {
        // Suggestions are optional. The cashier can keep entering the order.
      }
    });
  }

  bool _stillCurrent(int generation, String scope) =>
      mounted &&
      generation == _generation &&
      scope == ref.read(posCustomerSuggestionsScopeProvider);

  void _select(PosCustomerSuggestion match, int generation) {
    final scope = _resultScope;
    if (scope == null || !_stillCurrent(generation, scope)) {
      return;
    }
    _dismiss();
    ref
        .read(orderSetupControllerProvider.notifier)
        .selectCustomer(name: match.name, phone: match.phone);
    final selected = ref.read(orderSetupControllerProvider);
    _setText(_name, selected.customerName ?? '');
    _setText(_phone, selected.customerPhoneInput);
  }

  void _setText(TextEditingController field, String value) {
    if (field.text == value) return;
    field.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  InputDecoration _decoration({
    required IconData icon,
    required String label,
    required String hint,
    String? error,
  }) => InputDecoration(
    isDense: true,
    counterText: '',
    prefixIcon: Icon(icon),
    labelText: label,
    hintText: hint,
    errorText: error,
    filled: true,
    fillColor: kPosInnerSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      borderSide: const BorderSide(color: kPosInputBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RestoflowRadii.md),
      borderSide: const BorderSide(color: kPosInputBorder),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(orderSetupControllerProvider);
    final l10n = AppLocalizations.of(context);
    ref.listen(posCustomerSuggestionsScopeProvider, (_, _) => _dismiss());
    ref.listen(orderSetupControllerProvider, (previous, next) {
      // Submit/reset or a parked-cart restore can happen during a lookup.
      if (previous?.customerName != next.customerName ||
          previous?.customerPhoneInput != next.customerPhoneInput) {
        _dismiss();
      }
      // The draft trims the name during typing. Preserve the cashier's raw
      // spelling, caret and IME composition when they already represent it.
      if (normalizeCustomerName(_name.text) != next.customerName) {
        _setText(_name, next.customerName ?? '');
      }
      _setText(_phone, next.customerPhoneInput);
    });

    final name = TextField(
      key: const Key('customer-name-field'),
      controller: _name,
      maxLength: kCustomerNameMaxLength,
      textInputAction: TextInputAction.done,
      onTap: _dismiss,
      onChanged: (value) => _typed(value, byPhone: false),
      decoration: _decoration(
        icon: Icons.person_outline,
        label: l10n.customerNameLabel,
        hint: l10n.customerNamePlaceholder,
      ),
    );
    final phone = TextField(
      key: const Key('customer-phone-field'),
      controller: _phone,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      maxLength: kCustomerPhoneMaxLength,
      onTap: _dismiss,
      onChanged: (value) => _typed(value, byPhone: true),
      decoration: _decoration(
        icon: Icons.phone_outlined,
        label: l10n.customerPhoneLabel,
        hint: l10n.customerPhonePlaceholder,
        error: switch (setup.customerPhoneError) {
          CustomerPhoneError.unsupportedCharacters =>
            l10n.customerPhoneErrorChars,
          CustomerPhoneError.tooFewDigits => l10n.customerPhoneErrorDigits,
          CustomerPhoneError.tooLong => l10n.customerPhoneErrorInvalid,
          null => null,
        },
      ),
    );
    final generation = _generation;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (focused) {
        if (!focused && mounted) _dismiss();
      },
      child: TextFieldTapRegion(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth + 2 * RestoflowSpacing.lg;
                if (width < kPosCartPairedFieldsMinWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [name, phone],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: RestoflowSpacing.sm),
                    Expanded(child: phone),
                  ],
                );
              },
            ),
            if (_matches.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 144),
                child: ListView(
                  primary: false,
                  shrinkWrap: true,
                  children: [
                    for (final match in _matches)
                      ListTile(
                        dense: true,
                        minTileHeight: 48,
                        title: Text(
                          match.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _maskedPhone(match.phone),
                          textDirection: TextDirection.ltr,
                        ),
                        onTap: () => _select(match, generation),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _maskedPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final suffix = digits.length > 4 ? digits.substring(digits.length - 4) : '';
  return '•••• $suffix';
}
