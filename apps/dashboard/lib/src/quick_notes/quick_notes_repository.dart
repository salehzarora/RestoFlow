/// POS-QUICK-NOTES-124 — the Dashboard seam for the restaurant's reusable POS
/// note phrases.
///
/// Restaurant-wide by contract: there is no branch dimension in v1, so one list
/// serves every POS device of the restaurant. Every write is a manager+ RPC
/// (D-011); this seam never touches the table directly, and it never reports a
/// success the server did not give it — a failed save leaves the caller to
/// reload the authoritative list rather than keeping an optimistic guess on
/// screen.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// The strict label contract, enforced identically here, in the RPC, and by a
/// CHECK constraint. Smaller than the POS note field's own 140 so a cashier can
/// still combine two or three presets in one note.
const int kQuickNoteMaxLength = 60;

/// The soft guidance shown to the owner. NOT enforced anywhere: a restaurant
/// with a genuine reason for more is not blocked, they are only told that the
/// POS chips get harder to scan.
const int kQuickNoteSoftMax = 12;

/// One preset as the Dashboard sees it — including one the owner has switched
/// OFF, which `pos_menu` deliberately withholds from the cashier.
class QuickNotePreset {
  const QuickNotePreset({
    required this.id,
    required this.label,
    required this.displayOrder,
    required this.isActive,
  });

  final String id;
  final String label;
  final int displayOrder;
  final bool isActive;

  QuickNotePreset copyWith({String? label, bool? isActive}) => QuickNotePreset(
    id: id,
    label: label ?? this.label,
    displayOrder: displayOrder,
    isActive: isActive ?? this.isActive,
  );
}

/// Why a read failed, or that it did not.
enum QuickNotesLoadStatus {
  ok,

  /// The caller is authenticated but outranked (a cashier). Distinct from a
  /// transport failure because retrying will not help.
  denied,

  /// Network/transport trouble, or a reply this build could not parse.
  unavailable,
}

/// The outcome of a write. Every value is something the owner can be told
/// truthfully; there is no "probably worked".
enum QuickNoteWrite {
  ok,

  /// The server refused a live duplicate label in this restaurant.
  duplicateLabel,

  /// Manager+ is required and the caller is not.
  denied,

  /// Rejected before the call: blank, or longer than [kQuickNoteMaxLength].
  invalid,

  /// The call did not complete, or the server refused for another reason.
  failed,
}

/// What a read produced.
class QuickNotesSnapshot {
  const QuickNotesSnapshot(this.status, this.presets);

  const QuickNotesSnapshot.ok(List<QuickNotePreset> presets)
    : this(QuickNotesLoadStatus.ok, presets);

  const QuickNotesSnapshot.failed(QuickNotesLoadStatus status)
    : this(status, const []);

  final QuickNotesLoadStatus status;

  /// Display-ordered, tombstones excluded, DISABLED presets included.
  final List<QuickNotePreset> presets;
}

abstract class QuickNotesRepository {
  /// `public.list_quick_note_presets`.
  Future<QuickNotesSnapshot> load();

  /// `public.upsert_quick_note_preset` — create ([id] null; appends after the
  /// live siblings) or rename/enable/disable an existing preset.
  Future<QuickNoteWrite> upsert({
    String? id,
    required String label,
    required bool isActive,
  });

  /// `public.soft_delete_quick_note_preset` — tombstones it (D-020).
  Future<QuickNoteWrite> delete(String id);

  /// `public.reorder_quick_note_presets` — the COMPLETE live id list in the
  /// owner's new order. A partial list is refused by the server rather than
  /// silently inventing an order for what it omitted.
  Future<QuickNoteWrite> reorder(List<String> ids);
}

class SupabaseQuickNotesRepository implements QuickNotesRepository {
  SupabaseQuickNotesRepository({
    required SyncRpcTransport transport,
    required String organizationId,
    required String restaurantId,
    String? Function()? currentUserId,
    int Function()? nonce,
  }) : _t = transport,
       _org = organizationId,
       _restaurant = restaurantId,
       _uid = currentUserId ?? _noUser,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final String _org;
  final String _restaurant;
  final String? Function() _uid;
  final int Function() _nonce;

