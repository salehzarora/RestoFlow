// POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 — the optional customer phone (validation,
// serialization, recovery round-trip) + the printer_only dispatch/close policy.
// Synthetic phone numbers only.
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/customer_phone.dart';
import 'package:restoflow_pos/src/data/order_close_policy.dart';
import 'package:restoflow_pos/src/data/order_dispatch.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart'
    show CartDraftSnapshot;
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 12);
  KitchenModePrinterOnlyWithRevision printerOnly() =>
      KitchenModePrinterOnlyWithRevision(revision: 3, verifiedAt: now);
  KitchenModeVerifiedKds kds() =>
      KitchenModeVerifiedKds(verifiedAt: now, revision: 3);

  group('validateCustomerPhone / normalizeCustomerPhone', () {
    test('null / empty / whitespace -> null, acceptable (never blocks)', () {
      for (final raw in <String?>[null, '', '   ', '\t ']) {
        final v = validateCustomerPhone(raw);
        expect(v.value, isNull);
        expect(v.error, isNull);
        expect(v.isAcceptable, isTrue);
        expect(normalizeCustomerPhone(raw), isNull);
      }
    });

    test('valid local number is kept trimmed', () {
      expect(normalizeCustomerPhone('  054-1234567  '), '054-1234567');
      expect(validateCustomerPhone('054-1234567').error, isNull);
    });

    test('valid international + / spaces / parentheses are preserved', () {
      expect(normalizeCustomerPhone('+972 54 987 6543'), '+972 54 987 6543');
      expect(normalizeCustomerPhone('+1 (555) 019-2837'), '+1 (555) 019-2837');
    });

    test('letters are rejected', () {
      final v = validateCustomerPhone('054-ABC-1234');
      expect(v.error, CustomerPhoneError.unsupportedCharacters);
      expect(v.isAcceptable, isFalse);
      expect(normalizeCustomerPhone('054-ABC-1234'), isNull);
    });

    test('control chars / newline / tab are rejected', () {
      expect(
        validateCustomerPhone('054\n12345').error,
        CustomerPhoneError.unsupportedCharacters,
      );
      expect(
        validateCustomerPhone('054\t12345').error,
        CustomerPhoneError.unsupportedCharacters,
      );
    });

    test('fewer than 5 digits is rejected', () {
      expect(
        validateCustomerPhone('12 34').error,
        CustomerPhoneError.tooFewDigits,
      );
      expect(
        validateCustomerPhone('(1) 2-3').error,
        CustomerPhoneError.tooFewDigits,
      );
    });

    test('over 32 chars is rejected', () {
      expect(
        validateCustomerPhone('+${'9' * 40}').error,
        CustomerPhoneError.tooLong,
      );
    });

    test('exactly 5 digits + max length are accepted', () {
      expect(validateCustomerPhone('12345').error, isNull);
      final thirtyTwo = '+${'1' * 31}'; // 32 chars, 31 digits
      expect(thirtyTwo.length, kCustomerPhoneMaxLength);
      expect(validateCustomerPhone(thirtyTwo).error, isNull);
    });
  });

  group('serialization + equality', () {
    test(
      'OrderSubmissionPayload.toJson carries customer_phone + dispatch_mode',
      () {
        final payload = OrderSubmissionPayload(
          orderId: 'o1',
          localOperationId: 'op1',
          deviceId: 'd1',
          organizationId: 'org',
          restaurantId: 'r',
          branchId: 'b',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 500,
          grandTotalMinor: 500,
          items: const [],
          clientCreatedAt: now,
          customerPhone: '054-1234567',
          dispatchMode: OrderDispatchMode.directPrint,
        );
        final json = payload.toJson();
        expect(json['customer_phone'], '054-1234567');
        expect(json['dispatch_mode'], 'direct_print');
        // A kds order OMITS dispatch_mode entirely — the durable body + transport op
        // stay byte-identical to the pre-feature shape (server defaults to 'kds').
        final kdsJson = OrderSubmissionPayload(
          orderId: 'o',
          localOperationId: 'op',
          deviceId: 'd',
          organizationId: 'org',
          restaurantId: 'r',
          branchId: 'b',
          orderType: OrderType.takeaway,
          currencyCode: 'ILS',
          subtotalMinor: 0,
          grandTotalMinor: 0,
          items: const [],
          clientCreatedAt: now,
        ).toJson();
        expect(kdsJson.containsKey('dispatch_mode'), isFalse);
      },
    );

    test('OrderSummary JSON round-trips the phone (and null legacy)', () {
      const s = OrderSummary(
        orderNumber: 'DEMO-1',
        orderType: OrderType.dineIn,
        tableLabel: 'T1',
        itemCount: 1,
        subtotalMinor: 500,
        currencyCode: 'ILS',
        customerName: 'Layla',
        customerPhone: '050-7654321',
      );
      expect(OrderSummary.fromJson(s.toJson()).customerPhone, '050-7654321');
      expect(
        OrderSummary.fromJson(const {'order_number': 'x'}).customerPhone,
        isNull,
      );
    });

    test('SubmittedOrderView.copyWith preserves the phone', () {
      const v = SubmittedOrderView(
        orderNumber: 'DEMO-1',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 500,
        lines: [],
        customerPhone: '054-1234567',
      );
      expect(v.copyWith(subtotalMinor: 600).customerPhone, '054-1234567');
    });

    test(
      'PosDraftRecovery JSON round-trips the phone; legacy decodes null',
      () {
        final rec = PosDraftRecovery(
          // MONEY-LOCAL-DECODE-INTEGRITY-002B: an EMPTY draft is now spelled
          // out. `{}` used to decode as one only because a missing `lines` key
          // was reinterpreted as an empty cart — the fail-open this phase
          // removes. The subject of this test is the phone round-trip.
          draft: CartDraftSnapshot.fromJson(const {'lines': <Object?>[]}),
          orderType: OrderType.takeaway,
          outboxEntryId: 'e1',
          binding: const PosRecoveryBinding(
            scopeKey: 's',
            employeeProfileId: 'w',
          ),
          customerName: 'Layla',
          customerPhone: '050-7654321',
        );
        final back = PosDraftRecovery.fromJson(rec.toJson());
        expect(back.customerPhone, '050-7654321');
        expect(back.customerName, 'Layla');
        // A pre-feature record (no key) decodes null — old clients stay safe.
        final legacy = PosDraftRecovery.fromJson({
          ...rec.toJson()..remove('customer_phone'),
        });
        expect(legacy.customerPhone, isNull);
      },
    );
  });

  group('OrderSetupState phone getters', () {
    test('empty input: no phone, no error, does not block submit', () {
      const s = OrderSetupState(orderType: OrderType.takeaway);
      expect(s.customerPhone, isNull);
      expect(s.customerPhoneError, isNull);
      expect(s.hasBlockingCustomerPhone, isFalse);
    });

    test('valid input exposes the normalized phone, no error', () {
      const s = OrderSetupState(
        orderType: OrderType.takeaway,
        customerPhoneInput: '  054-1234567 ',
      );
      expect(s.customerPhone, '054-1234567');
      expect(s.hasBlockingCustomerPhone, isFalse);
    });

    test('invalid non-empty input blocks submit with a typed error', () {
      const s = OrderSetupState(
        orderType: OrderType.takeaway,
        customerPhoneInput: 'not-a-phone',
      );
      expect(s.customerPhone, isNull);
      expect(s.customerPhoneError, CustomerPhoneError.unsupportedCharacters);
      expect(s.hasBlockingCustomerPhone, isTrue);
    });
  });

  group('resolveOrderDispatchMode (fail-closed)', () {
    test('trusted printer_only -> direct_print', () {
      expect(
        resolveOrderDispatchMode(printerOnly()),
        OrderDispatchMode.directPrint,
      );
    });
    test('every other / null mode -> kds', () {
      expect(resolveOrderDispatchMode(kds()), OrderDispatchMode.kds);
      expect(resolveOrderDispatchMode(null), OrderDispatchMode.kds);
      expect(
        resolveOrderDispatchMode(const KitchenModeRevisionUnavailable()),
        OrderDispatchMode.kds,
      );
      expect(
        resolveOrderDispatchMode(const KitchenModeInvalidSession()),
        OrderDispatchMode.kds,
      );
      expect(
        resolveOrderDispatchMode(const KitchenModeTransientFailure()),
        OrderDispatchMode.kds,
      );
    });
  });

  group('posOrderCloseEligibility', () {
    PosOrderCloseEligibility eval({
      String status = 'served',
      bool settled = true,
      KitchenModeResult? mode,
      bool nullMode = false,
      bool authorized = true,
      bool inFlight = false,
    }) => posOrderCloseEligibility(
      status: status,
      settled: settled,
      verifiedMode: nullMode ? null : (mode ?? printerOnly()),
      actorAuthorized: authorized,
      transitionInFlight: inFlight,
    );

    test('served + settled + printer_only + authorized -> allowed', () {
      expect(eval(), PosOrderCloseEligibility.allowed);
    });
    test('terminal -> alreadyCompleted', () {
      for (final s in ['completed', 'cancelled', 'voided']) {
        expect(eval(status: s), PosOrderCloseEligibility.alreadyCompleted);
      }
    });
    test('served but unsettled -> paymentRequired', () {
      expect(eval(settled: false), PosOrderCloseEligibility.paymentRequired);
    });
    test('kds mode -> kdsCompletionRequired', () {
      expect(eval(mode: kds()), PosOrderCloseEligibility.kdsCompletionRequired);
    });
    test('unverified mode -> workflowUnavailable (fail-closed)', () {
      expect(
        eval(nullMode: true),
        PosOrderCloseEligibility.workflowUnavailable,
      );
    });
    test('unauthorized actor -> unauthorized', () {
      expect(eval(authorized: false), PosOrderCloseEligibility.unauthorized);
    });
    test('printer_only but not served -> invalidState', () {
      expect(eval(status: 'submitted'), PosOrderCloseEligibility.invalidState);
    });
    test('transition in flight -> transitionInFlight', () {
      expect(eval(inFlight: true), PosOrderCloseEligibility.transitionInFlight);
    });
  });
}
