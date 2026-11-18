import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

import 'storefront_background_upload.dart';
import 'storefront_content_models.dart';
import 'storefront_media_publisher.dart';
import 'storefront_media_slot.dart';
import 'storefront_models.dart';
import 'storefront_profile_repository.dart';

/// An independently uploaded welcome original, not the current receipt logo.
/// The existing publisher creates the editorial w960 derivative; only the
/// existing profile CAS assigner can then place it in the welcome Hero slot.
/// Welcome text/content remains a separate draft/save operation.
class StorefrontWelcomeImageUpload extends StatefulWidget {
  const StorefrontWelcomeImageUpload({
    required this.upload,
    required this.publisher,
    required this.onAssign,
    required this.onRefresh,
    required this.bindingIdentity,
    this.onBusyChanged,
    this.enabled = true,
    this.nonce,
    super.key,
  });

  final StorefrontBackgroundUpload upload;
  final StorefrontMediaPublisher publisher;
  final StorefrontSlotAssigner onAssign;
  final StorefrontRefresher onRefresh;

  /// Stable while this authenticated member/restaurant/branch binding is valid.
  /// The parent must change it on authority/binding changes and guard all three
  /// callbacks against their captured binding before changing parent state.
  final Object bindingIdentity;
  final ValueChanged<bool>? onBusyChanged;
  final bool enabled;
  final int Function()? nonce;

  @override
  State<StorefrontWelcomeImageUpload> createState() =>
      _StorefrontWelcomeImageUploadState();
}

class _Binding {
  _Binding(StorefrontWelcomeImageUpload widget)
    : upload = widget.upload,
      publisher = widget.publisher,
      identity = widget.bindingIdentity,
      assign = widget.onAssign,
      refresh = widget.onRefresh,
      busy = widget.onBusyChanged;
  final StorefrontBackgroundUpload upload;
  final StorefrontMediaPublisher publisher;
  final Object identity;
  final StorefrontSlotAssigner assign;
  final StorefrontRefresher refresh;
  final ValueChanged<bool>? busy;

  bool matches(StorefrontWelcomeImageUpload widget) =>
      identical(upload, widget.upload) &&
      identical(publisher, widget.publisher) &&
      identity == widget.bindingIdentity;
}

class _Operation {
  _Operation(this.binding, this.generation);
  final _Binding binding;
  final int generation;
  bool released = false;
}

class _Retry {
  const _Retry.publish(this.binding, this.source, this.requestId)
    : mediaId = null,
      replay = null;
  const _Retry.assign(this.binding, this.mediaId, this.replay)
    : source = null,
      requestId = null;
  final _Binding binding;
  final StorefrontMediaSource? source;
  final String? requestId, mediaId;
  final StorefrontSlotReplay? replay;
}

