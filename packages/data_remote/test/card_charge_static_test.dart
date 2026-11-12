// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C: static guards of the card Edge transport
// (execution packet §5 and §6). They read repository files only; no network.
import 'dart:io';
import 'dart:math' as math;

import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:test/test.dart';

/// The repository root, found from the working directory (`dart test` may run
/// from the root or from the package).
final Directory _root = () {
  var dir = Directory.current.absolute;
  while (true) {
    if (File(
      '${dir.path}/supabase/functions/pos-card-charge/index.ts',
    ).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repository root not found from ${Directory.current}');
    }
    dir = parent;
  }
}();

String _read(String relative) =>
    File('${_root.path}/$relative').readAsStringSync().replaceAll('\r\n', '\n');

/// Every file under [relativeDir] whose path ends with one of [suffixes].
List<String> _files(String relativeDir, List<String> suffixes) {
  final base = Directory('${_root.path}/$relativeDir');
  return [
    for (final entity in base.listSync(recursive: true))
      if (entity is File && suffixes.any(entity.path.endsWith))
        entity.path
            .substring(_root.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
  ]..sort();
}

/// Dart source with `//` and `/* */` comments removed (strings kept).
String _code(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    })
    .join('\n');

/// The body of the method declared by [signature] (ending with its opening
/// parenthesis) in [code]: past the matched parameter list, braces matched.
String _methodBody(String code, String signature) {
  final at = code.indexOf(signature);
  expect(at, greaterThanOrEqualTo(0), reason: 'missing: $signature');
  var i = at + signature.length;
  for (var parens = 1; parens > 0; i++) {
    if (code[i] == '(') parens++;
    if (code[i] == ')') parens--;
  }
  final open = code.indexOf('{', i);
  var depth = 0;
  for (var j = open; j < code.length; j++) {
    if (code[j] == '{') depth++;
    if (code[j] == '}' && --depth == 0) return code.substring(open, j + 1);
  }
  throw StateError('unbalanced: $signature');
}

/// The expression body (`=> ...;`) of the member declared by [signature]
/// (ending with its opening parenthesis) in [code].
String _expressionBody(String code, String signature) {
  final at = code.indexOf(signature);
  expect(at, greaterThanOrEqualTo(0), reason: 'missing: $signature');
  var i = at + signature.length;
  for (var parens = 1; parens > 0; i++) {
    if (code[i] == '(') parens++;
    if (code[i] == ')') parens--;
  }
  final arrow = code.indexOf('=>', i);
  expect(code.substring(i, arrow).trim(), isEmpty, reason: signature);
  var depth = 0;
  for (var j = arrow; j < code.length; j++) {
    if ('({['.contains(code[j])) depth++;
    if (')}]'.contains(code[j])) depth--;
    if (code[j] == ';' && depth == 0) return code.substring(arrow, j + 1);
  }
  throw StateError('unterminated: $signature');
}

/// The braced body of the declaration that starts with [declaration].
String _declarationBody(String code, String declaration) {
  final at = code.indexOf(declaration);
  expect(at, greaterThanOrEqualTo(0), reason: 'missing: $declaration');
  final open = code.indexOf('{', at);
  var depth = 0;
  for (var j = open; j < code.length; j++) {
    if (code[j] == '{') depth++;
    if (code[j] == '}' && --depth == 0) return code.substring(open, j + 1);
  }
  throw StateError('unbalanced: $declaration');
}

int _count(String text, Pattern pattern) => pattern.allMatches(text).length;

/// The argument text of every call of [name] in [source] (whitespace allowed
/// before the parenthesis), parentheses matched across lines.
List<String> _callArguments(String source, String name) => [
  for (final match in RegExp('\\b$name\\s*\\(').allMatches(source))
    _balanced(source, match.end),
];

String _balanced(String source, int start) {
  var depth = 1;
  for (var i = start; i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')' && --depth == 0) return source.substring(start, i);
  }
  throw StateError('unbalanced call at $start');
}

/// The index of the last comma outside any bracket in [arguments], or -1.
int _lastTopLevelComma(String arguments) {
  var depth = 0;
  var last = -1;
  for (var i = 0; i < arguments.length; i++) {
    final c = arguments[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) last = i;
  }
  return last;
}

