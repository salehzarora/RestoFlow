import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_dashboard/src/storefront/product_cutout_gateway.dart';
import 'package:restoflow_dashboard/src/storefront/product_cutout_repository.dart';
import 'package:restoflow_dashboard/src/storefront/storefront_media_publisher.dart';
import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';
import 'package:supabase/supabase.dart';

// BIZBOT-STOREFRONT-VISUAL-PARITY-001: client orchestration only. The companion
// pgTAP suite establishes server authorization, generations and atomic selection.
const _org = '11111111-1111-4111-8111-111111111111';
const _restaurant = '22222222-2222-4222-8222-222222222222';
const _itemId = '33333333-3333-4333-8333-333333333333';
const _derivative = '44444444-4444-4444-8444-444444444444';
const _request = '55555555-5555-4555-8555-555555555555';
const _key = '$_org/$_restaurant/global/menu_item/$_itemId/original.png';
const _readRpc = 'get_storefront_product_original_v1';
const _registerRpc = 'register_storefront_product_derivative_v1';
const _selectRpc = 'select_storefront_product_derivative_v1';
const _snapshot = {'version': 'generation-1', 'size': 1234};
const _item = MenuItem(
  id: _itemId,
  organizationId: _org,
  restaurantId: _restaurant,
  branchId: null,
  menuCategoryId: 'category',
  name: 'Test product',
  description: null,
  basePriceMinor: 1000,
  currencyCode: 'ILS',
  defaultStationId: null,
  displayOrder: 0,
  isActive: true,
  imagePath: _key,
);

ProductCutoutOriginal _original({int version = 7}) => ProductCutoutOriginal(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/png',
  sourceKey: _key,
  sourceGeneration: jsonEncode({
    'source_snapshot': _snapshot,
    'selection_version': version,
  }),
);

Map<String, dynamic> _read({bool selected = false}) => {
  'ok': true,
  'source_key': _key,
  'source_snapshot': _snapshot,
  'selection_version': selected ? 8 : 7,
  'selected_derivative_id': selected ? _derivative : null,
};

StorefrontFunctionReply _published(Map<String, Object?> body) =>
    StorefrontFunctionReply(
      httpStatus: 200,
      json: {
        'ok': true,
        'status': 'published',
        'recipe': 'storefront-media-c4',
        'media': {
          'state': 'published',
          'source_key': body['source_key'],
          'source_bucket': 'menu-images',
          'variant': body['variant'],
          'content_hash': 'a' * 64,
        },
      },
    );

class _Invoker implements StorefrontFunctionInvoker {
  _Invoker(this.callback);
  final Future<StorefrontFunctionReply> Function(Map<String, Object?>) callback;
  @override
  Future<StorefrontFunctionReply> invoke(Map<String, Object?> body) =>
      callback(body);
}

class _Harness {
  final events = <String>[];
  final calls = <({String name, Map<String, dynamic> params})>[];
  final bodies = <Map<String, Object?>>[];
  final uploads = <({String key, Uint8List bytes})>[];
  final responses = <String, List<Object>>{};
  Future<StorefrontFunctionReply> Function(Map<String, Object?>)? publication;
  Future<Uint8List> Function(String)? download;
  bool selected = false;

  late final repo = StorefrontProductCutoutRepository(
    rpc: (name, params) async {
      events.add(name);
      calls.add((name: name, params: Map.of(params)));
      final queue = responses[name];
      if (queue != null && queue.isNotEmpty) {
        final response = queue.removeAt(0);
        if (response is Exception) throw response;
        return Map<String, dynamic>.from(response as Map);
      }
      switch (name) {
        case _readRpc:
          return _read(selected: selected);
        case _registerRpc:
          return {
            'ok': true,
            'derivative_id': _derivative,
            'candidate_key': params['p_candidate_key'],
          };
        case _selectRpc:
          selected = true;
          return {
            'ok': true,
            'derivative_id': _derivative,
            'selection_version': 8,
          };
        default:
          throw StateError('Unexpected RPC $name');
      }
    },
    download: (key) async {
      events.add('download:$key');
      return download != null
          ? await download!(key)
          : Uint8List.fromList([1, 2, 3]);
    },
    uploadCandidate: (key, bytes) async {
      events.add('upload');
      uploads.add((key: key, bytes: Uint8List.fromList(bytes)));
    },
    publisher: _Invoker((body) async {
      events.add('publish:${body['variant']}');
      bodies.add(Map.of(body));
      return publication != null ? await publication!(body) : _published(body);
    }),
  );

