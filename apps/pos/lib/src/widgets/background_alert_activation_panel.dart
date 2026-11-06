import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../media/background_order_alert_bridge.dart';
import '../state/background_alert_attempt_report.dart';
import '../state/background_alert_duty.dart';
import '../state/background_order_alerts.dart';

/// Current bound grant, separate from the historical activation report below.
class BackgroundAlertGrantStatus extends StatelessWidget {
  const BackgroundAlertGrantStatus({
    super.key,
    required this.authorizedUntil,
    required this.expired,
    required this.onDisable,
  });

  final DateTime? authorizedUntil;
  final bool expired;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final copy = _Copy(Localizations.localeOf(context).languageCode);
    if (expired) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          key: const Key('background-alert-clear-preference'),
          onPressed: onDisable,
          child: Text(copy.text('clear_opt_in')),
        ),
      );
    }
    final until = authorizedUntil?.toLocal();
    if (until == null) return const SizedBox.shrink();
    final local = MaterialLocalizations.of(context);
    final date = local.formatShortDate(until);
    final time = TimeOfDay.fromDateTime(until).format(context);
    return Text(
      copy.field('authorized_until', '$date $time'),
      key: const Key('background-alert-authorized-until'),
    );
  }
}

/// Presents the server-approved time before any enrollment RPC.
class ShiftAlertControl extends ConsumerStatefulWidget {
  const ShiftAlertControl({super.key});
  @override
  ConsumerState<ShiftAlertControl> createState() => _ShiftAlertControlState();
}

class _ShiftAlertControlState extends ConsumerState<ShiftAlertControl> {
  bool _pending = false;
  Future<void> _choose() async {
    if (_pending) return;
    final controller = ref.read(backgroundOrderAlertsProvider.notifier);
    final copy = _Copy(Localizations.localeOf(context).languageCode);
    setState(() => _pending = true);
    try {
      final preview = await controller.previewShift();
      if (preview == null) {
        if (mounted)
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(copy.text('shift_unavailable'))),
          );
        return;
      }
      if (!mounted) {
        await controller.cancelShiftPreview(preview);
        return;
      }
      final date = preview.end.toLocal(),
          labels = MaterialLocalizations.of(context);
      final end =
          '${labels.formatFullDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(copy.text('shift_enable')),
          content: Text(
            '${copy.text('shift_until')} $end\n${copy.text('shift_scope')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(labels.cancelButtonLabel),
            ),
            FilledButton(
              key: const Key('shift-alert-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(copy.text('shift_confirm')),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) {
        await controller.cancelShiftPreview(preview);
        return;
      }
      final ok = await controller.confirmShift(preview);
      if (!ok && mounted)
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(copy.text('shift_unavailable'))),
        );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backgroundOrderAlertsProvider);
    final controller = ref.read(backgroundOrderAlertsProvider.notifier);
    final copy = _Copy(Localizations.localeOf(context).languageCode);
    if (state.shiftPhase == ShiftAlertPhase.active && state.enabled) {
      return Text(
        copy.text('shift_active'),
        key: const Key('shift-alert-active'),
      );
    }
    final offer = controller.canPreviewShift;
    final stop = controller.needsDutyStop && !state.authorizationExpired;
    if (!offer && !stop) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.shiftPhase == ShiftAlertPhase.pending)
          Text(copy.text('shift_unknown')),
        if (state.shiftPhase == ShiftAlertPhase.revoking)
          Text(
            copy.text('shift_revoking'),
            key: const Key('shift-alert-revoking'),
          ),
        if (stop)
          TextButton(
            key: const Key('shift-alert-stop'),
            onPressed: () => controller.setEnabled(false),
            child: Text(copy.text('shift_stop')),
          ),
        if (offer)
          TextButton(
            key: const Key('shift-alert-preview'),
            onPressed: _pending ? null : _choose,
            child: Text(copy.text('shift_enable')),
          ),
      ],
    );
  }
}

