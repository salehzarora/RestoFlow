/// PAYMENT-ATTEMPT-RECOVERY-001 / K3-B04 — the STRICT, TOTAL codecs for the
/// optional `replacement_block` envelope field and its persisted server truth.
///
/// Everything in this file is TOTAL: every function returns a typed result for
/// every input, including `null`, a non-Map, a Map with a non-String key, a
/// present-null field and an unknown enum value. Nothing here throws.
///
/// WHY NOT `Map<String, Object?>.from(raw)`: that cast throws a `TypeError` on a
/// map whose keys are not all Strings, which escapes past the typed malformed
/// result the caller is relying on. [strictStringObjectMap] copies entry by
/// entry instead and reports the bad key as data.
///
/// WHY THIS IS NOT A FIELD OF `PaymentAttempt`: the record's 26-key allowlist
/// and its `toJson` are a frozen wire contract (`payment_attempt.dart:719-777`),
/// and a stored record carrying an unknown key is deliberately quarantined
/// (`:784-788`). The block therefore rides as a SIBLING key on the envelope
/// entry and is decoded by the store, which strips it before handing the
/// remaining 26 keys to the shipped strict decoder. The attempt's own wire shape
/// is unchanged.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'payment.dart' show PaymentMethod;
import 'payment_attempt.dart';

/// The envelope-entry key the block occupies, beside the attempt's own 26.
const String kReplacementBlockKey = 'replacement_block';

// ---------------------------------------------------------------------------
// Strict map conversion
// ---------------------------------------------------------------------------

@immutable
sealed class StrictMapDecodeResult {
  const StrictMapDecodeResult();
}

@immutable
final class StrictMapOk extends StrictMapDecodeResult {
  const StrictMapOk(this.map);
  final Map<String, Object?> map;
}

@immutable
final class StrictMapNotAMap extends StrictMapDecodeResult {
  const StrictMapNotAMap(this.observedTypeName);
  final String observedTypeName;
}

@immutable
final class StrictMapBadKey extends StrictMapDecodeResult {
  const StrictMapBadKey(this.observedTypeName);
  final String observedTypeName;
}

/// TOTAL. Never throws, whatever [raw] is.
StrictMapDecodeResult strictStringObjectMap(Object? raw) {
  if (raw is! Map) {
    return StrictMapNotAMap(raw == null ? 'null' : raw.runtimeType.toString());
  }
  final out = <String, Object?>{};
  for (final entry in raw.entries) {
    final k = entry.key;
    if (k is! String) {
      return StrictMapBadKey(k == null ? 'null' : k.runtimeType.toString());
    }
    out[k] = entry.value;
  }
  return StrictMapOk(out);
}