/// The constructs this scan names, matched on code with comments removed:
/// any timer (a Zone's createTimer included); a Future constructed directly or
/// through delayed, microtask, sync, doWhile, forEach, wait or any; a
/// scheduled microtask; periodic work; a retry of any spelling; a `for`,
/// `while` or `do` loop; a callback chained through then, catchError,
/// whenComplete or onError, typed or not; a Stream or Iterable callback
/// through forEach, handleError, firstWhere, lastWhere, singleWhere, drain,
/// asyncMap, asyncExpand, pipe, onData or onDone; and any listen but
/// `listen(null)`, which only cancels. A deadline-driven re-send through
/// `.timeout(` or a recursive call is caught by the call-site counts instead.
/// Any other form is left to the behaviour rows.
final _forbidden = RegExp(
  r'\w*timer\b|periodic|\bfuture\s*(<[^;{}()]*>)?\s*'
  r'(\.\s*(delayed|microtask|sync|dowhile|foreach|wait|any)\b|\()|'
  r'schedulemicrotask|retry|\bwhile\b|\bfor\s*\(|\bdo\s*\{|'
  r'\.(then|catcherror|whencomplete|onerror|foreach|handleerror|firstwhere|'
  r'lastwhere|singlewhere|drain|asyncmap|asyncexpand|pipe|ondata|ondone)'
  r'\s*(<[^;{}()]*>)?\s*\(|'
  r'\.listen\s*\((?!\s*null\s*\))',
  caseSensitive: false,
);

bool _luhn(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = digits.codeUnitAt(digits.length - 1 - i) - 48;
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}

const _cardSignature = 'Future<CardChargeTransportResult> sendCardCharge(';

/// The 001C client files (this file excluded: it holds the denylist itself).
const _ticketFiles = [
  'packages/data_remote/lib/src/card_charge_transport.dart',
  'packages/data_remote/lib/src/supabase_sync_rpc_transport.dart',
  'packages/data_remote/lib/src/upgradable_sync_transport.dart',
  'packages/data_remote/lib/src/kitchen_ack_http_boundary.dart',
  'packages/data_remote/lib/restoflow_data_remote.dart',
  'packages/data_remote/test/card_charge_transport_test.dart',
  'packages/data_remote/test/card_charge_loopback_test.dart',
  'packages/data_remote/test/support/captured_timers.dart',
  'packages/data_remote/test/support/no_network.dart',
  'packages/auth_identity/lib/src/device_session_guarded_transport.dart',
  'packages/auth_identity/test/device_session_guarded_card_charge_test.dart',
  'apps/pos/test/card_charge_transport_composition_test.dart',
  'apps/pos/test/fixtures/card_charge_edge.mjs',
];

