import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'product_cutout_gateway.dart';
import 'product_cutout_processor.dart';

/// Product-only, local candidate review. Private source upload remains owned
/// by MenuImagePanel. A changed persisted source automatically prepares a draft.
class ProductCutoutEditor extends StatefulWidget {
  const ProductCutoutEditor({
    super.key,
    required this.item,
    required this.gateway,
    this.processor,
  });
  final MenuItem item;
  final ProductCutoutGateway gateway;
  final ProductCutoutProcessor? processor;
  @override
  State<ProductCutoutEditor> createState() => _ProductCutoutEditorState();
}

class _ProductCutoutEditorState extends State<ProductCutoutEditor> {
  late final ProductCutoutProcessor _processor =
      widget.processor ?? createProductCutoutProcessor();
  ProductCutoutOriginal? _original;
  ProductCutoutCandidate? _candidate;
  bool _processing = false,
      _saving = false,
      _removeBackground = false,
      _dark = false;
  int _generation = 0;
  String? _error, _stage, _requestId;
  ProductCutoutPublishStatus? _status;

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
        oldWidget.item.restaurantId != widget.item.restaurantId) {
      _cancel();
      _saving = false;
      _original = null;
      _candidate = null;
      _status = null;
      _requestId = null;
      _removeBackground = false;
      if (widget.item.imagePath != null)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _prepare();
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
    _processing = false;
    _stage = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_processing || _saving || widget.item.imagePath == null) return;
    final generation = ++_generation;
    setState(() {
      _processing = true;
      _error = null;
      _status = null;
      _stage = 'loading-original';
    });
    try {
      final original = await widget.gateway.loadOriginal(widget.item);
      if (!mounted || generation != _generation) return;
      if (original.sourceKey != widget.item.imagePath)
        throw StateError('Source changed');
      setState(() {
        _original = original;
        _candidate = null;
        _requestId = null;
        _removeBackground = false;
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
          () => _error = _t(
            'Background removal could not finish. Your original is safe. Retry or keep Original.',
            'تعذرت إزالة الخلفية. الصورة الأصلية محفوظة. أعد المحاولة أو احتفظ بالأصل.',
            'הסרת הרקע לא הושלמה. המקור נשמר. נסו שוב או שמרו את המקור.',
          ),
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() {
          _processing = false;
          _stage = null;
        });
    }
  }

  Future<void> _publish() async {
    final original = _original;
    if (original == null ||
        _saving ||
        _processing ||
        (_removeBackground && _candidate == null))
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
          if (refreshed == null || !_sameSource(original, refreshed)) {
            _candidate = null;
            _removeBackground = false;
            if (refreshed != null)
              _status = ProductCutoutPublishStatus.staleSource;
          }
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

  @override
  Widget build(BuildContext context) {
    if (widget.item.imagePath == null) return const SizedBox.shrink();
    final locked =
        _processing ||
        _saving ||
        _status == ProductCutoutPublishStatus.uncertain;
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
              _t(
                'Prepare a transparent preview on this device. Review food, packaging and serving dishes before publishing. Complex shots and transparent cups may need Original.',
                'حضّر معاينة شفافة على هذا الجهاز. راجع الطعام والتغليف وأطباق التقديم قبل النشر. قد تحتاج الصور المعقدة والأكواب الشفافة إلى الصورة الأصلية.',
                'הכינו תצוגה שקופה במכשיר זה. בדקו את המזון, האריזה וכלי ההגשה לפני פרסום. בצילומים מורכבים ובכוסות שקופות ייתכן שעדיף המקור.',
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
                    enabled: candidate != null && !candidate.alreadyTransparent,
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
            if (_processing || _saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              Text(
                _saving
                    ? _t(
                        'Publishing selection…',
                        'جارٍ نشر الاختيار…',
                        'מפרסם את הבחירה…',
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('product-cutout-prepare'),
                  onPressed: locked ? null : _prepare,
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text(
                    _t(
                      candidate == null
                          ? 'Prepare background removal'
                          : 'Retry background removal',
                      'تحضير إزالة الخلفية',
                      'הכנת הסרת רקע',
                    ),
                  ),
                ),
                if (_processing)
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
                    onPressed: _processing || _saving ? null : _publish,
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