/// Null when [m] carries EXACTLY [allowed]; otherwise the violation.
///
/// Both directions are enforced, mirroring the record contract: no unknown key
/// (`payment_attempt.dart:784-788`) AND no missing key (its `toJson` emits every
/// allowlisted key unconditionally, `:719-746`). A present-null therefore never
/// silently defaults — the per-field reader rejects it.
String? exactKeys(Map<String, Object?> m, Set<String> allowed) {
  for (final k in m.keys) {
    if (!allowed.contains(k)) return 'unknown field $k';
  }
  for (final k in allowed) {
    if (!m.containsKey(k)) return 'missing field $k';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Canonical instants
// ---------------------------------------------------------------------------

/// The EXACT spelling both producers write:
///   `PaymentAttempt.mint`  — `now.toUtc().toIso8601String()` (`:337`)
///   `PaymentController`    — `_nowIso()`, the same expression (`:452-453`)
///
/// `DateTime.tryParse` alone accepts many spellings neither producer emits, so
/// the rule is a ROUND TRIP: parse, re-encode canonically, require the exact
/// input back.
bool isCanonicalInstant(Object? v) {
  if (v is! String) return false;
  if (v.trim().isEmpty) return false;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) return false;
  return parsed.toUtc().toIso8601String() == v;
}

/// The canonical spelling of [t]. Every value this produces also satisfies the
/// shipped `optTime` rule (`payment_attempt.dart:809-817`).
String canonicalInstant(DateTime t) => t.toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// Wire codecs — each total, each refusing to fall back on an unknown value
// ---------------------------------------------------------------------------

/// A stored value this build does not recognise is evidence it cannot
/// interpret, never a default. Same discipline as `PaymentRefusalCode.fromWire`
/// (`payment_attempt.dart:147-160`), and for the same reason: a corrupt value
/// that decoded to a known state could resolve an attempt and free an identity.
enum BlockStatus {
  active('active'),
  resolved('resolved');

  const BlockStatus(this.wire);
  final String wire;

  static BlockStatus? fromWire(Object? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

enum BlockResolutionKind {
  /// The ONLY value: only exact APPLIED evidence may resolve a block.
  applied('applied');

  const BlockResolutionKind(this.wire);
  final String wire;

  static BlockResolutionKind? fromWire(Object? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

/// Where an accepted truth came from. Carried BY THE TRUTH so it can never
/// disagree with a second Boolean: `PaymentSendAccepted` is a direct send and
/// `PaymentAttemptStatusApplied` is a passive ledger lookup "which executes
/// nothing" (`payment_repository.dart:147-151`, `:181-191`).
enum BlockEvidenceSource {
  directSend('direct_send'),
  passiveStatusLookup('status_lookup');

  const BlockEvidenceSource(this.wire);
  final String wire;

  static BlockEvidenceSource? fromWire(Object? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

enum IncidentReason {
  ownerBContradiction('owner_b_contradiction'),
  recordLoss('record_loss'),
  blockIdFailure('block_id_failure'),
  durableBlockWriteFailed('durable_block_write_failed'),
  storageUntrusted('storage_untrusted');

  const IncidentReason(this.wire);
  final String wire;

  static IncidentReason? fromWire(Object? w) {
    for (final v in values) {
      if (v.wire == w) return v;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// ServerTruth — four persisted variants, each with an EXACT key set
// ---------------------------------------------------------------------------

@immutable
sealed class ServerTruth {
  const ServerTruth();

  String get kind;
  Map<String, Object?> toJson();
}

@immutable
sealed class ServerTruthDecode {
  const ServerTruthDecode();
}

@immutable
final class ServerTruthOk extends ServerTruthDecode {
  const ServerTruthOk(this.truth);
  final ServerTruth truth;
}

@immutable
final class ServerTruthMalformed extends ServerTruthDecode {
  const ServerTruthMalformed(this.rule, this.message);
  final String rule;
  final String message;
}

/// MONEY identity. `replay` is EXCLUDED because it describes the REPLY, not the
/// money (`payment_attempt.dart:198-199`) — the same acceptance read back
/// through the idempotency ledger is the same money with `replay: true`.
///
/// This is source's own split: `sameTerminalAnswerAs` (`:709-717`) compares the
/// five money fields and deliberately omits `replay`, while `operator ==`
/// (`:598`) includes it.
bool sameMoneyTruth(PaymentAttemptResolution a, PaymentAttemptResolution b) =>
    a.paymentId == b.paymentId &&
    a.receiptNumber == b.receiptNumber &&
    a.changeDueMinor == b.changeDueMinor &&
    a.method == b.method &&
    a.orderStatus == b.orderStatus;

/// BYTE identity: all six fields. Codec equality and round-trip only.
bool identicalResolution(
  PaymentAttemptResolution a,
  PaymentAttemptResolution b,
) => sameMoneyTruth(a, b) && a.replay == b.replay;

@immutable
final class AcceptedTruth extends ServerTruth {
  const AcceptedTruth({required this.resolution, required this.evidenceSource});

  /// The WHOLE shipped resolution — never a reprojection, so no field can be
  /// lost between the wire and the record.
  final PaymentAttemptResolution resolution;

  /// Provenance, carried by the truth itself (K3-B05).
  final BlockEvidenceSource evidenceSource;

  @override
  String get kind => 'accepted';

  static const Set<String> keys = <String>{
    'kind',
    'resolution',
    'evidence_source',
  };

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'accepted',
    'resolution': resolution.toJson(),
    'evidence_source': evidenceSource.wire,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcceptedTruth &&
          evidenceSource == other.evidenceSource &&
          identicalResolution(resolution, other.resolution);

  @override
  int get hashCode => Object.hash(
    'accepted',
    evidenceSource,
    resolution.paymentId,
    resolution.receiptNumber,
    resolution.changeDueMinor,
    resolution.method,
    resolution.replay,
    resolution.orderStatus,
  );
}

@immutable
final class MemoizedRefusalTruth extends ServerTruth {
  const MemoizedRefusalTruth(this.code);
  final PaymentRefusalCode code;

  @override
  String get kind => 'memoized_refusal';

  static const Set<String> keys = <String>{'kind', 'refusal_code'};

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'memoized_refusal',
    'refusal_code': code.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is MemoizedRefusalTruth && code == other.code;

  @override
  int get hashCode => Object.hash('memoized_refusal', code);
}

@immutable
final class NonMemoizedRefusalTruth extends ServerTruth {
  const NonMemoizedRefusalTruth(this.code);
  final PaymentRefusalCode code;

  @override
  String get kind => 'nonmemoized_refusal';

  static const Set<String> keys = <String>{'kind', 'refusal_code'};

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'nonmemoized_refusal',
    'refusal_code': code.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is NonMemoizedRefusalTruth && code == other.code;

  @override
  int get hashCode => Object.hash('nonmemoized_refusal', code);
}

/// A diagnostic keeps the EXACT reason/code its public constructor needs, rather
/// than flattening to a marker: `PaymentAttemptUnconfirmed` requires a
/// `PaymentUnconfirmedReason` (`payment_controller.dart:251-256`) and
/// `PaymentSendNotApplied` carries a `String code` (`payment_repository.dart:171`).
@immutable
final class DiagnosticTruth extends ServerTruth {
  const DiagnosticTruth._(
    this.marker,
    this.unconfirmedReason,
    this.notAppliedCode,
  );

  factory DiagnosticTruth.unconfirmed(PaymentUnconfirmedReason r) =>
      DiagnosticTruth._(PaymentAttemptLastOutcome.unconfirmed, r, null);
  factory DiagnosticTruth.notApplied(String code) =>
      DiagnosticTruth._(PaymentAttemptLastOutcome.notApplied, null, code);
  factory DiagnosticTruth.authRequired() => const DiagnosticTruth._(
    PaymentAttemptLastOutcome.authRequired,
    null,
    null,
  );
  factory DiagnosticTruth.collision() =>
      const DiagnosticTruth._(PaymentAttemptLastOutcome.collision, null, null);

  final PaymentAttemptLastOutcome marker;
  final PaymentUnconfirmedReason? unconfirmedReason;
  final String? notAppliedCode;

  @override
  String get kind => 'diagnostic';

  static const Set<String> keys = <String>{
    'kind',
    'marker',
    'unconfirmed_reason',
    'not_applied_code',
  };

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'diagnostic',
    'marker': marker.wire,
    'unconfirmed_reason': unconfirmedReason?.name,
    'not_applied_code': notAppliedCode,
  };

  @override
  bool operator ==(Object other) =>
      other is DiagnosticTruth &&
      marker == other.marker &&
      unconfirmedReason == other.unconfirmedReason &&
      notAppliedCode == other.notAppliedCode;

  @override
  int get hashCode =>
      Object.hash('diagnostic', marker, unconfirmedReason, notAppliedCode);
}

/// TOTAL entry point. Never throws.
ServerTruthDecode decodeServerTruth(Object? raw) {
  final m = strictStringObjectMap(raw);
  switch (m) {
    case StrictMapNotAMap(:final observedTypeName):
      return ServerTruthMalformed(
        'T0',
        'server_truth: not an object ($observedTypeName)',
      );
    case StrictMapBadKey(:final observedTypeName):
      return ServerTruthMalformed(
        'T0',
        'server_truth: non-String key ($observedTypeName)',
      );
    case StrictMapOk(:final map):
      switch (map['kind']) {
        case 'accepted':
          return _decodeAccepted(map);
        case 'memoized_refusal':
          return _decodeRefusal(map, memoized: true);
        case 'nonmemoized_refusal':
          return _decodeRefusal(map, memoized: false);
        case 'diagnostic':
          return _decodeDiagnostic(map);
        default:
          return const ServerTruthMalformed('T1', 'server_truth: kind');
      }
  }
}

ServerTruthDecode _decodeAccepted(Map<String, Object?> m) {
  final bad = exactKeys(m, AcceptedTruth.keys);
  if (bad != null) return ServerTruthMalformed('T2', 'accepted_truth: $bad');
  final src = BlockEvidenceSource.fromWire(m['evidence_source']);
  if (src == null) {
    return const ServerTruthMalformed('T3', 'accepted_truth: evidence_source');
  }
  final rm = strictStringObjectMap(m['resolution']);
  if (rm is! StrictMapOk) {
    return const ServerTruthMalformed(
      'T4',
      'accepted_truth: resolution is not an object',
    );
  }
  // The SHIPPED strict decoder is the only resolution parser. It throws, so it
  // is wrapped here. `tenderType` is deliberately NOT supplied: this codec has
  // no attempt in hand, and the tender gate is applied against the frozen
  // subject at resolution time instead.
  final PaymentAttemptResolution parsed;
  try {
    parsed = PaymentAttemptResolution.fromJson(rm.map);
  } on FormatException catch (e) {
    return ServerTruthMalformed('T5', 'accepted_truth: ${e.message}');
  }
  return ServerTruthOk(AcceptedTruth(resolution: parsed, evidenceSource: src));
}

ServerTruthDecode _decodeRefusal(
  Map<String, Object?> m, {
  required bool memoized,
}) {
  final name = memoized
      ? 'memoized_refusal_truth'
      : 'nonmemoized_refusal_truth';
  final allowed = memoized
      ? MemoizedRefusalTruth.keys
      : NonMemoizedRefusalTruth.keys;
  final bad = exactKeys(m, allowed);
  if (bad != null) return ServerTruthMalformed('T6', '$name: $bad');
  final code = PaymentRefusalCode.fromWire(m['refusal_code']);
  if (code == null) return ServerTruthMalformed('T7', '$name: refusal_code');
  return ServerTruthOk(
    memoized ? MemoizedRefusalTruth(code) : NonMemoizedRefusalTruth(code),
  );
}

ServerTruthDecode _decodeDiagnostic(Map<String, Object?> m) {
  final bad = exactKeys(m, DiagnosticTruth.keys);
  if (bad != null) return ServerTruthMalformed('T8', 'diagnostic_truth: $bad');
  final marker = PaymentAttemptLastOutcome.fromWire(m['marker']);
  if (marker == null || marker == PaymentAttemptLastOutcome.none) {
    return const ServerTruthMalformed('T9', 'diagnostic_truth: marker');
  }

  final rawReason = m['unconfirmed_reason'];
  PaymentUnconfirmedReason? reason;
  if (rawReason != null) {
    if (rawReason is! String) {
      return const ServerTruthMalformed(
        'T10',
        'diagnostic_truth: unconfirmed_reason',
      );
    }
    for (final r in PaymentUnconfirmedReason.values) {
      if (r.name == rawReason) {
        reason = r;
        break;
      }
    }
    if (reason == null) {
      return const ServerTruthMalformed(
        'T10',
        'diagnostic_truth: unconfirmed_reason',
      );
    }
  }

  final rawCode = m['not_applied_code'];
  String? code;
  if (rawCode != null) {
    if (rawCode is! String || rawCode.trim().isEmpty) {
      return const ServerTruthMalformed(
        'T11',
        'diagnostic_truth: not_applied_code',
      );
    }
    code = rawCode;
  }

  // EXACTLY the companion the marker requires, and no other.
  switch (marker) {
    case PaymentAttemptLastOutcome.unconfirmed:
      if (reason == null || code != null) {
        return const ServerTruthMalformed(
          'T12',
          'diagnostic_truth: unconfirmed companions',
        );
      }
      return ServerTruthOk(DiagnosticTruth.unconfirmed(reason));
    case PaymentAttemptLastOutcome.notApplied:
      if (code == null || reason != null) {
        return const ServerTruthMalformed(
          'T13',
          'diagnostic_truth: not_applied companions',
        );
      }
      return ServerTruthOk(DiagnosticTruth.notApplied(code));
    case PaymentAttemptLastOutcome.authRequired:
      if (reason != null || code != null) {
        return const ServerTruthMalformed(
          'T14',
          'diagnostic_truth: auth_required companions',
        );
      }
      return ServerTruthOk(DiagnosticTruth.authRequired());
    case PaymentAttemptLastOutcome.collision:
      if (reason != null || code != null) {
        return const ServerTruthMalformed(
          'T15',
          'diagnostic_truth: collision companions',
        );
      }
      return ServerTruthOk(DiagnosticTruth.collision());
    case PaymentAttemptLastOutcome.none:
      return const ServerTruthMalformed('T9', 'diagnostic_truth: marker');
  }
}

// ---------------------------------------------------------------------------
// BlockOccurrence
// ---------------------------------------------------------------------------

/// Identifies ONE replacement episode on ONE record. Equality is over BOTH
/// parts, so a re-used block id under a new generation is a different
/// occurrence — which is what makes a stale clear impossible.
///
/// `FixedClientIdGenerator` repeats its last id forever (`ids.dart:39-50`), so
/// uniqueness never rests on the id source: the GENERATION carries it.
@immutable
final class BlockOccurrence {
  const BlockOccurrence(this.generation, this.blockId);
  final int generation;
  final String blockId;

  @override
  bool operator ==(Object other) =>
      other is BlockOccurrence &&
      generation == other.generation &&
      blockId == other.blockId;

  @override
  int get hashCode => Object.hash(generation, blockId);

  @override
  String toString() => 'BlockOccurrence($generation, $blockId)';
}

// ---------------------------------------------------------------------------
// BlockResolution
// ---------------------------------------------------------------------------

@immutable
final class BlockResolution {
  const BlockResolution({
    required this.kind,
    required this.resolvedAt,
    required this.resolutionOperationId,
    required this.resolutionTruth,
  });

  final BlockResolutionKind kind;
  final String resolvedAt;
  final String resolutionOperationId;
  final AcceptedTruth resolutionTruth;

  static const Set<String> keys = <String>{
    'kind',
    'resolved_at',
    'resolution_operation_id',
    'resolution_truth',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wire,
    'resolved_at': resolvedAt,
    'resolution_operation_id': resolutionOperationId,
    'resolution_truth': resolutionTruth.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is BlockResolution &&
      kind == other.kind &&
      resolvedAt == other.resolvedAt &&
      resolutionOperationId == other.resolutionOperationId &&
      resolutionTruth == other.resolutionTruth;

  @override
  int get hashCode =>
      Object.hash(kind, resolvedAt, resolutionOperationId, resolutionTruth);
}

@immutable
sealed class BlockResolutionDecode {
  const BlockResolutionDecode();
}

@immutable
final class BlockResolutionOk extends BlockResolutionDecode {
  const BlockResolutionOk(this.resolution);
  final BlockResolution resolution;
}

@immutable
final class BlockResolutionBad extends BlockResolutionDecode {
  const BlockResolutionBad(this.rule, this.message);
  final String rule;
  final String message;
}

BlockResolutionDecode decodeBlockResolution(Object? raw) {
  final m = strictStringObjectMap(raw);
  switch (m) {
    case StrictMapNotAMap(:final observedTypeName):
      return BlockResolutionBad(
        'Q0',
        'resolution: not an object ($observedTypeName)',
      );
    case StrictMapBadKey(:final observedTypeName):
      return BlockResolutionBad(
        'Q0',
        'resolution: non-String key ($observedTypeName)',
      );
    case StrictMapOk(:final map):
      final bad = exactKeys(map, BlockResolution.keys);
      if (bad != null) return BlockResolutionBad('Q1', 'resolution: $bad');
      final kind = BlockResolutionKind.fromWire(map['kind']);
      if (kind == null) {
        return const BlockResolutionBad('Q2', 'resolution: kind');
      }
      if (!isCanonicalInstant(map['resolved_at'])) {
        return const BlockResolutionBad('Q3', 'resolution: resolved_at');
      }
      final op = map['resolution_operation_id'];
      if (op is! String || op.trim().isEmpty) {
        return const BlockResolutionBad(
          'Q4',
          'resolution: resolution_operation_id',
        );
      }
      final truth = decodeServerTruth(map['resolution_truth']);
      if (truth is ServerTruthMalformed) {
        return BlockResolutionBad('Q5', 'resolution: ${truth.message}');
      }
      final t = (truth as ServerTruthOk).truth;
      if (t is! AcceptedTruth) {
        return const BlockResolutionBad(
          'Q6',
          'resolution: truth is not accepted-class',
        );
      }
      return BlockResolutionOk(
        BlockResolution(
          kind: kind,
          resolvedAt: map['resolved_at']! as String,
          resolutionOperationId: op,
          resolutionTruth: t,
        ),
      );
  }
}

// ---------------------------------------------------------------------------
// PaymentReplacementBlock
// ---------------------------------------------------------------------------

/// The facts about the PARENT record a block must agree with. Kept as a small
/// value so the decoder never has to reach for a live object.
@immutable
final class PaymentAttemptParentFacts {
  const PaymentAttemptParentFacts({
    required this.localOperationId,
    required this.phase,
    required this.resolution,
    required this.autoEffectsReservedAt,
    required this.refusal,
    required this.refusalMemoized,
  });

  factory PaymentAttemptParentFacts.of(PaymentAttempt a) =>
      PaymentAttemptParentFacts(
        localOperationId: a.localOperationId,
        phase: a.phase,
        resolution: a.resolution,
        autoEffectsReservedAt: a.autoEffectsReservedAt,
        refusal: a.refusal,
        refusalMemoized: a.refusalMemoized,
      );

  final String localOperationId;
  final PaymentAttemptPhase phase;
  final PaymentAttemptResolution? resolution;
  final String? autoEffectsReservedAt;
  final PaymentRefusalCode? refusal;
  final bool refusalMemoized;
}

@immutable
final class PaymentReplacementBlock {
  const PaymentReplacementBlock({
    required this.generation,
    required this.blockId,
    required this.status,
    required this.contradictedOperationId,
    required this.contradictedPhase,
    required this.reason,
    required this.evidenceSource,
    required this.observedAt,
    required this.serverTruth,
    required this.resolution,
  });

  final int generation;
  final String blockId;
  final BlockStatus status;
  final String contradictedOperationId;
  final PaymentAttemptPhase contradictedPhase;
  final IncidentReason reason;
  final BlockEvidenceSource evidenceSource;
  final String observedAt;
  final ServerTruth serverTruth;

  /// Present IFF [status] is [BlockStatus.resolved]. Both producers hold that
  /// invariant: the decoder chooses the key set BY the status, and
  /// [resolvedWith] sets status and resolution in one expression.
  final BlockResolution? resolution;

  BlockOccurrence get occurrence => BlockOccurrence(generation, blockId);

  static const Set<String> baseKeys = <String>{
    'generation',
    'block_id',
    'status',
    'contradicted_operation_id',
    'contradicted_phase',
    'reason',
    'evidence_source',
    'observed_at',
    'server_truth',
  };

  static const Set<String> resolvedKeys = <String>{...baseKeys, 'resolution'};

  static Set<String> keysFor(BlockStatus s) =>
      s == BlockStatus.active ? baseKeys : resolvedKeys;

  Map<String, Object?> toJson() {
    final out = <String, Object?>{
      'generation': generation,
      'block_id': blockId,
      'status': status.wire,
      'contradicted_operation_id': contradictedOperationId,
      'contradicted_phase': contradictedPhase.wire,
      'reason': reason.wire,
      'evidence_source': evidenceSource.wire,
      'observed_at': observedAt,
      'server_truth': serverTruth.toJson(),
    };
    if (status == BlockStatus.resolved) {
      final r = resolution;
      if (r == null) {
        // Unreachable through either producer; enforced rather than assumed.
        throw StateError('replacement_block: resolved without a resolution');
      }
      out['resolution'] = r.toJson();
    }
    return out;
  }

  /// Returns a NEW block. Nothing is mutated.
  PaymentReplacementBlock resolvedWith(BlockResolution r) =>
      PaymentReplacementBlock(
        generation: generation,
        blockId: blockId,
        status: BlockStatus.resolved,
        contradictedOperationId: contradictedOperationId,
        contradictedPhase: contradictedPhase,
        reason: reason,
        evidenceSource: evidenceSource,
        observedAt: observedAt,
        serverTruth: serverTruth,
        resolution: r,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentReplacementBlock &&
          generation == other.generation &&
          blockId == other.blockId &&
          status == other.status &&
          contradictedOperationId == other.contradictedOperationId &&
          contradictedPhase == other.contradictedPhase &&
          reason == other.reason &&
          evidenceSource == other.evidenceSource &&
          observedAt == other.observedAt &&
          serverTruth == other.serverTruth &&
          resolution == other.resolution;

  @override
  int get hashCode => Object.hash(
    generation,
    blockId,
    status,
    contradictedOperationId,
    contradictedPhase,
    reason,
    evidenceSource,
    observedAt,
    serverTruth,
    resolution,
  );
}

// ---------------------------------------------------------------------------
// Parent-level presence, then the block decoder
// ---------------------------------------------------------------------------

@immutable
sealed class ReplacementBlockFieldDecode {
  const ReplacementBlockFieldDecode();
}

@immutable
final class BlockAbsent extends ReplacementBlockFieldDecode {
  const BlockAbsent();
}

@immutable
final class BlockDecoded extends ReplacementBlockFieldDecode {
  const BlockDecoded(this.block);
  final PaymentReplacementBlock block;
}

@immutable
final class BlockMalformed extends ReplacementBlockFieldDecode {
  const BlockMalformed(this.rule, this.message);
  final String rule;
  final String message;
}

/// TOTAL. [entryValue] is the WHOLE envelope entry, so ABSENT and PRESENT-NULL
/// are decided at the parent map — a distinction `fromJson(value)` cannot make.
ReplacementBlockFieldDecode decodeReplacementBlockField(
  Object? entryValue,
  PaymentAttemptParentFacts parent, {
  BlockOccurrence? incidentOccurrence,
  ServerTruth? incidentTruth,
  String? incidentOperationId,
}) {
  final m = strictStringObjectMap(entryValue);
  switch (m) {
    case StrictMapNotAMap(:final observedTypeName):
      return BlockMalformed('P0', 'entry: not an object ($observedTypeName)');
    case StrictMapBadKey(:final observedTypeName):
      return BlockMalformed('P0', 'entry: non-String key ($observedTypeName)');
    case StrictMapOk(:final map):
      if (!map.containsKey(kReplacementBlockKey)) return const BlockAbsent();
      final v = map[kReplacementBlockKey];
      if (v == null) {
        return const BlockMalformed('P1', 'replacement_block: present null');
      }
      return decodeReplacementBlock(
        v,
        parent,
        incidentOccurrence: incidentOccurrence,
        incidentTruth: incidentTruth,
        incidentOperationId: incidentOperationId,
      );
  }
}

/// TOTAL. Validates shape, then ACTIVE/RESOLVED cross-field rules, then
/// incident agreement when an incident was supplied.
ReplacementBlockFieldDecode decodeReplacementBlock(
  Object? raw,
  PaymentAttemptParentFacts parent, {
  BlockOccurrence? incidentOccurrence,
  ServerTruth? incidentTruth,
  String? incidentOperationId,
}) {
  final sm = strictStringObjectMap(raw);
  switch (sm) {
    case StrictMapNotAMap(:final observedTypeName):
      return BlockMalformed(
        'S0',
        'replacement_block: not an object ($observedTypeName)',
      );
    case StrictMapBadKey(:final observedTypeName):
      return BlockMalformed(
        'S0',
        'replacement_block: non-String key ($observedTypeName)',
      );
    case StrictMapOk(:final map):
      // ---- S1 status first: it selects the EXACT key set -------------------
      final status = BlockStatus.fromWire(map['status']);
      if (status == null) return const BlockMalformed('S1', 'status');

      // ---- S2 exact keys, BOTH directions ----------------------------------
      final bad = exactKeys(map, PaymentReplacementBlock.keysFor(status));
      if (bad != null) return BlockMalformed('S2', bad);

      // ---- S3 types and grammars -------------------------------------------
      final gen = map['generation'];
      if (gen is! int || gen < 1) {
        return const BlockMalformed('S3a', 'generation');
      }
      final blockId = map['block_id'];
      if (blockId is! String || blockId.trim().isEmpty) {
        return const BlockMalformed('S3b', 'block_id');
      }
      final op = map['contradicted_operation_id'];
      if (op is! String || op.trim().isEmpty) {
        return const BlockMalformed('S3c', 'contradicted_operation_id');
      }
      final cPhase = PaymentAttemptPhase.fromWire(map['contradicted_phase']);
      if (cPhase == null) {
        return const BlockMalformed('S3d', 'contradicted_phase');
      }
      final reason = IncidentReason.fromWire(map['reason']);
      if (reason == null) return const BlockMalformed('S3e', 'reason');
      final src = BlockEvidenceSource.fromWire(map['evidence_source']);
      if (src == null) return const BlockMalformed('S3f', 'evidence_source');
      if (!isCanonicalInstant(map['observed_at'])) {
        return const BlockMalformed('S3g', 'observed_at');
      }
      final td = decodeServerTruth(map['server_truth']);
      if (td is ServerTruthMalformed) {
        return BlockMalformed('S3h', 'server_truth: ${td.message}');
      }
      final truth = (td as ServerTruthOk).truth;

      // ---- S4 the truth's own provenance must match the block's ------------
      if (truth is AcceptedTruth && truth.evidenceSource != src) {
        return const BlockMalformed(
          'S4a',
          'evidence_source != truth provenance',
        );
      }

      // ---- S5 ACTIVE cross-field -------------------------------------------
      BlockResolution? res;
      if (status == BlockStatus.active) {
        if (truth is! AcceptedTruth) {
          return const BlockMalformed(
            'S5a',
            'active block truth is not accepted-class',
          );
        }
        if (op != parent.localOperationId) {
          return const BlockMalformed(
            'S5b',
            'contradicted op != parent operation',
          );
        }
        if (cPhase != parent.phase) {
          return const BlockMalformed(
            'S5c',
            'contradicted phase != parent phase',
          );
        }
        if (cPhase != PaymentAttemptPhase.refused &&
            cPhase != PaymentAttemptPhase.settledElsewhere) {
          return const BlockMalformed(
            'S5d',
            'parent phase is not replacement-risky',
          );
        }
        if (parent.refusal == null) {
          return const BlockMalformed(
            'S5e',
            'contradicted parent without a refusal',
          );
        }
        if (parent.resolution != null) {
          return const BlockMalformed(
            'S5f',
            'contradicted parent carries a resolution',
          );
        }
        if (parent.autoEffectsReservedAt != null) {
          return const BlockMalformed(
            'S5g',
            'contradicted parent carries an effect claim',
          );
        }
        if (reason != IncidentReason.ownerBContradiction) {
          return const BlockMalformed(
            'S5h',
            'reason inconsistent with an active block',
          );
        }
      }

      // ---- S6 RESOLVED cross-field -----------------------------------------
      if (status == BlockStatus.resolved) {
        final rd = decodeBlockResolution(map['resolution']);
        if (rd is BlockResolutionBad) {
          return BlockMalformed('S6a', '${rd.rule}: ${rd.message}');
        }
        res = (rd as BlockResolutionOk).resolution;
        if (truth is! AcceptedTruth) {
          return const BlockMalformed(
            'S6b',
            'resolved block truth is not accepted-class',
          );
        }
        if (op != parent.localOperationId) {
          return const BlockMalformed(
            'S6c',
            'contradicted op != parent operation',
          );
        }
        // THE COUNTEREXAMPLE-I RULE.
        if (parent.phase != PaymentAttemptPhase.accepted) {
          return const BlockMalformed(
            'S6d',
            'resolved block on a non-accepted parent',
          );
        }
        if (cPhase != PaymentAttemptPhase.refused &&
            cPhase != PaymentAttemptPhase.settledElsewhere) {
          return const BlockMalformed(
            'S6e',
            'retained phase is not replacement-risky',
          );
        }
        if (res.resolutionOperationId != op) {
          return const BlockMalformed(
            'S6f',
            'resolution op != contradicted op',
          );
        }
        if (parent.resolution == null) {
          return const BlockMalformed(
            'S6g',
            'accepted parent without a resolution',
          );
        }
        if (parent.autoEffectsReservedAt == null) {
          return const BlockMalformed(
            'S6h',
            'accepted parent without an effect claim',
          );
        }
        if (parent.refusal != null) {
          return const BlockMalformed(
            'S6i',
            'accepted parent still carries a refusal',
          );
        }
        if (parent.refusalMemoized) {
          return const BlockMalformed(
            'S6j',
            'accepted parent still carries refusal_memoized',
          );
        }
        if (!sameMoneyTruth(
          res.resolutionTruth.resolution,
          parent.resolution!,
        )) {
          return const BlockMalformed(
            'S6k',
            'resolution truth != parent money truth',
          );
        }
        if (reason != IncidentReason.ownerBContradiction) {
          return const BlockMalformed('S6l', 'reason inconsistent');
        }
      }

      // ---- S7 incident agreement, only when an incident was supplied -------
      if (incidentOccurrence != null &&
          incidentOccurrence != BlockOccurrence(gen, blockId)) {
        return const BlockMalformed('S7a', 'occurrence != incident occurrence');
      }
      if (incidentTruth != null && incidentTruth != truth) {
        return const BlockMalformed('S7b', 'truth != incident truth');
      }
      if (incidentOperationId != null && incidentOperationId != op) {
        return const BlockMalformed('S7d', 'operation != incident operation');
      }

      return BlockDecoded(
        PaymentReplacementBlock(
          generation: gen,
          blockId: blockId,
          status: status,
          contradictedOperationId: op,
          contradictedPhase: cPhase,
          reason: reason,
          evidenceSource: src,
          observedAt: map['observed_at']! as String,
          serverTruth: truth,
          resolution: res,
        ),
      );
  }
}

/// The provenance-carrying constructors. These are the ONLY two ways a wire
/// acceptance becomes an [AcceptedTruth], so provenance can never disagree with
/// the truth it travels on.
AcceptedTruth acceptedTruthFromSend(PaymentAttemptResolution r) =>
    AcceptedTruth(
      resolution: r,
      evidenceSource: BlockEvidenceSource.directSend,
    );

AcceptedTruth acceptedTruthFromLookup(PaymentAttemptResolution r) =>
    AcceptedTruth(
      resolution: r,
      evidenceSource: BlockEvidenceSource.passiveStatusLookup,
    );

/// Whether [method] matches the frozen tender of the record the truth would be
/// written onto. `PaymentAttemptResolution.fromJson` applies this check only
/// when a `tenderType` is supplied (`payment_attempt.dart:250-252`), and the
/// codec above has no attempt in hand.
bool truthTenderMatches(AcceptedTruth t, String frozenTenderType) =>
    _wireOf(t.resolution.method) == frozenTenderType;

String _wireOf(PaymentMethod m) => m.wire;