void main() {
  group('the dedicated timeout', () {
    test(
      'is pinned at 40 s: the largest configured 001E worst case (31 s) plus '
      'the documented 9 s margin',
      () {
        expect(posCardChargeTimeout, const Duration(seconds: 40));
        final constants = _read(
          'supabase/functions/pos-card-charge/lib/constants.mjs',
        );
        int ms(String name) => int.parse(
          RegExp(
            '$name: ([0-9_]+),',
          ).firstMatch(constants)!.group(1)!.replaceAll('_', ''),
        );
        final request = ms('requestMs');
        final rpc = ms('rpcMs');
        final window = ms('startWindowMs');
        final lookup = ms('lookupMs');
        final release = ms('releaseMs');
        // The accepted 001E figures, body read included (packet §5.5).
        final worst = {
          'start': request + 2 * rpc + window,
          'status': request + 3 * rpc + lookup,
          'release': request + 4 * rpc + release,
          'free_order': request + 2 * rpc,
        };
        expect(worst, {
          'start': 18000,
          'status': 26000,
          'release': 31000,
          'free_order': 15000,
        });
        for (final entry in worst.entries) {
          expect(
            posCardChargeTimeout.inMilliseconds,
            greaterThan(entry.value),
            reason: entry.key,
          );
        }
        final largest = worst.values.reduce(math.max);
        expect(posCardChargeTimeout.inMilliseconds - largest, 9000);
      },
    );

    test('only the card call uses it; every other call keeps the general '
        '15 s default', () {
      final source = _code(
        _read('packages/data_remote/lib/src/supabase_sync_rpc_transport.dart'),
      );
      final dedicated = RegExp(r'\.timeout\(\s*posCardChargeTimeout\b');
      expect(_count(source, dedicated), 1);
      expect(_count(_methodBody(source, _cardSignature), dedicated), 1);
      // decideWebOrder and the RPC path.
      expect(_count(source, '.timeout(_timeout)'), 2);
      expect(
        _count(source, 'Duration timeout = const Duration(seconds: 15)'),
        2,
      );
    });
  });

  group('one exchange, no retry', () {
    test('the no-retry pattern catches every way to schedule a second '
        'send (positive control)', () {
      for (final mutant in [
        'Future<void>.delayed(const Duration(seconds: 1), send);',
        'Future.delayed(Duration.zero, send);',
        'Timer(const Duration(seconds: 1), send);',
        'Zone.current.createTimer(Duration.zero, send);',
        'Timer.run(send);',
        'Stream<void>.periodic(const Duration(seconds: 1));',
        'scheduleMicrotask(send);',
        'Future.microtask(send);',
        'Future<void>(send);',
        'Future.sync(send);',
        'RetryClient(inner);',
        'await retry(send);',
        'while (true) {}',
        'for (;;) {}',
        'do {} while (pending);',
        'pending.then((_) => send());',
        'pending.catchError((_) => send());',
        'pending.whenComplete(send);',
        'pending.then<void>((_) => send());',
        'Future<void>.value().then<void>((_) => send());',
        'Future.doWhile(() => send());',
        'Future.forEach([1, 2], (_) => send());',
        'Stream<void>.fromFuture(pending).listen((_) => send());',
        'pending.asStream().listen(send);',
        'pending.onError((Object e, StackTrace s) => send());',
        'pending.onError<Object>((_, __) => send());',
        'pending.asStream().forEach((_) => send());',
        '[1, 2].forEach((_) => send());',
        'stream.handleError((_) => send());',
        'data.listen(null).onDone(send);',
        'await stream.firstWhere((e) => e.ok);',
        'pending.asStream().map((_) => send()).drain<void>();',
        'stream.asyncMap((_) => send());',
        'Future.wait([pending], cleanUp: (_) => send());',
      ]) {
        expect(_forbidden.hasMatch(mutant), isTrue, reason: mutant);
      }
      for (final allowed in [
        'return Future.value(result);',
        'return Future.error(refusal);',
        'abortTrigger: permit._ended.future,',
        'unawaited(data.listen(null).cancel());',
        'Future<CardChargeTransportResult> sendCardCharge(',
        'uri.pathSegments.any((segment) => segment == name);',
      ]) {
        expect(_forbidden.hasMatch(allowed), isFalse, reason: allowed);
      }
    });

    test('the card methods add no timer, delay, periodic work, loop or second '
        'send', () {
      final bodies = {
        'supabase': _methodBody(
          _code(
            _read(
              'packages/data_remote/lib/src/supabase_sync_rpc_transport.dart',
            ),
          ),
          _cardSignature,
        ),
        'upgradable': _methodBody(
          _code(
            _read(
              'packages/data_remote/lib/src/upgradable_sync_transport.dart',
            ),
          ),
          _cardSignature,
        ),
        'guard': _methodBody(
          _code(
            _read(
              'packages/auth_identity/lib/src/device_session_guarded_transport.dart',
            ),
          ),
          _cardSignature,
        ),
      };
      for (final entry in bodies.entries) {
        expect(
          _forbidden.allMatches(entry.value).map((m) => m.group(0)),
          isEmpty,
          reason: entry.key,
        );
      }
      expect(_count(bodies['supabase']!, '.invoke('), 1);
      expect(_count(bodies['supabase']!, 'posCardChargeFunction'), 1);
      expect(_count(bodies['upgradable']!, '.sendCardCharge('), 1);
      expect(_count(bodies['guard']!, '.sendCardCharge('), 1);
      // The whole capability file has no executable timer or loop either.
      final capability = _code(
        _read('packages/data_remote/lib/src/card_charge_transport.dart'),
      );
      // (Its JSON helpers iterate the decoded answer, so loops are allowed.)
      expect(
        RegExp(
          r'\w*timer\b|periodic|\bfuture\s*(<[^;{}()]*>)?\s*'
          r'(\.\s*(delayed|microtask|sync)\b|\()|schedulemicrotask|retry|'
          r'\bwhile\b|\.then\(|import ',
          caseSensitive: false,
        ).allMatches(capability).map((m) => m.group(0)),
        isEmpty,
      );
    });

    test('the card path files hold no timer, delay, periodic work, retry, '
        'loop or chained callback beyond the pinned existing ones, and the '
        'Supabase implementation has one card call site', () {
      final expected = <String, List<String>>{
        // The answer's JSON helpers iterate the decoded body.
        'packages/data_remote/lib/src/card_charge_transport.dart': [
          'for (',
          'for (',
          'for (',
        ],
        'packages/data_remote/lib/src/supabase_sync_rpc_transport.dart': [],
        // A generic signature the pattern over-matches; the byte comparison.
        'packages/data_remote/lib/src/kitchen_ack_http_boundary.dart': [
          'Future<T> runCardCharge<T>(',
          'for (',
        ],
        // The upgrade listeners; the hold mode's message.
        'packages/data_remote/lib/src/upgradable_sync_transport.dart': [
          'for (',
          'retry',
        ],
        'packages/auth_identity/lib/src/device_session_guarded_transport.dart':
            [],
      };
      for (final entry in expected.entries) {
        expect(
          _forbidden
              .allMatches(_code(_read(entry.key)))
              .map((m) => m.group(0))
              .toList(),
          entry.value,
          reason: entry.key,
        );
      }
      // No other card-path file holds a timeout, and each names
      // sendCardCharge( only where it declares or forwards it (the boundary's
      // private _sendCardCharge twice).
      for (final (path, sends) in [
        ('packages/data_remote/lib/src/card_charge_transport.dart', 1),
        ('packages/data_remote/lib/src/kitchen_ack_http_boundary.dart', 2),
        ('packages/data_remote/lib/src/upgradable_sync_transport.dart', 2),
        (
          'packages/auth_identity/lib/src/device_session_guarded_transport.dart',
          2,
        ),
      ]) {
        final code = _code(_read(path));
        expect(_count(code, '.timeout('), 0, reason: path);
        expect(_count(code, 'onTimeout'), 0, reason: path);
        expect(_count(code, 'sendCardCharge('), sends, reason: path);
      }
      final supabase = _code(
        _read('packages/data_remote/lib/src/supabase_sync_rpc_transport.dart'),
      );
      // One card call site, one exchange, one deadline: a second send, a
      // recursive call or a timeout-driven re-send changes a count.
      expect(_count(supabase, 'sendCardCharge('), 1);
      expect(_count(supabase, 'CardChargeExchange('), 1);
      expect(_count(supabase, 'runCardCharge('), 1);
      expect(_count(supabase, '.invoke('), 2); // the decision and the card
      expect(_count(supabase, '.timeout('), 3); // 15 s twice, the deadline
      expect(_count(supabase, 'onTimeout'), 1);
      expect(_count(supabase, 'unawaited('), 1); // the event stream's cancel
      final body = _methodBody(supabase, _cardSignature);
      expect(_count(body, '.timeout('), 1);
      expect(_count(body, 'sendCardCharge('), 0);
    });

    test('the HTTP boundary card code adds no timer, delay, periodic work, '
        'loop or second send either', () {
      final boundary = _code(
        _read('packages/data_remote/lib/src/kitchen_ack_http_boundary.dart'),
      );
      final card = {
        '_sendCardCharge': _methodBody(
          boundary,
          'Future<http.StreamedResponse> _sendCardCharge(',
        ),
        '_cardRefusal': _methodBody(
          boundary,
          'CardChargeHandoffRefused? _cardRefusal(',
        ),
        'runCardCharge': _expressionBody(
          boundary,
          'Future<T> runCardCharge<T>(',
        ),
        '_isCardChargeRoute': _expressionBody(
          boundary,
          'static bool _isCardChargeRoute(',
        ),
        '_decoded': _methodBody(boundary, 'static String _decoded('),
        'CardChargeExchange': _declarationBody(
          boundary,
          'final class CardChargeExchange',
        ),
      };
      for (final entry in card.entries) {
        expect(entry.value.length, greaterThan(20), reason: entry.key);
        expect(
          _forbidden.allMatches(entry.value).map((m) => m.group(0)),
          isEmpty,
          reason: entry.key,
        );
      }
    });

    test('001C adds no SDK importer: the capability file imports nothing', () {
      final importers = [
        for (final path in _files('packages/data_remote/lib', ['.dart']))
          if (_read(path).contains("import 'package:supabase/")) path,
      ];
      // The same two importers as at the base.
      expect(importers, [
        'packages/data_remote/lib/src/realtime_invalidation_source.dart',
        'packages/data_remote/lib/src/supabase_sync_rpc_transport.dart',
      ]);
    });

    test('the HTTP boundary gates the card route before anything else and '
        'hands it off once, redirects off, abortable by the exchange end', () {
      final boundary = _code(
        _read('packages/data_remote/lib/src/kitchen_ack_http_boundary.dart'),
      );
      final send = _methodBody(boundary, 'Future<http.StreamedResponse> send(');
      expect(
        send.indexOf(
          'if (_isCardChargeRoute(request.url)) return '
          '_sendCardCharge(request);',
        ),
        allOf(
          greaterThanOrEqualTo(0),
          lessThan(send.indexOf('_isAckRoute(request.url)')),
        ),
      );
      final card = _methodBody(
        boundary,
        'Future<http.StreamedResponse> _sendCardCharge(',
      );
      expect(_count(card, '_inner.send('), 1);
      expect(_count(card, '..followRedirects = false'), 1);
      expect(_count(card, 'abortTrigger: permit._ended.future'), 1);
      expect(_count(card, 'permit._handedOff = true;'), 1);
      // The ACK path keeps its own single redirect rule.
      expect(_count(boundary, 'request.followRedirects = false;'), 1);
    });

    test('a web build refuses before any IO', () {
      final source = _code(
        _read('packages/data_remote/lib/src/supabase_sync_rpc_transport.dart'),
      );
      expect(
        _count(
          source,
          "const bool _onWeb = bool.fromEnvironment('dart.library.js_interop');",
        ),
        1,
      );
      final body = _methodBody(source, _cardSignature);
      expect(
        body.indexOf('if (_onWeb)'),
        allOf(greaterThanOrEqualTo(0), lessThan(body.indexOf('jsonEncode('))),
      );
    });

    test('the refusal tokens a 200 can never carry are exactly the ones the '
        'function only answers with another status: statusOf maps and the '
        'handler replies explicitly', () {
      final envelope = _read(
        'supabase/functions/pos-card-charge/lib/envelope.mjs',
      );
      final statusOf = envelope.substring(
        envelope.indexOf('export function statusOf('),
      );
      final mapped = RegExp(
        r'answer\.error === "([a-z_]+)"',
      ).allMatches(statusOf).map((m) => m.group(1)!).toSet();
      expect(mapped, {
        'invalid_request',
        'invalid_session',
        'provider_unavailable',
        'unavailable',
      });
      final handler = _read('supabase/functions/pos-card-charge/handler.mjs');
      expect(
        handler,
        contains(
          'const UNAVAILABLE = Object.freeze({ ok: false, error: '
          '"unavailable" });',
        ),
      );
      // The handler answers only through `reply` (its own jsonResponse call),
      // and every reply call - parentheses matched across lines - is either
      // the one statusOf reply or an explicit non-200 status with a literal
      // refusal or UNAVAILABLE.
      expect(_count(handler, RegExp(r'\bjsonResponse\s*\(')), 1);
      expect(_count(handler, RegExp(r'\bnew\s+Response\b')), 0);
      expect(
        _count(handler, RegExp(r'\bResponse\s*\.\s*(json|error|redirect)\b')),
        0,
      );
      final calls = _callArguments(handler, 'reply');
      expect(calls, hasLength(9));
      final explicit = <String>{};
      var statusOfReplies = 0;
      for (final arguments in calls) {
        final comma = _lastTopLevelComma(arguments);
        if (comma < 0) {
          statusOfReplies++;
          continue;
        }
        final body = arguments.substring(0, comma).trim();
        final status = arguments.substring(comma + 1).trim();
        expect(status, matches(RegExp(r'^[0-9]{3}$')), reason: arguments);
        expect(status, isNot('200'), reason: arguments);
        final literal = RegExp(r'^refusal\("([a-z_]+)"\)$').firstMatch(body);
        if (literal == null) {
          expect(body, 'UNAVAILABLE', reason: arguments);
          explicit.add('unavailable');
        } else {
          explicit.add(literal.group(1)!);
        }
      }
      expect(statusOfReplies, 1);
      expect(explicit, {
        'origin_not_allowed',
        'not_found',
        'method_not_allowed',
        'invalid_session',
        'invalid_request',
        'unavailable',
      });
      expect({...mapped, ...explicit}, cardChargeNon200Errors);
    });
  });

  group('the production composition grants the capability', () {
    test('the POS session factory asks for the guarded client, and the '
        'bootstrap builds it with the default inner client', () {
      final main = _read('apps/pos/lib/main.dart');
      final factory = main.substring(
        main.indexOf(
          'static Future<PosAnonymousDeviceSession> '
          '_defaultCreateSession()',
        ),
      );
      expect(
        factory.substring(0, factory.indexOf('}')),
        contains('guardKitchenAcknowledgements: true,'),
      );
      final bootstrap = _code(
        _read('packages/auth_identity/lib/src/supabase_auth_bootstrap.dart'),
      );
      expect(
        RegExp(
          r'SupabaseSyncRpcTransport\.createKitchenAckClient\(\s*_config\.url,\s*_config\.anonKey,\s*\)',
        ).allMatches(bootstrap),
        hasLength(1),
      );
    });
  });

  group('no secret, provider value or card value in the client', () {
    test('no service-role value, provider host, vendor field, terminal '
        'reference or provider key in the client Dart sources', () {
      final scanned = <String>{
        ..._files('packages/data_remote', ['.dart']),
        ..._files('packages/auth_identity/lib', ['.dart']),
        ..._files('apps/pos/lib', ['.dart']),
        'packages/auth_identity/test/device_session_guarded_card_charge_test.dart',
        'apps/pos/test/card_charge_transport_composition_test.dart',
      }..remove('packages/data_remote/test/card_charge_static_test.dart');
      final vendor = RegExp(
        r'zcredit\.co|ZCreditWS|TerminalNumber|Track2|ExpDate_MMYY|'
        r'TransactionUniqueI[Dd]|UniqueQuery|PINPAD|terminal_number|'
        r'terminal_ref|credential_ref|provider_query_key|'
        r'provider_duplicate_key',
      );
      final secret = RegExp(
        r'service_role|serviceRole|SERVICE_ROLE|sb_secret_',
      );
      const rejectionRule =
          'packages/auth_identity/lib/src/supabase_bootstrap_config.dart';
      final hits = <String>[];
      for (final path in scanned) {
        final text = _read(path);
        for (final match in vendor.allMatches(text)) {
          hits.add('$path: ${match.group(0)}');
        }
        // Only the bootstrap's own rejection rule may name a service-role or
        // secret key shape (it refuses such a key at configuration time).
        if (path != rejectionRule && secret.hasMatch(text)) {
          hits.add('$path: a service-role or secret key shape');
        }
      }
      expect(hits, isEmpty);
      expect(
        secret.hasMatch(_read(rejectionRule)),
        isTrue,
        reason: 'the exception is the rejection rule itself',
      );
    });

    test('no card-shaped digit run in the ticket files', () {
      final run = RegExp(r'[0-9](?:[ -]?[0-9]){12,18}');
      final hits = <String>[];
      for (final path in _ticketFiles) {
        final file = File('${_root.path}/$path');
        if (!file.existsSync()) continue;
        for (final match in run.allMatches(file.readAsStringSync())) {
          final digits = match.group(0)!.replaceAll(RegExp(r'[ -]'), '');
          if (_luhn(digits)) hits.add('$path: a Luhn-valid run');
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('the provider profile stays unwired (read-only)', () {
    test(
      'index.ts keeps providerProfile: null and imports only the handler',
      () {
        final index = _read('supabase/functions/pos-card-charge/index.ts');
        expect(
          _count(
            index,
            RegExp(r'^\s*providerProfile: null,$', multiLine: true),
          ),
          1,
        );
        expect(
          RegExp(
            r'^import .*$',
            multiLine: true,
          ).allMatches(index).map((m) => m.group(0)),
          ['import { createHandler } from "./handler.mjs";'],
        );
      },
    );

    test('the Z-Credit candidate is imported only by its own test', () {
      final importers = [
        for (final path in _files('supabase/functions/pos-card-charge', [
          '.mjs',
          '.ts',
          '.js',
        ]))
          if (RegExp(
            r'''from\s+["'][^"']*zcredit_profile(\.mjs)?["']|import\(\s*["'][^"']*zcredit_profile''',
          ).hasMatch(_read(path)))
            path,
      ];
      expect(importers, [
        'supabase/functions/pos-card-charge/test/zcredit_profile.test.mjs',
      ]);
    });
  });
}