class _StorefrontWelcomeImageUploadState
    extends State<StorefrontWelcomeImageUpload> {
  int _generation = 0;
  bool _busy = false, _unknown = false;
  String? _message;
  _Operation? _active;
  _Retry? _retry;
  DialogRoute<bool>? _dialog;

  bool get _scopeSafe =>
      isCanonicalUuid(widget.upload.organizationId) &&
      isCanonicalUuid(widget.upload.restaurantId) &&
      widget.upload.organizationId == widget.publisher.organizationId &&
      widget.upload.restaurantId == widget.publisher.restaurantId;

  bool _current(_Operation operation) =>
      mounted &&
      operation.generation == _generation &&
      operation.binding.matches(widget);

  @override
  void didUpdateWidget(covariant StorefrontWelcomeImageUpload oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.upload, widget.upload) ||
        !identical(oldWidget.publisher, widget.publisher) ||
        oldWidget.bindingIdentity != widget.bindingIdentity) {
      _invalidate(defer: true);
      // didUpdateWidget already schedules this build; no setState/callback in it.
      _message = null;
    }
  }

  void _closeDialogLater() {
    final route = _dialog;
    _dialog = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute<bool>(route, false);
    });
  }

  void _release(_Operation operation, {bool defer = false}) {
    if (operation.released) return;
    operation.released = true;
    // Release only the callback that acquired this operation. The parent guards
    // this old callback by binding; a replacement binding never receives it.
    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        operation.binding.busy?.call(false);
      });
    } else {
      operation.binding.busy?.call(false);
    }
  }

  void _invalidate({bool defer = false}) {
    _generation++;
    final active = _active;
    _active = null;
    _busy = false;
    _retry = null;
    _unknown = false;
    _closeDialogLater();
    if (active != null) _release(active, defer: defer);
  }

  @override
  void dispose() {
    _invalidate(defer: true);
    super.dispose();
  }

  _Operation _start(_Binding binding, String message) {
    final operation = _Operation(binding, ++_generation);
    setState(() {
      _active = operation;
      _busy = true;
      _message = message;
      _retry = null;
    });
    binding.busy?.call(true);
    return operation;
  }

  void _finish(
    _Operation operation,
    String? message, {
    _Retry? retry,
    bool unknown = false,
  }) {
    if (_current(operation)) {
      setState(() {
        _active = null;
        _busy = false;
        _message = message;
        _retry = retry;
        _unknown = unknown;
      });
    }
    _release(operation);
  }

  Future<void> _refresh(_Operation operation) async {
    if (!_current(operation)) return;
    try {
      await operation.binding.refresh();
    } catch (_) {
      // This does not establish publication/assignment; the unknown/failure
      // message and exact retry identity remain the source of truth here.
    }
  }

  Future<void> _pick() async {
    if (_busy ||
        _unknown ||
        !widget.enabled ||
        !_scopeSafe ||
        !widget.upload.supported)
      return;
    final operation = _start(_Binding(widget), 'confirming');
    final l10n = AppLocalizations.of(context);
    var answered = false;
    void answer(BuildContext dialogContext, bool choice) {
      if (answered || !_current(operation)) return;
      answered = true;
      Navigator.of(dialogContext).pop(choice);
    }

    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('welcome-image-upload-confirm'),
        title: Text(_copy(l10n, 'confirmTitle')),
        content: Text(_copy(l10n, 'confirmBody')),
        actions: [
          TextButton(
            key: const Key('welcome-image-upload-confirm-cancel'),
            onPressed: () => answer(dialogContext, false),
            child: Text(_copy(l10n, 'cancel')),
          ),
          FilledButton(
            key: const Key('welcome-image-upload-confirm-action'),
            onPressed: () => answer(dialogContext, true),
            child: Text(_copy(l10n, 'confirmAction')),
          ),
        ],
      ),
    );
    _dialog = route;
    final confirmed = await Navigator.of(context).push<bool>(route);
    if (identical(_dialog, route)) _dialog = null;
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    if (confirmed != true) {
      _finish(operation, null);
      return;
    }
    setState(() => _message = 'uploading');
    StorefrontMediaSource? source;
    try {
      source = await operation.binding.upload.pickAndUpload(
        isCurrent: () => _current(operation),
      );
    } catch (_) {
      _finish(operation, 'uploadFailed');
      return;
    }
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    if (source == null) {
      _finish(operation, null);
      return;
    }
    final prefix =
        '${operation.binding.publisher.organizationId}/'
        '${operation.binding.publisher.restaurantId}/logo/';
    final filename = source.key.startsWith(prefix)
        ? source.key.substring(prefix.length)
        : '';
    if (source.bucket != StorefrontSourceBucket.restaurantLogos ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$',
        ).hasMatch(filename)) {
      _finish(operation, 'sourceMismatch');
      return;
    }
    final requestId = storefrontRequestId(
      'pbl:welcome-image:',
      [
        operation.binding.publisher.organizationId,
        operation.binding.publisher.restaurantId,
        source.bucket.wire,
        source.key,
      ],
      widget.nonce?.call() ?? DateTime.now().microsecondsSinceEpoch,
    );
    await _publish(operation, source, requestId);
  }

  Future<void> _publish(
    _Operation operation,
    StorefrontMediaSource source,
    String requestId,
  ) async {
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    setState(() => _message = 'publishing');
    StorefrontPublishResult result;
    try {
      result = await operation.binding.publisher.publish(
        slot: StorefrontEditorialTarget.editorial,
        source: source,
        requestId: requestId,
      );
    } catch (_) {
      await _refresh(operation);
      _finish(
        operation,
        'publishUnknown',
        unknown: true,
        retry: _Retry.publish(operation.binding, source, requestId),
      );
      return;
    }
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    if (result.status == StorefrontPublishStatus.published) {
      final media = result.media;
      final key = media == null
          ? null
          : RegExp(
              r'^[0-9a-f]{32}/([0-9a-f]{64})\.webp$',
            ).firstMatch(media.objectKey);
      if (media == null ||
          !isCanonicalUuid(media.id) ||
          key == null ||
          key.group(1) != media.contentHash ||
          media.sourceBucket != source.bucket ||
          media.sourceKey != source.key ||
          media.variant != StorefrontVariant.w960 ||
          media.width < 1 ||
          media.height < 1 ||
          media.width > 960 ||
          media.height > 960 ||
          media.byteLength < 1 ||
          media.byteLength > 512 * 1024 ||
          result.requestId != requestId ||
          result.slot != StorefrontEditorialTarget.editorial) {
        await _refresh(operation);
        _finish(
          operation,
          'publishUnknown',
          unknown: true,
          retry: _Retry.publish(operation.binding, source, requestId),
        );
        return;
      }
      await _assign(operation, media.id);
      return;
    }
    await _refresh(operation);
    final uncertain = result.status == StorefrontPublishStatus.uncertain;
    final message = switch (result.status) {
      StorefrontPublishStatus.uncertain => 'publishUnknown',
      StorefrontPublishStatus.refused => 'refused',
      StorefrontPublishStatus.denied => 'denied',
      StorefrontPublishStatus.unauthenticated => 'unauthenticated',
      StorefrontPublishStatus.sourceMissing => 'sourceMissing',
      StorefrontPublishStatus.restartRequired => 'restart',
      StorefrontPublishStatus.objectConflict => 'objectConflict',
      StorefrontPublishStatus.invalidRequest => 'invalid',
      _ => 'unavailable',
    };
    _finish(
      operation,
      message,
      unknown: uncertain,
      retry: uncertain
          ? _Retry.publish(operation.binding, source, requestId)
          : null,
    );
  }

  Future<void> _assign(
    _Operation operation,
    String mediaId, {
    StorefrontSlotReplay? replay,
  }) async {
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    setState(() => _message = 'assigning');
    StorefrontWriteResult result;
    try {
      result = await operation.binding.assign(
        StorefrontSlot.hero,
        mediaId,
        reReadFirst: true,
        replay: replay,
      );
    } catch (_) {
      // No invented request/version: without them only a read can reconcile.
      await _refresh(operation);
      _finish(operation, 'assignUnknown', unknown: true);
      return;
    }
    if (!_current(operation)) {
      _release(operation);
      return;
    }
    if (result.status == StorefrontWriteStatus.uncertain) {
      final id = result.requestId, version = result.expectedVersion;
      final exact =
          id != null && isCanonicalUuid(id) && version != null && version >= 0
          ? StorefrontSlotReplay(requestId: id, expectedVersion: version)
          : replay;
      _finish(
        operation,
        'assignUnknown',
        unknown: true,
        retry: exact == null
            ? null
            : _Retry.assign(operation.binding, mediaId, exact),
      );
      return;
    }
    _finish(operation, switch (result.status) {
      StorefrontWriteStatus.ok => 'applied',
      StorefrontWriteStatus.conflict => 'conflict',
      StorefrontWriteStatus.denied => 'denied',
      StorefrontWriteStatus.invalid => 'assignRefused',
      _ => 'assignFailed',
    });
  }

  Future<void> _tryAgain() async {
    final retry = _retry;
    if (_busy ||
        !widget.enabled ||
        !_scopeSafe ||
        retry == null ||
        !retry.binding.matches(widget))
      return;
    final operation = _start(retry.binding, 'publishing');
    if (retry.source != null) {
      await _publish(operation, retry.source!, retry.requestId!);
    } else {
      await _assign(operation, retry.mediaId!, replay: retry.replay);
    }
  }

  void _cancel() {
    final partial = _busy || _unknown;
    _invalidate();
    setState(() => _message = partial ? 'cancelledPartial' : null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('welcome-image-upload'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_copy(l10n, 'help'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('welcome-image-upload-pick'),
              onPressed:
                  widget.enabled &&
                      _scopeSafe &&
                      widget.upload.supported &&
                      !_busy &&
                      !_unknown
                  ? _pick
                  : null,
              icon: const Icon(Icons.upload_outlined),
              label: Text(_copy(l10n, 'upload')),
            ),
            if (_retry != null)
              OutlinedButton(
                key: const Key('welcome-image-upload-retry'),
                onPressed: widget.enabled && !_busy && _scopeSafe
                    ? _tryAgain
                    : null,
                child: Text(_copy(l10n, 'retry')),
              ),
            if (_busy || _unknown)
              TextButton(
                key: const Key('welcome-image-upload-cancel'),
                onPressed: _cancel,
                child: Text(_copy(l10n, 'cancel')),
              ),
          ],
        ),
        if (!_scopeSafe) Text(_copy(l10n, 'bindingMismatch')),
        if (!widget.upload.supported) Text(_copy(l10n, 'unsupported')),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _copy(l10n, _message!),
              key: const Key('welcome-image-upload-message'),
            ),
          ),
      ],
    );
  }
}

