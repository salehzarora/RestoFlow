import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:supabase/supabase.dart';

import 'product_cutout_gateway.dart';
import 'storefront_media_publisher.dart';
import 'storefront_models.dart';

typedef ProductMediaRpc =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> parameters,
    );

/// Separate product presentation, over the existing caller-authorized publisher.
/// Private originals and menu/POS/receipt/Hero pointers are never written here.
class StorefrontProductCutoutRepository implements ProductCutoutGateway {
  StorefrontProductCutoutRepository({
    required ProductMediaRpc rpc,
    required Future<Uint8List> Function(String key) download,
    required Future<void> Function(String key, Uint8List bytes) uploadCandidate,
    required StorefrontFunctionInvoker publisher,
  }) : _rpc = rpc,
       _download = download,
       _upload = uploadCandidate,
       _publisher = publisher;

  factory StorefrontProductCutoutRepository.supabase(SupabaseClient client) {
    final bucket = client.storage.from(kMenuImagesBucketId);
    return StorefrontProductCutoutRepository(
      rpc: (name, parameters) async {
        final data = await client
            .rpc(name, params: parameters)
            .timeout(const Duration(seconds: 30));
        if (data is! Map) throw const FormatException('product media response');
        return Map<String, dynamic>.from(data);
      },
      download: (key) =>
          bucket.download(key).timeout(const Duration(seconds: 30)),
      uploadCandidate: (key, bytes) async {
        try {
          await bucket
              .uploadBinary(
                key,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/png',
                  upsert: false,
                ),
              )
              .timeout(const Duration(seconds: 30));
        } on StorageException catch (error) {
          // Same request after a lost reply: compare the private bytes. No
          // upsert, delete, or replacement of an existing source is permitted.
          if (error.statusCode != '409' && error.statusCode != '400') rethrow;
          final existing = await bucket
              .download(key)
              .timeout(const Duration(seconds: 30));
          if (existing.length != bytes.length ||
              sha256.convert(existing) != sha256.convert(bytes)) {
            throw const FormatException('candidate object conflict');
          }
        }
      },
      publisher: SupabaseStorefrontFunctionInvoker(client),
    );
  }

  final ProductMediaRpc _rpc;
  final Future<Uint8List> Function(String key) _download;
  final Future<void> Function(String key, Uint8List bytes) _upload;
  final StorefrontFunctionInvoker _publisher;

  Map<String, dynamic> _scope(MenuItem item) => {
    'p_organization_id': item.organizationId,
    'p_restaurant_id': item.restaurantId,
  };
  Future<Map<String, dynamic>> _read(MenuItem item) => _rpc(
    'get_storefront_product_original_v1',
    {..._scope(item), 'p_item_id': item.id},
  );
  static String _generation(Map<String, dynamic> data) => jsonEncode({
    'source_snapshot': data['source_snapshot'],
    'selection_version': data['selection_version'],
  });
  static String _step(String request, String purpose) =>
      storefrontRequestId('pbl:storefront:product:', [request, purpose], 0);

  @override
  Future<ProductCutoutOriginal> loadOriginal(MenuItem item) async {
    final before = await _read(item);
    if (before['ok'] != true ||
        before['source_key'] != item.imagePath ||
        before['source_snapshot'] is! Map ||
        before['selection_version'] is! int) {
      throw const FormatException('original is not current');
    }
    final key = before['source_key'] as String;
    final bytes = await _download(key);
    if (!isWithinMenuImageSizeLimit(bytes.length)) {
      throw const FormatException('original size');
    }
    // An overwrite during download must never become a new candidate's parent.
    final after = await _read(item);
    if (after['ok'] != true ||
        after['source_key'] != key ||
        _generation(before) != _generation(after)) {
      throw const FormatException('original changed during download');
    }
    final mime = switch (key.split('.').last) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => throw const FormatException('original type'),
    };
    return ProductCutoutOriginal(
      bytes: bytes,
      mimeType: mime,
      sourceKey: key,
      sourceGeneration: _generation(before),
    );
  }

  Future<Map<String, dynamic>?> _write(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _rpc(name, parameters);
      } on PostgrestException catch (error) {
        if (error.code == '42501' || error.code == 'PGRST301') {
          return {'ok': false, 'error': 'permission_denied'};
        }
        // A database timeout or lost commit acknowledgement is not a denial.
        // Keep the idempotency key for the same bounded retry as network loss.
      } catch (_) {
        /* Unknown outcome: retry the exact same id and payload once. */
      }
    }
    return null;
  }

  static ProductCutoutPublishStatus _failure(Map<String, dynamic>? data) =>
      switch (data?['error']) {
        'source_stale' ||
        'source_not_found' ||
        'selection_stale' ||
        'stale_request' => ProductCutoutPublishStatus.staleSource,
        'permission_denied' => ProductCutoutPublishStatus.denied,
        null => ProductCutoutPublishStatus.uncertain,
        _ => ProductCutoutPublishStatus.unavailable,
      };

  @override
  Future<ProductCutoutPublishResult> publish({
    required MenuItem item,
    required ProductCutoutOriginal original,
    required String requestId,
    Uint8List? candidateBytes,
    String? candidateMimeType,
  }) async {
    ProductCutoutPublishResult result(ProductCutoutPublishStatus status) =>
        ProductCutoutPublishResult(status);
    try {
      final generation =
          jsonDecode(original.sourceGeneration) as Map<String, dynamic>;
      if (original.sourceKey != item.imagePath ||
          generation['source_snapshot'] is! Map ||
          generation['selection_version'] is! int)
        return result(ProductCutoutPublishStatus.staleSource);
      final candidate = candidateBytes != null;
      if (candidate &&
          (candidateMimeType != 'image/png' ||
              !isWithinMenuImageSizeLimit(candidateBytes.length))) {
        return result(ProductCutoutPublishStatus.unavailable);
      }
      // Deterministic fresh private object per logical request. A retry compares
      // exact bytes; it cannot overwrite this candidate or the original.
      final key = candidate
          ? buildMenuImageObjectKey(
              organizationId: item.organizationId,
              restaurantId: item.restaurantId,
              branchId: item.branchId,
              menuItemId: item.id,
              imageId: _step(requestId, 'candidate'),
              extension: 'png',
            )
          : original.sourceKey;
      if (candidate) await _upload(key, candidateBytes);
      final registered =
          await _write('register_storefront_product_derivative_v1', {
            ..._scope(item),
            'p_client_request_id': _step(requestId, 'register'),
            'p_item_id': item.id,
            'p_original_key': original.sourceKey,
            'p_original_snapshot': generation['source_snapshot'],
            'p_candidate_key': key,
            'p_treatment': candidate ? 'cutout' : 'original',
            'p_expected_selection_version': generation['selection_version'],
          });
      if (registered?['ok'] != true) return result(_failure(registered));
      final derivative = registered!['derivative_id'];
      if (derivative is! String ||
          !RegExp(r'^[0-9a-f-]{36}$').hasMatch(derivative) ||
          registered['candidate_key'] != key)
        return result(ProductCutoutPublishStatus.uncertain);
      for (final variant in ['w480', 'w960']) {
        final status = await _publishVariant(
          item,
          key,
          derivative,
          variant,
          _step(requestId, variant),
        );
        if (status != ProductCutoutPublishStatus.published)
          return result(status);
      }
      // This is the only selection write. A failed second variant leaves the
      // previous complete presentation intact, including on uncertain outcomes.
      final selected = await _write('select_storefront_product_derivative_v1', {
        ..._scope(item),
        'p_client_request_id': _step(requestId, 'select'),
        'p_derivative_id': derivative,
      });
      if (selected?['ok'] != true) return result(_failure(selected));
      final authoritative = await _read(item);
      if (authoritative['ok'] != true ||
          authoritative['selected_derivative_id'] != derivative ||
          authoritative['source_key'] != original.sourceKey ||
          selected!['derivative_id'] != derivative ||
          selected['selection_version'] is! int ||
          authoritative['selection_version'] != selected['selection_version'] ||
          jsonEncode(authoritative['source_snapshot']) !=
              jsonEncode(generation['source_snapshot']))
        return result(ProductCutoutPublishStatus.uncertain);
      return result(ProductCutoutPublishStatus.published);
    } on PostgrestException catch (error) {
      return result(
        error.code == '42501' || error.code == 'PGRST301'
            ? ProductCutoutPublishStatus.denied
            : ProductCutoutPublishStatus.uncertain,
      );
    } on FormatException {
      return result(ProductCutoutPublishStatus.unavailable);
    } catch (_) {
      return result(ProductCutoutPublishStatus.uncertain);
    }
  }

  Future<ProductCutoutPublishStatus> _publishVariant(
    MenuItem item,
    String key,
    String derivative,
    String variant,
    String requestId,
  ) async {
    var rung = 0;
    while (rung <= 4) {
      StorefrontFunctionReply? reply;
      for (var attempt = 0; attempt < 2; attempt++) {
        reply = await _publisher.invoke({
          'request_id': requestId,
          'organization_id': item.organizationId,
          'restaurant_id': item.restaurantId,
          'slot': 'product',
          'variant': variant,
          'source_bucket': 'menu-images',
          'source_key': key,
          'rung': rung,
          'product_derivative_id': derivative,
        });
        if (!reply.transportFailed &&
            reply.httpStatus != null &&
            reply.httpStatus! < 500)
          break;
      }
      final data = reply?.json;
      if (reply?.httpStatus == 202 && data?['status'] == 'ladder_next') {
        final next = data?['next_rung'];
        if (next is! int || next <= rung || next > 4)
          return ProductCutoutPublishStatus.uncertain;
        rung = next;
        continue;
      }
      if (reply?.httpStatus == 200 &&
          data?['ok'] == true &&
          data?['status'] == 'published' &&
          data?['recipe'] == 'storefront-media-c4') {
        final media = data?['media'];
        if (media is Map &&
            media['state'] == 'published' &&
            media['source_key'] == key &&
            media['source_bucket'] == 'menu-images' &&
            media['variant'] == variant &&
            media['content_hash'] is String &&
            RegExp(
              r'^[0-9a-f]{64}$',
            ).hasMatch(media['content_hash'] as String)) {
          return ProductCutoutPublishStatus.published;
        }
        return ProductCutoutPublishStatus.uncertain;
      }
      if (reply?.httpStatus == 401 || reply?.httpStatus == 403)
        return ProductCutoutPublishStatus.denied;
      if (data?['code'] == 'source_stale' ||
          reply?.httpStatus == 404 ||
          reply?.httpStatus == 409)
        return ProductCutoutPublishStatus.staleSource;
      if (reply?.httpStatus != null &&
          reply!.httpStatus! >= 400 &&
          reply.httpStatus! < 500)
        return ProductCutoutPublishStatus.unavailable;
      return ProductCutoutPublishStatus.uncertain;
    }
    return ProductCutoutPublishStatus.uncertain;
  }
}