/// Small read-only support view. Opening settings never prepares/registers/binds.
class BackgroundAlertActivationPanel extends ConsumerStatefulWidget {
  const BackgroundAlertActivationPanel({super.key});
  @override
  ConsumerState<BackgroundAlertActivationPanel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<BackgroundAlertActivationPanel>
    with WidgetsBindingObserver {
  BackgroundAlertAttemptReport? _attempt;
  BackgroundAlertReadiness _readiness = BackgroundAlertReadiness.fromNative({});
  bool _previous = true, _reading = false, _opening = false;
  bool _settingsFailed = false;
  DateTime? _readAt;
  final _timeouts = <Timer>{};

  Future<T> _bounded<T>(Future<T> work, T fallback) async {
    final timeout = Completer<T>();
    final timer = Timer(
      const Duration(seconds: 3),
      () => timeout.complete(fallback),
    );
    _timeouts.add(timer);
    try {
      return await Future.any([work, timeout.future]);
    } finally {
      timer.cancel();
      _timeouts.remove(timer);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    latestBackgroundAlertAttempt.addListener(_onAttempt);
    _attempt = latestBackgroundAlertAttempt.value;
    _previous = _attempt == null;
    unawaited(_load());
    unawaited(_refresh());
  }

  Future<void> _load() async {
    final report = await BackgroundAlertAttemptReport.load();
    if (mounted && _attempt == null) setState(() => _attempt = report);
  }

  void _onAttempt() {
    if (!mounted) return;
    setState(() {
      _attempt = latestBackgroundAlertAttempt.value;
      _previous = false;
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;
    final bridge = ref.read(backgroundOrderAlertBridgeProvider);
    var raw = <String, dynamic>{};
    try {
      if (bridge is BackgroundOrderAlertActivationSupport) {
        raw = await _bounded(
          (bridge as BackgroundOrderAlertActivationSupport).activationStatus(),
          <String, dynamic>{},
        );
      }
    } catch (_) {
      /* Unknown is not false or a registration failure. */
    }
    if (!mounted) return;
    setState(() {
      _readiness = BackgroundAlertReadiness.fromNative(raw);
      _readAt = DateTime.now().toUtc();
      _reading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _settings(bool channel) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _settingsFailed = false;
    });
    var opened = false;
    try {
      final bridge = ref.read(backgroundOrderAlertBridgeProvider);
      if (bridge is BackgroundOrderAlertActivationSupport) {
        opened = await _bounded(
          (bridge as BackgroundOrderAlertActivationSupport)
              .openNotificationSettings(channel: channel),
          false,
        );
      }
    } catch (_) {
      /* Keep Inbox usable; never expose platform exceptions. */
    }
    if (mounted)
      setState(() {
        _opening = false;
        _settingsFailed = !opened;
      });
  }

  @override
  void dispose() {
    for (final timer in _timeouts) {
      timer.cancel();
    }
    latestBackgroundAlertAttempt.removeListener(_onAttempt);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _Copy(Localizations.localeOf(context).languageCode);
    final values = _readiness.values;
    final attempt = _attempt?.values;
    final permissions =
        values['permission_allowed'] == false ||
        values['notifications_enabled'] == false;
    final channel =
        values['channel_present'] == false ||
        values['channel_importance_allowed'] == false ||
        values['channel_sound_present'] == false;
    String display(Object? value) => value == null || value == 'unknown'
        ? copy.text('unknown')
        : value == true
        ? copy.text('yes')
        : value == false
        ? copy.text('no')
        : '$value';
    Widget row(String key, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(copy.field(key, display(value))),
    );
    return ExpansionTile(
      key: const Key('background-alert-diagnostics'),
      tilePadding: EdgeInsets.zero,
      title: Text(copy.text('title')),
      subtitle: Text(
        copy.summary(
          display(values['app_version']),
          display(attempt?['result']),
        ),
      ),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(copy.text(_previous ? 'previous' : 'attempt')),
              if (attempt != null) ...[
                row('at', attempt['at']),
                for (final key in [
                  'result',
                  ...BackgroundAlertAttemptReport.flags,
                  'registration',
                ])
                  row(key, attempt[key]),
              ] else
                Text(copy.text('unknown')),
              const Divider(),
              Text(copy.text('current')),
              row('at', _readAt?.toIso8601String()),
              for (final entry in values.entries) row(entry.key, entry.value),
              if (permissions || channel) ...[
                Text(copy.text('settings_help')),
                TextButton.icon(
                  key: const Key('background-alert-settings'),
                  onPressed: _opening
                      ? null
                      : () => _settings(!permissions && channel),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(copy.text('settings')),
                ),
                if (_settingsFailed)
                  Text(
                    copy.text('settings_unavailable'),
                    key: const Key('background-alert-settings-unavailable'),
                  ),
              ],
              TextButton.icon(
                key: const Key('background-alert-copy'),
                onPressed: () async {
                  // Only already-validated projections can reach the clipboard.
                  final summary = jsonEncode({
                    'attempt_kind': _previous ? 'previous' : 'current',
                    'attempt': attempt,
                    'current_readiness_at': _readAt?.toIso8601String(),
                    'current_readiness': values,
                  });
                  if (utf8.encode(summary).length > 4096) return;
                  try {
                    await Clipboard.setData(ClipboardData(text: summary));
                  } catch (_) {
                    /* No payload/exception logging. */
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: Text(copy.text('copy')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Feature-local copy keeps the payment workstream's shared ARB files untouched.
class _Copy {
  const _Copy(this.language);
  final String language;
  String field(String key, String value) => '${text(key)}: $value';
  String summary(String version, String result) =>
      '${field('app_version', version)} · ${field('result', result)}';
  String text(String key) {
    final row = _words[key];
    return row == null
        ? key
        : row[language == 'ar'
              ? 0
              : language == 'he'
              ? 1
              : 2];
  }

  static const _words = <String, List<String>>{
    'shift_unknown': [
      'تعذّر التحقق من جاهزية تنبيهات المناوبة',
      'כשירות התראות המשמרת טרם אומתה',
      'Shift alert readiness is unconfirmed',
    ],
    'shift_stop': [
      'إيقاف التنبيهات على هذا الجهاز',
      'כיבוי התראות במכשיר זה',
      'Turn off alerts on this device',
    ],
    'shift_enable': [
      'تنبيهات المناوبة لهذا الجهاز',
      'התראות משמרת למכשיר הזה',
      'Shift alerts for this device',
    ],
    'shift_until': [
      'يسمح الخادم بالتنبيه حتى',
      'השרת מאשר התראות עד',
      'The server authorizes alerts until',
    ],
    'shift_scope': [
      'يستطيع الجهاز التنبيه بعد قفل الشاشة وانتهاء جلسة الموظف. تتطلب إدارة الطلبات إدخال PIN.',
      'המכשיר יכול להתריע לאחר נעילה ותום חיבור העובד. פעולות בהזמנות דורשות קוד PIN.',
      'The device may alert after the screen locks and staff sign-in expires. Order actions still require a PIN.',
    ],
    'shift_confirm': [
      'تفعيل تنبيهات المناوبة',
      'הפעלת התראות משמרת',
      'Enable shift alerts',
    ],
    'shift_active': [
      'تنبيهات المناوبة مفعّلة لهذا الجهاز',
      'התראות המשמרת מופעלות במכשיר זה',
      'Shift alerts enabled on this device',
    ],
    'shift_revoking': [
      'جارٍ التحقق من إلغاء تفويض المناوبة',
      'ביטול הרשאת המשמרת ממתין לאימות',
      'Shift alert revocation awaiting confirmation',
    ],
    'shift_unavailable': [
      'تعذّر تأكيد تفويض تنبيهات المناوبة لهذا الجهاز.',
      'לא ניתן לאשר הרשאת התראות משמרת למכשיר זה.',
      'Shift alert authorization could not be confirmed for this device.',
    ],
    'authorized_until': [
      'تفويض التنبيهات الحالي صالح حتى',
      'הרשאת ההתראות הנוכחית בתוקף עד',
      'Current alert authorization valid until',
    ],
    'clear_opt_in': [
      'إلغاء تفضيل تفعيل التنبيهات',
      'ביטול ההעדפה לקבלת התראות',
      'Clear saved alert preference',
    ],
    'title': [
      'تفاصيل تفعيل التنبيهات',
      'פרטי הפעלת התראות',
      'Alert activation details',
    ],
    'app_version': ['إصدار التطبيق', 'גרסת האפליקציה', 'App version'],
    'result': ['رمز النتيجة', 'קוד התוצאה', 'Result code'],
    'unknown': [
      'غير معروف / لم يُفحص',
      'לא ידוע / לא נבדק',
      'Unknown / not checked',
    ],
    'yes': ['نعم', 'כן', 'Yes'],
    'no': ['لا', 'לא', 'No'],
    'previous': [
      'نتيجة سابقة محفوظة؛ لا تثبت الحالة الحالية',
      'תוצאה קודמת שנשמרה; אינה מעידה על המצב הנוכחי',
      'Saved previous result; does not establish current state',
    ],
    'attempt': [
      'نتيجة آخر محاولة في هذا التشغيل',
      'תוצאת הניסיון האחרון בהפעלה זו',
      'Last attempt in this app run',
    ],
    'current': [
      'إعدادات Android الحالية؛ ليست نتيجة المحاولة السابقة',
      'הגדרות Android כעת; לא תוצאת הניסיון הקודם',
      'Current Android settings; not evidence of the earlier attempt',
    ],
    'at': ['الوقت UTC', 'זמן UTC', 'Time UTC'],
    'android_sdk': ['إصدار Android SDK', 'גרסת Android SDK', 'Android SDK'],
    'model': ['طراز الجهاز', 'דגם המכשיר', 'Device model'],
    'permission_allowed': [
      'إذن الإشعارات',
      'הרשאת התראות',
      'Notification permission',
    ],
    'notifications_enabled': [
      'إشعارات التطبيق مسموحة',
      'התראות האפליקציה מותרות',
      'App notifications allowed',
    ],
    'channel_present': [
      'قناة التنبيه موجودة',
      'ערוץ ההתראות קיים',
      'Alert channel present',
    ],
    'channel_importance_allowed': [
      'أهمية القناة مناسبة',
      'חשיבות הערוץ מתאימה',
      'Channel importance allowed',
    ],
    'channel_sound_present': [
      'صوت القناة موجود',
      'צליל הערוץ קיים',
      'Channel sound present',
    ],
    'google_play_services': [
      'خدمات Google Play',
      'שירותי Google Play',
      'Google Play services',
    ],
    'firebase_initialized': [
      'تهيئة Firebase',
      'אתחול Firebase',
      'Firebase initialized',
    ],
    'token_acquired': [
      'الحصول على رمز الإشعارات',
      'קבלת אסימון התראות',
      'Notification token acquired',
    ],
    'registration': ['نتيجة التسجيل', 'תוצאת הרישום', 'Registration result'],
    'bound': ['الربط المحلي', 'הקישור המקומי', 'Local binding'],
    'registration_quarantined': [
      'التفعيل موقوف لنتيجة غير مؤكدة',
      'הפעלה חסומה עקב תוצאה לא מאומתת',
      'Activation held for uncertain result',
    ],
    'cleanup_quarantined': [
      'التفعيل موقوف لتأكيد الإيقاف',
      'הפעלה חסומה עד אימות הכיבוי',
      'Activation held for shutdown confirmation',
    ],
    'settings': [
      'فتح إعدادات الإشعارات',
      'פתיחת הגדרות התראות',
      'Open notification settings',
    ],
    'settings_unavailable': [
      'تعذّر فتح الإعدادات. افتح إعدادات Android ثم التطبيقات ثم POS ثم الإشعارات.',
      'לא ניתן לפתוח את ההגדרות. יש לפתוח הגדרות Android, אפליקציות, POS ואז התראות.',
      'Could not open Settings. Open Android Settings, then Apps, POS, and Notifications.',
    ],
    'settings_help': [
      'بعد العودة، فعّل التنبيهات بنفسك مرة واحدة. فتح الإعدادات لا يفعّلها.',
      'לאחר החזרה, יש להפעיל התראות ידנית פעם אחת. פתיחת ההגדרות אינה מפעילה אותן.',
      'After returning, enable alerts explicitly once. Opening Settings does not enable them.',
    ],
    'copy': [
      'نسخ ملخص التشخيص الآمن',
      'העתקת סיכום אבחון בטוח',
      'Copy safe diagnostic summary',
    ],
  };
}