  List<Map<String, dynamic>> rpcCalls(String name) => [
    for (final call in calls)
      if (call.name == name) call.params,
  ];

  Future<ProductCutoutPublishResult> publish({
    String request = _request,
    bool candidate = true,
  }) => repo.publish(
    item: _item,
    original: _original(),
    requestId: request,
    candidateBytes: candidate ? Uint8List.fromList([4, 5, 6]) : null,
    candidateMimeType: candidate ? 'image/png' : null,
  );
}

void main() {
  group('independent Original detail publication', () {
    const cutout = '66666666-6666-4666-8666-666666666666';
    Map<String, dynamic> proof() => {
      ..._read(),
      'selected_derivative_id': cutout,
    };
    Future<ProductCutoutPublishResult> prepare(_Harness h) =>
        h.repo.prepareDetailOriginal(
          item: _item,
          original: _original(),
          requestId: _request,
        );

    test(
      'publishes only current Original w960 without upload or selection',
      () async {
        final h = _Harness()..responses[_readRpc] = [proof(), proof()];
        expect((await prepare(h)).status, ProductCutoutPublishStatus.published);
        expect(h.uploads, isEmpty);
        expect(h.rpcCalls(_selectRpc), isEmpty);
        expect(h.bodies.single['variant'], 'w960');
        expect(h.bodies.single['source_key'], _key);
        final registered = h.rpcCalls(_registerRpc).single;
        expect(registered['p_treatment'], 'original');
        expect(registered['p_candidate_key'], _key);
        expect(registered['p_expected_selection_version'], 7);
        expect(h.events, [_readRpc, _registerRpc, 'publish:w960', _readRpc]);
      },
    );
    test(
      'lost transport answer retries the exact request and keeps the selected cutout',
      () async {
        final h = _Harness()..responses[_readRpc] = [proof(), proof()];
        var n = 0;
        h.publication = (body) async => n++ == 0
            ? const StorefrontFunctionReply.transportFailure()
            : _published(body);
        expect((await prepare(h)).status, ProductCutoutPublishStatus.published);
        expect(h.bodies, hasLength(2));
        expect(h.bodies[0], h.bodies[1]);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      },
    );
    for (final change in [
      {'selection_version': 8},
      {'source_key': 'changed.png'},
      {
        'source_snapshot': {'version': 'new'},
      },
      {'selected_derivative_id': _derivative},
    ]) {
      test('never restores a concurrent $change after publication', () async {
        final h = _Harness()
          ..responses[_readRpc] = [
            proof(),
            {...proof(), ...change},
          ];
        expect(
          (await prepare(h)).status,
          ProductCutoutPublishStatus.staleSource,
        );
        expect(h.rpcCalls(_selectRpc), isEmpty);
        expect(h.uploads, isEmpty);
      });
    }
    test(
      'malformed or unavailable proof is uncertain, not a successful selection comparison',
      () async {
        for (final after in [
          {'ok': false},
          {...proof()}..remove('selected_derivative_id'),
          {...proof(), 'selection_version': '7'},
        ]) {
          final h = _Harness()..responses[_readRpc] = [proof(), after];
          expect(
            (await prepare(h)).status,
            ProductCutoutPublishStatus.uncertain,
          );
          expect(h.rpcCalls(_selectRpc), isEmpty);
        }
      },
    );
    test(
      'stale original refuses publication and denied registration never invokes publisher',
      () async {
        final stale = _Harness()
          ..responses[_readRpc] = [
            {...proof(), 'selection_version': 8},
          ];
        expect(
          (await prepare(stale)).status,
          ProductCutoutPublishStatus.staleSource,
        );
        expect(stale.bodies, isEmpty);
        expect(stale.rpcCalls(_registerRpc), isEmpty);
        final denied = _Harness()
          ..responses[_registerRpc] = [
            {'ok': false, 'error': 'permission_denied'},
          ];
        expect(
          (await prepare(denied)).status,
          ProductCutoutPublishStatus.denied,
        );
        expect(denied.bodies, isEmpty);
        expect(denied.rpcCalls(_selectRpc), isEmpty);
      },
    );
  });

  group('private original generation', () {
    test(
      'reads around download and captures authoritative selection version',
      () async {
        final h = _Harness();
        final original = await h.repo.loadOriginal(_item);
        expect(h.events, [_readRpc, 'download:$_key', _readRpc]);
        expect(original.bytes, [1, 2, 3]);
        expect(original.mimeType, 'image/png');
        expect(jsonDecode(original.sourceGeneration), {
          'source_snapshot': _snapshot,
          'selection_version': 7,
        });
        expect(
          h.rpcCalls(_readRpc).every((p) => p['p_item_id'] == _itemId),
          isTrue,
        );
      },
    );

    for (final change in <String, Object?>{
      'source_key': 'another-original.png',
      'source_snapshot': {'version': 'generation-2', 'size': 1234},
      'selection_version': 8,
      'ok': false,
    }.entries) {
      test('refuses ${change.key} changing during private download', () async {
        final h = _Harness();
        h.responses[_readRpc] = [
          _read(),
          {..._read(), change.key: change.value},
        ];
        await expectLater(h.repo.loadOriginal(_item), throwsFormatException);
        expect(h.uploads, isEmpty);
        expect(h.bodies, isEmpty);
      });
    }

    for (final size in [0, kMaxMenuImageBytes + 1]) {
      test('rejects original byte count $size before processing', () async {
        final h = _Harness()..download = (_) async => Uint8List(size);
        await expectLater(h.repo.loadOriginal(_item), throwsFormatException);
        expect(h.rpcCalls(_readRpc), hasLength(1));
      });
    }

    test(
      'invalid ownership/current-pointer response never downloads',
      () async {
        final h = _Harness();
        h.responses[_readRpc] = [
          {'ok': false, 'error': 'permission_denied'},
        ];
        await expectLater(h.repo.loadOriginal(_item), throwsFormatException);
        expect(h.events, [_readRpc]);
      },
    );
  });

  group('complete product publication', () {
    test(
      'uploads privately, publishes both sizes, selects once, then reads back',
      () async {
        final h = _Harness();
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.events, [
          'upload',
          _registerRpc,
          'publish:w480',
          'publish:w960',
          _selectRpc,
          _readRpc,
        ]);
        final upload = h.uploads.single;
        expect(
          upload.key,
          startsWith('$_org/$_restaurant/global/menu_item/$_itemId/'),
        );
        expect(upload.key, endsWith('.png'));
        expect(upload.key, isNot(_key));
        expect(upload.bytes, [4, 5, 6]);
        final registration = h.rpcCalls(_registerRpc).single;
        expect(registration['p_original_key'], _key);
        expect(registration['p_original_snapshot'], _snapshot);
        expect(registration['p_expected_selection_version'], 7);
        expect(registration['p_treatment'], 'cutout');
        expect(registration['p_candidate_key'], upload.key);
        expect(h.bodies.map((b) => b['variant']), ['w480', 'w960']);
        for (final body in h.bodies) {
          expect(body['slot'], 'product');
          expect(body['source_bucket'], 'menu-images');
          expect(body['source_key'], upload.key);
          expect(body['product_derivative_id'], _derivative);
          expect(body['organization_id'], _org);
          expect(body['restaurant_id'], _restaurant);
          expect(body.values.every((v) => v is String || v is int), isTrue);
        }
        final ids = [
          registration['p_client_request_id'],
          ...h.bodies.map((b) => b['request_id']),
          h.rpcCalls(_selectRpc).single['p_client_request_id'],
        ];
        expect(ids.toSet(), hasLength(4));
        expect(_item.imagePath, _key);
      },
    );

    test(
      'Original still publishes both variants and never uploads a candidate',
      () async {
        final h = _Harness();
        expect(
          (await h.publish(candidate: false)).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.uploads, isEmpty);
        expect(h.rpcCalls(_registerRpc).single['p_treatment'], 'original');
        expect(h.rpcCalls(_registerRpc).single['p_candidate_key'], _key);
        expect(h.bodies.every((b) => b['source_key'] == _key), isTrue);
        expect(h.bodies.map((b) => b['variant']), ['w480', 'w960']);
      },
    );

    test(
      'retry keeps candidate and operation ids; new request gets a fresh candidate',
      () async {
        final h = _Harness();
        await h.publish();
        await h.publish();
        expect(h.uploads[0].key, h.uploads[1].key);
        expect(h.rpcCalls(_registerRpc)[0], h.rpcCalls(_registerRpc)[1]);
        expect(h.bodies[0], h.bodies[2]);
        expect(h.bodies[1], h.bodies[3]);
        expect(h.rpcCalls(_selectRpc)[0], h.rpcCalls(_selectRpc)[1]);
        await h.publish(request: '66666666-6666-4666-8666-666666666666');
        expect(h.uploads[2].key, isNot(h.uploads[0].key));
      },
    );

    test(
      'lost registration reply retries identical payload before publication',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [TimeoutException('lost response')];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.rpcCalls(_registerRpc), hasLength(2));
        expect(h.rpcCalls(_registerRpc)[0], h.rpcCalls(_registerRpc)[1]);
        expect(h.uploads, hasLength(1));
        expect(h.bodies, hasLength(2));
      },
    );

    test(
      'lost selection reply retries same request then requires readback',
      () async {
        final h = _Harness();
        h.responses[_selectRpc] = [TimeoutException('lost response')];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.rpcCalls(_selectRpc), hasLength(2));
        expect(h.rpcCalls(_selectRpc)[0], h.rpcCalls(_selectRpc)[1]);
        expect(h.events.last, _readRpc);
      },
    );
  });

  group('failure cannot select a partial pair', () {
    for (final entry in {
      'source_stale': ProductCutoutPublishStatus.staleSource,
      'selection_stale': ProductCutoutPublishStatus.staleSource,
      'permission_denied': ProductCutoutPublishStatus.denied,
      'media_unavailable': ProductCutoutPublishStatus.unavailable,
    }.entries) {
      test('registration ${entry.key} stops before public work', () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          {'ok': false, 'error': entry.key},
        ];
        expect((await h.publish()).status, entry.value);
        expect(h.rpcCalls(_registerRpc), hasLength(1));
        expect(h.bodies, isEmpty);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      });
    }

    test(
      'ambiguous registration exhausts one stable retry without publishing',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          TimeoutException('lost'),
          TimeoutException('lost'),
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.rpcCalls(_registerRpc), hasLength(2));
        expect(h.bodies, isEmpty);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      },
    );

    test('permission exception is definitive and is not retried', () async {
      final h = _Harness();
      h.responses[_registerRpc] = [
        const PostgrestException(message: 'denied', code: '42501'),
      ];
      expect((await h.publish()).status, ProductCutoutPublishStatus.denied);
      expect(h.rpcCalls(_registerRpc), hasLength(1));
      expect(h.bodies, isEmpty);
    });

    test(
      'expired caller token is denied without retrying registration',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          const PostgrestException(message: 'expired', code: 'PGRST301'),
        ];
        expect((await h.publish()).status, ProductCutoutPublishStatus.denied);
        expect(h.rpcCalls(_registerRpc), hasLength(1));
        expect(h.bodies, isEmpty);
      },
    );

    test(
      'transient database error retries the identical registration',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          const PostgrestException(message: 'serialization', code: '40001'),
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.rpcCalls(_registerRpc), hasLength(2));
        expect(h.rpcCalls(_registerRpc)[0], h.rpcCalls(_registerRpc)[1]);
      },
    );

    test(
      'persistent database error remains uncertain rather than denied',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          const PostgrestException(message: 'connection', code: '08006'),
          const PostgrestException(message: 'connection', code: '08006'),
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.rpcCalls(_registerRpc), hasLength(2));
        expect(h.bodies, isEmpty);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      },
    );

    test(
      'registration response must identify this candidate before publication',
      () async {
        final h = _Harness();
        h.responses[_registerRpc] = [
          {'ok': true, 'derivative_id': _derivative, 'candidate_key': _key},
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.bodies, isEmpty);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      },
    );

    for (final input in [
      (bytes: Uint8List(0), mime: 'image/png'),
      (bytes: Uint8List(kMaxMenuImageBytes + 1), mime: 'image/png'),
      (bytes: Uint8List.fromList([1, 2, 3]), mime: 'image/jpeg'),
    ]) {
      test(
        'invalid candidate ${input.mime}/${input.bytes.length} stops before upload',
        () async {
          final h = _Harness();
          final result = await h.repo.publish(
            item: _item,
            original: _original(),
            requestId: _request,
            candidateBytes: input.bytes,
            candidateMimeType: input.mime,
          );
          expect(result.status, ProductCutoutPublishStatus.unavailable);
          expect(h.events, isEmpty);
        },
      );
    }

    for (final variant in ['w480', 'w960']) {
      for (final status in [403, 409, 422, 503]) {
        test('$variant HTTP $status never selects', () async {
          final h = _Harness();
          h.publication = (body) async => body['variant'] == variant
              ? StorefrontFunctionReply(httpStatus: status)
              : _published(body);
          final expected = switch (status) {
            403 => ProductCutoutPublishStatus.denied,
            409 => ProductCutoutPublishStatus.staleSource,
            422 => ProductCutoutPublishStatus.unavailable,
            _ => ProductCutoutPublishStatus.uncertain,
          };
          expect((await h.publish()).status, expected);
          expect(h.rpcCalls(_selectRpc), isEmpty);
          if (variant == 'w480')
            expect(h.bodies.every((b) => b['variant'] == 'w480'), isTrue);
          if (status == 503) {
            expect(
              h.bodies[h.bodies.length - 1],
              h.bodies[h.bodies.length - 2],
            );
          }
        });
      }
    }

    test(
      'transport uncertainty on second size retains the previous selection',
      () async {
        final h = _Harness();
        h.publication = (body) async => body['variant'] == 'w960'
            ? const StorefrontFunctionReply.transportFailure()
            : _published(body);
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.bodies.map((b) => b['variant']), ['w480', 'w960', 'w960']);
        expect(h.bodies[1], h.bodies[2]);
        expect(h.rpcCalls(_selectRpc), isEmpty);
      },
    );

    for (final mutation in <String, Object?>{
      'source_key': 'wrong-item.png',
      'source_bucket': 'restaurant-logos',
      'variant': 'w480',
      'state': 'staged',
      'content_hash': 'not-a-hash',
    }.entries) {
      test(
        'unproven second publication ${mutation.key} never selects',
        () async {
          final h = _Harness();
          h.publication = (body) async {
            final reply = _published(body);
            if (body['variant'] == 'w960') {
              (reply.json!['media'] as Map)[mutation.key] = mutation.value;
            }
            return reply;
          };
          expect(
            (await h.publish()).status,
            ProductCutoutPublishStatus.uncertain,
          );
          expect(h.rpcCalls(_selectRpc), isEmpty);
        },
      );
    }

    test('wrong recipe never selects even with valid media metadata', () async {
      final h = _Harness();
      h.publication = (body) async {
        final reply = _published(body);
        reply.json!['recipe'] = 'other-recipe';
        return reply;
      };
      expect((await h.publish()).status, ProductCutoutPublishStatus.uncertain);
      expect(h.rpcCalls(_selectRpc), isEmpty);
    });

    test(
      'bounded quality ladder advances each variant with its stable request',
      () async {
        final h = _Harness();
        h.publication = (body) async => body['rung'] == 0
            ? const StorefrontFunctionReply(
                httpStatus: 202,
                json: {'status': 'ladder_next', 'next_rung': 2},
              )
            : _published(body);
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.published,
        );
        expect(h.bodies.map((b) => b['rung']), [0, 2, 0, 2]);
        expect(h.bodies[0]['request_id'], h.bodies[1]['request_id']);
        expect(h.bodies[2]['request_id'], h.bodies[3]['request_id']);
      },
    );

    for (final next in [0, 5, '1']) {
      test('invalid next rung $next stops without selection', () async {
        final h = _Harness();
        h.publication = (_) async => StorefrontFunctionReply(
          httpStatus: 202,
          json: {'status': 'ladder_next', 'next_rung': next},
        );
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.bodies, hasLength(1));
        expect(h.rpcCalls(_selectRpc), isEmpty);
      });
    }
  });

  group('selection acknowledgement is not authoritative readback', () {
    for (final mutation in <String, Object?>{
      'ok': false,
      'source_key': 'replaced-original.png',
      'selected_derivative_id': '66666666-6666-4666-8666-666666666666',
      'selection_version': 7,
      'source_snapshot': {'version': 'generation-2', 'size': 1234},
    }.entries) {
      test(
        'does not report published after authoritative ${mutation.key} mismatch',
        () async {
          final h = _Harness();
          h.responses[_readRpc] = [
            {..._read(selected: true), mutation.key: mutation.value},
          ];
          expect(
            (await h.publish()).status,
            isNot(ProductCutoutPublishStatus.published),
          );
          expect(h.rpcCalls(_selectRpc), hasLength(1));
          expect(h.rpcCalls(_readRpc), hasLength(1));
        },
      );
    }

    test(
      'unavailable readback stays uncertain after successful select',
      () async {
        final h = _Harness();
        h.responses[_readRpc] = [TimeoutException('read unavailable')];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.rpcCalls(_selectRpc), hasLength(1));
      },
    );

    for (final code in ['42501', 'PGRST301', '08006']) {
      test(
        'authoritative readback database error $code is classified correctly',
        () async {
          final h = _Harness();
          h.responses[_readRpc] = [
            PostgrestException(message: 'read failed', code: code),
          ];
          expect(
            (await h.publish()).status,
            code == '08006'
                ? ProductCutoutPublishStatus.uncertain
                : ProductCutoutPublishStatus.denied,
          );
          expect(h.rpcCalls(_selectRpc), hasLength(1));
        },
      );
    }

    for (final selectionReply in [
      {
        'ok': true,
        'derivative_id': 'another-derivative',
        'selection_version': 8,
      },
      {'ok': true, 'derivative_id': _derivative, 'selection_version': '8'},
      {'ok': true, 'derivative_id': _derivative},
    ]) {
      test(
        'malformed selection acknowledgement $selectionReply cannot confirm success',
        () async {
          final h = _Harness();
          h.responses[_selectRpc] = [selectionReply];
          h.responses[_readRpc] = [_read(selected: true)];
          expect(
            (await h.publish()).status,
            ProductCutoutPublishStatus.uncertain,
          );
          expect(h.rpcCalls(_selectRpc), hasLength(1));
        },
      );
    }

    test(
      'selection version conflict is surfaced after both variants',
      () async {
        final h = _Harness();
        h.responses[_selectRpc] = [
          {'ok': false, 'error': 'selection_stale'},
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.staleSource,
        );
        expect(h.bodies, hasLength(2));
        expect(h.rpcCalls(_readRpc), isEmpty);
      },
    );

    test(
      'two lost selection replies stay uncertain without another logical write',
      () async {
        final h = _Harness();
        h.responses[_selectRpc] = [
          TimeoutException('lost'),
          TimeoutException('lost'),
        ];
        expect(
          (await h.publish()).status,
          ProductCutoutPublishStatus.uncertain,
        );
        expect(h.rpcCalls(_selectRpc), hasLength(2));
        expect(h.rpcCalls(_selectRpc)[0], h.rpcCalls(_selectRpc)[1]);
        expect(h.bodies, hasLength(2));
      },
    );
  });

  group('Supabase candidate collision recovery', () {
    // Real SDK requests against an ephemeral loopback server verify the factory's
    // upload/no-upsert + exact-byte recovery path, without new dependencies.
    for (final status in [400, 409]) {
      for (final equal in [true, false]) {
        test(
          'HTTP $status candidate collision with ${equal ? 'equal' : 'different same-length'} bytes',
          () async {
            final server = await HttpServer.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            addTearDown(() => server.close(force: true));
            final requests = <({String method, String path, String? upsert})>[];
            var registrations = 0;
            final errors = <Object>[];
            server.listen((request) async {
              try {
                requests.add((
                  method: request.method,
                  path: request.uri.path,
                  upsert: request.headers.value('x-upsert'),
                ));
                await request.drain<void>();
                if (request.uri.path.startsWith('/storage/v1/object/') &&
                    request.method == 'POST') {
                  request.response.statusCode = status;
                  request.response.headers.contentType = ContentType.json;
                  request.response.write(
                    jsonEncode({
                      'statusCode': '$status',
                      'error': 'Duplicate',
                      'message': 'already exists',
                    }),
                  );
                } else if (request.uri.path.startsWith('/storage/v1/object/') &&
                    request.method == 'GET') {
                  request.response.add(equal ? [4, 5, 6] : [4, 5, 7]);
                } else if (request.uri.path == '/rest/v1/rpc/$_registerRpc') {
                  registrations++;
                  request.response.headers.contentType = ContentType.json;
                  request.response.write(
                    jsonEncode({'ok': false, 'error': 'permission_denied'}),
                  );
                } else {
                  errors.add(
                    StateError(
                      'Unexpected ${request.method} ${request.uri.path}',
                    ),
                  );
                  request.response.statusCode = 500;
                }
                await request.response.close();
              } catch (error) {
                errors.add(error);
                await request.response.close();
              }
            });
            final client = SupabaseClient(
              'http://127.0.0.1:${server.port}',
              'local-test-anon-key',
            );
            addTearDown(client.dispose);
            final repo = StorefrontProductCutoutRepository.supabase(client);
            final result = await repo.publish(
              item: _item,
              original: _original(),
              requestId: _request,
              candidateBytes: Uint8List.fromList([4, 5, 6]),
              candidateMimeType: 'image/png',
            );
            expect(errors, isEmpty);
            expect(
              result.status,
              equal
                  ? ProductCutoutPublishStatus.denied
                  : ProductCutoutPublishStatus.unavailable,
            );
            expect(
              registrations,
              equal ? 1 : 0,
              reason: 'only exact bytes permit registration',
            );
            expect(requests[0].method, 'POST');
            expect(requests[0].upsert, 'false');
            expect(requests[1].method, 'GET');
            expect(requests[1].path, requests[0].path);
            expect(requests[0].path, isNot(contains('/original.png')));
            expect(
              requests.every((r) => r.method != 'DELETE' && r.method != 'PUT'),
              isTrue,
            );
            expect(requests.any((r) => r.path.contains(_selectRpc)), isFalse);
          },
        );
      }
    }
  });
}