String _copy(AppLocalizations l10n, String key) {
  const values = <String, List<String>>{
    'help': [
      'Choose a background image from your device. The image is saved after confirmation; text and background type use Save welcome page below.',
      'اختر صورة خلفية من جهازك. تُحفظ الصورة بعد التأكيد؛ النصوص ونوع الخلفية من زر «حفظ صفحة الترحيب» بالأسفل.',
      'בחרו תמונת רקע מהמכשיר. התמונה נשמרת לאחר אישור; הטקסט וסוג הרקע נשמרים בכפתור שמירת עמוד הפתיחה למטה.',
    ],
    'upload': [
      'Choose image from device',
      'اختيار صورة من الجهاز',
      'בחירת תמונה מהמכשיר',
    ],
    'confirmTitle': [
      'Change the welcome image?',
      'تغيير صورة الترحيب؟',
      'להחליף את תמונת הפתיחה?',
    ],
    'confirmBody': [
      'A copy of the image will be visible to visitors and saved as the welcome image. Choose a file intended for public viewing. Text and background type are saved separately below.',
      'ستُجهّز نسخة يراها الزوار وتُحفظ كصورة الترحيب. اختر صورة مناسبة للعرض العام. تُحفظ النصوص ونوع الخلفية من الزر بالأسفل.',
      'עותק של התמונה יוצג למבקרים ויישמר כתמונת הפתיחה. בחרו קובץ המיועד לצפייה ציבורית. הטקסט וסוג הרקע נשמרים בנפרד למטה.',
    ],
    'confirmAction': ['Choose image', 'اختيار الصورة', 'בחירת תמונה'],
    'cancel': ['Cancel', 'إلغاء', 'ביטול'],
    'retry': [
      'Try the same operation again',
      'إعادة المحاولة نفسها',
      'ניסיון חוזר של אותה פעולה',
    ],
    'confirming': [
      'Confirm before upload.',
      'أكّد قبل الرفع.',
      'יש לאשר לפני ההעלאה.',
    ],
    'uploading': ['Uploading image…', 'جارٍ رفع الصورة…', 'מעלה תמונה…'],
    'publishing': ['Preparing image…', 'جارٍ تجهيز الصورة…', 'מכין תמונה…'],
    'assigning': ['Saving image…', 'جارٍ حفظ الصورة…', 'שומר תמונה…'],
    'applied': [
      'Welcome image saved. Use Save welcome page below for text and background type.',
      'حُفظت صورة الترحيب. احفظ النصوص ونوع الخلفية من زر «حفظ صفحة الترحيب» بالأسفل.',
      'תמונת הפתיחה נשמרה. שמרו את הטקסט וסוג הרקע בכפתור שמירת עמוד הפתיחה למטה.',
    ],
    'uploadFailed': [
      'The upload could not be confirmed. No published image was confirmed.',
      'تعذّر تأكيد الرفع. لم تتأكد صورة منشورة.',
      'לא ניתן לאשר את ההעלאה. לא אושרה תמונה שפורסמה.',
    ],
    'publishUnknown': [
      'Publication is unconfirmed. Current settings were requested; retry uses the same original and request.',
      'نتيجة النشر غير مؤكدة. طُلبت قراءة الإعدادات؛ المحاولة تعيد الأصل والطلب نفسيهما.',
      'הפרסום אינו מאושר. התבקשה קריאת ההגדרות; הניסיון החוזר משתמש באותו מקור ובאותה בקשה.',
    ],
    'assignUnknown': [
      'The welcome assignment is unconfirmed. Retry, when available, repeats only the original assignment; it does not upload or publish again.',
      'تطبيق صورة الترحيب غير مؤكد. المحاولة المتاحة تعيد طلب التطبيق الأصلي فقط، دون رفع أو نشر جديد.',
      'החלת תמונת הפתיחה אינה מאושרת. אם זמין, הניסיון החוזר חוזר רק על ההחלה המקורית, ללא העלאה או פרסום נוספים.',
    ],
    'refused': [
      'The publisher refused this source. Choose another supported image.',
      'رفض الناشر هذه الصورة. اختر صورة مدعومة أخرى.',
      'המפרסם דחה מקור זה. יש לבחור תמונה נתמכת אחרת.',
    ],
    'denied': [
      'The current member cannot complete this action.',
      'المستخدم الحالي لا يملك صلاحية إكمال هذه العملية.',
      'למשתמש הנוכחי אין הרשאה להשלים פעולה זו.',
    ],
    'unauthenticated': [
      'Sign in again before publishing.',
      'سجّل الدخول مجددًا قبل النشر.',
      'יש להתחבר מחדש לפני הפרסום.',
    ],
    'sourceMissing': [
      'The private original is unavailable. No publication was confirmed.',
      'الأصل الخاص غير متاح. لم يتأكد النشر.',
      'המקור הפרטי אינו זמין. הפרסום לא אושר.',
    ],
    'sourceMismatch': [
      'The uploaded source does not match this restaurant. No assignment was requested.',
      'مصدر الرفع لا يطابق هذا المطعم. لم يُطلب تطبيق صورة.',
      'מקור ההעלאה אינו תואם למסעדה. לא התבקשה החלת תמונה.',
    ],
    'restart': [
      'This publish request cannot continue. Re-read settings before choosing a new upload.',
      'لا يمكن متابعة طلب النشر. أعد قراءة الإعدادات قبل اختيار رفع جديد.',
      'לא ניתן להמשיך בבקשת פרסום זו. יש לקרוא מחדש את ההגדרות לפני העלאה חדשה.',
    ],
    'objectConflict': [
      'Stored publication bytes could not be verified. No assignment was requested.',
      'تعذّر التحقق من النسخة المنشورة. لم يُطلب تطبيق صورة.',
      'לא ניתן לאמת את העותק שפורסם. לא התבקשה החלת תמונה.',
    ],
    'invalid': [
      'The publication request was refused. No assignment was requested.',
      'رُفض طلب النشر. لم يُطلب تطبيق صورة.',
      'בקשת הפרסום נדחתה. לא התבקשה החלת תמונה.',
    ],
    'unavailable': [
      'The publishing service is unavailable; publication is not confirmed.',
      'خدمة النشر غير متاحة؛ النشر غير مؤكد.',
      'שירות הפרסום אינו זמין; הפרסום אינו מאושר.',
    ],
    'conflict': [
      'The image was published but was not applied because settings changed. Re-read settings.',
      'نُشرت الصورة ولم تُطبَّق بسبب تغيّر الإعدادات. أعد القراءة.',
      'התמונה פורסמה אך לא הוחלה משום שההגדרות השתנו. יש לקרוא מחדש.',
    ],
    'assignRefused': [
      'The image was published, but applying it was refused. Check the storefront requirements.',
      'نُشرت الصورة لكن رُفض تطبيقها. تحقق من متطلبات الموقع.',
      'התמונה פורסמה, אך החלתה נדחתה. יש לבדוק את דרישות האתר.',
    ],
    'assignFailed': [
      'Publication was confirmed, but applying the image was not completed.',
      'تأكد النشر، لكن تطبيق الصورة لم يكتمل.',
      'הפרסום אושר, אך החלת התמונה לא הושלמה.',
    ],
    'cancelledPartial': [
      'Continuation stopped. An upload, publication or assignment may already have started; re-read current settings. No rollback was performed.',
      'توقفت المتابعة. قد يكون الرفع أو النشر أو التطبيق بدأ؛ أعد قراءة الإعدادات الحالية. لم يُنفَّذ تراجع.',
      'ההמשך נעצר. ייתכן שההעלאה, הפרסום או ההחלה כבר התחילו; יש לקרוא את ההגדרות העדכניות. לא בוצע שחזור.',
    ],
    'bindingMismatch': [
      'Upload and publisher must belong to the same signed-in restaurant.',
      'يجب أن يتبع الرفع والناشر المطعم نفسه في جلسة الدخول الحالية.',
      'ההעלאה והמפרסם חייבים להשתייך לאותה מסעדה מחוברת.',
    ],
    'unsupported': [
      'File picking is unavailable in this environment.',
      'اختيار الملفات غير متاح في هذه البيئة.',
      'בחירת קבצים אינה זמינה בסביבה זו.',
    ],
  };
  final language = l10n.localeName.split(RegExp('[-_]')).first;
  return values[key]![language == 'ar'
      ? 1
      : language == 'he'
      ? 2
      : 0];
}