  static String? _noUser() => null;
  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<QuickNotesSnapshot> load() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_quick_note_presets', <String, dynamic>{
        'p_organization_id': _org,
        'p_restaurant_id': _restaurant,
      });
    } on SyncTransportException catch (e) {
      return QuickNotesSnapshot.failed(
        e.kind == SyncTransportErrorKind.auth
            ? QuickNotesLoadStatus.denied
            : QuickNotesLoadStatus.unavailable,
      );
    } catch (_) {
      return const QuickNotesSnapshot.failed(QuickNotesLoadStatus.unavailable);
    }
    if (raw is! Map) {
      return const QuickNotesSnapshot.failed(QuickNotesLoadStatus.unavailable);
    }
    if (raw['ok'] != true) {
      return QuickNotesSnapshot.failed(
        raw['error'] == 'permission_denied'
            ? QuickNotesLoadStatus.denied
            : QuickNotesLoadStatus.unavailable,
      );
    }
    final rows = raw['presets'];
    if (rows is! List) {
      return const QuickNotesSnapshot.failed(QuickNotesLoadStatus.unavailable);
    }
    final presets = <QuickNotePreset>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['id'];
      final label = row['label'];
      if (id is! String || id.isEmpty || label is! String) continue;
      final order = row['display_order'];
      presets.add(
        QuickNotePreset(
          id: id,
          label: label,
          displayOrder: order is int ? order : presets.length,
          // Absent means nothing here: the server always sends it, and
          // defaulting a missing flag to "enabled" would show a switched-off
          // preset as live. Only an explicit `true` is enabled.
          isActive: row['is_active'] == true,
        ),
      );
    }
    return QuickNotesSnapshot.ok(presets);
  }

  @override
  Future<QuickNoteWrite> upsert({
    String? id,
    required String label,
    required bool isActive,
  }) async {
    final trimmed = label.trim();
    // Checked here as well as on the server, so the owner gets an immediate,
    // specific message instead of a round trip that ends in a generic failure.
    if (trimmed.isEmpty || trimmed.length > kQuickNoteMaxLength) {
      return QuickNoteWrite.invalid;
    }
    return _write('upsert_quick_note_preset', <String, dynamic>{
      'p_client_request_id': _requestId('upsert', [
        id ?? '',
        trimmed,
        '$isActive',
      ]),
      'p_organization_id': _org,
      'p_restaurant_id': _restaurant,
      'p_id': id,
      'p_label': trimmed,
      'p_is_active': isActive,
    });
  }

  @override
  Future<QuickNoteWrite> delete(String id) =>
      _write('soft_delete_quick_note_preset', <String, dynamic>{
        'p_client_request_id': _requestId('delete', [id]),
        'p_organization_id': _org,
        'p_preset_id': id,
      });

  @override
  Future<QuickNoteWrite> reorder(List<String> ids) {
    if (ids.isEmpty) return Future.value(QuickNoteWrite.invalid);
    return _write('reorder_quick_note_presets', <String, dynamic>{
      'p_organization_id': _org,
      'p_restaurant_id': _restaurant,
      'p_ids': ids,
    });
  }

  Future<QuickNoteWrite> _write(
    String function,
    Map<String, dynamic> params,
  ) async {
    final Object? raw;
    try {
      raw = await _t.invoke(function, params);
    } on SyncTransportException catch (e) {
      return e.kind == SyncTransportErrorKind.auth
          ? QuickNoteWrite.denied
          : QuickNoteWrite.failed;
    } catch (_) {
      return QuickNoteWrite.failed;
    }
    if (raw is! Map) return QuickNoteWrite.failed;
    if (raw['ok'] == true) return QuickNoteWrite.ok;
    return switch (raw['error']) {
      'duplicate_label' => QuickNoteWrite.duplicateLabel,
      'permission_denied' => QuickNoteWrite.denied,
      _ => QuickNoteWrite.failed,
    };
  }

  /// RFC-4122-shaped UUID with a per-call nonce — the same pattern the tables,
  /// staff and printers repositories use. Every press is a distinct operation
  /// for the server's client_request_id ledger, so a deliberate second edit is
  /// never swallowed as a replay of the first.
  String _requestId(String op, List<String> parts) {
    final seed = [_uid() ?? '', op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('qn124:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
