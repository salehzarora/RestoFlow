import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'product_cutout_gateway.dart';
import 'product_cutout_processor.dart';

/// Product-only, local candidate review. Private source upload remains owned
/// by MenuImagePanel. Optional removal runs only after explicit intent;
/// ordinary Original review/publication never invokes the processor.
class ProductCutoutEditor extends StatefulWidget {
  const ProductCutoutEditor({
    super.key,
    required this.item,
    required this.gateway,
    this.processor,
    this.removalEnabled = const bool.fromEnvironment(
      'SF_PRODUCT_CUTOUT_REVIEW',
    ),
  });
  final MenuItem item;
  final ProductCutoutGateway gateway;
  final ProductCutoutProcessor? processor;
  final bool removalEnabled;
  @override
  State<ProductCutoutEditor> createState() => _ProductCutoutEditorState();
}

class _ProductCutoutEditorState extends State<ProductCutoutEditor> {
  late final ProductCutoutProcessor _processor =
      widget.processor ?? createProductCutoutProcessor();
  ProductCutoutOriginal? _original;
  ProductCutoutCandidate? _candidate;
  bool _loadingOriginal = false,
      _processing = false,
      _saving = false,
      _publishingDetail = false,
      _removeBackground = false,
      _dark = false;
  int _generation = 0;
  String? _error, _stage, _requestId;
  String? _detailRequestId, _publishedDetailProof;
  ProductCutoutPublishStatus? _detailStatus;
  String? _publishedSelectionProof;
  bool? _publishedRemoveBackground;
  ProductCutoutPublishStatus? _status;

  bool get _alreadyPublished =>
      _original != null &&
      _publishedSelectionProof == _original!.sourceGeneration &&
      _publishedRemoveBackground == _removeBackground;

  String _t(String en, String ar, String he) =>
      switch (Localizations.localeOf(context).languageCode) {
        'ar' => ar,
        'he' => he,
        _ => en,
      };

