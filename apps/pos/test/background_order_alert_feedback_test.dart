import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/state/background_order_alerts.dart';
import 'package:restoflow_pos/src/state/online_order_inbox_controller.dart';
import 'package:restoflow_pos/src/spool/online_order_print_hooks.dart';
import 'package:restoflow_pos/src/widgets/online_order_inbox_sheet.dart';

class _FailedAlerts extends BackgroundOrderAlerts {
  _FailedAlerts(this.reason);
  final BackgroundOrderAlertFailure reason;
  @override
  BackgroundOrderAlertState build() => BackgroundOrderAlertState(
    available: true,
    failed: true,
    failureReason: reason,
  );
}

class _EmptyInbox extends OnlineOrderInboxController {
  @override
  OnlineOrderInboxState build() => const OnlineOrderInboxState();
}

// Literal expectations are independent of both the UI selector and generated
// localization getters. No live transport, registration or device is involved.
const _expected = {
  'en': {
    BackgroundOrderAlertFailure.permissionDenied:
        "Notifications are blocked. In Android Settings, allow notifications for POS, then enable alerts again.",
    BackgroundOrderAlertFailure.notificationsDisabled:
        "Notifications are blocked. In Android Settings, allow notifications for POS, then enable alerts again.",
    BackgroundOrderAlertFailure.channelUnavailable:
        "In Android notification settings, set Pickup alerts to High importance and choose a sound, then enable alerts again.",
    BackgroundOrderAlertFailure.channelImportanceTooLow:
        "In Android notification settings, set Pickup alerts to High importance and choose a sound, then enable alerts again.",
    BackgroundOrderAlertFailure.channelSoundMissing:
        "In Android notification settings, set Pickup alerts to High importance and choose a sound, then enable alerts again.",
    BackgroundOrderAlertFailure.firebaseUnavailable:
        "Alert services are unavailable in this app. Keep using Inbox and contact support.",
    BackgroundOrderAlertFailure.tokenUnavailable:
        "Could not obtain a notification token. Check this device's connection and notification services, then enable alerts again.",
    BackgroundOrderAlertFailure.registrationDisabled:
        "Background alerts are disabled for this scope. Ask an authorized administrator to check alert settings.",
    BackgroundOrderAlertFailure.registrationRejected:
        "Alert registration was rejected. Contact support to check registration and the existing installation binding. Do not reset pairing.",
    BackgroundOrderAlertFailure.registrationUncertain:
        "The registration result is unconfirmed. Further activation is held. Contact support for reconciliation; do not retry or reset pairing.",
    BackgroundOrderAlertFailure.bindingFailed:
        "Registration was confirmed, but alerts could not bind on this device. Keep using Inbox and contact support.",
    BackgroundOrderAlertFailure.cleanupFailed:
        "Alert shutdown could not be confirmed. Further activation is held. Contact support before trying again.",
  },
  'ar': {
    BackgroundOrderAlertFailure.permissionDenied:
        "الإشعارات محظورة. اسمح بإشعارات POS من إعدادات Android، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.notificationsDisabled:
        "الإشعارات محظورة. اسمح بإشعارات POS من إعدادات Android، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.channelUnavailable:
        "من إعدادات إشعارات Android، اضبط تنبيهات طلبات الاستلام على أهمية عالية واختر صوتًا، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.channelImportanceTooLow:
        "من إعدادات إشعارات Android، اضبط تنبيهات طلبات الاستلام على أهمية عالية واختر صوتًا، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.channelSoundMissing:
        "من إعدادات إشعارات Android، اضبط تنبيهات طلبات الاستلام على أهمية عالية واختر صوتًا، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.firebaseUnavailable:
        "خدمات التنبيه غير متاحة في هذا التطبيق. تابع استخدام صندوق الطلبات وتواصل مع الدعم.",
    BackgroundOrderAlertFailure.tokenUnavailable:
        "تعذّر الحصول على رمز الإشعارات. تحقق من اتصال الجهاز وخدمات الإشعارات، ثم فعّل التنبيهات مجددًا.",
    BackgroundOrderAlertFailure.registrationDisabled:
        "تنبيهات الخلفية معطّلة لهذا النطاق. اطلب من مسؤول مخوّل التحقق من إعدادات التنبيه.",
    BackgroundOrderAlertFailure.registrationRejected:
        "رُفض تسجيل التنبيهات. تواصل مع الدعم لفحص التسجيل وارتباط التثبيت الحالي. لا تُعِد ضبط الاقتران.",
    BackgroundOrderAlertFailure.registrationUncertain:
        "نتيجة التسجيل غير مؤكدة، لذا أُوقف أي تفعيل إضافي. تواصل مع الدعم للمصالحة؛ لا تُعِد المحاولة أو ضبط الاقتران.",
    BackgroundOrderAlertFailure.bindingFailed:
        "تأكد التسجيل، لكن تعذّر ربط التنبيهات بهذا الجهاز. تابع استخدام صندوق الطلبات وتواصل مع الدعم.",
    BackgroundOrderAlertFailure.cleanupFailed:
        "تعذّر تأكيد إيقاف التنبيهات، لذا أُوقف أي تفعيل إضافي. تواصل مع الدعم قبل المحاولة مجددًا.",
  },
  'he': {
    BackgroundOrderAlertFailure.permissionDenied:
        "ההתראות חסומות. יש לאפשר התראות ל-POS בהגדרות Android, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.notificationsDisabled:
        "ההתראות חסומות. יש לאפשר התראות ל-POS בהגדרות Android, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.channelUnavailable:
        "בהגדרות ההתראות של Android, יש להגדיר התראות איסוף בחשיבות גבוהה ולבחור צליל, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.channelImportanceTooLow:
        "בהגדרות ההתראות של Android, יש להגדיר התראות איסוף בחשיבות גבוהה ולבחור צליל, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.channelSoundMissing:
        "בהגדרות ההתראות של Android, יש להגדיר התראות איסוף בחשיבות גבוהה ולבחור צליל, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.firebaseUnavailable:
        "שירותי ההתראות אינם זמינים באפליקציה זו. יש להמשיך להשתמש בתיבת ההזמנות ולפנות לתמיכה.",
    BackgroundOrderAlertFailure.tokenUnavailable:
        "לא ניתן לקבל אסימון התראות. יש לבדוק את חיבור המכשיר ושירותי ההתראות, ואז להפעיל שוב את ההתראות.",
    BackgroundOrderAlertFailure.registrationDisabled:
        "התראות הרקע מושבתות בהיקף הרשאה זה. יש לבקש ממנהל מורשה לבדוק את הגדרות ההתראות.",
    BackgroundOrderAlertFailure.registrationRejected:
        "רישום ההתראות נדחה. יש לפנות לתמיכה לבדיקת הרישום ושיוך ההתקנה הקיים. אין לאפס את הצימוד.",
    BackgroundOrderAlertFailure.registrationUncertain:
        "תוצאת הרישום אינה מאומתת, ולכן הפעלה נוספת חסומה. יש לפנות לתמיכה לבירור; אין לנסות שוב או לאפס את הצימוד.",
    BackgroundOrderAlertFailure.bindingFailed:
        "הרישום אושר, אך לא ניתן לקשר את ההתראות במכשיר זה. יש להמשיך להשתמש בתיבת ההזמנות ולפנות לתמיכה.",
    BackgroundOrderAlertFailure.cleanupFailed:
        "לא ניתן לאמת שההתראות הופסקו, ולכן הפעלה נוספת חסומה. יש לפנות לתמיכה לפני ניסיון נוסף.",
  },
};
void main() {
  for (final locale in _expected.entries) {
    for (final example in locale.value.entries) {
      testWidgets('actionable ${example.key.name} feedback ${locale.key}', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              onlineOrderInboxIdentityProvider.overrideWithValue(
                'synthetic-authority',
              ),
              onlineOrderInboxControllerProvider.overrideWith(_EmptyInbox.new),
              onlineInboxPrintRecoveryProvider.overrideWith(
                (ref) async => null,
              ),
              backgroundOrderAlertsProvider.overrideWith(
                () => _FailedAlerts(example.key),
              ),
            ],
            child: MaterialApp(
              locale: Locale(locale.key),
              supportedLocales: kSupportedLocales,
              localizationsDelegates: restoflowLocalizationsDelegates,
              home: const Scaffold(body: OnlineOrderInboxSheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final control = find.byKey(const Key('background-order-alert-switch'));
        expect(
          find.descendant(of: control, matching: find.text(example.value)),
          findsOneWidget,
        );
        expect(tester.widget<SwitchListTile>(control).value, false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