  @override
  void didUpdateWidget(ProductCutoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.imagePath != widget.item.imagePath ||
        oldWidget.item.id != widget.item.id ||
        oldWidget.item.organizationId != widget.item.organizationId ||
        oldWidget.item.restaurantId != widget.item.restaurantId ||
        oldWidget.removalEnabled != widget.removalEnabled) {
      _cancel();
      _saving = false;
      _publishingDetail = false;
      _original = null;
      _candidate = null;
      _status = null;
      _requestId = null;
      _detailRequestId = _publishedDetailProof = null;
      _detailStatus = null;
      _publishedSelectionProof = null;
      _publishedRemoveBackground = null;
      _removeBackground = false;
      final generation = _generation;
      if (widget.item.imagePath != null)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) _loadOriginal();
        });
    }
  }

  // Selection version advances on publication; it is not source identity.
  // A same-key overwrite must never rebind an old candidate to a fresh proof.
  // Compare both the authoritative source snapshot and the downloaded bytes.
  bool _sameSource(ProductCutoutOriginal before, ProductCutoutOriginal after) {
    if (before.sourceKey != after.sourceKey ||
        before.mimeType != after.mimeType ||
        !listEquals(before.bytes, after.bytes))
      return false;
    try {
      final oldProof = jsonDecode(before.sourceGeneration);
      final newProof = jsonDecode(after.sourceGeneration);
      if (oldProof is! Map ||
          newProof is! Map ||
          oldProof['source_snapshot'] is! Map ||
          newProof['source_snapshot'] is! Map)
        return false;
      Object? canonical(Object? value) {
        if (value is Map) {
          final keys = value.keys.cast<String>().toList()..sort();
          return {for (final key in keys) key: canonical(value[key])};
        }
        if (value is List) return value.map(canonical).toList();
        return value;
      }

      return jsonEncode(canonical(oldProof['source_snapshot'])) ==
          jsonEncode(canonical(newProof['source_snapshot']));
    } catch (_) {
      return false; // An unreadable proof requires fresh processing/review.
    }
  }

  void _cancel() {
    _generation++;
    if (_processing) _processor.cancel();
    _loadingOriginal = false;
    _processing = false;
    _stage = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  Future<void> _prepare() => _loadOriginal(prepareRemoval: true);

  Future<void> _loadOriginal({bool prepareRemoval = false}) async {
    if (_loadingOriginal ||
        _processing ||
        _saving ||
        _status == ProductCutoutPublishStatus.uncertain ||
        _detailStatus == ProductCutoutPublishStatus.uncertain ||
        widget.item.imagePath == null)
      return;
    final generation = ++_generation;
    setState(() {
      _loadingOriginal = true;
      _error = null;
      _status = null;
      _detailStatus = null;
      _stage = 'loading-original';
    });
    try {
      final original = await widget.gateway.loadOriginal(widget.item);
      if (!mounted || generation != _generation) return;
      if (original.sourceKey != widget.item.imagePath)
        throw StateError('Source changed');
      final unchanged = _original != null && _sameSource(_original!, original);
      setState(() {
        _original = original;
        if (!unchanged) {
          _candidate = null;
          _removeBackground = false;
          _publishedSelectionProof = null;
          _publishedRemoveBackground = null;
        }
        _requestId = null;
        _loadingOriginal = false;
        _stage = null;
      });
      // A valid candidate belongs only to this source and editor session.
      // Revalidating/reviewing it must not download the model or infer again.
      if (!prepareRemoval || !widget.removalEnabled || _candidate != null)
        return;
      setState(() {
        _processing = true;
        _stage = 'preparing';
      });
      final candidate = await _processor.process(
        original.bytes,
        original.mimeType,
        onProgress: (stage) {
          if (mounted && generation == _generation)
            setState(() => _stage = stage);
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() => _candidate = candidate);
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _error = _stage == 'loading-original'
              ? _t(
                  'The original photo could not be loaded. Ordinary upload is still available. Try loading Original again.',
                  'تعذر تحميل الصورة الأصلية. رفع الصور المعتاد ما زال متاحًا. حاول تحميل الأصل مجددًا.',
                  'לא ניתן לטעון את התמונה המקורית. העלאה רגילה עדיין זמינה. נסו לטעון שוב את המקור.',
                )
              : _stage == 'unavailable-device'
              ? _t(
                  'Local background removal is not supported on this device. Your original is safe. Use ordinary upload or publish Original.',
                  'إزالة الخلفية المحلية غير مدعومة على هذا الجهاز. الصورة الأصلية محفوظة. يمكنك رفع الصورة كالمعتاد أو نشر الأصل.',
                  'הסרת רקע מקומית אינה נתמכת במכשיר זה. המקור נשמר. אפשר להעלות תמונה כרגיל או לפרסם את המקור.',
                )
              : _t(
                  'Background removal could not finish. Your original is safe. Retry or keep Original.',
                  'تعذرت إزالة الخلفية. الصورة الأصلية محفوظة. أعد المحاولة أو احتفظ بالأصل.',
                  'הסרת הרקע לא הושלמה. המקור נשמר. נסו שוב או שמרו את המקור.',
                ),
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() {
          _loadingOriginal = false;
          _processing = false;
          _stage = null;
        });
    }
  }

  Future<void> _publish() async {
    final original = _original;
    if (original == null ||
        _alreadyPublished ||
        _saving ||
        _loadingOriginal ||
        _processing ||
        (_removeBackground && (!widget.removalEnabled || _candidate == null)))
      return;
    final generation = _generation;
    final item = widget.item;
    _requestId ??= RandomImageIdGenerator().newImageId();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.publish(
        item: item,
        original: original,
        requestId: _requestId!,
        candidateBytes: _removeBackground ? _candidate!.bytes : null,
        candidateMimeType: _removeBackground ? _candidate!.mimeType : null,
      );
      if (!mounted || generation != _generation) return;
      ProductCutoutOriginal? refreshed;
      if (result.status == ProductCutoutPublishStatus.published) {
        // Publication advances the authoritative selection version. Keep the
        // accepted local candidate, but refresh its source proof before the
        // next explicit choice (e.g. switching back to Original).
        try {
          refreshed = await widget.gateway.loadOriginal(item);
        } catch (_) {
          // Success remains success; require a new preparation before another
          // write if the refreshed authoritative proof cannot be read.
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = result.status;
        if (result.status == ProductCutoutPublishStatus.published) {
          _original = refreshed;
          _publishedSelectionProof = null;
          _publishedRemoveBackground = null;
          if (refreshed == null || !_sameSource(original, refreshed)) {
            _candidate = null;
            _removeBackground = false;
            if (refreshed != null)
              _status = ProductCutoutPublishStatus.staleSource;
          } else {
            // Repeated clicks on the confirmed choice are not a new logical
            // publication. A changed choice/proof remains explicitly writable.
            _publishedSelectionProof = refreshed.sourceGeneration;
            _publishedRemoveBackground = _removeBackground;
          }
        } else if (result.status == ProductCutoutPublishStatus.staleSource) {
          _original = null;
          _candidate = null;
          _removeBackground = false;
        }
        if (result.status != ProductCutoutPublishStatus.uncertain)
          _requestId = null;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() => _status = ProductCutoutPublishStatus.uncertain);
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  Future<void> _prepareDetailOriginal() async {
    final original = _original;
    if (original == null ||
        _saving ||
        _loadingOriginal ||
        _processing ||
        _status == ProductCutoutPublishStatus.uncertain ||
        _publishedDetailProof == original.sourceGeneration)
      return;
    final generation = _generation;
    _detailRequestId ??= RandomImageIdGenerator().newImageId();
    setState(() {
      _saving = _publishingDetail = true;
      _detailStatus = null;
    });
    try {
      final result = await widget.gateway.prepareDetailOriginal(
        item: widget.item,
        original: original,
        requestId: _detailRequestId!,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _detailStatus = result.status;
        if (result.status == ProductCutoutPublishStatus.published) {
          _publishedDetailProof = original.sourceGeneration;
        }
        if (result.status != ProductCutoutPublishStatus.uncertain)
          _detailRequestId = null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _detailStatus = ProductCutoutPublishStatus.uncertain);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _saving = _publishingDetail = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.imagePath == null) return const SizedBox.shrink();
    final locked =
        _loadingOriginal ||
        _processing ||
        _saving ||
        _status == ProductCutoutPublishStatus.uncertain ||
        _detailStatus == ProductCutoutPublishStatus.uncertain;
    final original = _original, candidate = _candidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                'Storefront product photo',
                'صورة المنتج في المتجر',
                'תמונת מוצר בחנות',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.removalEnabled
                  ? _t(
                      'Background removal is optional and starts only when you choose Prepare. It may remove parts of food, packaging or dishes, or retain background objects. Review the result before choosing and publishing it. Original stays selected by default.',
                      'إزالة الخلفية اختيارية وتبدأ فقط عند اختيار التحضير. قد تُزال أجزاء من الطعام أو التغليف أو الأطباق، وقد تبقى عناصر من الخلفية. راجع النتيجة قبل اختيارها ونشرها. تبقى الصورة الأصلية مختارة افتراضيًا.',
                      'הסרת רקע היא אפשרות שמתחילה רק בלחיצה על הכנה. היא עלולה להסיר חלקי מזון, אריזה או כלי הגשה, או להשאיר עצמים ברקע. בדקו את התוצאה לפני בחירה ופרסום. המקור נשאר מסומן כברירת מחדל.',
                    )
                  : _t(
                      'Optional background removal is unavailable in this build. You can upload a photo normally, review Original and publish it.',
                      'إزالة الخلفية الاختيارية غير متاحة في هذا الإصدار. يمكنك رفع الصورة كالمعتاد ومراجعة الأصل ونشره.',
                      'הסרת רקע אופציונלית אינה זמינה בגרסה זו. אפשר להעלות תמונה כרגיל, לבדוק את המקור ולפרסם אותו.',
                    ),
            ),
            const SizedBox(height: 12),
            if (original != null) ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _preview(_t('Original', 'الأصل', 'מקור'), original.bytes),
                  if (candidate != null)
                    _preview(
                      _t('Remove background', 'إزالة الخلفية', 'הסרת רקע'),
                      candidate.bytes,
                    ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _t(
                    'Check edges on dark background',
                    'فحص الحواف على خلفية داكنة',
                    'בדיקת קצוות על רקע כהה',
                  ),
                ),
                value: _dark,
                onChanged: (value) => setState(() => _dark = value),
              ),
              if (candidate?.alreadyTransparent == true)
                Text(
                  _t(
                    'This image already has transparency; no segmentation was run.',
                    'هذه الصورة شفافة بالفعل؛ لم تُجرَ عملية فصل.',
                    'לתמונה כבר יש שקיפות; לא בוצע פילוח.',
                  ),
                ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(_t('Original', 'الأصل', 'מקור')),
                  ),
                  ButtonSegment(
                    value: true,
                    enabled:
                        widget.removalEnabled &&
                        candidate != null &&
                        !candidate.alreadyTransparent,
                    label: Text(
                      _t('Remove background', 'إزالة الخلفية', 'הסרת רקע'),
                    ),
                  ),
                ],
                selected: {_removeBackground},
                onSelectionChanged: locked
                    ? null
                    : (values) => setState(() {
                        _removeBackground = values.first;
                        _status = null;
                        _requestId = null;
                      }),
              ),
            ],
            if (_loadingOriginal || _processing || _saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              Text(
                _saving && _publishingDetail
                    ? _t(
                        'Publishing Original for details…',
                        'جارٍ نشر الأصل للتفاصيل…',
                        'מפרסם מקור לפרטי המוצר…',
                      )
                    : _saving
                    ? _t(
                        'Publishing selection…',
                        'جارٍ نشر الاختيار…',
                        'מפרסם את הבחירה…',
                      )
                    : _loadingOriginal
                    ? _t(
                        'Loading Original photo…',
                        'تحميل الصورة الأصلية…',
                        'טוען את התמונה המקורית…',
                      )
                    : _stage == 'loading'
                    ? _t(
                        'Loading local processor (first use: about 188 MB)…',
                        'تحميل المعالج المحلي (أول استخدام: نحو 188 ميغابايت)…',
                        'טוען מעבד מקומי (שימוש ראשון: כ־188 MB)…',
                      )
                    : _t(
                        'Preparing preview on this device…',
                        'تحضير المعاينة على هذا الجهاز…',
                        'מכין תצוגה במכשיר זה…',
                      ),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_status != null)
              Text(switch (_status!) {
                ProductCutoutPublishStatus.published => _t(
                  'Selection published.',
                  'تم نشر الاختيار.',
                  'הבחירה פורסמה.',
                ),
                ProductCutoutPublishStatus.uncertain => _t(
                  'Publication is not confirmed. Retry safely with the same selection.',
                  'لم يتأكد النشر. أعد المحاولة بأمان بنفس الاختيار.',
                  'הפרסום לא אושר. נסו שוב בבטחה עם אותה בחירה.',
                ),
                ProductCutoutPublishStatus.staleSource => _t(
                  'The original changed. Prepare a new preview.',
                  'تغيرت الصورة الأصلية. حضّر معاينة جديدة.',
                  'המקור השתנה. הכינו תצוגה חדשה.',
                ),
                _ => _t(
                  'Nothing was published. Check access and retry.',
                  'لم يُنشر شيء. تحقق من الصلاحيات وأعد المحاولة.',
                  'דבר לא פורסם. בדקו הרשאות ונסו שוב.',
                ),
              }),
            const SizedBox(height: 12),
            if (original != null) ...[
              Text(
                _t(
                  'Publish a bounded public copy of Original for product details only. The menu photo selection stays unchanged.',
                  'انشر نسخة عامة محدودة من الأصل لتفاصيل الوجبة فقط. اختيار صورة المنيو يبقى كما هو.',
                  'פרסמו עותק ציבורי מוגבל של המקור לפרטי המוצר בלבד. בחירת תמונת התפריט לא תשתנה.',
                ),
              ),
              if (_detailStatus != null)
                Text(switch (_detailStatus!) {
                  ProductCutoutPublishStatus.published => _t(
                    'Original for details published.',
                    'تم نشر الأصل للتفاصيل.',
                    'המקור לפרטי המוצר פורסם.',
                  ),
                  ProductCutoutPublishStatus.uncertain => _t(
                    'Detail publication is unconfirmed. Retry the same action.',
                    'نشر صورة التفاصيل غير مؤكد. أعد المحاولة بنفس الإجراء.',
                    'פרסום התמונה לפרטים לא אושר. נסו שוב את אותה פעולה.',
                  ),
                  ProductCutoutPublishStatus.staleSource => _t(
                    'The source or selection changed. Load Original again.',
                    'تغير الأصل أو الاختيار. حمّل الأصل مجددًا.',
                    'המקור או הבחירה השתנו. טענו את המקור שוב.',
                  ),
                  _ => _t(
                    'Detail publication failed. Selection was not changed.',
                    'تعذر نشر صورة التفاصيل. لم يتغير الاختيار.',
                    'פרסום תמונת הפרטים נכשל. הבחירה לא השתנתה.',
                  ),
                }),
              OutlinedButton(
                key: const Key('product-detail-publish-original'),
                onPressed:
                    _saving ||
                        _loadingOriginal ||
                        _processing ||
                        _status == ProductCutoutPublishStatus.uncertain ||
                        _publishedDetailProof == original.sourceGeneration
                    ? null
                    : _prepareDetailOriginal,
                child: Text(
                  _t(
                    'Publish Original for details',
                    'نشر الأصل للتفاصيل',
                    'פרסום מקור לפרטי המוצר',
                  ),
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('product-cutout-load-original'),
                  onPressed: locked ? null : _loadOriginal,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _t(
                      'Load Original photo',
                      'تحميل الصورة الأصلية',
                      'טעינת התמונה המקורית',
                    ),
                  ),
                ),
                if (widget.removalEnabled)
                  OutlinedButton.icon(
                    key: const Key('product-cutout-prepare'),
                    onPressed: locked ? null : _prepare,
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      _t(
                        candidate == null
                            ? 'Prepare background removal'
                            : 'Review prepared background removal',
                        candidate == null
                            ? 'تحضير إزالة الخلفية'
                            : 'مراجعة إزالة الخلفية المحضّرة',
                        candidate == null
                            ? 'הכנת הסרת רקע'
                            : 'בדיקת הסרת הרקע המוכנה',
                      ),
                    ),
                  ),
                if (_loadingOriginal || _processing)
                  TextButton(
                    key: const Key('product-cutout-cancel'),
                    onPressed: () => setState(_cancel),
                    child: Text(
                      _t('Cancel processing', 'إلغاء المعالجة', 'ביטול עיבוד'),
                    ),
                  ),
                if (original != null)
                  FilledButton(
                    key: const Key('product-cutout-publish'),
                    onPressed:
                        _loadingOriginal ||
                            _processing ||
                            _saving ||
                            _detailStatus ==
                                ProductCutoutPublishStatus.uncertain ||
                            _alreadyPublished
                        ? null
                        : _publish,
                    child: Text(
                      _t(
                        'Publish selected photo',
                        'نشر الصورة المختارة',
                        'פרסום התמונה הנבחרת',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(String label, Uint8List bytes) => SizedBox(
    width: 230,
    child: Column(
      children: [
        Text(label),
        const SizedBox(height: 4),
        Container(
          color: _dark ? const Color(0xff171717) : const Color(0xfffafafa),
          child: Image.memory(
            bytes,
            width: 230,
            height: 230,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(
              width: 230,
              height: 230,
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ],
    ),
  );
}
