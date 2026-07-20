// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $OutboxOperationsTable extends OutboxOperations
    with TableInfo<$OutboxOperationsTable, OutboxOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetEntityMeta = const VerificationMeta(
    'targetEntity',
  );
  @override
  late final GeneratedColumn<String> targetEntity = GeneratedColumn<String>(
    'target_entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dependsOnMeta = const VerificationMeta(
    'dependsOn',
  );
  @override
  late final GeneratedColumn<String> dependsOn = GeneratedColumn<String>(
    'depends_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SyncOperationState, String>
  syncState =
      GeneratedColumn<String>(
        'sync_state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('created'),
      ).withConverter<SyncOperationState>(
        $OutboxOperationsTable.$convertersyncState,
      );
  static const VerificationMeta _clientCreatedAtMeta = const VerificationMeta(
    'clientCreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientCreatedAt =
      GeneratedColumn<DateTime>(
        'client_created_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorClassMeta = const VerificationMeta(
    'lastErrorClass',
  );
  @override
  late final GeneratedColumn<String> lastErrorClass = GeneratedColumn<String>(
    'last_error_class',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    localOperationId,
    organizationId,
    restaurantId,
    branchId,
    stationId,
    operationType,
    targetEntity,
    targetId,
    payload,
    dependsOn,
    baseRevision,
    syncState,
    clientCreatedAt,
    clientUpdatedAt,
    attemptCount,
    nextAttemptAt,
    lastErrorCode,
    lastErrorClass,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('target_entity')) {
      context.handle(
        _targetEntityMeta,
        targetEntity.isAcceptableOrUnknown(
          data['target_entity']!,
          _targetEntityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetEntityMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('depends_on')) {
      context.handle(
        _dependsOnMeta,
        dependsOn.isAcceptableOrUnknown(data['depends_on']!, _dependsOnMeta),
      );
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionMeta);
    }
    if (data.containsKey('client_created_at')) {
      context.handle(
        _clientCreatedAtMeta,
        clientCreatedAt.isAcceptableOrUnknown(
          data['client_created_at']!,
          _clientCreatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientCreatedAtMeta);
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_class')) {
      context.handle(
        _lastErrorClassMeta,
        lastErrorClass.isAcceptableOrUnknown(
          data['last_error_class']!,
          _lastErrorClassMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
  @override
  OutboxOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      ),
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      targetEntity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_entity'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      dependsOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}depends_on'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      syncState: $OutboxOperationsTable.$convertersyncState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_state'],
        )!,
      ),
      clientCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_created_at'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_class'],
      ),
    );
  }

  @override
  $OutboxOperationsTable createAlias(String alias) {
    return $OutboxOperationsTable(attachedDatabase, alias);
  }

  static TypeConverter<SyncOperationState, String> $convertersyncState =
      const SyncOperationStateConverter();
}

class OutboxOperation extends DataClass implements Insertable<OutboxOperation> {
  /// Client-generated UUID primary key for this outbox entry.
  final String id;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Monotonic-per-device local operation id (DECISION D-022).
  final String localOperationId;

  /// Tenant scope carried with the operation (DECISION D-001).
  final String organizationId;

  /// Operational scope (present where relevant).
  final String? restaurantId;
  final String? branchId;
  final String? stationId;

  /// e.g. `order.create`, `payment.create`. Maps to a server RPC (RF-056).
  final String operationType;

  /// The entity and its client UUID this operation targets.
  final String targetEntity;
  final String targetId;

  /// Operation arguments as JSON text. Any money inside is integer minor units
  /// only (`*_minor`) — never floating point (DECISION D-007). RF-018 stores it
  /// opaquely; concrete business payload schemas are RF-030+.
  final String payload;

  /// JSON array of `localOperationId`s that must be applied first; `[]` = none
  /// (OFFLINE_SYNC_SPEC section 5).
  final String dependsOn;

  /// The entity revision this change was computed against (optimistic
  /// concurrency; OFFLINE_SYNC_SPEC section 9).
  final int baseRevision;

  /// Sync-operation lifecycle state (DECISION D-018); stored as wire text.
  final SyncOperationState syncState;

  /// Device-clock timestamps.
  final DateTime clientCreatedAt;
  final DateTime clientUpdatedAt;

  /// Number of delivery attempts; policy/limits are RF-056 (not frozen here).
  final int attemptCount;

  /// When the next attempt is due; engine-populated (RF-056).
  final DateTime? nextAttemptAt;

  /// Last error diagnostics (transient vs permanent classification is RF-056).
  final String? lastErrorCode;
  final String? lastErrorClass;
  const OutboxOperation({
    required this.id,
    required this.deviceId,
    required this.localOperationId,
    required this.organizationId,
    this.restaurantId,
    this.branchId,
    this.stationId,
    required this.operationType,
    required this.targetEntity,
    required this.targetId,
    required this.payload,
    required this.dependsOn,
    required this.baseRevision,
    required this.syncState,
    required this.clientCreatedAt,
    required this.clientUpdatedAt,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorClass,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['organization_id'] = Variable<String>(organizationId);
    if (!nullToAbsent || restaurantId != null) {
      map['restaurant_id'] = Variable<String>(restaurantId);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<String>(stationId);
    }
    map['operation_type'] = Variable<String>(operationType);
    map['target_entity'] = Variable<String>(targetEntity);
    map['target_id'] = Variable<String>(targetId);
    map['payload'] = Variable<String>(payload);
    map['depends_on'] = Variable<String>(dependsOn);
    map['base_revision'] = Variable<int>(baseRevision);
    {
      map['sync_state'] = Variable<String>(
        $OutboxOperationsTable.$convertersyncState.toSql(syncState),
      );
    }
    map['client_created_at'] = Variable<DateTime>(clientCreatedAt);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorClass != null) {
      map['last_error_class'] = Variable<String>(lastErrorClass);
    }
    return map;
  }

  OutboxOperationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxOperationsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      organizationId: Value(organizationId),
      restaurantId: restaurantId == null && nullToAbsent
          ? const Value.absent()
          : Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      operationType: Value(operationType),
      targetEntity: Value(targetEntity),
      targetId: Value(targetId),
      payload: Value(payload),
      dependsOn: Value(dependsOn),
      baseRevision: Value(baseRevision),
      syncState: Value(syncState),
      clientCreatedAt: Value(clientCreatedAt),
      clientUpdatedAt: Value(clientUpdatedAt),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorClass: lastErrorClass == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorClass),
    );
  }

  factory OutboxOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOperation(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      restaurantId: serializer.fromJson<String?>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      stationId: serializer.fromJson<String?>(json['stationId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      targetEntity: serializer.fromJson<String>(json['targetEntity']),
      targetId: serializer.fromJson<String>(json['targetId']),
      payload: serializer.fromJson<String>(json['payload']),
      dependsOn: serializer.fromJson<String>(json['dependsOn']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      syncState: serializer.fromJson<SyncOperationState>(json['syncState']),
      clientCreatedAt: serializer.fromJson<DateTime>(json['clientCreatedAt']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorClass: serializer.fromJson<String?>(json['lastErrorClass']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'organizationId': serializer.toJson<String>(organizationId),
      'restaurantId': serializer.toJson<String?>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'stationId': serializer.toJson<String?>(stationId),
      'operationType': serializer.toJson<String>(operationType),
      'targetEntity': serializer.toJson<String>(targetEntity),
      'targetId': serializer.toJson<String>(targetId),
      'payload': serializer.toJson<String>(payload),
      'dependsOn': serializer.toJson<String>(dependsOn),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'syncState': serializer.toJson<SyncOperationState>(syncState),
      'clientCreatedAt': serializer.toJson<DateTime>(clientCreatedAt),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorClass': serializer.toJson<String?>(lastErrorClass),
    };
  }

  OutboxOperation copyWith({
    String? id,
    String? deviceId,
    String? localOperationId,
    String? organizationId,
    Value<String?> restaurantId = const Value.absent(),
    Value<String?> branchId = const Value.absent(),
    Value<String?> stationId = const Value.absent(),
    String? operationType,
    String? targetEntity,
    String? targetId,
    String? payload,
    String? dependsOn,
    int? baseRevision,
    SyncOperationState? syncState,
    DateTime? clientCreatedAt,
    DateTime? clientUpdatedAt,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorClass = const Value.absent(),
  }) => OutboxOperation(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    organizationId: organizationId ?? this.organizationId,
    restaurantId: restaurantId.present ? restaurantId.value : this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    stationId: stationId.present ? stationId.value : this.stationId,
    operationType: operationType ?? this.operationType,
    targetEntity: targetEntity ?? this.targetEntity,
    targetId: targetId ?? this.targetId,
    payload: payload ?? this.payload,
    dependsOn: dependsOn ?? this.dependsOn,
    baseRevision: baseRevision ?? this.baseRevision,
    syncState: syncState ?? this.syncState,
    clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorClass: lastErrorClass.present
        ? lastErrorClass.value
        : this.lastErrorClass,
  );
  OutboxOperation copyWithCompanion(OutboxOperationsCompanion data) {
    return OutboxOperation(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      targetEntity: data.targetEntity.present
          ? data.targetEntity.value
          : this.targetEntity,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      payload: data.payload.present ? data.payload.value : this.payload,
      dependsOn: data.dependsOn.present ? data.dependsOn.value : this.dependsOn,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      clientCreatedAt: data.clientCreatedAt.present
          ? data.clientCreatedAt.value
          : this.clientCreatedAt,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorClass: data.lastErrorClass.present
          ? data.lastErrorClass.value
          : this.lastErrorClass,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperation(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('organizationId: $organizationId, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('stationId: $stationId, ')
          ..write('operationType: $operationType, ')
          ..write('targetEntity: $targetEntity, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('syncState: $syncState, ')
          ..write('clientCreatedAt: $clientCreatedAt, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorClass: $lastErrorClass')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    localOperationId,
    organizationId,
    restaurantId,
    branchId,
    stationId,
    operationType,
    targetEntity,
    targetId,
    payload,
    dependsOn,
    baseRevision,
    syncState,
    clientCreatedAt,
    clientUpdatedAt,
    attemptCount,
    nextAttemptAt,
    lastErrorCode,
    lastErrorClass,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOperation &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.organizationId == this.organizationId &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.stationId == this.stationId &&
          other.operationType == this.operationType &&
          other.targetEntity == this.targetEntity &&
          other.targetId == this.targetId &&
          other.payload == this.payload &&
          other.dependsOn == this.dependsOn &&
          other.baseRevision == this.baseRevision &&
          other.syncState == this.syncState &&
          other.clientCreatedAt == this.clientCreatedAt &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorClass == this.lastErrorClass);
}

class OutboxOperationsCompanion extends UpdateCompanion<OutboxOperation> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<String> organizationId;
  final Value<String?> restaurantId;
  final Value<String?> branchId;
  final Value<String?> stationId;
  final Value<String> operationType;
  final Value<String> targetEntity;
  final Value<String> targetId;
  final Value<String> payload;
  final Value<String> dependsOn;
  final Value<int> baseRevision;
  final Value<SyncOperationState> syncState;
  final Value<DateTime> clientCreatedAt;
  final Value<DateTime> clientUpdatedAt;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorClass;
  final Value<int> rowid;
  const OutboxOperationsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.targetEntity = const Value.absent(),
    this.targetId = const Value.absent(),
    this.payload = const Value.absent(),
    this.dependsOn = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.syncState = const Value.absent(),
    this.clientCreatedAt = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorClass = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxOperationsCompanion.insert({
    required String id,
    required String deviceId,
    required String localOperationId,
    required String organizationId,
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.stationId = const Value.absent(),
    required String operationType,
    required String targetEntity,
    required String targetId,
    required String payload,
    this.dependsOn = const Value.absent(),
    required int baseRevision,
    this.syncState = const Value.absent(),
    required DateTime clientCreatedAt,
    required DateTime clientUpdatedAt,
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorClass = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       organizationId = Value(organizationId),
       operationType = Value(operationType),
       targetEntity = Value(targetEntity),
       targetId = Value(targetId),
       payload = Value(payload),
       baseRevision = Value(baseRevision),
       clientCreatedAt = Value(clientCreatedAt),
       clientUpdatedAt = Value(clientUpdatedAt);
  static Insertable<OutboxOperation> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<String>? organizationId,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? stationId,
    Expression<String>? operationType,
    Expression<String>? targetEntity,
    Expression<String>? targetId,
    Expression<String>? payload,
    Expression<String>? dependsOn,
    Expression<int>? baseRevision,
    Expression<String>? syncState,
    Expression<DateTime>? clientCreatedAt,
    Expression<DateTime>? clientUpdatedAt,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorClass,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (organizationId != null) 'organization_id': organizationId,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (stationId != null) 'station_id': stationId,
      if (operationType != null) 'operation_type': operationType,
      if (targetEntity != null) 'target_entity': targetEntity,
      if (targetId != null) 'target_id': targetId,
      if (payload != null) 'payload': payload,
      if (dependsOn != null) 'depends_on': dependsOn,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (syncState != null) 'sync_state': syncState,
      if (clientCreatedAt != null) 'client_created_at': clientCreatedAt,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorClass != null) 'last_error_class': lastErrorClass,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxOperationsCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<String>? organizationId,
    Value<String?>? restaurantId,
    Value<String?>? branchId,
    Value<String?>? stationId,
    Value<String>? operationType,
    Value<String>? targetEntity,
    Value<String>? targetId,
    Value<String>? payload,
    Value<String>? dependsOn,
    Value<int>? baseRevision,
    Value<SyncOperationState>? syncState,
    Value<DateTime>? clientCreatedAt,
    Value<DateTime>? clientUpdatedAt,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorClass,
    Value<int>? rowid,
  }) {
    return OutboxOperationsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      organizationId: organizationId ?? this.organizationId,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      stationId: stationId ?? this.stationId,
      operationType: operationType ?? this.operationType,
      targetEntity: targetEntity ?? this.targetEntity,
      targetId: targetId ?? this.targetId,
      payload: payload ?? this.payload,
      dependsOn: dependsOn ?? this.dependsOn,
      baseRevision: baseRevision ?? this.baseRevision,
      syncState: syncState ?? this.syncState,
      clientCreatedAt: clientCreatedAt ?? this.clientCreatedAt,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorClass: lastErrorClass ?? this.lastErrorClass,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (targetEntity.present) {
      map['target_entity'] = Variable<String>(targetEntity.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (dependsOn.present) {
      map['depends_on'] = Variable<String>(dependsOn.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(
        $OutboxOperationsTable.$convertersyncState.toSql(syncState.value),
      );
    }
    if (clientCreatedAt.present) {
      map['client_created_at'] = Variable<DateTime>(clientCreatedAt.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorClass.present) {
      map['last_error_class'] = Variable<String>(lastErrorClass.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperationsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('organizationId: $organizationId, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('stationId: $stationId, ')
          ..write('operationType: $operationType, ')
          ..write('targetEntity: $targetEntity, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('dependsOn: $dependsOn, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('syncState: $syncState, ')
          ..write('clientCreatedAt: $clientCreatedAt, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorClass: $lastErrorClass, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProcessedPullLogTable extends ProcessedPullLog
    with TableInfo<$ProcessedPullLogTable, ProcessedPullLogData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessedPullLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appliedAtMeta = const VerificationMeta(
    'appliedAt',
  );
  @override
  late final GeneratedColumn<DateTime> appliedAt = GeneratedColumn<DateTime>(
    'applied_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    localOperationId,
    appliedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processed_pull_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProcessedPullLogData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('applied_at')) {
      context.handle(
        _appliedAtMeta,
        appliedAt.isAcceptableOrUnknown(data['applied_at']!, _appliedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_appliedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
  @override
  ProcessedPullLogData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessedPullLogData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      appliedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}applied_at'],
      )!,
    );
  }

  @override
  $ProcessedPullLogTable createAlias(String alias) {
    return $ProcessedPullLogTable(attachedDatabase, alias);
  }
}

class ProcessedPullLogData extends DataClass
    implements Insertable<ProcessedPullLogData> {
  /// Client-generated UUID primary key for this ledger entry.
  final String id;

  /// Originating device of the applied operation (DECISION D-022).
  final String deviceId;

  /// Local operation id of the applied operation (DECISION D-022).
  final String localOperationId;

  /// When the operation was applied locally.
  final DateTime appliedAt;
  const ProcessedPullLogData({
    required this.id,
    required this.deviceId,
    required this.localOperationId,
    required this.appliedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['applied_at'] = Variable<DateTime>(appliedAt);
    return map;
  }

  ProcessedPullLogCompanion toCompanion(bool nullToAbsent) {
    return ProcessedPullLogCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      appliedAt: Value(appliedAt),
    );
  }

  factory ProcessedPullLogData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessedPullLogData(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      appliedAt: serializer.fromJson<DateTime>(json['appliedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'appliedAt': serializer.toJson<DateTime>(appliedAt),
    };
  }

  ProcessedPullLogData copyWith({
    String? id,
    String? deviceId,
    String? localOperationId,
    DateTime? appliedAt,
  }) => ProcessedPullLogData(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    appliedAt: appliedAt ?? this.appliedAt,
  );
  ProcessedPullLogData copyWithCompanion(ProcessedPullLogCompanion data) {
    return ProcessedPullLogData(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      appliedAt: data.appliedAt.present ? data.appliedAt.value : this.appliedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedPullLogData(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('appliedAt: $appliedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deviceId, localOperationId, appliedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessedPullLogData &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.appliedAt == this.appliedAt);
}

class ProcessedPullLogCompanion extends UpdateCompanion<ProcessedPullLogData> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<DateTime> appliedAt;
  final Value<int> rowid;
  const ProcessedPullLogCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.appliedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessedPullLogCompanion.insert({
    required String id,
    required String deviceId,
    required String localOperationId,
    required DateTime appliedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       appliedAt = Value(appliedAt);
  static Insertable<ProcessedPullLogData> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<DateTime>? appliedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (appliedAt != null) 'applied_at': appliedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessedPullLogCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<DateTime>? appliedAt,
    Value<int>? rowid,
  }) {
    return ProcessedPullLogCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      appliedAt: appliedAt ?? this.appliedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (appliedAt.present) {
      map['applied_at'] = Variable<DateTime>(appliedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedPullLogCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('appliedAt: $appliedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MenuCategoriesTable extends MenuCategories
    with TableInfo<$MenuCategoriesTable, MenuCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MenuCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    name,
    displayOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'menu_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<MenuCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MenuCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MenuCategory(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $MenuCategoriesTable createAlias(String alias) {
    return $MenuCategoriesTable(attachedDatabase, alias);
  }
}

class MenuCategory extends DataClass implements Insertable<MenuCategory> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;

  /// Operational tenant scope (DECISION D-001/D-002); organization_id is on the
  /// mixin. `branch_id` is nullable for branch-specific overrides.
  final String restaurantId;
  final String? branchId;
  final String name;
  final int displayOrder;
  final bool isActive;
  const MenuCategory({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.name,
    required this.displayOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['name'] = Variable<String>(name);
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  MenuCategoriesCompanion toCompanion(bool nullToAbsent) {
    return MenuCategoriesCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      name: Value(name),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
    );
  }

  factory MenuCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MenuCategory(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      name: serializer.fromJson<String>(json['name']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'name': serializer.toJson<String>(name),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  MenuCategory copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? name,
    int? displayOrder,
    bool? isActive,
  }) => MenuCategory(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    name: name ?? this.name,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
  );
  MenuCategory copyWithCompanion(MenuCategoriesCompanion data) {
    return MenuCategory(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      name: data.name.present ? data.name.value : this.name,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MenuCategory(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    name,
    displayOrder,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MenuCategory &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.name == this.name &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive);
}

class MenuCategoriesCompanion extends UpdateCompanion<MenuCategory> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> name;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const MenuCategoriesCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.name = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MenuCategoriesCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String name,
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       name = Value(name);
  static Insertable<MenuCategory> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? name,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (name != null) 'name': name,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MenuCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? name,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return MenuCategoriesCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MenuCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MenuItemsTable extends MenuItems
    with TableInfo<$MenuItemsTable, MenuItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MenuItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _menuCategoryIdMeta = const VerificationMeta(
    'menuCategoryId',
  );
  @override
  late final GeneratedColumn<String> menuCategoryId = GeneratedColumn<String>(
    'menu_category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES menu_categories (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _basePriceMinorMeta = const VerificationMeta(
    'basePriceMinor',
  );
  @override
  late final GeneratedColumn<int> basePriceMinor = GeneratedColumn<int>(
    'base_price_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuCategoryId,
    name,
    description,
    basePriceMinor,
    currencyCode,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'menu_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MenuItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('menu_category_id')) {
      context.handle(
        _menuCategoryIdMeta,
        menuCategoryId.isAcceptableOrUnknown(
          data['menu_category_id']!,
          _menuCategoryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_menuCategoryIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('base_price_minor')) {
      context.handle(
        _basePriceMinorMeta,
        basePriceMinor.isAcceptableOrUnknown(
          data['base_price_minor']!,
          _basePriceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_basePriceMinorMeta);
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyCodeMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MenuItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MenuItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      menuCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}menu_category_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      basePriceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_price_minor'],
      )!,
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $MenuItemsTable createAlias(String alias) {
    return $MenuItemsTable(attachedDatabase, alias);
  }
}

class MenuItem extends DataClass implements Insertable<MenuItem> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;
  final String restaurantId;
  final String? branchId;

  /// Owning category (DECISION D-017 FK).
  final String menuCategoryId;
  final String name;
  final String? description;

  /// Base price in integer MINOR units (DECISION D-007). No floating point.
  final int basePriceMinor;

  /// ISO 4217 currency code (e.g. ILS / USD). Child price deltas inherit it.
  final String currencyCode;
  final bool isActive;
  const MenuItem({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.menuCategoryId,
    required this.name,
    this.description,
    required this.basePriceMinor,
    required this.currencyCode,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['menu_category_id'] = Variable<String>(menuCategoryId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['base_price_minor'] = Variable<int>(basePriceMinor);
    map['currency_code'] = Variable<String>(currencyCode);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  MenuItemsCompanion toCompanion(bool nullToAbsent) {
    return MenuItemsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      menuCategoryId: Value(menuCategoryId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      basePriceMinor: Value(basePriceMinor),
      currencyCode: Value(currencyCode),
      isActive: Value(isActive),
    );
  }

  factory MenuItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MenuItem(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      menuCategoryId: serializer.fromJson<String>(json['menuCategoryId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      basePriceMinor: serializer.fromJson<int>(json['basePriceMinor']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'menuCategoryId': serializer.toJson<String>(menuCategoryId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'basePriceMinor': serializer.toJson<int>(basePriceMinor),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  MenuItem copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? menuCategoryId,
    String? name,
    Value<String?> description = const Value.absent(),
    int? basePriceMinor,
    String? currencyCode,
    bool? isActive,
  }) => MenuItem(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    menuCategoryId: menuCategoryId ?? this.menuCategoryId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    basePriceMinor: basePriceMinor ?? this.basePriceMinor,
    currencyCode: currencyCode ?? this.currencyCode,
    isActive: isActive ?? this.isActive,
  );
  MenuItem copyWithCompanion(MenuItemsCompanion data) {
    return MenuItem(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      menuCategoryId: data.menuCategoryId.present
          ? data.menuCategoryId.value
          : this.menuCategoryId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      basePriceMinor: data.basePriceMinor.present
          ? data.basePriceMinor.value
          : this.basePriceMinor,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MenuItem(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuCategoryId: $menuCategoryId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('basePriceMinor: $basePriceMinor, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuCategoryId,
    name,
    description,
    basePriceMinor,
    currencyCode,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MenuItem &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.menuCategoryId == this.menuCategoryId &&
          other.name == this.name &&
          other.description == this.description &&
          other.basePriceMinor == this.basePriceMinor &&
          other.currencyCode == this.currencyCode &&
          other.isActive == this.isActive);
}

class MenuItemsCompanion extends UpdateCompanion<MenuItem> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> menuCategoryId;
  final Value<String> name;
  final Value<String?> description;
  final Value<int> basePriceMinor;
  final Value<String> currencyCode;
  final Value<bool> isActive;
  final Value<int> rowid;
  const MenuItemsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.menuCategoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.basePriceMinor = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MenuItemsCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String menuCategoryId,
    required String name,
    this.description = const Value.absent(),
    required int basePriceMinor,
    required String currencyCode,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       menuCategoryId = Value(menuCategoryId),
       name = Value(name),
       basePriceMinor = Value(basePriceMinor),
       currencyCode = Value(currencyCode);
  static Insertable<MenuItem> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? menuCategoryId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? basePriceMinor,
    Expression<String>? currencyCode,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (menuCategoryId != null) 'menu_category_id': menuCategoryId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (basePriceMinor != null) 'base_price_minor': basePriceMinor,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MenuItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? menuCategoryId,
    Value<String>? name,
    Value<String?>? description,
    Value<int>? basePriceMinor,
    Value<String>? currencyCode,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return MenuItemsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      menuCategoryId: menuCategoryId ?? this.menuCategoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      basePriceMinor: basePriceMinor ?? this.basePriceMinor,
      currencyCode: currencyCode ?? this.currencyCode,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (menuCategoryId.present) {
      map['menu_category_id'] = Variable<String>(menuCategoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (basePriceMinor.present) {
      map['base_price_minor'] = Variable<int>(basePriceMinor.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MenuItemsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuCategoryId: $menuCategoryId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('basePriceMinor: $basePriceMinor, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemSizesTable extends ItemSizes
    with TableInfo<$ItemSizesTable, ItemSize> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemSizesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _menuItemIdMeta = const VerificationMeta(
    'menuItemId',
  );
  @override
  late final GeneratedColumn<String> menuItemId = GeneratedColumn<String>(
    'menu_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES menu_items (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceDeltaMinorMeta = const VerificationMeta(
    'priceDeltaMinor',
  );
  @override
  late final GeneratedColumn<int> priceDeltaMinor = GeneratedColumn<int>(
    'price_delta_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_sizes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemSize> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('menu_item_id')) {
      context.handle(
        _menuItemIdMeta,
        menuItemId.isAcceptableOrUnknown(
          data['menu_item_id']!,
          _menuItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_menuItemIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_delta_minor')) {
      context.handle(
        _priceDeltaMinorMeta,
        priceDeltaMinor.isAcceptableOrUnknown(
          data['price_delta_minor']!,
          _priceDeltaMinorMeta,
        ),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ItemSize map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemSize(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      menuItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}menu_item_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceDeltaMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_delta_minor'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ItemSizesTable createAlias(String alias) {
    return $ItemSizesTable(attachedDatabase, alias);
  }
}

class ItemSize extends DataClass implements Insertable<ItemSize> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;
  final String restaurantId;
  final String? branchId;
  final String menuItemId;
  final String name;

  /// Price delta vs the item base price, integer MINOR units (DECISION D-007).
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;
  const ItemSize({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.menuItemId,
    required this.name,
    required this.priceDeltaMinor,
    required this.displayOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['menu_item_id'] = Variable<String>(menuItemId);
    map['name'] = Variable<String>(name);
    map['price_delta_minor'] = Variable<int>(priceDeltaMinor);
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ItemSizesCompanion toCompanion(bool nullToAbsent) {
    return ItemSizesCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      menuItemId: Value(menuItemId),
      name: Value(name),
      priceDeltaMinor: Value(priceDeltaMinor),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
    );
  }

  factory ItemSize.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemSize(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      menuItemId: serializer.fromJson<String>(json['menuItemId']),
      name: serializer.fromJson<String>(json['name']),
      priceDeltaMinor: serializer.fromJson<int>(json['priceDeltaMinor']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'menuItemId': serializer.toJson<String>(menuItemId),
      'name': serializer.toJson<String>(name),
      'priceDeltaMinor': serializer.toJson<int>(priceDeltaMinor),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  ItemSize copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? menuItemId,
    String? name,
    int? priceDeltaMinor,
    int? displayOrder,
    bool? isActive,
  }) => ItemSize(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    menuItemId: menuItemId ?? this.menuItemId,
    name: name ?? this.name,
    priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
  );
  ItemSize copyWithCompanion(ItemSizesCompanion data) {
    return ItemSize(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      menuItemId: data.menuItemId.present
          ? data.menuItemId.value
          : this.menuItemId,
      name: data.name.present ? data.name.value : this.name,
      priceDeltaMinor: data.priceDeltaMinor.present
          ? data.priceDeltaMinor.value
          : this.priceDeltaMinor,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemSize(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemSize &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.menuItemId == this.menuItemId &&
          other.name == this.name &&
          other.priceDeltaMinor == this.priceDeltaMinor &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive);
}

class ItemSizesCompanion extends UpdateCompanion<ItemSize> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> menuItemId;
  final Value<String> name;
  final Value<int> priceDeltaMinor;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ItemSizesCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.menuItemId = const Value.absent(),
    this.name = const Value.absent(),
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemSizesCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String menuItemId,
    required String name,
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       menuItemId = Value(menuItemId),
       name = Value(name);
  static Insertable<ItemSize> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? menuItemId,
    Expression<String>? name,
    Expression<int>? priceDeltaMinor,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (menuItemId != null) 'menu_item_id': menuItemId,
      if (name != null) 'name': name,
      if (priceDeltaMinor != null) 'price_delta_minor': priceDeltaMinor,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemSizesCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? menuItemId,
    Value<String>? name,
    Value<int>? priceDeltaMinor,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ItemSizesCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (menuItemId.present) {
      map['menu_item_id'] = Variable<String>(menuItemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceDeltaMinor.present) {
      map['price_delta_minor'] = Variable<int>(priceDeltaMinor.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemSizesCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemVariantsTable extends ItemVariants
    with TableInfo<$ItemVariantsTable, ItemVariant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemVariantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _menuItemIdMeta = const VerificationMeta(
    'menuItemId',
  );
  @override
  late final GeneratedColumn<String> menuItemId = GeneratedColumn<String>(
    'menu_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES menu_items (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceDeltaMinorMeta = const VerificationMeta(
    'priceDeltaMinor',
  );
  @override
  late final GeneratedColumn<int> priceDeltaMinor = GeneratedColumn<int>(
    'price_delta_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<ItemVariant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('menu_item_id')) {
      context.handle(
        _menuItemIdMeta,
        menuItemId.isAcceptableOrUnknown(
          data['menu_item_id']!,
          _menuItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_menuItemIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_delta_minor')) {
      context.handle(
        _priceDeltaMinorMeta,
        priceDeltaMinor.isAcceptableOrUnknown(
          data['price_delta_minor']!,
          _priceDeltaMinorMeta,
        ),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ItemVariant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemVariant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      menuItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}menu_item_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceDeltaMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_delta_minor'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ItemVariantsTable createAlias(String alias) {
    return $ItemVariantsTable(attachedDatabase, alias);
  }
}

class ItemVariant extends DataClass implements Insertable<ItemVariant> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;
  final String restaurantId;
  final String? branchId;
  final String menuItemId;
  final String name;

  /// Price delta vs the item base price, integer MINOR units (DECISION D-007).
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;
  const ItemVariant({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.menuItemId,
    required this.name,
    required this.priceDeltaMinor,
    required this.displayOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['menu_item_id'] = Variable<String>(menuItemId);
    map['name'] = Variable<String>(name);
    map['price_delta_minor'] = Variable<int>(priceDeltaMinor);
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ItemVariantsCompanion toCompanion(bool nullToAbsent) {
    return ItemVariantsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      menuItemId: Value(menuItemId),
      name: Value(name),
      priceDeltaMinor: Value(priceDeltaMinor),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
    );
  }

  factory ItemVariant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemVariant(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      menuItemId: serializer.fromJson<String>(json['menuItemId']),
      name: serializer.fromJson<String>(json['name']),
      priceDeltaMinor: serializer.fromJson<int>(json['priceDeltaMinor']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'menuItemId': serializer.toJson<String>(menuItemId),
      'name': serializer.toJson<String>(name),
      'priceDeltaMinor': serializer.toJson<int>(priceDeltaMinor),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  ItemVariant copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? menuItemId,
    String? name,
    int? priceDeltaMinor,
    int? displayOrder,
    bool? isActive,
  }) => ItemVariant(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    menuItemId: menuItemId ?? this.menuItemId,
    name: name ?? this.name,
    priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
  );
  ItemVariant copyWithCompanion(ItemVariantsCompanion data) {
    return ItemVariant(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      menuItemId: data.menuItemId.present
          ? data.menuItemId.value
          : this.menuItemId,
      name: data.name.present ? data.name.value : this.name,
      priceDeltaMinor: data.priceDeltaMinor.present
          ? data.priceDeltaMinor.value
          : this.priceDeltaMinor,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemVariant(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ItemVariant &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.menuItemId == this.menuItemId &&
          other.name == this.name &&
          other.priceDeltaMinor == this.priceDeltaMinor &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive);
}

class ItemVariantsCompanion extends UpdateCompanion<ItemVariant> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> menuItemId;
  final Value<String> name;
  final Value<int> priceDeltaMinor;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ItemVariantsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.menuItemId = const Value.absent(),
    this.name = const Value.absent(),
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemVariantsCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String menuItemId,
    required String name,
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       menuItemId = Value(menuItemId),
       name = Value(name);
  static Insertable<ItemVariant> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? menuItemId,
    Expression<String>? name,
    Expression<int>? priceDeltaMinor,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (menuItemId != null) 'menu_item_id': menuItemId,
      if (name != null) 'name': name,
      if (priceDeltaMinor != null) 'price_delta_minor': priceDeltaMinor,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemVariantsCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? menuItemId,
    Value<String>? name,
    Value<int>? priceDeltaMinor,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ItemVariantsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (menuItemId.present) {
      map['menu_item_id'] = Variable<String>(menuItemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceDeltaMinor.present) {
      map['price_delta_minor'] = Variable<int>(priceDeltaMinor.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemVariantsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModifiersTable extends Modifiers
    with TableInfo<$ModifiersTable, Modifier> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModifiersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _menuItemIdMeta = const VerificationMeta(
    'menuItemId',
  );
  @override
  late final GeneratedColumn<String> menuItemId = GeneratedColumn<String>(
    'menu_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES menu_items (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selectionTypeMeta = const VerificationMeta(
    'selectionType',
  );
  @override
  late final GeneratedColumn<String> selectionType = GeneratedColumn<String>(
    'selection_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minSelectMeta = const VerificationMeta(
    'minSelect',
  );
  @override
  late final GeneratedColumn<int> minSelect = GeneratedColumn<int>(
    'min_select',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxSelectMeta = const VerificationMeta(
    'maxSelect',
  );
  @override
  late final GeneratedColumn<int> maxSelect = GeneratedColumn<int>(
    'max_select',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isRequiredMeta = const VerificationMeta(
    'isRequired',
  );
  @override
  late final GeneratedColumn<bool> isRequired = GeneratedColumn<bool>(
    'is_required',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_required" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    selectionType,
    minSelect,
    maxSelect,
    isRequired,
    displayOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'modifiers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Modifier> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('menu_item_id')) {
      context.handle(
        _menuItemIdMeta,
        menuItemId.isAcceptableOrUnknown(
          data['menu_item_id']!,
          _menuItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_menuItemIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('selection_type')) {
      context.handle(
        _selectionTypeMeta,
        selectionType.isAcceptableOrUnknown(
          data['selection_type']!,
          _selectionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectionTypeMeta);
    }
    if (data.containsKey('min_select')) {
      context.handle(
        _minSelectMeta,
        minSelect.isAcceptableOrUnknown(data['min_select']!, _minSelectMeta),
      );
    }
    if (data.containsKey('max_select')) {
      context.handle(
        _maxSelectMeta,
        maxSelect.isAcceptableOrUnknown(data['max_select']!, _maxSelectMeta),
      );
    }
    if (data.containsKey('is_required')) {
      context.handle(
        _isRequiredMeta,
        isRequired.isAcceptableOrUnknown(data['is_required']!, _isRequiredMeta),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Modifier map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Modifier(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      menuItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}menu_item_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      selectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selection_type'],
      )!,
      minSelect: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_select'],
      )!,
      maxSelect: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_select'],
      )!,
      isRequired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_required'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ModifiersTable createAlias(String alias) {
    return $ModifiersTable(attachedDatabase, alias);
  }
}

class Modifier extends DataClass implements Insertable<Modifier> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;
  final String restaurantId;
  final String? branchId;
  final String menuItemId;
  final String name;

  /// 'single' or 'multiple' (stored as text; not enforced in RF-030).
  final String selectionType;
  final int minSelect;
  final int maxSelect;
  final bool isRequired;
  final int displayOrder;
  final bool isActive;
  const Modifier({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.menuItemId,
    required this.name,
    required this.selectionType,
    required this.minSelect,
    required this.maxSelect,
    required this.isRequired,
    required this.displayOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['menu_item_id'] = Variable<String>(menuItemId);
    map['name'] = Variable<String>(name);
    map['selection_type'] = Variable<String>(selectionType);
    map['min_select'] = Variable<int>(minSelect);
    map['max_select'] = Variable<int>(maxSelect);
    map['is_required'] = Variable<bool>(isRequired);
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ModifiersCompanion toCompanion(bool nullToAbsent) {
    return ModifiersCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      menuItemId: Value(menuItemId),
      name: Value(name),
      selectionType: Value(selectionType),
      minSelect: Value(minSelect),
      maxSelect: Value(maxSelect),
      isRequired: Value(isRequired),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
    );
  }

  factory Modifier.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Modifier(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      menuItemId: serializer.fromJson<String>(json['menuItemId']),
      name: serializer.fromJson<String>(json['name']),
      selectionType: serializer.fromJson<String>(json['selectionType']),
      minSelect: serializer.fromJson<int>(json['minSelect']),
      maxSelect: serializer.fromJson<int>(json['maxSelect']),
      isRequired: serializer.fromJson<bool>(json['isRequired']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'menuItemId': serializer.toJson<String>(menuItemId),
      'name': serializer.toJson<String>(name),
      'selectionType': serializer.toJson<String>(selectionType),
      'minSelect': serializer.toJson<int>(minSelect),
      'maxSelect': serializer.toJson<int>(maxSelect),
      'isRequired': serializer.toJson<bool>(isRequired),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Modifier copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? menuItemId,
    String? name,
    String? selectionType,
    int? minSelect,
    int? maxSelect,
    bool? isRequired,
    int? displayOrder,
    bool? isActive,
  }) => Modifier(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    menuItemId: menuItemId ?? this.menuItemId,
    name: name ?? this.name,
    selectionType: selectionType ?? this.selectionType,
    minSelect: minSelect ?? this.minSelect,
    maxSelect: maxSelect ?? this.maxSelect,
    isRequired: isRequired ?? this.isRequired,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
  );
  Modifier copyWithCompanion(ModifiersCompanion data) {
    return Modifier(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      menuItemId: data.menuItemId.present
          ? data.menuItemId.value
          : this.menuItemId,
      name: data.name.present ? data.name.value : this.name,
      selectionType: data.selectionType.present
          ? data.selectionType.value
          : this.selectionType,
      minSelect: data.minSelect.present ? data.minSelect.value : this.minSelect,
      maxSelect: data.maxSelect.present ? data.maxSelect.value : this.maxSelect,
      isRequired: data.isRequired.present
          ? data.isRequired.value
          : this.isRequired,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Modifier(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('selectionType: $selectionType, ')
          ..write('minSelect: $minSelect, ')
          ..write('maxSelect: $maxSelect, ')
          ..write('isRequired: $isRequired, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    menuItemId,
    name,
    selectionType,
    minSelect,
    maxSelect,
    isRequired,
    displayOrder,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Modifier &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.menuItemId == this.menuItemId &&
          other.name == this.name &&
          other.selectionType == this.selectionType &&
          other.minSelect == this.minSelect &&
          other.maxSelect == this.maxSelect &&
          other.isRequired == this.isRequired &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive);
}

class ModifiersCompanion extends UpdateCompanion<Modifier> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> menuItemId;
  final Value<String> name;
  final Value<String> selectionType;
  final Value<int> minSelect;
  final Value<int> maxSelect;
  final Value<bool> isRequired;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ModifiersCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.menuItemId = const Value.absent(),
    this.name = const Value.absent(),
    this.selectionType = const Value.absent(),
    this.minSelect = const Value.absent(),
    this.maxSelect = const Value.absent(),
    this.isRequired = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModifiersCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String menuItemId,
    required String name,
    required String selectionType,
    this.minSelect = const Value.absent(),
    this.maxSelect = const Value.absent(),
    this.isRequired = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       menuItemId = Value(menuItemId),
       name = Value(name),
       selectionType = Value(selectionType);
  static Insertable<Modifier> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? menuItemId,
    Expression<String>? name,
    Expression<String>? selectionType,
    Expression<int>? minSelect,
    Expression<int>? maxSelect,
    Expression<bool>? isRequired,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (menuItemId != null) 'menu_item_id': menuItemId,
      if (name != null) 'name': name,
      if (selectionType != null) 'selection_type': selectionType,
      if (minSelect != null) 'min_select': minSelect,
      if (maxSelect != null) 'max_select': maxSelect,
      if (isRequired != null) 'is_required': isRequired,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModifiersCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? menuItemId,
    Value<String>? name,
    Value<String>? selectionType,
    Value<int>? minSelect,
    Value<int>? maxSelect,
    Value<bool>? isRequired,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ModifiersCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      selectionType: selectionType ?? this.selectionType,
      minSelect: minSelect ?? this.minSelect,
      maxSelect: maxSelect ?? this.maxSelect,
      isRequired: isRequired ?? this.isRequired,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (menuItemId.present) {
      map['menu_item_id'] = Variable<String>(menuItemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (selectionType.present) {
      map['selection_type'] = Variable<String>(selectionType.value);
    }
    if (minSelect.present) {
      map['min_select'] = Variable<int>(minSelect.value);
    }
    if (maxSelect.present) {
      map['max_select'] = Variable<int>(maxSelect.value);
    }
    if (isRequired.present) {
      map['is_required'] = Variable<bool>(isRequired.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModifiersCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('menuItemId: $menuItemId, ')
          ..write('name: $name, ')
          ..write('selectionType: $selectionType, ')
          ..write('minSelect: $minSelect, ')
          ..write('maxSelect: $maxSelect, ')
          ..write('isRequired: $isRequired, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ModifierOptionsTable extends ModifierOptions
    with TableInfo<$ModifierOptionsTable, ModifierOption> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModifierOptionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _clientUpdatedAtMeta = const VerificationMeta(
    'clientUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> clientUpdatedAt =
      GeneratedColumn<DateTime>(
        'client_updated_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _serverUpdatedAtMeta = const VerificationMeta(
    'serverUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> serverUpdatedAt =
      GeneratedColumn<DateTime>(
        'server_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modifierIdMeta = const VerificationMeta(
    'modifierId',
  );
  @override
  late final GeneratedColumn<String> modifierId = GeneratedColumn<String>(
    'modifier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES modifiers (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceDeltaMinorMeta = const VerificationMeta(
    'priceDeltaMinor',
  );
  @override
  late final GeneratedColumn<int> priceDeltaMinor = GeneratedColumn<int>(
    'price_delta_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    modifierId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'modifier_options';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModifierOption> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('client_updated_at')) {
      context.handle(
        _clientUpdatedAtMeta,
        clientUpdatedAt.isAcceptableOrUnknown(
          data['client_updated_at']!,
          _clientUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientUpdatedAtMeta);
    }
    if (data.containsKey('server_updated_at')) {
      context.handle(
        _serverUpdatedAtMeta,
        serverUpdatedAt.isAcceptableOrUnknown(
          data['server_updated_at']!,
          _serverUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('modifier_id')) {
      context.handle(
        _modifierIdMeta,
        modifierId.isAcceptableOrUnknown(data['modifier_id']!, _modifierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modifierIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_delta_minor')) {
      context.handle(
        _priceDeltaMinorMeta,
        priceDeltaMinor.isAcceptableOrUnknown(
          data['price_delta_minor']!,
          _priceDeltaMinorMeta,
        ),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ModifierOption map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModifierOption(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      clientUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}client_updated_at'],
      )!,
      serverUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_updated_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      ),
      modifierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}modifier_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceDeltaMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_delta_minor'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ModifierOptionsTable createAlias(String alias) {
    return $ModifierOptionsTable(attachedDatabase, alias);
  }
}

class ModifierOption extends DataClass implements Insertable<ModifierOption> {
  /// Client-generated UUID primary key (rows exist before any server round-trip).
  final String id;

  /// Tenant isolation boundary (DECISION D-001).
  final String organizationId;

  /// Originating device identity (DECISION D-022).
  final String deviceId;

  /// Client-generated per-operation id; `(deviceId, localOperationId)` is the
  /// idempotency key (DECISION D-022).
  final String localOperationId;

  /// Monotonic per-entity version; optimistic-concurrency token.
  final int revision;

  /// Wall-clock time the change was made on the device (advisory, not trusted).
  final DateTime clientUpdatedAt;

  /// Authoritative time set by the server on accept; null until first accepted.
  final DateTime? serverUpdatedAt;

  /// Standard audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Tombstone marker (DECISION D-020). Null = live; non-null = soft-deleted.
  final DateTime? deletedAt;
  final String restaurantId;
  final String? branchId;
  final String modifierId;
  final String name;

  /// Price delta in integer MINOR units (DECISION D-007).
  final int priceDeltaMinor;
  final int displayOrder;
  final bool isActive;
  const ModifierOption({
    required this.id,
    required this.organizationId,
    required this.deviceId,
    required this.localOperationId,
    required this.revision,
    required this.clientUpdatedAt,
    this.serverUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.restaurantId,
    this.branchId,
    required this.modifierId,
    required this.name,
    required this.priceDeltaMinor,
    required this.displayOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['device_id'] = Variable<String>(deviceId);
    map['local_operation_id'] = Variable<String>(localOperationId);
    map['revision'] = Variable<int>(revision);
    map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt);
    if (!nullToAbsent || serverUpdatedAt != null) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['restaurant_id'] = Variable<String>(restaurantId);
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<String>(branchId);
    }
    map['modifier_id'] = Variable<String>(modifierId);
    map['name'] = Variable<String>(name);
    map['price_delta_minor'] = Variable<int>(priceDeltaMinor);
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ModifierOptionsCompanion toCompanion(bool nullToAbsent) {
    return ModifierOptionsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      deviceId: Value(deviceId),
      localOperationId: Value(localOperationId),
      revision: Value(revision),
      clientUpdatedAt: Value(clientUpdatedAt),
      serverUpdatedAt: serverUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverUpdatedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      restaurantId: Value(restaurantId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      modifierId: Value(modifierId),
      name: Value(name),
      priceDeltaMinor: Value(priceDeltaMinor),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
    );
  }

  factory ModifierOption.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModifierOption(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      revision: serializer.fromJson<int>(json['revision']),
      clientUpdatedAt: serializer.fromJson<DateTime>(json['clientUpdatedAt']),
      serverUpdatedAt: serializer.fromJson<DateTime?>(json['serverUpdatedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String?>(json['branchId']),
      modifierId: serializer.fromJson<String>(json['modifierId']),
      name: serializer.fromJson<String>(json['name']),
      priceDeltaMinor: serializer.fromJson<int>(json['priceDeltaMinor']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'revision': serializer.toJson<int>(revision),
      'clientUpdatedAt': serializer.toJson<DateTime>(clientUpdatedAt),
      'serverUpdatedAt': serializer.toJson<DateTime?>(serverUpdatedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String?>(branchId),
      'modifierId': serializer.toJson<String>(modifierId),
      'name': serializer.toJson<String>(name),
      'priceDeltaMinor': serializer.toJson<int>(priceDeltaMinor),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  ModifierOption copyWith({
    String? id,
    String? organizationId,
    String? deviceId,
    String? localOperationId,
    int? revision,
    DateTime? clientUpdatedAt,
    Value<DateTime?> serverUpdatedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? restaurantId,
    Value<String?> branchId = const Value.absent(),
    String? modifierId,
    String? name,
    int? priceDeltaMinor,
    int? displayOrder,
    bool? isActive,
  }) => ModifierOption(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    deviceId: deviceId ?? this.deviceId,
    localOperationId: localOperationId ?? this.localOperationId,
    revision: revision ?? this.revision,
    clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
    serverUpdatedAt: serverUpdatedAt.present
        ? serverUpdatedAt.value
        : this.serverUpdatedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId.present ? branchId.value : this.branchId,
    modifierId: modifierId ?? this.modifierId,
    name: name ?? this.name,
    priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
  );
  ModifierOption copyWithCompanion(ModifierOptionsCompanion data) {
    return ModifierOption(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      revision: data.revision.present ? data.revision.value : this.revision,
      clientUpdatedAt: data.clientUpdatedAt.present
          ? data.clientUpdatedAt.value
          : this.clientUpdatedAt,
      serverUpdatedAt: data.serverUpdatedAt.present
          ? data.serverUpdatedAt.value
          : this.serverUpdatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      modifierId: data.modifierId.present
          ? data.modifierId.value
          : this.modifierId,
      name: data.name.present ? data.name.value : this.name,
      priceDeltaMinor: data.priceDeltaMinor.present
          ? data.priceDeltaMinor.value
          : this.priceDeltaMinor,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModifierOption(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('modifierId: $modifierId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    organizationId,
    deviceId,
    localOperationId,
    revision,
    clientUpdatedAt,
    serverUpdatedAt,
    createdAt,
    updatedAt,
    deletedAt,
    restaurantId,
    branchId,
    modifierId,
    name,
    priceDeltaMinor,
    displayOrder,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModifierOption &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.deviceId == this.deviceId &&
          other.localOperationId == this.localOperationId &&
          other.revision == this.revision &&
          other.clientUpdatedAt == this.clientUpdatedAt &&
          other.serverUpdatedAt == this.serverUpdatedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.modifierId == this.modifierId &&
          other.name == this.name &&
          other.priceDeltaMinor == this.priceDeltaMinor &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive);
}

class ModifierOptionsCompanion extends UpdateCompanion<ModifierOption> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> deviceId;
  final Value<String> localOperationId;
  final Value<int> revision;
  final Value<DateTime> clientUpdatedAt;
  final Value<DateTime?> serverUpdatedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> restaurantId;
  final Value<String?> branchId;
  final Value<String> modifierId;
  final Value<String> name;
  final Value<int> priceDeltaMinor;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ModifierOptionsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.revision = const Value.absent(),
    this.clientUpdatedAt = const Value.absent(),
    this.serverUpdatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.modifierId = const Value.absent(),
    this.name = const Value.absent(),
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModifierOptionsCompanion.insert({
    required String id,
    required String organizationId,
    required String deviceId,
    required String localOperationId,
    this.revision = const Value.absent(),
    required DateTime clientUpdatedAt,
    this.serverUpdatedAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String restaurantId,
    this.branchId = const Value.absent(),
    required String modifierId,
    required String name,
    this.priceDeltaMinor = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       clientUpdatedAt = Value(clientUpdatedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       restaurantId = Value(restaurantId),
       modifierId = Value(modifierId),
       name = Value(name);
  static Insertable<ModifierOption> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? deviceId,
    Expression<String>? localOperationId,
    Expression<int>? revision,
    Expression<DateTime>? clientUpdatedAt,
    Expression<DateTime>? serverUpdatedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? modifierId,
    Expression<String>? name,
    Expression<int>? priceDeltaMinor,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (deviceId != null) 'device_id': deviceId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (revision != null) 'revision': revision,
      if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
      if (serverUpdatedAt != null) 'server_updated_at': serverUpdatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (modifierId != null) 'modifier_id': modifierId,
      if (name != null) 'name': name,
      if (priceDeltaMinor != null) 'price_delta_minor': priceDeltaMinor,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModifierOptionsCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? deviceId,
    Value<String>? localOperationId,
    Value<int>? revision,
    Value<DateTime>? clientUpdatedAt,
    Value<DateTime?>? serverUpdatedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? restaurantId,
    Value<String?>? branchId,
    Value<String>? modifierId,
    Value<String>? name,
    Value<int>? priceDeltaMinor,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ModifierOptionsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      deviceId: deviceId ?? this.deviceId,
      localOperationId: localOperationId ?? this.localOperationId,
      revision: revision ?? this.revision,
      clientUpdatedAt: clientUpdatedAt ?? this.clientUpdatedAt,
      serverUpdatedAt: serverUpdatedAt ?? this.serverUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      modifierId: modifierId ?? this.modifierId,
      name: name ?? this.name,
      priceDeltaMinor: priceDeltaMinor ?? this.priceDeltaMinor,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (clientUpdatedAt.present) {
      map['client_updated_at'] = Variable<DateTime>(clientUpdatedAt.value);
    }
    if (serverUpdatedAt.present) {
      map['server_updated_at'] = Variable<DateTime>(serverUpdatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (modifierId.present) {
      map['modifier_id'] = Variable<String>(modifierId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceDeltaMinor.present) {
      map['price_delta_minor'] = Variable<int>(priceDeltaMinor.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModifierOptionsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('revision: $revision, ')
          ..write('clientUpdatedAt: $clientUpdatedAt, ')
          ..write('serverUpdatedAt: $serverUpdatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('modifierId: $modifierId, ')
          ..write('name: $name, ')
          ..write('priceDeltaMinor: $priceDeltaMinor, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PrintJobsTable extends PrintJobs
    with TableInfo<$PrintJobsTable, PrintJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrintJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localOperationIdMeta = const VerificationMeta(
    'localOperationId',
  );
  @override
  late final GeneratedColumn<String> localOperationId = GeneratedColumn<String>(
    'local_operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PrintJobType, String> jobType =
      GeneratedColumn<String>(
        'job_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PrintJobType>($PrintJobsTable.$converterjobType);
  @override
  late final GeneratedColumnWithTypeConverter<PrintJobState, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('created'),
      ).withConverter<PrintJobState>($PrintJobsTable.$converterstatus);
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxRetriesMeta = const VerificationMeta(
    'maxRetries',
  );
  @override
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
    'max_retries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(12),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta(
    'lastErrorMessage',
  );
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reprintOfMeta = const VerificationMeta(
    'reprintOf',
  );
  @override
  late final GeneratedColumn<String> reprintOf = GeneratedColumn<String>(
    'reprint_of',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reprintReasonMeta = const VerificationMeta(
    'reprintReason',
  );
  @override
  late final GeneratedColumn<String> reprintReason = GeneratedColumn<String>(
    'reprint_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _printedAtMeta = const VerificationMeta(
    'printedAt',
  );
  @override
  late final GeneratedColumn<DateTime> printedAt = GeneratedColumn<DateTime>(
    'printed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _abandonedAtMeta = const VerificationMeta(
    'abandonedAt',
  );
  @override
  late final GeneratedColumn<DateTime> abandonedAt = GeneratedColumn<DateTime>(
    'abandoned_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    organizationId,
    branchId,
    deviceId,
    stationId,
    localOperationId,
    jobType,
    status,
    payloadJson,
    retryCount,
    maxRetries,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    reprintOf,
    reprintReason,
    createdAt,
    updatedAt,
    printedAt,
    abandonedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'print_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrintJobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('local_operation_id')) {
      context.handle(
        _localOperationIdMeta,
        localOperationId.isAcceptableOrUnknown(
          data['local_operation_id']!,
          _localOperationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localOperationIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('max_retries')) {
      context.handle(
        _maxRetriesMeta,
        maxRetries.isAcceptableOrUnknown(data['max_retries']!, _maxRetriesMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(
          data['last_error_message']!,
          _lastErrorMessageMeta,
        ),
      );
    }
    if (data.containsKey('reprint_of')) {
      context.handle(
        _reprintOfMeta,
        reprintOf.isAcceptableOrUnknown(data['reprint_of']!, _reprintOfMeta),
      );
    }
    if (data.containsKey('reprint_reason')) {
      context.handle(
        _reprintReasonMeta,
        reprintReason.isAcceptableOrUnknown(
          data['reprint_reason']!,
          _reprintReasonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('printed_at')) {
      context.handle(
        _printedAtMeta,
        printedAt.isAcceptableOrUnknown(data['printed_at']!, _printedAtMeta),
      );
    }
    if (data.containsKey('abandoned_at')) {
      context.handle(
        _abandonedAtMeta,
        abandonedAt.isAcceptableOrUnknown(
          data['abandoned_at']!,
          _abandonedAtMeta,
        ),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {deviceId, localOperationId},
  ];
  @override
  PrintJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrintJobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      ),
      localOperationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_operation_id'],
      )!,
      jobType: $PrintJobsTable.$converterjobType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}job_type'],
        )!,
      ),
      status: $PrintJobsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      maxRetries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_retries'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
      reprintOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reprint_of'],
      ),
      reprintReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reprint_reason'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      printedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}printed_at'],
      ),
      abandonedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}abandoned_at'],
      ),
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $PrintJobsTable createAlias(String alias) {
    return $PrintJobsTable(attachedDatabase, alias);
  }

  static TypeConverter<PrintJobType, String> $converterjobType =
      const PrintJobTypeConverter();
  static TypeConverter<PrintJobState, String> $converterstatus =
      const PrintJobStateConverter();
}

class PrintJobRow extends DataClass implements Insertable<PrintJobRow> {
  /// Client-generated UUID primary key.
  final String id;

  /// Tenant scope (DECISION D-001).
  final String organizationId;
  final String branchId;
  final String deviceId;

  /// nullable station scope (kitchen-station tickets).
  final String? stationId;

  /// Idempotency key part (DECISION D-022); UNIQUE with [deviceId].
  final String localOperationId;

  /// `receipt` / `kitchen_ticket` / `drawer_kick` (PrintJobType wire value).
  final PrintJobType jobType;

  /// Lifecycle state (DECISION D-018); stored as wire text.
  final PrintJobState status;

  /// The render-neutral [PrintDocument] serialized as JSON (A4). No raw bytes,
  /// no money — text is caller-pre-formatted (D-007/D-008).
  final String payloadJson;

  /// Retry bookkeeping (policy/limits configurable, Q-018; defaults in engine).
  final int retryCount;
  final int maxRetries;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  /// Reprint linkage (PRINTERS §8.4): the original job id + mandatory reason.
  final String? reprintOf;
  final String? reprintReason;

  /// Lifecycle timestamps (stored as UTC ISO-8601 text — DB option).
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? printedAt;
  final DateTime? abandonedAt;

  /// Tombstone for local pruning (matches the local convention; not synced).
  final DateTime? deletedAt;
  const PrintJobRow({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.deviceId,
    this.stationId,
    required this.localOperationId,
    required this.jobType,
    required this.status,
    required this.payloadJson,
    required this.retryCount,
    required this.maxRetries,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.reprintOf,
    this.reprintReason,
    required this.createdAt,
    required this.updatedAt,
    this.printedAt,
    this.abandonedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<String>(stationId);
    }
    map['local_operation_id'] = Variable<String>(localOperationId);
    {
      map['job_type'] = Variable<String>(
        $PrintJobsTable.$converterjobType.toSql(jobType),
      );
    }
    {
      map['status'] = Variable<String>(
        $PrintJobsTable.$converterstatus.toSql(status),
      );
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['retry_count'] = Variable<int>(retryCount);
    map['max_retries'] = Variable<int>(maxRetries);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    if (!nullToAbsent || reprintOf != null) {
      map['reprint_of'] = Variable<String>(reprintOf);
    }
    if (!nullToAbsent || reprintReason != null) {
      map['reprint_reason'] = Variable<String>(reprintReason);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || printedAt != null) {
      map['printed_at'] = Variable<DateTime>(printedAt);
    }
    if (!nullToAbsent || abandonedAt != null) {
      map['abandoned_at'] = Variable<DateTime>(abandonedAt);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  PrintJobsCompanion toCompanion(bool nullToAbsent) {
    return PrintJobsCompanion(
      id: Value(id),
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      deviceId: Value(deviceId),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      localOperationId: Value(localOperationId),
      jobType: Value(jobType),
      status: Value(status),
      payloadJson: Value(payloadJson),
      retryCount: Value(retryCount),
      maxRetries: Value(maxRetries),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorMessage),
      reprintOf: reprintOf == null && nullToAbsent
          ? const Value.absent()
          : Value(reprintOf),
      reprintReason: reprintReason == null && nullToAbsent
          ? const Value.absent()
          : Value(reprintReason),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      printedAt: printedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(printedAt),
      abandonedAt: abandonedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(abandonedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory PrintJobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrintJobRow(
      id: serializer.fromJson<String>(json['id']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      stationId: serializer.fromJson<String?>(json['stationId']),
      localOperationId: serializer.fromJson<String>(json['localOperationId']),
      jobType: serializer.fromJson<PrintJobType>(json['jobType']),
      status: serializer.fromJson<PrintJobState>(json['status']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      maxRetries: serializer.fromJson<int>(json['maxRetries']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
      reprintOf: serializer.fromJson<String?>(json['reprintOf']),
      reprintReason: serializer.fromJson<String?>(json['reprintReason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      printedAt: serializer.fromJson<DateTime?>(json['printedAt']),
      abandonedAt: serializer.fromJson<DateTime?>(json['abandonedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'deviceId': serializer.toJson<String>(deviceId),
      'stationId': serializer.toJson<String?>(stationId),
      'localOperationId': serializer.toJson<String>(localOperationId),
      'jobType': serializer.toJson<PrintJobType>(jobType),
      'status': serializer.toJson<PrintJobState>(status),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'retryCount': serializer.toJson<int>(retryCount),
      'maxRetries': serializer.toJson<int>(maxRetries),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
      'reprintOf': serializer.toJson<String?>(reprintOf),
      'reprintReason': serializer.toJson<String?>(reprintReason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'printedAt': serializer.toJson<DateTime?>(printedAt),
      'abandonedAt': serializer.toJson<DateTime?>(abandonedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  PrintJobRow copyWith({
    String? id,
    String? organizationId,
    String? branchId,
    String? deviceId,
    Value<String?> stationId = const Value.absent(),
    String? localOperationId,
    PrintJobType? jobType,
    PrintJobState? status,
    String? payloadJson,
    int? retryCount,
    int? maxRetries,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
    Value<String?> reprintOf = const Value.absent(),
    Value<String?> reprintReason = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> printedAt = const Value.absent(),
    Value<DateTime?> abandonedAt = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => PrintJobRow(
    id: id ?? this.id,
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    deviceId: deviceId ?? this.deviceId,
    stationId: stationId.present ? stationId.value : this.stationId,
    localOperationId: localOperationId ?? this.localOperationId,
    jobType: jobType ?? this.jobType,
    status: status ?? this.status,
    payloadJson: payloadJson ?? this.payloadJson,
    retryCount: retryCount ?? this.retryCount,
    maxRetries: maxRetries ?? this.maxRetries,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present
        ? lastErrorMessage.value
        : this.lastErrorMessage,
    reprintOf: reprintOf.present ? reprintOf.value : this.reprintOf,
    reprintReason: reprintReason.present
        ? reprintReason.value
        : this.reprintReason,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    printedAt: printedAt.present ? printedAt.value : this.printedAt,
    abandonedAt: abandonedAt.present ? abandonedAt.value : this.abandonedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  PrintJobRow copyWithCompanion(PrintJobsCompanion data) {
    return PrintJobRow(
      id: data.id.present ? data.id.value : this.id,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      localOperationId: data.localOperationId.present
          ? data.localOperationId.value
          : this.localOperationId,
      jobType: data.jobType.present ? data.jobType.value : this.jobType,
      status: data.status.present ? data.status.value : this.status,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      maxRetries: data.maxRetries.present
          ? data.maxRetries.value
          : this.maxRetries,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present
          ? data.lastErrorMessage.value
          : this.lastErrorMessage,
      reprintOf: data.reprintOf.present ? data.reprintOf.value : this.reprintOf,
      reprintReason: data.reprintReason.present
          ? data.reprintReason.value
          : this.reprintReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      printedAt: data.printedAt.present ? data.printedAt.value : this.printedAt,
      abandonedAt: data.abandonedAt.present
          ? data.abandonedAt.value
          : this.abandonedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrintJobRow(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('deviceId: $deviceId, ')
          ..write('stationId: $stationId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('jobType: $jobType, ')
          ..write('status: $status, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('reprintOf: $reprintOf, ')
          ..write('reprintReason: $reprintReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('printedAt: $printedAt, ')
          ..write('abandonedAt: $abandonedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    organizationId,
    branchId,
    deviceId,
    stationId,
    localOperationId,
    jobType,
    status,
    payloadJson,
    retryCount,
    maxRetries,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    reprintOf,
    reprintReason,
    createdAt,
    updatedAt,
    printedAt,
    abandonedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrintJobRow &&
          other.id == this.id &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.deviceId == this.deviceId &&
          other.stationId == this.stationId &&
          other.localOperationId == this.localOperationId &&
          other.jobType == this.jobType &&
          other.status == this.status &&
          other.payloadJson == this.payloadJson &&
          other.retryCount == this.retryCount &&
          other.maxRetries == this.maxRetries &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage &&
          other.reprintOf == this.reprintOf &&
          other.reprintReason == this.reprintReason &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.printedAt == this.printedAt &&
          other.abandonedAt == this.abandonedAt &&
          other.deletedAt == this.deletedAt);
}

class PrintJobsCompanion extends UpdateCompanion<PrintJobRow> {
  final Value<String> id;
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> deviceId;
  final Value<String?> stationId;
  final Value<String> localOperationId;
  final Value<PrintJobType> jobType;
  final Value<PrintJobState> status;
  final Value<String> payloadJson;
  final Value<int> retryCount;
  final Value<int> maxRetries;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<String?> reprintOf;
  final Value<String?> reprintReason;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> printedAt;
  final Value<DateTime?> abandonedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const PrintJobsCompanion({
    this.id = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.localOperationId = const Value.absent(),
    this.jobType = const Value.absent(),
    this.status = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.reprintOf = const Value.absent(),
    this.reprintReason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.printedAt = const Value.absent(),
    this.abandonedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrintJobsCompanion.insert({
    required String id,
    required String organizationId,
    required String branchId,
    required String deviceId,
    this.stationId = const Value.absent(),
    required String localOperationId,
    required PrintJobType jobType,
    this.status = const Value.absent(),
    required String payloadJson,
    this.retryCount = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.reprintOf = const Value.absent(),
    this.reprintReason = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.printedAt = const Value.absent(),
    this.abandonedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       organizationId = Value(organizationId),
       branchId = Value(branchId),
       deviceId = Value(deviceId),
       localOperationId = Value(localOperationId),
       jobType = Value(jobType),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PrintJobRow> custom({
    Expression<String>? id,
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? deviceId,
    Expression<String>? stationId,
    Expression<String>? localOperationId,
    Expression<String>? jobType,
    Expression<String>? status,
    Expression<String>? payloadJson,
    Expression<int>? retryCount,
    Expression<int>? maxRetries,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<String>? reprintOf,
    Expression<String>? reprintReason,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? printedAt,
    Expression<DateTime>? abandonedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (deviceId != null) 'device_id': deviceId,
      if (stationId != null) 'station_id': stationId,
      if (localOperationId != null) 'local_operation_id': localOperationId,
      if (jobType != null) 'job_type': jobType,
      if (status != null) 'status': status,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (retryCount != null) 'retry_count': retryCount,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (reprintOf != null) 'reprint_of': reprintOf,
      if (reprintReason != null) 'reprint_reason': reprintReason,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (printedAt != null) 'printed_at': printedAt,
      if (abandonedAt != null) 'abandoned_at': abandonedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrintJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? deviceId,
    Value<String?>? stationId,
    Value<String>? localOperationId,
    Value<PrintJobType>? jobType,
    Value<PrintJobState>? status,
    Value<String>? payloadJson,
    Value<int>? retryCount,
    Value<int>? maxRetries,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<String?>? reprintOf,
    Value<String?>? reprintReason,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? printedAt,
    Value<DateTime?>? abandonedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return PrintJobsCompanion(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      deviceId: deviceId ?? this.deviceId,
      stationId: stationId ?? this.stationId,
      localOperationId: localOperationId ?? this.localOperationId,
      jobType: jobType ?? this.jobType,
      status: status ?? this.status,
      payloadJson: payloadJson ?? this.payloadJson,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      reprintOf: reprintOf ?? this.reprintOf,
      reprintReason: reprintReason ?? this.reprintReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      printedAt: printedAt ?? this.printedAt,
      abandonedAt: abandonedAt ?? this.abandonedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (localOperationId.present) {
      map['local_operation_id'] = Variable<String>(localOperationId.value);
    }
    if (jobType.present) {
      map['job_type'] = Variable<String>(
        $PrintJobsTable.$converterjobType.toSql(jobType.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $PrintJobsTable.$converterstatus.toSql(status.value),
      );
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (reprintOf.present) {
      map['reprint_of'] = Variable<String>(reprintOf.value);
    }
    if (reprintReason.present) {
      map['reprint_reason'] = Variable<String>(reprintReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (printedAt.present) {
      map['printed_at'] = Variable<DateTime>(printedAt.value);
    }
    if (abandonedAt.present) {
      map['abandoned_at'] = Variable<DateTime>(abandonedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrintJobsCompanion(')
          ..write('id: $id, ')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('deviceId: $deviceId, ')
          ..write('stationId: $stationId, ')
          ..write('localOperationId: $localOperationId, ')
          ..write('jobType: $jobType, ')
          ..write('status: $status, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('retryCount: $retryCount, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('reprintOf: $reprintOf, ')
          ..write('reprintReason: $reprintReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('printedAt: $printedAt, ')
          ..write('abandonedAt: $abandonedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KitchenSpoolJobsTable extends KitchenSpoolJobs
    with TableInfo<$KitchenSpoolJobsTable, KitchenSpoolJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KitchenSpoolJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localJobIdMeta = const VerificationMeta(
    'localJobId',
  );
  @override
  late final GeneratedColumn<String> localJobId = GeneratedColumn<String>(
    'local_job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dispatchIdMeta = const VerificationMeta(
    'dispatchId',
  );
  @override
  late final GeneratedColumn<String> dispatchId = GeneratedColumn<String>(
    'dispatch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serviceRoundIdMeta = const VerificationMeta(
    'serviceRoundId',
  );
  @override
  late final GeneratedColumn<String> serviceRoundId = GeneratedColumn<String>(
    'service_round_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<KitchenSpoolDispatchType, String>
  dispatchType =
      GeneratedColumn<String>(
        'dispatch_type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<KitchenSpoolDispatchType>(
        $KitchenSpoolJobsTable.$converterdispatchType,
      );
  @override
  late final GeneratedColumnWithTypeConverter<KitchenSpoolJobStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('imported'),
      ).withConverter<KitchenSpoolJobStatus>(
        $KitchenSpoolJobsTable.$converterstatus,
      );
  static const VerificationMeta _encryptedPayloadBlobMeta =
      const VerificationMeta('encryptedPayloadBlob');
  @override
  late final GeneratedColumn<Uint8List> encryptedPayloadBlob =
      GeneratedColumn<Uint8List>(
        'encrypted_payload_blob',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _encryptionVersionMeta = const VerificationMeta(
    'encryptionVersion',
  );
  @override
  late final GeneratedColumn<int> encryptionVersion = GeneratedColumn<int>(
    'encryption_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationFingerprintMeta =
      const VerificationMeta('destinationFingerprint');
  @override
  late final GeneratedColumn<String> destinationFingerprint =
      GeneratedColumn<String>(
        'destination_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _destinationDisplayLabelMeta =
      const VerificationMeta('destinationDisplayLabel');
  @override
  late final GeneratedColumn<String> destinationDisplayLabel =
      GeneratedColumn<String>(
        'destination_display_label',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _transportKindMeta = const VerificationMeta(
    'transportKind',
  );
  @override
  late final GeneratedColumn<String> transportKind = GeneratedColumn<String>(
    'transport_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paperWidthMeta = const VerificationMeta(
    'paperWidth',
  );
  @override
  late final GeneratedColumn<String> paperWidth = GeneratedColumn<String>(
    'paper_width',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadVersionMeta = const VerificationMeta(
    'payloadVersion',
  );
  @override
  late final GeneratedColumn<int> payloadVersion = GeneratedColumn<int>(
    'payload_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentVersionMeta = const VerificationMeta(
    'documentVersion',
  );
  @override
  late final GeneratedColumn<int> documentVersion = GeneratedColumn<int>(
    'document_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rasterVersionMeta = const VerificationMeta(
    'rasterVersion',
  );
  @override
  late final GeneratedColumn<int> rasterVersion = GeneratedColumn<int>(
    'raster_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverClaimExpiresAtMeta =
      const VerificationMeta('serverClaimExpiresAt');
  @override
  late final GeneratedColumn<DateTime> serverClaimExpiresAt =
      GeneratedColumn<DateTime>(
        'server_claim_expires_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<KitchenServerAckStatus?, String>
  pendingServerAckStatus =
      GeneratedColumn<String>(
        'pending_server_ack_status',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<KitchenServerAckStatus?>(
        $KitchenSpoolJobsTable.$converterpendingServerAckStatusn,
      );
  static const VerificationMeta _serverAckAttemptCountMeta =
      const VerificationMeta('serverAckAttemptCount');
  @override
  late final GeneratedColumn<int> serverAckAttemptCount = GeneratedColumn<int>(
    'server_ack_attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverAckNextAttemptAtMeta =
      const VerificationMeta('serverAckNextAttemptAt');
  @override
  late final GeneratedColumn<DateTime> serverAckNextAttemptAt =
      GeneratedColumn<DateTime>(
        'server_ack_next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverAckLastErrorCodeMeta =
      const VerificationMeta('serverAckLastErrorCode');
  @override
  late final GeneratedColumn<String> serverAckLastErrorCode =
      GeneratedColumn<String>(
        'server_ack_last_error_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transportAcceptedAtMeta =
      const VerificationMeta('transportAcceptedAt');
  @override
  late final GeneratedColumn<DateTime> transportAcceptedAt =
      GeneratedColumn<DateTime>(
        'transport_accepted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _serverAcknowledgedAtMeta =
      const VerificationMeta('serverAcknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> serverAcknowledgedAt =
      GeneratedColumn<DateTime>(
        'server_acknowledged_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<DateTime> reviewedAt = GeneratedColumn<DateTime>(
    'reviewed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reprintOfLocalJobIdMeta =
      const VerificationMeta('reprintOfLocalJobId');
  @override
  late final GeneratedColumn<String> reprintOfLocalJobId =
      GeneratedColumn<String>(
        'reprint_of_local_job_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _supersededByDispatchIdMeta =
      const VerificationMeta('supersededByDispatchId');
  @override
  late final GeneratedColumn<String> supersededByDispatchId =
      GeneratedColumn<String>(
        'superseded_by_dispatch_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    localJobId,
    dispatchId,
    organizationId,
    restaurantId,
    branchId,
    deviceId,
    orderId,
    serviceRoundId,
    dispatchType,
    status,
    encryptedPayloadBlob,
    encryptionVersion,
    destinationFingerprint,
    destinationDisplayLabel,
    transportKind,
    paperWidth,
    payloadVersion,
    documentVersion,
    rasterVersion,
    attemptCount,
    nextAttemptAt,
    lastAttemptAt,
    lastErrorCode,
    serverClaimExpiresAt,
    pendingServerAckStatus,
    serverAckAttemptCount,
    serverAckNextAttemptAt,
    serverAckLastErrorCode,
    createdAt,
    updatedAt,
    transportAcceptedAt,
    serverAcknowledgedAt,
    reviewedAt,
    reprintOfLocalJobId,
    supersededByDispatchId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kitchen_spool_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<KitchenSpoolJobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_job_id')) {
      context.handle(
        _localJobIdMeta,
        localJobId.isAcceptableOrUnknown(
          data['local_job_id']!,
          _localJobIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localJobIdMeta);
    }
    if (data.containsKey('dispatch_id')) {
      context.handle(
        _dispatchIdMeta,
        dispatchId.isAcceptableOrUnknown(data['dispatch_id']!, _dispatchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_dispatchIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('service_round_id')) {
      context.handle(
        _serviceRoundIdMeta,
        serviceRoundId.isAcceptableOrUnknown(
          data['service_round_id']!,
          _serviceRoundIdMeta,
        ),
      );
    }
    if (data.containsKey('encrypted_payload_blob')) {
      context.handle(
        _encryptedPayloadBlobMeta,
        encryptedPayloadBlob.isAcceptableOrUnknown(
          data['encrypted_payload_blob']!,
          _encryptedPayloadBlobMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedPayloadBlobMeta);
    }
    if (data.containsKey('encryption_version')) {
      context.handle(
        _encryptionVersionMeta,
        encryptionVersion.isAcceptableOrUnknown(
          data['encryption_version']!,
          _encryptionVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptionVersionMeta);
    }
    if (data.containsKey('destination_fingerprint')) {
      context.handle(
        _destinationFingerprintMeta,
        destinationFingerprint.isAcceptableOrUnknown(
          data['destination_fingerprint']!,
          _destinationFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('destination_display_label')) {
      context.handle(
        _destinationDisplayLabelMeta,
        destinationDisplayLabel.isAcceptableOrUnknown(
          data['destination_display_label']!,
          _destinationDisplayLabelMeta,
        ),
      );
    }
    if (data.containsKey('transport_kind')) {
      context.handle(
        _transportKindMeta,
        transportKind.isAcceptableOrUnknown(
          data['transport_kind']!,
          _transportKindMeta,
        ),
      );
    }
    if (data.containsKey('paper_width')) {
      context.handle(
        _paperWidthMeta,
        paperWidth.isAcceptableOrUnknown(data['paper_width']!, _paperWidthMeta),
      );
    }
    if (data.containsKey('payload_version')) {
      context.handle(
        _payloadVersionMeta,
        payloadVersion.isAcceptableOrUnknown(
          data['payload_version']!,
          _payloadVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadVersionMeta);
    }
    if (data.containsKey('document_version')) {
      context.handle(
        _documentVersionMeta,
        documentVersion.isAcceptableOrUnknown(
          data['document_version']!,
          _documentVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentVersionMeta);
    }
    if (data.containsKey('raster_version')) {
      context.handle(
        _rasterVersionMeta,
        rasterVersion.isAcceptableOrUnknown(
          data['raster_version']!,
          _rasterVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rasterVersionMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('server_claim_expires_at')) {
      context.handle(
        _serverClaimExpiresAtMeta,
        serverClaimExpiresAt.isAcceptableOrUnknown(
          data['server_claim_expires_at']!,
          _serverClaimExpiresAtMeta,
        ),
      );
    }
    if (data.containsKey('server_ack_attempt_count')) {
      context.handle(
        _serverAckAttemptCountMeta,
        serverAckAttemptCount.isAcceptableOrUnknown(
          data['server_ack_attempt_count']!,
          _serverAckAttemptCountMeta,
        ),
      );
    }
    if (data.containsKey('server_ack_next_attempt_at')) {
      context.handle(
        _serverAckNextAttemptAtMeta,
        serverAckNextAttemptAt.isAcceptableOrUnknown(
          data['server_ack_next_attempt_at']!,
          _serverAckNextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('server_ack_last_error_code')) {
      context.handle(
        _serverAckLastErrorCodeMeta,
        serverAckLastErrorCode.isAcceptableOrUnknown(
          data['server_ack_last_error_code']!,
          _serverAckLastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('transport_accepted_at')) {
      context.handle(
        _transportAcceptedAtMeta,
        transportAcceptedAt.isAcceptableOrUnknown(
          data['transport_accepted_at']!,
          _transportAcceptedAtMeta,
        ),
      );
    }
    if (data.containsKey('server_acknowledged_at')) {
      context.handle(
        _serverAcknowledgedAtMeta,
        serverAcknowledgedAt.isAcceptableOrUnknown(
          data['server_acknowledged_at']!,
          _serverAcknowledgedAtMeta,
        ),
      );
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    }
    if (data.containsKey('reprint_of_local_job_id')) {
      context.handle(
        _reprintOfLocalJobIdMeta,
        reprintOfLocalJobId.isAcceptableOrUnknown(
          data['reprint_of_local_job_id']!,
          _reprintOfLocalJobIdMeta,
        ),
      );
    }
    if (data.containsKey('superseded_by_dispatch_id')) {
      context.handle(
        _supersededByDispatchIdMeta,
        supersededByDispatchId.isAcceptableOrUnknown(
          data['superseded_by_dispatch_id']!,
          _supersededByDispatchIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localJobId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {dispatchId},
  ];
  @override
  KitchenSpoolJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KitchenSpoolJobRow(
      localJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_job_id'],
      )!,
      dispatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dispatch_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_id'],
      )!,
      serviceRoundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_round_id'],
      ),
      dispatchType: $KitchenSpoolJobsTable.$converterdispatchType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}dispatch_type'],
        )!,
      ),
      status: $KitchenSpoolJobsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      encryptedPayloadBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_payload_blob'],
      )!,
      encryptionVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}encryption_version'],
      )!,
      destinationFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_fingerprint'],
      ),
      destinationDisplayLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_display_label'],
      ),
      transportKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transport_kind'],
      ),
      paperWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}paper_width'],
      ),
      payloadVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_version'],
      )!,
      documentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_version'],
      )!,
      rasterVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}raster_version'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      serverClaimExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_claim_expires_at'],
      ),
      pendingServerAckStatus: $KitchenSpoolJobsTable
          .$converterpendingServerAckStatusn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}pending_server_ack_status'],
            ),
          ),
      serverAckAttemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_ack_attempt_count'],
      )!,
      serverAckNextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_ack_next_attempt_at'],
      ),
      serverAckLastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_ack_last_error_code'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      transportAcceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transport_accepted_at'],
      ),
      serverAcknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_acknowledged_at'],
      ),
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reviewed_at'],
      ),
      reprintOfLocalJobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reprint_of_local_job_id'],
      ),
      supersededByDispatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}superseded_by_dispatch_id'],
      ),
    );
  }

  @override
  $KitchenSpoolJobsTable createAlias(String alias) {
    return $KitchenSpoolJobsTable(attachedDatabase, alias);
  }

  static TypeConverter<KitchenSpoolDispatchType, String>
  $converterdispatchType = const KitchenSpoolDispatchTypeConverter();
  static TypeConverter<KitchenSpoolJobStatus, String> $converterstatus =
      const KitchenSpoolJobStatusConverter();
  static TypeConverter<KitchenServerAckStatus, String>
  $converterpendingServerAckStatus = const KitchenServerAckStatusConverter();
  static TypeConverter<KitchenServerAckStatus?, String?>
  $converterpendingServerAckStatusn = NullAwareTypeConverter.wrap(
    $converterpendingServerAckStatus,
  );
}

class KitchenSpoolJobRow extends DataClass
    implements Insertable<KitchenSpoolJobRow> {
  /// Client-generated UUID primary key.
  final String localJobId;

  /// The server dispatch this job materializes; UNIQUE (idempotent import).
  final String dispatchId;

  /// Tenant/device scope (DECISION D-001) — matches the AAD binding.
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;

  /// Order linkage (IDs only — the order CONTENT is inside the blob).
  final String orderId;
  final String? serviceRoundId;

  /// `initial_order` / `service_round` / `void` (closed).
  final KitchenSpoolDispatchType dispatchType;

  /// Closed local lifecycle; see [KitchenSpoolJobStatus].
  final KitchenSpoolJobStatus status;

  /// The AES-256-GCM envelope (versioned binary format; AAD-bound).
  final Uint8List encryptedPayloadBlob;

  /// The envelope/crypto version used for this row.
  final int encryptionVersion;

  /// NON-SECRET digest of the pinned destination (single-flight lookups);
  /// null while no destination is pinned (blocked configuration).
  final String? destinationFingerprint;

  /// SAFE, GENERIC display label only — the store normalizes anything that
  /// looks like an endpoint (IP/port/MAC) into a generic label before
  /// storage. Never host/port/address.
  final String? destinationDisplayLabel;

  /// `network` / `bluetooth`; null while blocked.
  final String? transportKind;

  /// `58mm` / `80mm`; null while blocked.
  final String? paperWidth;

  /// Version pins for later rendering (payload = server payload version).
  final int payloadVersion;
  final int documentVersion;
  final int rasterVersion;

  /// Local transport retry bookkeeping.
  final int attemptCount;
  final DateTime? nextAttemptAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;

  /// Mirror of the server claim lease this import rode on (metadata only).
  final DateTime? serverClaimExpiresAt;

  /// The acknowledgement this device still owes the server — INDEPENDENT of
  /// local print state: ack retries never make a printed job runnable again.
  final KitchenServerAckStatus? pendingServerAckStatus;
  final int serverAckAttemptCount;
  final DateTime? serverAckNextAttemptAt;
  final String? serverAckLastErrorCode;

  /// Lifecycle timestamps (stored as UTC ISO-8601 text — DB option).
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? transportAcceptedAt;
  final DateTime? serverAcknowledgedAt;

  /// Operator review of terminal ambiguity (001C4; column reserved now so
  /// the schema needs no second migration).
  final DateTime? reviewedAt;

  /// Reprint linkage: the original local job (never itself — CHECK).
  final String? reprintOfLocalJobId;

  /// SERVER EVIDENCE ONLY: the void dispatch that superseded this one.
  final String? supersededByDispatchId;
  const KitchenSpoolJobRow({
    required this.localJobId,
    required this.dispatchId,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.orderId,
    this.serviceRoundId,
    required this.dispatchType,
    required this.status,
    required this.encryptedPayloadBlob,
    required this.encryptionVersion,
    this.destinationFingerprint,
    this.destinationDisplayLabel,
    this.transportKind,
    this.paperWidth,
    required this.payloadVersion,
    required this.documentVersion,
    required this.rasterVersion,
    required this.attemptCount,
    this.nextAttemptAt,
    this.lastAttemptAt,
    this.lastErrorCode,
    this.serverClaimExpiresAt,
    this.pendingServerAckStatus,
    required this.serverAckAttemptCount,
    this.serverAckNextAttemptAt,
    this.serverAckLastErrorCode,
    required this.createdAt,
    required this.updatedAt,
    this.transportAcceptedAt,
    this.serverAcknowledgedAt,
    this.reviewedAt,
    this.reprintOfLocalJobId,
    this.supersededByDispatchId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_job_id'] = Variable<String>(localJobId);
    map['dispatch_id'] = Variable<String>(dispatchId);
    map['organization_id'] = Variable<String>(organizationId);
    map['restaurant_id'] = Variable<String>(restaurantId);
    map['branch_id'] = Variable<String>(branchId);
    map['device_id'] = Variable<String>(deviceId);
    map['order_id'] = Variable<String>(orderId);
    if (!nullToAbsent || serviceRoundId != null) {
      map['service_round_id'] = Variable<String>(serviceRoundId);
    }
    {
      map['dispatch_type'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterdispatchType.toSql(dispatchType),
      );
    }
    {
      map['status'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterstatus.toSql(status),
      );
    }
    map['encrypted_payload_blob'] = Variable<Uint8List>(encryptedPayloadBlob);
    map['encryption_version'] = Variable<int>(encryptionVersion);
    if (!nullToAbsent || destinationFingerprint != null) {
      map['destination_fingerprint'] = Variable<String>(destinationFingerprint);
    }
    if (!nullToAbsent || destinationDisplayLabel != null) {
      map['destination_display_label'] = Variable<String>(
        destinationDisplayLabel,
      );
    }
    if (!nullToAbsent || transportKind != null) {
      map['transport_kind'] = Variable<String>(transportKind);
    }
    if (!nullToAbsent || paperWidth != null) {
      map['paper_width'] = Variable<String>(paperWidth);
    }
    map['payload_version'] = Variable<int>(payloadVersion);
    map['document_version'] = Variable<int>(documentVersion);
    map['raster_version'] = Variable<int>(rasterVersion);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || serverClaimExpiresAt != null) {
      map['server_claim_expires_at'] = Variable<DateTime>(serverClaimExpiresAt);
    }
    if (!nullToAbsent || pendingServerAckStatus != null) {
      map['pending_server_ack_status'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterpendingServerAckStatusn.toSql(
          pendingServerAckStatus,
        ),
      );
    }
    map['server_ack_attempt_count'] = Variable<int>(serverAckAttemptCount);
    if (!nullToAbsent || serverAckNextAttemptAt != null) {
      map['server_ack_next_attempt_at'] = Variable<DateTime>(
        serverAckNextAttemptAt,
      );
    }
    if (!nullToAbsent || serverAckLastErrorCode != null) {
      map['server_ack_last_error_code'] = Variable<String>(
        serverAckLastErrorCode,
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || transportAcceptedAt != null) {
      map['transport_accepted_at'] = Variable<DateTime>(transportAcceptedAt);
    }
    if (!nullToAbsent || serverAcknowledgedAt != null) {
      map['server_acknowledged_at'] = Variable<DateTime>(serverAcknowledgedAt);
    }
    if (!nullToAbsent || reviewedAt != null) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt);
    }
    if (!nullToAbsent || reprintOfLocalJobId != null) {
      map['reprint_of_local_job_id'] = Variable<String>(reprintOfLocalJobId);
    }
    if (!nullToAbsent || supersededByDispatchId != null) {
      map['superseded_by_dispatch_id'] = Variable<String>(
        supersededByDispatchId,
      );
    }
    return map;
  }

  KitchenSpoolJobsCompanion toCompanion(bool nullToAbsent) {
    return KitchenSpoolJobsCompanion(
      localJobId: Value(localJobId),
      dispatchId: Value(dispatchId),
      organizationId: Value(organizationId),
      restaurantId: Value(restaurantId),
      branchId: Value(branchId),
      deviceId: Value(deviceId),
      orderId: Value(orderId),
      serviceRoundId: serviceRoundId == null && nullToAbsent
          ? const Value.absent()
          : Value(serviceRoundId),
      dispatchType: Value(dispatchType),
      status: Value(status),
      encryptedPayloadBlob: Value(encryptedPayloadBlob),
      encryptionVersion: Value(encryptionVersion),
      destinationFingerprint: destinationFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationFingerprint),
      destinationDisplayLabel: destinationDisplayLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationDisplayLabel),
      transportKind: transportKind == null && nullToAbsent
          ? const Value.absent()
          : Value(transportKind),
      paperWidth: paperWidth == null && nullToAbsent
          ? const Value.absent()
          : Value(paperWidth),
      payloadVersion: Value(payloadVersion),
      documentVersion: Value(documentVersion),
      rasterVersion: Value(rasterVersion),
      attemptCount: Value(attemptCount),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      serverClaimExpiresAt: serverClaimExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverClaimExpiresAt),
      pendingServerAckStatus: pendingServerAckStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingServerAckStatus),
      serverAckAttemptCount: Value(serverAckAttemptCount),
      serverAckNextAttemptAt: serverAckNextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverAckNextAttemptAt),
      serverAckLastErrorCode: serverAckLastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(serverAckLastErrorCode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      transportAcceptedAt: transportAcceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(transportAcceptedAt),
      serverAcknowledgedAt: serverAcknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(serverAcknowledgedAt),
      reviewedAt: reviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedAt),
      reprintOfLocalJobId: reprintOfLocalJobId == null && nullToAbsent
          ? const Value.absent()
          : Value(reprintOfLocalJobId),
      supersededByDispatchId: supersededByDispatchId == null && nullToAbsent
          ? const Value.absent()
          : Value(supersededByDispatchId),
    );
  }

  factory KitchenSpoolJobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KitchenSpoolJobRow(
      localJobId: serializer.fromJson<String>(json['localJobId']),
      dispatchId: serializer.fromJson<String>(json['dispatchId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      orderId: serializer.fromJson<String>(json['orderId']),
      serviceRoundId: serializer.fromJson<String?>(json['serviceRoundId']),
      dispatchType: serializer.fromJson<KitchenSpoolDispatchType>(
        json['dispatchType'],
      ),
      status: serializer.fromJson<KitchenSpoolJobStatus>(json['status']),
      encryptedPayloadBlob: serializer.fromJson<Uint8List>(
        json['encryptedPayloadBlob'],
      ),
      encryptionVersion: serializer.fromJson<int>(json['encryptionVersion']),
      destinationFingerprint: serializer.fromJson<String?>(
        json['destinationFingerprint'],
      ),
      destinationDisplayLabel: serializer.fromJson<String?>(
        json['destinationDisplayLabel'],
      ),
      transportKind: serializer.fromJson<String?>(json['transportKind']),
      paperWidth: serializer.fromJson<String?>(json['paperWidth']),
      payloadVersion: serializer.fromJson<int>(json['payloadVersion']),
      documentVersion: serializer.fromJson<int>(json['documentVersion']),
      rasterVersion: serializer.fromJson<int>(json['rasterVersion']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      serverClaimExpiresAt: serializer.fromJson<DateTime?>(
        json['serverClaimExpiresAt'],
      ),
      pendingServerAckStatus: serializer.fromJson<KitchenServerAckStatus?>(
        json['pendingServerAckStatus'],
      ),
      serverAckAttemptCount: serializer.fromJson<int>(
        json['serverAckAttemptCount'],
      ),
      serverAckNextAttemptAt: serializer.fromJson<DateTime?>(
        json['serverAckNextAttemptAt'],
      ),
      serverAckLastErrorCode: serializer.fromJson<String?>(
        json['serverAckLastErrorCode'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      transportAcceptedAt: serializer.fromJson<DateTime?>(
        json['transportAcceptedAt'],
      ),
      serverAcknowledgedAt: serializer.fromJson<DateTime?>(
        json['serverAcknowledgedAt'],
      ),
      reviewedAt: serializer.fromJson<DateTime?>(json['reviewedAt']),
      reprintOfLocalJobId: serializer.fromJson<String?>(
        json['reprintOfLocalJobId'],
      ),
      supersededByDispatchId: serializer.fromJson<String?>(
        json['supersededByDispatchId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localJobId': serializer.toJson<String>(localJobId),
      'dispatchId': serializer.toJson<String>(dispatchId),
      'organizationId': serializer.toJson<String>(organizationId),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'branchId': serializer.toJson<String>(branchId),
      'deviceId': serializer.toJson<String>(deviceId),
      'orderId': serializer.toJson<String>(orderId),
      'serviceRoundId': serializer.toJson<String?>(serviceRoundId),
      'dispatchType': serializer.toJson<KitchenSpoolDispatchType>(dispatchType),
      'status': serializer.toJson<KitchenSpoolJobStatus>(status),
      'encryptedPayloadBlob': serializer.toJson<Uint8List>(
        encryptedPayloadBlob,
      ),
      'encryptionVersion': serializer.toJson<int>(encryptionVersion),
      'destinationFingerprint': serializer.toJson<String?>(
        destinationFingerprint,
      ),
      'destinationDisplayLabel': serializer.toJson<String?>(
        destinationDisplayLabel,
      ),
      'transportKind': serializer.toJson<String?>(transportKind),
      'paperWidth': serializer.toJson<String?>(paperWidth),
      'payloadVersion': serializer.toJson<int>(payloadVersion),
      'documentVersion': serializer.toJson<int>(documentVersion),
      'rasterVersion': serializer.toJson<int>(rasterVersion),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'serverClaimExpiresAt': serializer.toJson<DateTime?>(
        serverClaimExpiresAt,
      ),
      'pendingServerAckStatus': serializer.toJson<KitchenServerAckStatus?>(
        pendingServerAckStatus,
      ),
      'serverAckAttemptCount': serializer.toJson<int>(serverAckAttemptCount),
      'serverAckNextAttemptAt': serializer.toJson<DateTime?>(
        serverAckNextAttemptAt,
      ),
      'serverAckLastErrorCode': serializer.toJson<String?>(
        serverAckLastErrorCode,
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'transportAcceptedAt': serializer.toJson<DateTime?>(transportAcceptedAt),
      'serverAcknowledgedAt': serializer.toJson<DateTime?>(
        serverAcknowledgedAt,
      ),
      'reviewedAt': serializer.toJson<DateTime?>(reviewedAt),
      'reprintOfLocalJobId': serializer.toJson<String?>(reprintOfLocalJobId),
      'supersededByDispatchId': serializer.toJson<String?>(
        supersededByDispatchId,
      ),
    };
  }

  KitchenSpoolJobRow copyWith({
    String? localJobId,
    String? dispatchId,
    String? organizationId,
    String? restaurantId,
    String? branchId,
    String? deviceId,
    String? orderId,
    Value<String?> serviceRoundId = const Value.absent(),
    KitchenSpoolDispatchType? dispatchType,
    KitchenSpoolJobStatus? status,
    Uint8List? encryptedPayloadBlob,
    int? encryptionVersion,
    Value<String?> destinationFingerprint = const Value.absent(),
    Value<String?> destinationDisplayLabel = const Value.absent(),
    Value<String?> transportKind = const Value.absent(),
    Value<String?> paperWidth = const Value.absent(),
    int? payloadVersion,
    int? documentVersion,
    int? rasterVersion,
    int? attemptCount,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<DateTime?> serverClaimExpiresAt = const Value.absent(),
    Value<KitchenServerAckStatus?> pendingServerAckStatus =
        const Value.absent(),
    int? serverAckAttemptCount,
    Value<DateTime?> serverAckNextAttemptAt = const Value.absent(),
    Value<String?> serverAckLastErrorCode = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> transportAcceptedAt = const Value.absent(),
    Value<DateTime?> serverAcknowledgedAt = const Value.absent(),
    Value<DateTime?> reviewedAt = const Value.absent(),
    Value<String?> reprintOfLocalJobId = const Value.absent(),
    Value<String?> supersededByDispatchId = const Value.absent(),
  }) => KitchenSpoolJobRow(
    localJobId: localJobId ?? this.localJobId,
    dispatchId: dispatchId ?? this.dispatchId,
    organizationId: organizationId ?? this.organizationId,
    restaurantId: restaurantId ?? this.restaurantId,
    branchId: branchId ?? this.branchId,
    deviceId: deviceId ?? this.deviceId,
    orderId: orderId ?? this.orderId,
    serviceRoundId: serviceRoundId.present
        ? serviceRoundId.value
        : this.serviceRoundId,
    dispatchType: dispatchType ?? this.dispatchType,
    status: status ?? this.status,
    encryptedPayloadBlob: encryptedPayloadBlob ?? this.encryptedPayloadBlob,
    encryptionVersion: encryptionVersion ?? this.encryptionVersion,
    destinationFingerprint: destinationFingerprint.present
        ? destinationFingerprint.value
        : this.destinationFingerprint,
    destinationDisplayLabel: destinationDisplayLabel.present
        ? destinationDisplayLabel.value
        : this.destinationDisplayLabel,
    transportKind: transportKind.present
        ? transportKind.value
        : this.transportKind,
    paperWidth: paperWidth.present ? paperWidth.value : this.paperWidth,
    payloadVersion: payloadVersion ?? this.payloadVersion,
    documentVersion: documentVersion ?? this.documentVersion,
    rasterVersion: rasterVersion ?? this.rasterVersion,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    serverClaimExpiresAt: serverClaimExpiresAt.present
        ? serverClaimExpiresAt.value
        : this.serverClaimExpiresAt,
    pendingServerAckStatus: pendingServerAckStatus.present
        ? pendingServerAckStatus.value
        : this.pendingServerAckStatus,
    serverAckAttemptCount: serverAckAttemptCount ?? this.serverAckAttemptCount,
    serverAckNextAttemptAt: serverAckNextAttemptAt.present
        ? serverAckNextAttemptAt.value
        : this.serverAckNextAttemptAt,
    serverAckLastErrorCode: serverAckLastErrorCode.present
        ? serverAckLastErrorCode.value
        : this.serverAckLastErrorCode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    transportAcceptedAt: transportAcceptedAt.present
        ? transportAcceptedAt.value
        : this.transportAcceptedAt,
    serverAcknowledgedAt: serverAcknowledgedAt.present
        ? serverAcknowledgedAt.value
        : this.serverAcknowledgedAt,
    reviewedAt: reviewedAt.present ? reviewedAt.value : this.reviewedAt,
    reprintOfLocalJobId: reprintOfLocalJobId.present
        ? reprintOfLocalJobId.value
        : this.reprintOfLocalJobId,
    supersededByDispatchId: supersededByDispatchId.present
        ? supersededByDispatchId.value
        : this.supersededByDispatchId,
  );
  KitchenSpoolJobRow copyWithCompanion(KitchenSpoolJobsCompanion data) {
    return KitchenSpoolJobRow(
      localJobId: data.localJobId.present
          ? data.localJobId.value
          : this.localJobId,
      dispatchId: data.dispatchId.present
          ? data.dispatchId.value
          : this.dispatchId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      restaurantId: data.restaurantId.present
          ? data.restaurantId.value
          : this.restaurantId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      serviceRoundId: data.serviceRoundId.present
          ? data.serviceRoundId.value
          : this.serviceRoundId,
      dispatchType: data.dispatchType.present
          ? data.dispatchType.value
          : this.dispatchType,
      status: data.status.present ? data.status.value : this.status,
      encryptedPayloadBlob: data.encryptedPayloadBlob.present
          ? data.encryptedPayloadBlob.value
          : this.encryptedPayloadBlob,
      encryptionVersion: data.encryptionVersion.present
          ? data.encryptionVersion.value
          : this.encryptionVersion,
      destinationFingerprint: data.destinationFingerprint.present
          ? data.destinationFingerprint.value
          : this.destinationFingerprint,
      destinationDisplayLabel: data.destinationDisplayLabel.present
          ? data.destinationDisplayLabel.value
          : this.destinationDisplayLabel,
      transportKind: data.transportKind.present
          ? data.transportKind.value
          : this.transportKind,
      paperWidth: data.paperWidth.present
          ? data.paperWidth.value
          : this.paperWidth,
      payloadVersion: data.payloadVersion.present
          ? data.payloadVersion.value
          : this.payloadVersion,
      documentVersion: data.documentVersion.present
          ? data.documentVersion.value
          : this.documentVersion,
      rasterVersion: data.rasterVersion.present
          ? data.rasterVersion.value
          : this.rasterVersion,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      serverClaimExpiresAt: data.serverClaimExpiresAt.present
          ? data.serverClaimExpiresAt.value
          : this.serverClaimExpiresAt,
      pendingServerAckStatus: data.pendingServerAckStatus.present
          ? data.pendingServerAckStatus.value
          : this.pendingServerAckStatus,
      serverAckAttemptCount: data.serverAckAttemptCount.present
          ? data.serverAckAttemptCount.value
          : this.serverAckAttemptCount,
      serverAckNextAttemptAt: data.serverAckNextAttemptAt.present
          ? data.serverAckNextAttemptAt.value
          : this.serverAckNextAttemptAt,
      serverAckLastErrorCode: data.serverAckLastErrorCode.present
          ? data.serverAckLastErrorCode.value
          : this.serverAckLastErrorCode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      transportAcceptedAt: data.transportAcceptedAt.present
          ? data.transportAcceptedAt.value
          : this.transportAcceptedAt,
      serverAcknowledgedAt: data.serverAcknowledgedAt.present
          ? data.serverAcknowledgedAt.value
          : this.serverAcknowledgedAt,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      reprintOfLocalJobId: data.reprintOfLocalJobId.present
          ? data.reprintOfLocalJobId.value
          : this.reprintOfLocalJobId,
      supersededByDispatchId: data.supersededByDispatchId.present
          ? data.supersededByDispatchId.value
          : this.supersededByDispatchId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KitchenSpoolJobRow(')
          ..write('localJobId: $localJobId, ')
          ..write('dispatchId: $dispatchId, ')
          ..write('organizationId: $organizationId, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('deviceId: $deviceId, ')
          ..write('orderId: $orderId, ')
          ..write('serviceRoundId: $serviceRoundId, ')
          ..write('dispatchType: $dispatchType, ')
          ..write('status: $status, ')
          ..write('encryptedPayloadBlob: $encryptedPayloadBlob, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('destinationFingerprint: $destinationFingerprint, ')
          ..write('destinationDisplayLabel: $destinationDisplayLabel, ')
          ..write('transportKind: $transportKind, ')
          ..write('paperWidth: $paperWidth, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('documentVersion: $documentVersion, ')
          ..write('rasterVersion: $rasterVersion, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('serverClaimExpiresAt: $serverClaimExpiresAt, ')
          ..write('pendingServerAckStatus: $pendingServerAckStatus, ')
          ..write('serverAckAttemptCount: $serverAckAttemptCount, ')
          ..write('serverAckNextAttemptAt: $serverAckNextAttemptAt, ')
          ..write('serverAckLastErrorCode: $serverAckLastErrorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('transportAcceptedAt: $transportAcceptedAt, ')
          ..write('serverAcknowledgedAt: $serverAcknowledgedAt, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('reprintOfLocalJobId: $reprintOfLocalJobId, ')
          ..write('supersededByDispatchId: $supersededByDispatchId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    localJobId,
    dispatchId,
    organizationId,
    restaurantId,
    branchId,
    deviceId,
    orderId,
    serviceRoundId,
    dispatchType,
    status,
    $driftBlobEquality.hash(encryptedPayloadBlob),
    encryptionVersion,
    destinationFingerprint,
    destinationDisplayLabel,
    transportKind,
    paperWidth,
    payloadVersion,
    documentVersion,
    rasterVersion,
    attemptCount,
    nextAttemptAt,
    lastAttemptAt,
    lastErrorCode,
    serverClaimExpiresAt,
    pendingServerAckStatus,
    serverAckAttemptCount,
    serverAckNextAttemptAt,
    serverAckLastErrorCode,
    createdAt,
    updatedAt,
    transportAcceptedAt,
    serverAcknowledgedAt,
    reviewedAt,
    reprintOfLocalJobId,
    supersededByDispatchId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KitchenSpoolJobRow &&
          other.localJobId == this.localJobId &&
          other.dispatchId == this.dispatchId &&
          other.organizationId == this.organizationId &&
          other.restaurantId == this.restaurantId &&
          other.branchId == this.branchId &&
          other.deviceId == this.deviceId &&
          other.orderId == this.orderId &&
          other.serviceRoundId == this.serviceRoundId &&
          other.dispatchType == this.dispatchType &&
          other.status == this.status &&
          $driftBlobEquality.equals(
            other.encryptedPayloadBlob,
            this.encryptedPayloadBlob,
          ) &&
          other.encryptionVersion == this.encryptionVersion &&
          other.destinationFingerprint == this.destinationFingerprint &&
          other.destinationDisplayLabel == this.destinationDisplayLabel &&
          other.transportKind == this.transportKind &&
          other.paperWidth == this.paperWidth &&
          other.payloadVersion == this.payloadVersion &&
          other.documentVersion == this.documentVersion &&
          other.rasterVersion == this.rasterVersion &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.serverClaimExpiresAt == this.serverClaimExpiresAt &&
          other.pendingServerAckStatus == this.pendingServerAckStatus &&
          other.serverAckAttemptCount == this.serverAckAttemptCount &&
          other.serverAckNextAttemptAt == this.serverAckNextAttemptAt &&
          other.serverAckLastErrorCode == this.serverAckLastErrorCode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.transportAcceptedAt == this.transportAcceptedAt &&
          other.serverAcknowledgedAt == this.serverAcknowledgedAt &&
          other.reviewedAt == this.reviewedAt &&
          other.reprintOfLocalJobId == this.reprintOfLocalJobId &&
          other.supersededByDispatchId == this.supersededByDispatchId);
}

class KitchenSpoolJobsCompanion extends UpdateCompanion<KitchenSpoolJobRow> {
  final Value<String> localJobId;
  final Value<String> dispatchId;
  final Value<String> organizationId;
  final Value<String> restaurantId;
  final Value<String> branchId;
  final Value<String> deviceId;
  final Value<String> orderId;
  final Value<String?> serviceRoundId;
  final Value<KitchenSpoolDispatchType> dispatchType;
  final Value<KitchenSpoolJobStatus> status;
  final Value<Uint8List> encryptedPayloadBlob;
  final Value<int> encryptionVersion;
  final Value<String?> destinationFingerprint;
  final Value<String?> destinationDisplayLabel;
  final Value<String?> transportKind;
  final Value<String?> paperWidth;
  final Value<int> payloadVersion;
  final Value<int> documentVersion;
  final Value<int> rasterVersion;
  final Value<int> attemptCount;
  final Value<DateTime?> nextAttemptAt;
  final Value<DateTime?> lastAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<DateTime?> serverClaimExpiresAt;
  final Value<KitchenServerAckStatus?> pendingServerAckStatus;
  final Value<int> serverAckAttemptCount;
  final Value<DateTime?> serverAckNextAttemptAt;
  final Value<String?> serverAckLastErrorCode;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> transportAcceptedAt;
  final Value<DateTime?> serverAcknowledgedAt;
  final Value<DateTime?> reviewedAt;
  final Value<String?> reprintOfLocalJobId;
  final Value<String?> supersededByDispatchId;
  final Value<int> rowid;
  const KitchenSpoolJobsCompanion({
    this.localJobId = const Value.absent(),
    this.dispatchId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.orderId = const Value.absent(),
    this.serviceRoundId = const Value.absent(),
    this.dispatchType = const Value.absent(),
    this.status = const Value.absent(),
    this.encryptedPayloadBlob = const Value.absent(),
    this.encryptionVersion = const Value.absent(),
    this.destinationFingerprint = const Value.absent(),
    this.destinationDisplayLabel = const Value.absent(),
    this.transportKind = const Value.absent(),
    this.paperWidth = const Value.absent(),
    this.payloadVersion = const Value.absent(),
    this.documentVersion = const Value.absent(),
    this.rasterVersion = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.serverClaimExpiresAt = const Value.absent(),
    this.pendingServerAckStatus = const Value.absent(),
    this.serverAckAttemptCount = const Value.absent(),
    this.serverAckNextAttemptAt = const Value.absent(),
    this.serverAckLastErrorCode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.transportAcceptedAt = const Value.absent(),
    this.serverAcknowledgedAt = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.reprintOfLocalJobId = const Value.absent(),
    this.supersededByDispatchId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KitchenSpoolJobsCompanion.insert({
    required String localJobId,
    required String dispatchId,
    required String organizationId,
    required String restaurantId,
    required String branchId,
    required String deviceId,
    required String orderId,
    this.serviceRoundId = const Value.absent(),
    required KitchenSpoolDispatchType dispatchType,
    this.status = const Value.absent(),
    required Uint8List encryptedPayloadBlob,
    required int encryptionVersion,
    this.destinationFingerprint = const Value.absent(),
    this.destinationDisplayLabel = const Value.absent(),
    this.transportKind = const Value.absent(),
    this.paperWidth = const Value.absent(),
    required int payloadVersion,
    required int documentVersion,
    required int rasterVersion,
    this.attemptCount = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.serverClaimExpiresAt = const Value.absent(),
    this.pendingServerAckStatus = const Value.absent(),
    this.serverAckAttemptCount = const Value.absent(),
    this.serverAckNextAttemptAt = const Value.absent(),
    this.serverAckLastErrorCode = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.transportAcceptedAt = const Value.absent(),
    this.serverAcknowledgedAt = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.reprintOfLocalJobId = const Value.absent(),
    this.supersededByDispatchId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : localJobId = Value(localJobId),
       dispatchId = Value(dispatchId),
       organizationId = Value(organizationId),
       restaurantId = Value(restaurantId),
       branchId = Value(branchId),
       deviceId = Value(deviceId),
       orderId = Value(orderId),
       dispatchType = Value(dispatchType),
       encryptedPayloadBlob = Value(encryptedPayloadBlob),
       encryptionVersion = Value(encryptionVersion),
       payloadVersion = Value(payloadVersion),
       documentVersion = Value(documentVersion),
       rasterVersion = Value(rasterVersion),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<KitchenSpoolJobRow> custom({
    Expression<String>? localJobId,
    Expression<String>? dispatchId,
    Expression<String>? organizationId,
    Expression<String>? restaurantId,
    Expression<String>? branchId,
    Expression<String>? deviceId,
    Expression<String>? orderId,
    Expression<String>? serviceRoundId,
    Expression<String>? dispatchType,
    Expression<String>? status,
    Expression<Uint8List>? encryptedPayloadBlob,
    Expression<int>? encryptionVersion,
    Expression<String>? destinationFingerprint,
    Expression<String>? destinationDisplayLabel,
    Expression<String>? transportKind,
    Expression<String>? paperWidth,
    Expression<int>? payloadVersion,
    Expression<int>? documentVersion,
    Expression<int>? rasterVersion,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAt,
    Expression<DateTime>? lastAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<DateTime>? serverClaimExpiresAt,
    Expression<String>? pendingServerAckStatus,
    Expression<int>? serverAckAttemptCount,
    Expression<DateTime>? serverAckNextAttemptAt,
    Expression<String>? serverAckLastErrorCode,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? transportAcceptedAt,
    Expression<DateTime>? serverAcknowledgedAt,
    Expression<DateTime>? reviewedAt,
    Expression<String>? reprintOfLocalJobId,
    Expression<String>? supersededByDispatchId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localJobId != null) 'local_job_id': localJobId,
      if (dispatchId != null) 'dispatch_id': dispatchId,
      if (organizationId != null) 'organization_id': organizationId,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (branchId != null) 'branch_id': branchId,
      if (deviceId != null) 'device_id': deviceId,
      if (orderId != null) 'order_id': orderId,
      if (serviceRoundId != null) 'service_round_id': serviceRoundId,
      if (dispatchType != null) 'dispatch_type': dispatchType,
      if (status != null) 'status': status,
      if (encryptedPayloadBlob != null)
        'encrypted_payload_blob': encryptedPayloadBlob,
      if (encryptionVersion != null) 'encryption_version': encryptionVersion,
      if (destinationFingerprint != null)
        'destination_fingerprint': destinationFingerprint,
      if (destinationDisplayLabel != null)
        'destination_display_label': destinationDisplayLabel,
      if (transportKind != null) 'transport_kind': transportKind,
      if (paperWidth != null) 'paper_width': paperWidth,
      if (payloadVersion != null) 'payload_version': payloadVersion,
      if (documentVersion != null) 'document_version': documentVersion,
      if (rasterVersion != null) 'raster_version': rasterVersion,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (serverClaimExpiresAt != null)
        'server_claim_expires_at': serverClaimExpiresAt,
      if (pendingServerAckStatus != null)
        'pending_server_ack_status': pendingServerAckStatus,
      if (serverAckAttemptCount != null)
        'server_ack_attempt_count': serverAckAttemptCount,
      if (serverAckNextAttemptAt != null)
        'server_ack_next_attempt_at': serverAckNextAttemptAt,
      if (serverAckLastErrorCode != null)
        'server_ack_last_error_code': serverAckLastErrorCode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (transportAcceptedAt != null)
        'transport_accepted_at': transportAcceptedAt,
      if (serverAcknowledgedAt != null)
        'server_acknowledged_at': serverAcknowledgedAt,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (reprintOfLocalJobId != null)
        'reprint_of_local_job_id': reprintOfLocalJobId,
      if (supersededByDispatchId != null)
        'superseded_by_dispatch_id': supersededByDispatchId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KitchenSpoolJobsCompanion copyWith({
    Value<String>? localJobId,
    Value<String>? dispatchId,
    Value<String>? organizationId,
    Value<String>? restaurantId,
    Value<String>? branchId,
    Value<String>? deviceId,
    Value<String>? orderId,
    Value<String?>? serviceRoundId,
    Value<KitchenSpoolDispatchType>? dispatchType,
    Value<KitchenSpoolJobStatus>? status,
    Value<Uint8List>? encryptedPayloadBlob,
    Value<int>? encryptionVersion,
    Value<String?>? destinationFingerprint,
    Value<String?>? destinationDisplayLabel,
    Value<String?>? transportKind,
    Value<String?>? paperWidth,
    Value<int>? payloadVersion,
    Value<int>? documentVersion,
    Value<int>? rasterVersion,
    Value<int>? attemptCount,
    Value<DateTime?>? nextAttemptAt,
    Value<DateTime?>? lastAttemptAt,
    Value<String?>? lastErrorCode,
    Value<DateTime?>? serverClaimExpiresAt,
    Value<KitchenServerAckStatus?>? pendingServerAckStatus,
    Value<int>? serverAckAttemptCount,
    Value<DateTime?>? serverAckNextAttemptAt,
    Value<String?>? serverAckLastErrorCode,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? transportAcceptedAt,
    Value<DateTime?>? serverAcknowledgedAt,
    Value<DateTime?>? reviewedAt,
    Value<String?>? reprintOfLocalJobId,
    Value<String?>? supersededByDispatchId,
    Value<int>? rowid,
  }) {
    return KitchenSpoolJobsCompanion(
      localJobId: localJobId ?? this.localJobId,
      dispatchId: dispatchId ?? this.dispatchId,
      organizationId: organizationId ?? this.organizationId,
      restaurantId: restaurantId ?? this.restaurantId,
      branchId: branchId ?? this.branchId,
      deviceId: deviceId ?? this.deviceId,
      orderId: orderId ?? this.orderId,
      serviceRoundId: serviceRoundId ?? this.serviceRoundId,
      dispatchType: dispatchType ?? this.dispatchType,
      status: status ?? this.status,
      encryptedPayloadBlob: encryptedPayloadBlob ?? this.encryptedPayloadBlob,
      encryptionVersion: encryptionVersion ?? this.encryptionVersion,
      destinationFingerprint:
          destinationFingerprint ?? this.destinationFingerprint,
      destinationDisplayLabel:
          destinationDisplayLabel ?? this.destinationDisplayLabel,
      transportKind: transportKind ?? this.transportKind,
      paperWidth: paperWidth ?? this.paperWidth,
      payloadVersion: payloadVersion ?? this.payloadVersion,
      documentVersion: documentVersion ?? this.documentVersion,
      rasterVersion: rasterVersion ?? this.rasterVersion,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      serverClaimExpiresAt: serverClaimExpiresAt ?? this.serverClaimExpiresAt,
      pendingServerAckStatus:
          pendingServerAckStatus ?? this.pendingServerAckStatus,
      serverAckAttemptCount:
          serverAckAttemptCount ?? this.serverAckAttemptCount,
      serverAckNextAttemptAt:
          serverAckNextAttemptAt ?? this.serverAckNextAttemptAt,
      serverAckLastErrorCode:
          serverAckLastErrorCode ?? this.serverAckLastErrorCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      transportAcceptedAt: transportAcceptedAt ?? this.transportAcceptedAt,
      serverAcknowledgedAt: serverAcknowledgedAt ?? this.serverAcknowledgedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reprintOfLocalJobId: reprintOfLocalJobId ?? this.reprintOfLocalJobId,
      supersededByDispatchId:
          supersededByDispatchId ?? this.supersededByDispatchId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localJobId.present) {
      map['local_job_id'] = Variable<String>(localJobId.value);
    }
    if (dispatchId.present) {
      map['dispatch_id'] = Variable<String>(dispatchId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (serviceRoundId.present) {
      map['service_round_id'] = Variable<String>(serviceRoundId.value);
    }
    if (dispatchType.present) {
      map['dispatch_type'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterdispatchType.toSql(dispatchType.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterstatus.toSql(status.value),
      );
    }
    if (encryptedPayloadBlob.present) {
      map['encrypted_payload_blob'] = Variable<Uint8List>(
        encryptedPayloadBlob.value,
      );
    }
    if (encryptionVersion.present) {
      map['encryption_version'] = Variable<int>(encryptionVersion.value);
    }
    if (destinationFingerprint.present) {
      map['destination_fingerprint'] = Variable<String>(
        destinationFingerprint.value,
      );
    }
    if (destinationDisplayLabel.present) {
      map['destination_display_label'] = Variable<String>(
        destinationDisplayLabel.value,
      );
    }
    if (transportKind.present) {
      map['transport_kind'] = Variable<String>(transportKind.value);
    }
    if (paperWidth.present) {
      map['paper_width'] = Variable<String>(paperWidth.value);
    }
    if (payloadVersion.present) {
      map['payload_version'] = Variable<int>(payloadVersion.value);
    }
    if (documentVersion.present) {
      map['document_version'] = Variable<int>(documentVersion.value);
    }
    if (rasterVersion.present) {
      map['raster_version'] = Variable<int>(rasterVersion.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (serverClaimExpiresAt.present) {
      map['server_claim_expires_at'] = Variable<DateTime>(
        serverClaimExpiresAt.value,
      );
    }
    if (pendingServerAckStatus.present) {
      map['pending_server_ack_status'] = Variable<String>(
        $KitchenSpoolJobsTable.$converterpendingServerAckStatusn.toSql(
          pendingServerAckStatus.value,
        ),
      );
    }
    if (serverAckAttemptCount.present) {
      map['server_ack_attempt_count'] = Variable<int>(
        serverAckAttemptCount.value,
      );
    }
    if (serverAckNextAttemptAt.present) {
      map['server_ack_next_attempt_at'] = Variable<DateTime>(
        serverAckNextAttemptAt.value,
      );
    }
    if (serverAckLastErrorCode.present) {
      map['server_ack_last_error_code'] = Variable<String>(
        serverAckLastErrorCode.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (transportAcceptedAt.present) {
      map['transport_accepted_at'] = Variable<DateTime>(
        transportAcceptedAt.value,
      );
    }
    if (serverAcknowledgedAt.present) {
      map['server_acknowledged_at'] = Variable<DateTime>(
        serverAcknowledgedAt.value,
      );
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<DateTime>(reviewedAt.value);
    }
    if (reprintOfLocalJobId.present) {
      map['reprint_of_local_job_id'] = Variable<String>(
        reprintOfLocalJobId.value,
      );
    }
    if (supersededByDispatchId.present) {
      map['superseded_by_dispatch_id'] = Variable<String>(
        supersededByDispatchId.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KitchenSpoolJobsCompanion(')
          ..write('localJobId: $localJobId, ')
          ..write('dispatchId: $dispatchId, ')
          ..write('organizationId: $organizationId, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('branchId: $branchId, ')
          ..write('deviceId: $deviceId, ')
          ..write('orderId: $orderId, ')
          ..write('serviceRoundId: $serviceRoundId, ')
          ..write('dispatchType: $dispatchType, ')
          ..write('status: $status, ')
          ..write('encryptedPayloadBlob: $encryptedPayloadBlob, ')
          ..write('encryptionVersion: $encryptionVersion, ')
          ..write('destinationFingerprint: $destinationFingerprint, ')
          ..write('destinationDisplayLabel: $destinationDisplayLabel, ')
          ..write('transportKind: $transportKind, ')
          ..write('paperWidth: $paperWidth, ')
          ..write('payloadVersion: $payloadVersion, ')
          ..write('documentVersion: $documentVersion, ')
          ..write('rasterVersion: $rasterVersion, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('serverClaimExpiresAt: $serverClaimExpiresAt, ')
          ..write('pendingServerAckStatus: $pendingServerAckStatus, ')
          ..write('serverAckAttemptCount: $serverAckAttemptCount, ')
          ..write('serverAckNextAttemptAt: $serverAckNextAttemptAt, ')
          ..write('serverAckLastErrorCode: $serverAckLastErrorCode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('transportAcceptedAt: $transportAcceptedAt, ')
          ..write('serverAcknowledgedAt: $serverAcknowledgedAt, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('reprintOfLocalJobId: $reprintOfLocalJobId, ')
          ..write('supersededByDispatchId: $supersededByDispatchId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $OutboxOperationsTable outboxOperations = $OutboxOperationsTable(
    this,
  );
  late final $ProcessedPullLogTable processedPullLog = $ProcessedPullLogTable(
    this,
  );
  late final $MenuCategoriesTable menuCategories = $MenuCategoriesTable(this);
  late final $MenuItemsTable menuItems = $MenuItemsTable(this);
  late final $ItemSizesTable itemSizes = $ItemSizesTable(this);
  late final $ItemVariantsTable itemVariants = $ItemVariantsTable(this);
  late final $ModifiersTable modifiers = $ModifiersTable(this);
  late final $ModifierOptionsTable modifierOptions = $ModifierOptionsTable(
    this,
  );
  late final $PrintJobsTable printJobs = $PrintJobsTable(this);
  late final $KitchenSpoolJobsTable kitchenSpoolJobs = $KitchenSpoolJobsTable(
    this,
  );
  late final Index kitchenSpoolRunnableIdx = Index(
    'kitchen_spool_runnable_idx',
    'CREATE INDEX kitchen_spool_runnable_idx ON kitchen_spool_jobs (device_id, branch_id, status, next_attempt_at, created_at)',
  );
  late final Index kitchenSpoolDestinationIdx = Index(
    'kitchen_spool_destination_idx',
    'CREATE INDEX kitchen_spool_destination_idx ON kitchen_spool_jobs (destination_fingerprint, status)',
  );
  late final Index kitchenSpoolUnresolvedIdx = Index(
    'kitchen_spool_unresolved_idx',
    'CREATE INDEX kitchen_spool_unresolved_idx ON kitchen_spool_jobs (device_id, branch_id, status)',
  );
  late final Index kitchenSpoolPendingAckIdx = Index(
    'kitchen_spool_pending_ack_idx',
    'CREATE INDEX kitchen_spool_pending_ack_idx ON kitchen_spool_jobs (device_id, branch_id, pending_server_ack_status, server_ack_next_attempt_at)',
  );
  late final Index kitchenSpoolRetentionIdx = Index(
    'kitchen_spool_retention_idx',
    'CREATE INDEX kitchen_spool_retention_idx ON kitchen_spool_jobs (transport_accepted_at)',
  );
  late final Index kitchenSpoolOrderSequenceIdx = Index(
    'kitchen_spool_order_sequence_idx',
    'CREATE INDEX kitchen_spool_order_sequence_idx ON kitchen_spool_jobs (order_id, dispatch_type, created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    outboxOperations,
    processedPullLog,
    menuCategories,
    menuItems,
    itemSizes,
    itemVariants,
    modifiers,
    modifierOptions,
    printJobs,
    kitchenSpoolJobs,
    kitchenSpoolRunnableIdx,
    kitchenSpoolDestinationIdx,
    kitchenSpoolUnresolvedIdx,
    kitchenSpoolPendingAckIdx,
    kitchenSpoolRetentionIdx,
    kitchenSpoolOrderSequenceIdx,
  ];
}

typedef $$OutboxOperationsTableCreateCompanionBuilder =
    OutboxOperationsCompanion Function({
      required String id,
      required String deviceId,
      required String localOperationId,
      required String organizationId,
      Value<String?> restaurantId,
      Value<String?> branchId,
      Value<String?> stationId,
      required String operationType,
      required String targetEntity,
      required String targetId,
      required String payload,
      Value<String> dependsOn,
      required int baseRevision,
      Value<SyncOperationState> syncState,
      required DateTime clientCreatedAt,
      required DateTime clientUpdatedAt,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorClass,
      Value<int> rowid,
    });
typedef $$OutboxOperationsTableUpdateCompanionBuilder =
    OutboxOperationsCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<String> organizationId,
      Value<String?> restaurantId,
      Value<String?> branchId,
      Value<String?> stationId,
      Value<String> operationType,
      Value<String> targetEntity,
      Value<String> targetId,
      Value<String> payload,
      Value<String> dependsOn,
      Value<int> baseRevision,
      Value<SyncOperationState> syncState,
      Value<DateTime> clientCreatedAt,
      Value<DateTime> clientUpdatedAt,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorClass,
      Value<int> rowid,
    });

class $$OutboxOperationsTableFilterComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetEntity => $composableBuilder(
    column: $table.targetEntity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SyncOperationState, SyncOperationState, String>
  get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorClass => $composableBuilder(
    column: $table.lastErrorClass,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxOperationsTableOrderingComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetEntity => $composableBuilder(
    column: $table.targetEntity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependsOn => $composableBuilder(
    column: $table.dependsOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorClass => $composableBuilder(
    column: $table.lastErrorClass,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxOperationsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetEntity => $composableBuilder(
    column: $table.targetEntity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get dependsOn =>
      $composableBuilder(column: $table.dependsOn, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SyncOperationState, String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get clientCreatedAt => $composableBuilder(
    column: $table.clientCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorClass => $composableBuilder(
    column: $table.lastErrorClass,
    builder: (column) => column,
  );
}

class $$OutboxOperationsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $OutboxOperationsTable,
          OutboxOperation,
          $$OutboxOperationsTableFilterComposer,
          $$OutboxOperationsTableOrderingComposer,
          $$OutboxOperationsTableAnnotationComposer,
          $$OutboxOperationsTableCreateCompanionBuilder,
          $$OutboxOperationsTableUpdateCompanionBuilder,
          (
            OutboxOperation,
            BaseReferences<
              _$LocalDatabase,
              $OutboxOperationsTable,
              OutboxOperation
            >,
          ),
          OutboxOperation,
          PrefetchHooks Function()
        > {
  $$OutboxOperationsTableTableManager(
    _$LocalDatabase db,
    $OutboxOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String?> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<String> targetEntity = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> dependsOn = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<SyncOperationState> syncState = const Value.absent(),
                Value<DateTime> clientCreatedAt = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorClass = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion(
                id: id,
                deviceId: deviceId,
                localOperationId: localOperationId,
                organizationId: organizationId,
                restaurantId: restaurantId,
                branchId: branchId,
                stationId: stationId,
                operationType: operationType,
                targetEntity: targetEntity,
                targetId: targetId,
                payload: payload,
                dependsOn: dependsOn,
                baseRevision: baseRevision,
                syncState: syncState,
                clientCreatedAt: clientCreatedAt,
                clientUpdatedAt: clientUpdatedAt,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorClass: lastErrorClass,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                required String localOperationId,
                required String organizationId,
                Value<String?> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                required String operationType,
                required String targetEntity,
                required String targetId,
                required String payload,
                Value<String> dependsOn = const Value.absent(),
                required int baseRevision,
                Value<SyncOperationState> syncState = const Value.absent(),
                required DateTime clientCreatedAt,
                required DateTime clientUpdatedAt,
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorClass = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxOperationsCompanion.insert(
                id: id,
                deviceId: deviceId,
                localOperationId: localOperationId,
                organizationId: organizationId,
                restaurantId: restaurantId,
                branchId: branchId,
                stationId: stationId,
                operationType: operationType,
                targetEntity: targetEntity,
                targetId: targetId,
                payload: payload,
                dependsOn: dependsOn,
                baseRevision: baseRevision,
                syncState: syncState,
                clientCreatedAt: clientCreatedAt,
                clientUpdatedAt: clientUpdatedAt,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorClass: lastErrorClass,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $OutboxOperationsTable,
      OutboxOperation,
      $$OutboxOperationsTableFilterComposer,
      $$OutboxOperationsTableOrderingComposer,
      $$OutboxOperationsTableAnnotationComposer,
      $$OutboxOperationsTableCreateCompanionBuilder,
      $$OutboxOperationsTableUpdateCompanionBuilder,
      (
        OutboxOperation,
        BaseReferences<
          _$LocalDatabase,
          $OutboxOperationsTable,
          OutboxOperation
        >,
      ),
      OutboxOperation,
      PrefetchHooks Function()
    >;
typedef $$ProcessedPullLogTableCreateCompanionBuilder =
    ProcessedPullLogCompanion Function({
      required String id,
      required String deviceId,
      required String localOperationId,
      required DateTime appliedAt,
      Value<int> rowid,
    });
typedef $$ProcessedPullLogTableUpdateCompanionBuilder =
    ProcessedPullLogCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<DateTime> appliedAt,
      Value<int> rowid,
    });

class $$ProcessedPullLogTableFilterComposer
    extends Composer<_$LocalDatabase, $ProcessedPullLogTable> {
  $$ProcessedPullLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProcessedPullLogTableOrderingComposer
    extends Composer<_$LocalDatabase, $ProcessedPullLogTable> {
  $$ProcessedPullLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get appliedAt => $composableBuilder(
    column: $table.appliedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProcessedPullLogTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ProcessedPullLogTable> {
  $$ProcessedPullLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get appliedAt =>
      $composableBuilder(column: $table.appliedAt, builder: (column) => column);
}

class $$ProcessedPullLogTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ProcessedPullLogTable,
          ProcessedPullLogData,
          $$ProcessedPullLogTableFilterComposer,
          $$ProcessedPullLogTableOrderingComposer,
          $$ProcessedPullLogTableAnnotationComposer,
          $$ProcessedPullLogTableCreateCompanionBuilder,
          $$ProcessedPullLogTableUpdateCompanionBuilder,
          (
            ProcessedPullLogData,
            BaseReferences<
              _$LocalDatabase,
              $ProcessedPullLogTable,
              ProcessedPullLogData
            >,
          ),
          ProcessedPullLogData,
          PrefetchHooks Function()
        > {
  $$ProcessedPullLogTableTableManager(
    _$LocalDatabase db,
    $ProcessedPullLogTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessedPullLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessedPullLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessedPullLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<DateTime> appliedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessedPullLogCompanion(
                id: id,
                deviceId: deviceId,
                localOperationId: localOperationId,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                required String localOperationId,
                required DateTime appliedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProcessedPullLogCompanion.insert(
                id: id,
                deviceId: deviceId,
                localOperationId: localOperationId,
                appliedAt: appliedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProcessedPullLogTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ProcessedPullLogTable,
      ProcessedPullLogData,
      $$ProcessedPullLogTableFilterComposer,
      $$ProcessedPullLogTableOrderingComposer,
      $$ProcessedPullLogTableAnnotationComposer,
      $$ProcessedPullLogTableCreateCompanionBuilder,
      $$ProcessedPullLogTableUpdateCompanionBuilder,
      (
        ProcessedPullLogData,
        BaseReferences<
          _$LocalDatabase,
          $ProcessedPullLogTable,
          ProcessedPullLogData
        >,
      ),
      ProcessedPullLogData,
      PrefetchHooks Function()
    >;
typedef $$MenuCategoriesTableCreateCompanionBuilder =
    MenuCategoriesCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String name,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$MenuCategoriesTableUpdateCompanionBuilder =
    MenuCategoriesCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> name,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$MenuCategoriesTableReferences
    extends
        BaseReferences<_$LocalDatabase, $MenuCategoriesTable, MenuCategory> {
  $$MenuCategoriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$MenuItemsTable, List<MenuItem>>
  _menuItemsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.menuItems,
    aliasName: $_aliasNameGenerator(
      db.menuCategories.id,
      db.menuItems.menuCategoryId,
    ),
  );

  $$MenuItemsTableProcessedTableManager get menuItemsRefs {
    final manager = $$MenuItemsTableTableManager(
      $_db,
      $_db.menuItems,
    ).filter((f) => f.menuCategoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_menuItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MenuCategoriesTableFilterComposer
    extends Composer<_$LocalDatabase, $MenuCategoriesTable> {
  $$MenuCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> menuItemsRefs(
    Expression<bool> Function($$MenuItemsTableFilterComposer f) f,
  ) {
    final $$MenuItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.menuCategoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableFilterComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MenuCategoriesTableOrderingComposer
    extends Composer<_$LocalDatabase, $MenuCategoriesTable> {
  $$MenuCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MenuCategoriesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MenuCategoriesTable> {
  $$MenuCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> menuItemsRefs<T extends Object>(
    Expression<T> Function($$MenuItemsTableAnnotationComposer a) f,
  ) {
    final $$MenuItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.menuCategoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MenuCategoriesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MenuCategoriesTable,
          MenuCategory,
          $$MenuCategoriesTableFilterComposer,
          $$MenuCategoriesTableOrderingComposer,
          $$MenuCategoriesTableAnnotationComposer,
          $$MenuCategoriesTableCreateCompanionBuilder,
          $$MenuCategoriesTableUpdateCompanionBuilder,
          (MenuCategory, $$MenuCategoriesTableReferences),
          MenuCategory,
          PrefetchHooks Function({bool menuItemsRefs})
        > {
  $$MenuCategoriesTableTableManager(
    _$LocalDatabase db,
    $MenuCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MenuCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MenuCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MenuCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MenuCategoriesCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                name: name,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String name,
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MenuCategoriesCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                name: name,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MenuCategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({menuItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (menuItemsRefs) db.menuItems],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (menuItemsRefs)
                    await $_getPrefetchedData<
                      MenuCategory,
                      $MenuCategoriesTable,
                      MenuItem
                    >(
                      currentTable: table,
                      referencedTable: $$MenuCategoriesTableReferences
                          ._menuItemsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MenuCategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).menuItemsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.menuCategoryId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MenuCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MenuCategoriesTable,
      MenuCategory,
      $$MenuCategoriesTableFilterComposer,
      $$MenuCategoriesTableOrderingComposer,
      $$MenuCategoriesTableAnnotationComposer,
      $$MenuCategoriesTableCreateCompanionBuilder,
      $$MenuCategoriesTableUpdateCompanionBuilder,
      (MenuCategory, $$MenuCategoriesTableReferences),
      MenuCategory,
      PrefetchHooks Function({bool menuItemsRefs})
    >;
typedef $$MenuItemsTableCreateCompanionBuilder =
    MenuItemsCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String menuCategoryId,
      required String name,
      Value<String?> description,
      required int basePriceMinor,
      required String currencyCode,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$MenuItemsTableUpdateCompanionBuilder =
    MenuItemsCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> menuCategoryId,
      Value<String> name,
      Value<String?> description,
      Value<int> basePriceMinor,
      Value<String> currencyCode,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$MenuItemsTableReferences
    extends BaseReferences<_$LocalDatabase, $MenuItemsTable, MenuItem> {
  $$MenuItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MenuCategoriesTable _menuCategoryIdTable(_$LocalDatabase db) =>
      db.menuCategories.createAlias(
        $_aliasNameGenerator(db.menuItems.menuCategoryId, db.menuCategories.id),
      );

  $$MenuCategoriesTableProcessedTableManager get menuCategoryId {
    final $_column = $_itemColumn<String>('menu_category_id')!;

    final manager = $$MenuCategoriesTableTableManager(
      $_db,
      $_db.menuCategories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_menuCategoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ItemSizesTable, List<ItemSize>>
  _itemSizesRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.itemSizes,
    aliasName: $_aliasNameGenerator(db.menuItems.id, db.itemSizes.menuItemId),
  );

  $$ItemSizesTableProcessedTableManager get itemSizesRefs {
    final manager = $$ItemSizesTableTableManager(
      $_db,
      $_db.itemSizes,
    ).filter((f) => f.menuItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_itemSizesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ItemVariantsTable, List<ItemVariant>>
  _itemVariantsRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.itemVariants,
    aliasName: $_aliasNameGenerator(
      db.menuItems.id,
      db.itemVariants.menuItemId,
    ),
  );

  $$ItemVariantsTableProcessedTableManager get itemVariantsRefs {
    final manager = $$ItemVariantsTableTableManager(
      $_db,
      $_db.itemVariants,
    ).filter((f) => f.menuItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_itemVariantsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ModifiersTable, List<Modifier>>
  _modifiersRefsTable(_$LocalDatabase db) => MultiTypedResultKey.fromTable(
    db.modifiers,
    aliasName: $_aliasNameGenerator(db.menuItems.id, db.modifiers.menuItemId),
  );

  $$ModifiersTableProcessedTableManager get modifiersRefs {
    final manager = $$ModifiersTableTableManager(
      $_db,
      $_db.modifiers,
    ).filter((f) => f.menuItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_modifiersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MenuItemsTableFilterComposer
    extends Composer<_$LocalDatabase, $MenuItemsTable> {
  $$MenuItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get basePriceMinor => $composableBuilder(
    column: $table.basePriceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$MenuCategoriesTableFilterComposer get menuCategoryId {
    final $$MenuCategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuCategoryId,
      referencedTable: $db.menuCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuCategoriesTableFilterComposer(
            $db: $db,
            $table: $db.menuCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> itemSizesRefs(
    Expression<bool> Function($$ItemSizesTableFilterComposer f) f,
  ) {
    final $$ItemSizesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemSizes,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemSizesTableFilterComposer(
            $db: $db,
            $table: $db.itemSizes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> itemVariantsRefs(
    Expression<bool> Function($$ItemVariantsTableFilterComposer f) f,
  ) {
    final $$ItemVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemVariants,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemVariantsTableFilterComposer(
            $db: $db,
            $table: $db.itemVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> modifiersRefs(
    Expression<bool> Function($$ModifiersTableFilterComposer f) f,
  ) {
    final $$ModifiersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.modifiers,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifiersTableFilterComposer(
            $db: $db,
            $table: $db.modifiers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MenuItemsTableOrderingComposer
    extends Composer<_$LocalDatabase, $MenuItemsTable> {
  $$MenuItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get basePriceMinor => $composableBuilder(
    column: $table.basePriceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$MenuCategoriesTableOrderingComposer get menuCategoryId {
    final $$MenuCategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuCategoryId,
      referencedTable: $db.menuCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuCategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.menuCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MenuItemsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $MenuItemsTable> {
  $$MenuItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get basePriceMinor => $composableBuilder(
    column: $table.basePriceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$MenuCategoriesTableAnnotationComposer get menuCategoryId {
    final $$MenuCategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuCategoryId,
      referencedTable: $db.menuCategories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuCategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.menuCategories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> itemSizesRefs<T extends Object>(
    Expression<T> Function($$ItemSizesTableAnnotationComposer a) f,
  ) {
    final $$ItemSizesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemSizes,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemSizesTableAnnotationComposer(
            $db: $db,
            $table: $db.itemSizes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> itemVariantsRefs<T extends Object>(
    Expression<T> Function($$ItemVariantsTableAnnotationComposer a) f,
  ) {
    final $$ItemVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.itemVariants,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.itemVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> modifiersRefs<T extends Object>(
    Expression<T> Function($$ModifiersTableAnnotationComposer a) f,
  ) {
    final $$ModifiersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.modifiers,
      getReferencedColumn: (t) => t.menuItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifiersTableAnnotationComposer(
            $db: $db,
            $table: $db.modifiers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MenuItemsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $MenuItemsTable,
          MenuItem,
          $$MenuItemsTableFilterComposer,
          $$MenuItemsTableOrderingComposer,
          $$MenuItemsTableAnnotationComposer,
          $$MenuItemsTableCreateCompanionBuilder,
          $$MenuItemsTableUpdateCompanionBuilder,
          (MenuItem, $$MenuItemsTableReferences),
          MenuItem,
          PrefetchHooks Function({
            bool menuCategoryId,
            bool itemSizesRefs,
            bool itemVariantsRefs,
            bool modifiersRefs,
          })
        > {
  $$MenuItemsTableTableManager(_$LocalDatabase db, $MenuItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MenuItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MenuItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MenuItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> menuCategoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> basePriceMinor = const Value.absent(),
                Value<String> currencyCode = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MenuItemsCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuCategoryId: menuCategoryId,
                name: name,
                description: description,
                basePriceMinor: basePriceMinor,
                currencyCode: currencyCode,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String menuCategoryId,
                required String name,
                Value<String?> description = const Value.absent(),
                required int basePriceMinor,
                required String currencyCode,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MenuItemsCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuCategoryId: menuCategoryId,
                name: name,
                description: description,
                basePriceMinor: basePriceMinor,
                currencyCode: currencyCode,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MenuItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                menuCategoryId = false,
                itemSizesRefs = false,
                itemVariantsRefs = false,
                modifiersRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (itemSizesRefs) db.itemSizes,
                    if (itemVariantsRefs) db.itemVariants,
                    if (modifiersRefs) db.modifiers,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (menuCategoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.menuCategoryId,
                                    referencedTable: $$MenuItemsTableReferences
                                        ._menuCategoryIdTable(db),
                                    referencedColumn: $$MenuItemsTableReferences
                                        ._menuCategoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (itemSizesRefs)
                        await $_getPrefetchedData<
                          MenuItem,
                          $MenuItemsTable,
                          ItemSize
                        >(
                          currentTable: table,
                          referencedTable: $$MenuItemsTableReferences
                              ._itemSizesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MenuItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).itemSizesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.menuItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (itemVariantsRefs)
                        await $_getPrefetchedData<
                          MenuItem,
                          $MenuItemsTable,
                          ItemVariant
                        >(
                          currentTable: table,
                          referencedTable: $$MenuItemsTableReferences
                              ._itemVariantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MenuItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).itemVariantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.menuItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (modifiersRefs)
                        await $_getPrefetchedData<
                          MenuItem,
                          $MenuItemsTable,
                          Modifier
                        >(
                          currentTable: table,
                          referencedTable: $$MenuItemsTableReferences
                              ._modifiersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MenuItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).modifiersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.menuItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MenuItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $MenuItemsTable,
      MenuItem,
      $$MenuItemsTableFilterComposer,
      $$MenuItemsTableOrderingComposer,
      $$MenuItemsTableAnnotationComposer,
      $$MenuItemsTableCreateCompanionBuilder,
      $$MenuItemsTableUpdateCompanionBuilder,
      (MenuItem, $$MenuItemsTableReferences),
      MenuItem,
      PrefetchHooks Function({
        bool menuCategoryId,
        bool itemSizesRefs,
        bool itemVariantsRefs,
        bool modifiersRefs,
      })
    >;
typedef $$ItemSizesTableCreateCompanionBuilder =
    ItemSizesCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String menuItemId,
      required String name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$ItemSizesTableUpdateCompanionBuilder =
    ItemSizesCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> menuItemId,
      Value<String> name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$ItemSizesTableReferences
    extends BaseReferences<_$LocalDatabase, $ItemSizesTable, ItemSize> {
  $$ItemSizesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MenuItemsTable _menuItemIdTable(_$LocalDatabase db) =>
      db.menuItems.createAlias(
        $_aliasNameGenerator(db.itemSizes.menuItemId, db.menuItems.id),
      );

  $$MenuItemsTableProcessedTableManager get menuItemId {
    final $_column = $_itemColumn<String>('menu_item_id')!;

    final manager = $$MenuItemsTableTableManager(
      $_db,
      $_db.menuItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_menuItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ItemSizesTableFilterComposer
    extends Composer<_$LocalDatabase, $ItemSizesTable> {
  $$ItemSizesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$MenuItemsTableFilterComposer get menuItemId {
    final $$MenuItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableFilterComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemSizesTableOrderingComposer
    extends Composer<_$LocalDatabase, $ItemSizesTable> {
  $$ItemSizesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$MenuItemsTableOrderingComposer get menuItemId {
    final $$MenuItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableOrderingComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemSizesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ItemSizesTable> {
  $$ItemSizesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$MenuItemsTableAnnotationComposer get menuItemId {
    final $$MenuItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemSizesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ItemSizesTable,
          ItemSize,
          $$ItemSizesTableFilterComposer,
          $$ItemSizesTableOrderingComposer,
          $$ItemSizesTableAnnotationComposer,
          $$ItemSizesTableCreateCompanionBuilder,
          $$ItemSizesTableUpdateCompanionBuilder,
          (ItemSize, $$ItemSizesTableReferences),
          ItemSize,
          PrefetchHooks Function({bool menuItemId})
        > {
  $$ItemSizesTableTableManager(_$LocalDatabase db, $ItemSizesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemSizesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemSizesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemSizesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> menuItemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemSizesCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String menuItemId,
                required String name,
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemSizesCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ItemSizesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({menuItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (menuItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.menuItemId,
                                referencedTable: $$ItemSizesTableReferences
                                    ._menuItemIdTable(db),
                                referencedColumn: $$ItemSizesTableReferences
                                    ._menuItemIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ItemSizesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ItemSizesTable,
      ItemSize,
      $$ItemSizesTableFilterComposer,
      $$ItemSizesTableOrderingComposer,
      $$ItemSizesTableAnnotationComposer,
      $$ItemSizesTableCreateCompanionBuilder,
      $$ItemSizesTableUpdateCompanionBuilder,
      (ItemSize, $$ItemSizesTableReferences),
      ItemSize,
      PrefetchHooks Function({bool menuItemId})
    >;
typedef $$ItemVariantsTableCreateCompanionBuilder =
    ItemVariantsCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String menuItemId,
      required String name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$ItemVariantsTableUpdateCompanionBuilder =
    ItemVariantsCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> menuItemId,
      Value<String> name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$ItemVariantsTableReferences
    extends BaseReferences<_$LocalDatabase, $ItemVariantsTable, ItemVariant> {
  $$ItemVariantsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MenuItemsTable _menuItemIdTable(_$LocalDatabase db) =>
      db.menuItems.createAlias(
        $_aliasNameGenerator(db.itemVariants.menuItemId, db.menuItems.id),
      );

  $$MenuItemsTableProcessedTableManager get menuItemId {
    final $_column = $_itemColumn<String>('menu_item_id')!;

    final manager = $$MenuItemsTableTableManager(
      $_db,
      $_db.menuItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_menuItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ItemVariantsTableFilterComposer
    extends Composer<_$LocalDatabase, $ItemVariantsTable> {
  $$ItemVariantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$MenuItemsTableFilterComposer get menuItemId {
    final $$MenuItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableFilterComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemVariantsTableOrderingComposer
    extends Composer<_$LocalDatabase, $ItemVariantsTable> {
  $$ItemVariantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$MenuItemsTableOrderingComposer get menuItemId {
    final $$MenuItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableOrderingComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemVariantsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ItemVariantsTable> {
  $$ItemVariantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$MenuItemsTableAnnotationComposer get menuItemId {
    final $$MenuItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ItemVariantsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ItemVariantsTable,
          ItemVariant,
          $$ItemVariantsTableFilterComposer,
          $$ItemVariantsTableOrderingComposer,
          $$ItemVariantsTableAnnotationComposer,
          $$ItemVariantsTableCreateCompanionBuilder,
          $$ItemVariantsTableUpdateCompanionBuilder,
          (ItemVariant, $$ItemVariantsTableReferences),
          ItemVariant,
          PrefetchHooks Function({bool menuItemId})
        > {
  $$ItemVariantsTableTableManager(_$LocalDatabase db, $ItemVariantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> menuItemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemVariantsCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String menuItemId,
                required String name,
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemVariantsCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ItemVariantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({menuItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (menuItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.menuItemId,
                                referencedTable: $$ItemVariantsTableReferences
                                    ._menuItemIdTable(db),
                                referencedColumn: $$ItemVariantsTableReferences
                                    ._menuItemIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ItemVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ItemVariantsTable,
      ItemVariant,
      $$ItemVariantsTableFilterComposer,
      $$ItemVariantsTableOrderingComposer,
      $$ItemVariantsTableAnnotationComposer,
      $$ItemVariantsTableCreateCompanionBuilder,
      $$ItemVariantsTableUpdateCompanionBuilder,
      (ItemVariant, $$ItemVariantsTableReferences),
      ItemVariant,
      PrefetchHooks Function({bool menuItemId})
    >;
typedef $$ModifiersTableCreateCompanionBuilder =
    ModifiersCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String menuItemId,
      required String name,
      required String selectionType,
      Value<int> minSelect,
      Value<int> maxSelect,
      Value<bool> isRequired,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$ModifiersTableUpdateCompanionBuilder =
    ModifiersCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> menuItemId,
      Value<String> name,
      Value<String> selectionType,
      Value<int> minSelect,
      Value<int> maxSelect,
      Value<bool> isRequired,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$ModifiersTableReferences
    extends BaseReferences<_$LocalDatabase, $ModifiersTable, Modifier> {
  $$ModifiersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MenuItemsTable _menuItemIdTable(_$LocalDatabase db) =>
      db.menuItems.createAlias(
        $_aliasNameGenerator(db.modifiers.menuItemId, db.menuItems.id),
      );

  $$MenuItemsTableProcessedTableManager get menuItemId {
    final $_column = $_itemColumn<String>('menu_item_id')!;

    final manager = $$MenuItemsTableTableManager(
      $_db,
      $_db.menuItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_menuItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ModifierOptionsTable, List<ModifierOption>>
  _modifierOptionsRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.modifierOptions,
        aliasName: $_aliasNameGenerator(
          db.modifiers.id,
          db.modifierOptions.modifierId,
        ),
      );

  $$ModifierOptionsTableProcessedTableManager get modifierOptionsRefs {
    final manager = $$ModifierOptionsTableTableManager(
      $_db,
      $_db.modifierOptions,
    ).filter((f) => f.modifierId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _modifierOptionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ModifiersTableFilterComposer
    extends Composer<_$LocalDatabase, $ModifiersTable> {
  $$ModifiersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectionType => $composableBuilder(
    column: $table.selectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minSelect => $composableBuilder(
    column: $table.minSelect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxSelect => $composableBuilder(
    column: $table.maxSelect,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$MenuItemsTableFilterComposer get menuItemId {
    final $$MenuItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableFilterComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> modifierOptionsRefs(
    Expression<bool> Function($$ModifierOptionsTableFilterComposer f) f,
  ) {
    final $$ModifierOptionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.modifierOptions,
      getReferencedColumn: (t) => t.modifierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifierOptionsTableFilterComposer(
            $db: $db,
            $table: $db.modifierOptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ModifiersTableOrderingComposer
    extends Composer<_$LocalDatabase, $ModifiersTable> {
  $$ModifiersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectionType => $composableBuilder(
    column: $table.selectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minSelect => $composableBuilder(
    column: $table.minSelect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxSelect => $composableBuilder(
    column: $table.maxSelect,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$MenuItemsTableOrderingComposer get menuItemId {
    final $$MenuItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableOrderingComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ModifiersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ModifiersTable> {
  $$ModifiersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get selectionType => $composableBuilder(
    column: $table.selectionType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minSelect =>
      $composableBuilder(column: $table.minSelect, builder: (column) => column);

  GeneratedColumn<int> get maxSelect =>
      $composableBuilder(column: $table.maxSelect, builder: (column) => column);

  GeneratedColumn<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => column,
  );

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$MenuItemsTableAnnotationComposer get menuItemId {
    final $$MenuItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.menuItemId,
      referencedTable: $db.menuItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MenuItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.menuItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> modifierOptionsRefs<T extends Object>(
    Expression<T> Function($$ModifierOptionsTableAnnotationComposer a) f,
  ) {
    final $$ModifierOptionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.modifierOptions,
      getReferencedColumn: (t) => t.modifierId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifierOptionsTableAnnotationComposer(
            $db: $db,
            $table: $db.modifierOptions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ModifiersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ModifiersTable,
          Modifier,
          $$ModifiersTableFilterComposer,
          $$ModifiersTableOrderingComposer,
          $$ModifiersTableAnnotationComposer,
          $$ModifiersTableCreateCompanionBuilder,
          $$ModifiersTableUpdateCompanionBuilder,
          (Modifier, $$ModifiersTableReferences),
          Modifier,
          PrefetchHooks Function({bool menuItemId, bool modifierOptionsRefs})
        > {
  $$ModifiersTableTableManager(_$LocalDatabase db, $ModifiersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModifiersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModifiersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModifiersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> menuItemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> selectionType = const Value.absent(),
                Value<int> minSelect = const Value.absent(),
                Value<int> maxSelect = const Value.absent(),
                Value<bool> isRequired = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModifiersCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                selectionType: selectionType,
                minSelect: minSelect,
                maxSelect: maxSelect,
                isRequired: isRequired,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String menuItemId,
                required String name,
                required String selectionType,
                Value<int> minSelect = const Value.absent(),
                Value<int> maxSelect = const Value.absent(),
                Value<bool> isRequired = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModifiersCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                menuItemId: menuItemId,
                name: name,
                selectionType: selectionType,
                minSelect: minSelect,
                maxSelect: maxSelect,
                isRequired: isRequired,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ModifiersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({menuItemId = false, modifierOptionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (modifierOptionsRefs) db.modifierOptions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (menuItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.menuItemId,
                                    referencedTable: $$ModifiersTableReferences
                                        ._menuItemIdTable(db),
                                    referencedColumn: $$ModifiersTableReferences
                                        ._menuItemIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (modifierOptionsRefs)
                        await $_getPrefetchedData<
                          Modifier,
                          $ModifiersTable,
                          ModifierOption
                        >(
                          currentTable: table,
                          referencedTable: $$ModifiersTableReferences
                              ._modifierOptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ModifiersTableReferences(
                                db,
                                table,
                                p0,
                              ).modifierOptionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.modifierId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ModifiersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ModifiersTable,
      Modifier,
      $$ModifiersTableFilterComposer,
      $$ModifiersTableOrderingComposer,
      $$ModifiersTableAnnotationComposer,
      $$ModifiersTableCreateCompanionBuilder,
      $$ModifiersTableUpdateCompanionBuilder,
      (Modifier, $$ModifiersTableReferences),
      Modifier,
      PrefetchHooks Function({bool menuItemId, bool modifierOptionsRefs})
    >;
typedef $$ModifierOptionsTableCreateCompanionBuilder =
    ModifierOptionsCompanion Function({
      required String id,
      required String organizationId,
      required String deviceId,
      required String localOperationId,
      Value<int> revision,
      required DateTime clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String restaurantId,
      Value<String?> branchId,
      required String modifierId,
      required String name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$ModifierOptionsTableUpdateCompanionBuilder =
    ModifierOptionsCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> deviceId,
      Value<String> localOperationId,
      Value<int> revision,
      Value<DateTime> clientUpdatedAt,
      Value<DateTime?> serverUpdatedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> restaurantId,
      Value<String?> branchId,
      Value<String> modifierId,
      Value<String> name,
      Value<int> priceDeltaMinor,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$ModifierOptionsTableReferences
    extends
        BaseReferences<_$LocalDatabase, $ModifierOptionsTable, ModifierOption> {
  $$ModifierOptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ModifiersTable _modifierIdTable(_$LocalDatabase db) =>
      db.modifiers.createAlias(
        $_aliasNameGenerator(db.modifierOptions.modifierId, db.modifiers.id),
      );

  $$ModifiersTableProcessedTableManager get modifierId {
    final $_column = $_itemColumn<String>('modifier_id')!;

    final manager = $$ModifiersTableTableManager(
      $_db,
      $_db.modifiers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_modifierIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ModifierOptionsTableFilterComposer
    extends Composer<_$LocalDatabase, $ModifierOptionsTable> {
  $$ModifierOptionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$ModifiersTableFilterComposer get modifierId {
    final $$ModifiersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.modifierId,
      referencedTable: $db.modifiers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifiersTableFilterComposer(
            $db: $db,
            $table: $db.modifiers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ModifierOptionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $ModifierOptionsTable> {
  $$ModifierOptionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$ModifiersTableOrderingComposer get modifierId {
    final $$ModifiersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.modifierId,
      referencedTable: $db.modifiers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifiersTableOrderingComposer(
            $db: $db,
            $table: $db.modifiers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ModifierOptionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $ModifierOptionsTable> {
  $$ModifierOptionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<DateTime> get clientUpdatedAt => $composableBuilder(
    column: $table.clientUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverUpdatedAt => $composableBuilder(
    column: $table.serverUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get priceDeltaMinor => $composableBuilder(
    column: $table.priceDeltaMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$ModifiersTableAnnotationComposer get modifierId {
    final $$ModifiersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.modifierId,
      referencedTable: $db.modifiers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ModifiersTableAnnotationComposer(
            $db: $db,
            $table: $db.modifiers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ModifierOptionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $ModifierOptionsTable,
          ModifierOption,
          $$ModifierOptionsTableFilterComposer,
          $$ModifierOptionsTableOrderingComposer,
          $$ModifierOptionsTableAnnotationComposer,
          $$ModifierOptionsTableCreateCompanionBuilder,
          $$ModifierOptionsTableUpdateCompanionBuilder,
          (ModifierOption, $$ModifierOptionsTableReferences),
          ModifierOption,
          PrefetchHooks Function({bool modifierId})
        > {
  $$ModifierOptionsTableTableManager(
    _$LocalDatabase db,
    $ModifierOptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModifierOptionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModifierOptionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModifierOptionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<DateTime> clientUpdatedAt = const Value.absent(),
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String?> branchId = const Value.absent(),
                Value<String> modifierId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModifierOptionsCompanion(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                modifierId: modifierId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String deviceId,
                required String localOperationId,
                Value<int> revision = const Value.absent(),
                required DateTime clientUpdatedAt,
                Value<DateTime?> serverUpdatedAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String restaurantId,
                Value<String?> branchId = const Value.absent(),
                required String modifierId,
                required String name,
                Value<int> priceDeltaMinor = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModifierOptionsCompanion.insert(
                id: id,
                organizationId: organizationId,
                deviceId: deviceId,
                localOperationId: localOperationId,
                revision: revision,
                clientUpdatedAt: clientUpdatedAt,
                serverUpdatedAt: serverUpdatedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                restaurantId: restaurantId,
                branchId: branchId,
                modifierId: modifierId,
                name: name,
                priceDeltaMinor: priceDeltaMinor,
                displayOrder: displayOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ModifierOptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({modifierId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (modifierId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.modifierId,
                                referencedTable:
                                    $$ModifierOptionsTableReferences
                                        ._modifierIdTable(db),
                                referencedColumn:
                                    $$ModifierOptionsTableReferences
                                        ._modifierIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ModifierOptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $ModifierOptionsTable,
      ModifierOption,
      $$ModifierOptionsTableFilterComposer,
      $$ModifierOptionsTableOrderingComposer,
      $$ModifierOptionsTableAnnotationComposer,
      $$ModifierOptionsTableCreateCompanionBuilder,
      $$ModifierOptionsTableUpdateCompanionBuilder,
      (ModifierOption, $$ModifierOptionsTableReferences),
      ModifierOption,
      PrefetchHooks Function({bool modifierId})
    >;
typedef $$PrintJobsTableCreateCompanionBuilder =
    PrintJobsCompanion Function({
      required String id,
      required String organizationId,
      required String branchId,
      required String deviceId,
      Value<String?> stationId,
      required String localOperationId,
      required PrintJobType jobType,
      Value<PrintJobState> status,
      required String payloadJson,
      Value<int> retryCount,
      Value<int> maxRetries,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<String?> reprintOf,
      Value<String?> reprintReason,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> printedAt,
      Value<DateTime?> abandonedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$PrintJobsTableUpdateCompanionBuilder =
    PrintJobsCompanion Function({
      Value<String> id,
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> deviceId,
      Value<String?> stationId,
      Value<String> localOperationId,
      Value<PrintJobType> jobType,
      Value<PrintJobState> status,
      Value<String> payloadJson,
      Value<int> retryCount,
      Value<int> maxRetries,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<String?> reprintOf,
      Value<String?> reprintReason,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> printedAt,
      Value<DateTime?> abandonedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$PrintJobsTableFilterComposer
    extends Composer<_$LocalDatabase, $PrintJobsTable> {
  $$PrintJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PrintJobType, PrintJobType, String>
  get jobType => $composableBuilder(
    column: $table.jobType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<PrintJobState, PrintJobState, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reprintOf => $composableBuilder(
    column: $table.reprintOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reprintReason => $composableBuilder(
    column: $table.reprintReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get printedAt => $composableBuilder(
    column: $table.printedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get abandonedAt => $composableBuilder(
    column: $table.abandonedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PrintJobsTableOrderingComposer
    extends Composer<_$LocalDatabase, $PrintJobsTable> {
  $$PrintJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jobType => $composableBuilder(
    column: $table.jobType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reprintOf => $composableBuilder(
    column: $table.reprintOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reprintReason => $composableBuilder(
    column: $table.reprintReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get printedAt => $composableBuilder(
    column: $table.printedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get abandonedAt => $composableBuilder(
    column: $table.abandonedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrintJobsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $PrintJobsTable> {
  $$PrintJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get localOperationId => $composableBuilder(
    column: $table.localOperationId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PrintJobType, String> get jobType =>
      $composableBuilder(column: $table.jobType, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PrintJobState, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reprintOf =>
      $composableBuilder(column: $table.reprintOf, builder: (column) => column);

  GeneratedColumn<String> get reprintReason => $composableBuilder(
    column: $table.reprintReason,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get printedAt =>
      $composableBuilder(column: $table.printedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get abandonedAt => $composableBuilder(
    column: $table.abandonedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$PrintJobsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $PrintJobsTable,
          PrintJobRow,
          $$PrintJobsTableFilterComposer,
          $$PrintJobsTableOrderingComposer,
          $$PrintJobsTableAnnotationComposer,
          $$PrintJobsTableCreateCompanionBuilder,
          $$PrintJobsTableUpdateCompanionBuilder,
          (
            PrintJobRow,
            BaseReferences<_$LocalDatabase, $PrintJobsTable, PrintJobRow>,
          ),
          PrintJobRow,
          PrefetchHooks Function()
        > {
  $$PrintJobsTableTableManager(_$LocalDatabase db, $PrintJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrintJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrintJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrintJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String> localOperationId = const Value.absent(),
                Value<PrintJobType> jobType = const Value.absent(),
                Value<PrintJobState> status = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int> maxRetries = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> reprintOf = const Value.absent(),
                Value<String?> reprintReason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> printedAt = const Value.absent(),
                Value<DateTime?> abandonedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrintJobsCompanion(
                id: id,
                organizationId: organizationId,
                branchId: branchId,
                deviceId: deviceId,
                stationId: stationId,
                localOperationId: localOperationId,
                jobType: jobType,
                status: status,
                payloadJson: payloadJson,
                retryCount: retryCount,
                maxRetries: maxRetries,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                reprintOf: reprintOf,
                reprintReason: reprintReason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                printedAt: printedAt,
                abandonedAt: abandonedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String organizationId,
                required String branchId,
                required String deviceId,
                Value<String?> stationId = const Value.absent(),
                required String localOperationId,
                required PrintJobType jobType,
                Value<PrintJobState> status = const Value.absent(),
                required String payloadJson,
                Value<int> retryCount = const Value.absent(),
                Value<int> maxRetries = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> reprintOf = const Value.absent(),
                Value<String?> reprintReason = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> printedAt = const Value.absent(),
                Value<DateTime?> abandonedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PrintJobsCompanion.insert(
                id: id,
                organizationId: organizationId,
                branchId: branchId,
                deviceId: deviceId,
                stationId: stationId,
                localOperationId: localOperationId,
                jobType: jobType,
                status: status,
                payloadJson: payloadJson,
                retryCount: retryCount,
                maxRetries: maxRetries,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                reprintOf: reprintOf,
                reprintReason: reprintReason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                printedAt: printedAt,
                abandonedAt: abandonedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrintJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $PrintJobsTable,
      PrintJobRow,
      $$PrintJobsTableFilterComposer,
      $$PrintJobsTableOrderingComposer,
      $$PrintJobsTableAnnotationComposer,
      $$PrintJobsTableCreateCompanionBuilder,
      $$PrintJobsTableUpdateCompanionBuilder,
      (
        PrintJobRow,
        BaseReferences<_$LocalDatabase, $PrintJobsTable, PrintJobRow>,
      ),
      PrintJobRow,
      PrefetchHooks Function()
    >;
typedef $$KitchenSpoolJobsTableCreateCompanionBuilder =
    KitchenSpoolJobsCompanion Function({
      required String localJobId,
      required String dispatchId,
      required String organizationId,
      required String restaurantId,
      required String branchId,
      required String deviceId,
      required String orderId,
      Value<String?> serviceRoundId,
      required KitchenSpoolDispatchType dispatchType,
      Value<KitchenSpoolJobStatus> status,
      required Uint8List encryptedPayloadBlob,
      required int encryptionVersion,
      Value<String?> destinationFingerprint,
      Value<String?> destinationDisplayLabel,
      Value<String?> transportKind,
      Value<String?> paperWidth,
      required int payloadVersion,
      required int documentVersion,
      required int rasterVersion,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastErrorCode,
      Value<DateTime?> serverClaimExpiresAt,
      Value<KitchenServerAckStatus?> pendingServerAckStatus,
      Value<int> serverAckAttemptCount,
      Value<DateTime?> serverAckNextAttemptAt,
      Value<String?> serverAckLastErrorCode,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> transportAcceptedAt,
      Value<DateTime?> serverAcknowledgedAt,
      Value<DateTime?> reviewedAt,
      Value<String?> reprintOfLocalJobId,
      Value<String?> supersededByDispatchId,
      Value<int> rowid,
    });
typedef $$KitchenSpoolJobsTableUpdateCompanionBuilder =
    KitchenSpoolJobsCompanion Function({
      Value<String> localJobId,
      Value<String> dispatchId,
      Value<String> organizationId,
      Value<String> restaurantId,
      Value<String> branchId,
      Value<String> deviceId,
      Value<String> orderId,
      Value<String?> serviceRoundId,
      Value<KitchenSpoolDispatchType> dispatchType,
      Value<KitchenSpoolJobStatus> status,
      Value<Uint8List> encryptedPayloadBlob,
      Value<int> encryptionVersion,
      Value<String?> destinationFingerprint,
      Value<String?> destinationDisplayLabel,
      Value<String?> transportKind,
      Value<String?> paperWidth,
      Value<int> payloadVersion,
      Value<int> documentVersion,
      Value<int> rasterVersion,
      Value<int> attemptCount,
      Value<DateTime?> nextAttemptAt,
      Value<DateTime?> lastAttemptAt,
      Value<String?> lastErrorCode,
      Value<DateTime?> serverClaimExpiresAt,
      Value<KitchenServerAckStatus?> pendingServerAckStatus,
      Value<int> serverAckAttemptCount,
      Value<DateTime?> serverAckNextAttemptAt,
      Value<String?> serverAckLastErrorCode,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> transportAcceptedAt,
      Value<DateTime?> serverAcknowledgedAt,
      Value<DateTime?> reviewedAt,
      Value<String?> reprintOfLocalJobId,
      Value<String?> supersededByDispatchId,
      Value<int> rowid,
    });

class $$KitchenSpoolJobsTableFilterComposer
    extends Composer<_$LocalDatabase, $KitchenSpoolJobsTable> {
  $$KitchenSpoolJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localJobId => $composableBuilder(
    column: $table.localJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dispatchId => $composableBuilder(
    column: $table.dispatchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceRoundId => $composableBuilder(
    column: $table.serviceRoundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    KitchenSpoolDispatchType,
    KitchenSpoolDispatchType,
    String
  >
  get dispatchType => $composableBuilder(
    column: $table.dispatchType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    KitchenSpoolJobStatus,
    KitchenSpoolJobStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedPayloadBlob => $composableBuilder(
    column: $table.encryptedPayloadBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationFingerprint => $composableBuilder(
    column: $table.destinationFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationDisplayLabel => $composableBuilder(
    column: $table.destinationDisplayLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transportKind => $composableBuilder(
    column: $table.transportKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paperWidth => $composableBuilder(
    column: $table.paperWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get documentVersion => $composableBuilder(
    column: $table.documentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rasterVersion => $composableBuilder(
    column: $table.rasterVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverClaimExpiresAt => $composableBuilder(
    column: $table.serverClaimExpiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    KitchenServerAckStatus?,
    KitchenServerAckStatus,
    String
  >
  get pendingServerAckStatus => $composableBuilder(
    column: $table.pendingServerAckStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get serverAckAttemptCount => $composableBuilder(
    column: $table.serverAckAttemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverAckNextAttemptAt => $composableBuilder(
    column: $table.serverAckNextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverAckLastErrorCode => $composableBuilder(
    column: $table.serverAckLastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transportAcceptedAt => $composableBuilder(
    column: $table.transportAcceptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverAcknowledgedAt => $composableBuilder(
    column: $table.serverAcknowledgedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reprintOfLocalJobId => $composableBuilder(
    column: $table.reprintOfLocalJobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get supersededByDispatchId => $composableBuilder(
    column: $table.supersededByDispatchId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KitchenSpoolJobsTableOrderingComposer
    extends Composer<_$LocalDatabase, $KitchenSpoolJobsTable> {
  $$KitchenSpoolJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localJobId => $composableBuilder(
    column: $table.localJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dispatchId => $composableBuilder(
    column: $table.dispatchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceRoundId => $composableBuilder(
    column: $table.serviceRoundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dispatchType => $composableBuilder(
    column: $table.dispatchType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedPayloadBlob => $composableBuilder(
    column: $table.encryptedPayloadBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationFingerprint => $composableBuilder(
    column: $table.destinationFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationDisplayLabel => $composableBuilder(
    column: $table.destinationDisplayLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transportKind => $composableBuilder(
    column: $table.transportKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paperWidth => $composableBuilder(
    column: $table.paperWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get documentVersion => $composableBuilder(
    column: $table.documentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rasterVersion => $composableBuilder(
    column: $table.rasterVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverClaimExpiresAt => $composableBuilder(
    column: $table.serverClaimExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingServerAckStatus => $composableBuilder(
    column: $table.pendingServerAckStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverAckAttemptCount => $composableBuilder(
    column: $table.serverAckAttemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverAckNextAttemptAt => $composableBuilder(
    column: $table.serverAckNextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverAckLastErrorCode => $composableBuilder(
    column: $table.serverAckLastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transportAcceptedAt => $composableBuilder(
    column: $table.transportAcceptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverAcknowledgedAt => $composableBuilder(
    column: $table.serverAcknowledgedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reprintOfLocalJobId => $composableBuilder(
    column: $table.reprintOfLocalJobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get supersededByDispatchId => $composableBuilder(
    column: $table.supersededByDispatchId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KitchenSpoolJobsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $KitchenSpoolJobsTable> {
  $$KitchenSpoolJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localJobId => $composableBuilder(
    column: $table.localJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dispatchId => $composableBuilder(
    column: $table.dispatchId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get serviceRoundId => $composableBuilder(
    column: $table.serviceRoundId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<KitchenSpoolDispatchType, String>
  get dispatchType => $composableBuilder(
    column: $table.dispatchType,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<KitchenSpoolJobStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<Uint8List> get encryptedPayloadBlob => $composableBuilder(
    column: $table.encryptedPayloadBlob,
    builder: (column) => column,
  );

  GeneratedColumn<int> get encryptionVersion => $composableBuilder(
    column: $table.encryptionVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationFingerprint => $composableBuilder(
    column: $table.destinationFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationDisplayLabel => $composableBuilder(
    column: $table.destinationDisplayLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transportKind => $composableBuilder(
    column: $table.transportKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paperWidth => $composableBuilder(
    column: $table.paperWidth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get payloadVersion => $composableBuilder(
    column: $table.payloadVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get documentVersion => $composableBuilder(
    column: $table.documentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rasterVersion => $composableBuilder(
    column: $table.rasterVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverClaimExpiresAt => $composableBuilder(
    column: $table.serverClaimExpiresAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<KitchenServerAckStatus?, String>
  get pendingServerAckStatus => $composableBuilder(
    column: $table.pendingServerAckStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverAckAttemptCount => $composableBuilder(
    column: $table.serverAckAttemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverAckNextAttemptAt => $composableBuilder(
    column: $table.serverAckNextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverAckLastErrorCode => $composableBuilder(
    column: $table.serverAckLastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get transportAcceptedAt => $composableBuilder(
    column: $table.transportAcceptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverAcknowledgedAt => $composableBuilder(
    column: $table.serverAcknowledgedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reprintOfLocalJobId => $composableBuilder(
    column: $table.reprintOfLocalJobId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get supersededByDispatchId => $composableBuilder(
    column: $table.supersededByDispatchId,
    builder: (column) => column,
  );
}

class $$KitchenSpoolJobsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $KitchenSpoolJobsTable,
          KitchenSpoolJobRow,
          $$KitchenSpoolJobsTableFilterComposer,
          $$KitchenSpoolJobsTableOrderingComposer,
          $$KitchenSpoolJobsTableAnnotationComposer,
          $$KitchenSpoolJobsTableCreateCompanionBuilder,
          $$KitchenSpoolJobsTableUpdateCompanionBuilder,
          (
            KitchenSpoolJobRow,
            BaseReferences<
              _$LocalDatabase,
              $KitchenSpoolJobsTable,
              KitchenSpoolJobRow
            >,
          ),
          KitchenSpoolJobRow,
          PrefetchHooks Function()
        > {
  $$KitchenSpoolJobsTableTableManager(
    _$LocalDatabase db,
    $KitchenSpoolJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KitchenSpoolJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KitchenSpoolJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KitchenSpoolJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> localJobId = const Value.absent(),
                Value<String> dispatchId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> orderId = const Value.absent(),
                Value<String?> serviceRoundId = const Value.absent(),
                Value<KitchenSpoolDispatchType> dispatchType =
                    const Value.absent(),
                Value<KitchenSpoolJobStatus> status = const Value.absent(),
                Value<Uint8List> encryptedPayloadBlob = const Value.absent(),
                Value<int> encryptionVersion = const Value.absent(),
                Value<String?> destinationFingerprint = const Value.absent(),
                Value<String?> destinationDisplayLabel = const Value.absent(),
                Value<String?> transportKind = const Value.absent(),
                Value<String?> paperWidth = const Value.absent(),
                Value<int> payloadVersion = const Value.absent(),
                Value<int> documentVersion = const Value.absent(),
                Value<int> rasterVersion = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime?> serverClaimExpiresAt = const Value.absent(),
                Value<KitchenServerAckStatus?> pendingServerAckStatus =
                    const Value.absent(),
                Value<int> serverAckAttemptCount = const Value.absent(),
                Value<DateTime?> serverAckNextAttemptAt = const Value.absent(),
                Value<String?> serverAckLastErrorCode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> transportAcceptedAt = const Value.absent(),
                Value<DateTime?> serverAcknowledgedAt = const Value.absent(),
                Value<DateTime?> reviewedAt = const Value.absent(),
                Value<String?> reprintOfLocalJobId = const Value.absent(),
                Value<String?> supersededByDispatchId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KitchenSpoolJobsCompanion(
                localJobId: localJobId,
                dispatchId: dispatchId,
                organizationId: organizationId,
                restaurantId: restaurantId,
                branchId: branchId,
                deviceId: deviceId,
                orderId: orderId,
                serviceRoundId: serviceRoundId,
                dispatchType: dispatchType,
                status: status,
                encryptedPayloadBlob: encryptedPayloadBlob,
                encryptionVersion: encryptionVersion,
                destinationFingerprint: destinationFingerprint,
                destinationDisplayLabel: destinationDisplayLabel,
                transportKind: transportKind,
                paperWidth: paperWidth,
                payloadVersion: payloadVersion,
                documentVersion: documentVersion,
                rasterVersion: rasterVersion,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastAttemptAt: lastAttemptAt,
                lastErrorCode: lastErrorCode,
                serverClaimExpiresAt: serverClaimExpiresAt,
                pendingServerAckStatus: pendingServerAckStatus,
                serverAckAttemptCount: serverAckAttemptCount,
                serverAckNextAttemptAt: serverAckNextAttemptAt,
                serverAckLastErrorCode: serverAckLastErrorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                transportAcceptedAt: transportAcceptedAt,
                serverAcknowledgedAt: serverAcknowledgedAt,
                reviewedAt: reviewedAt,
                reprintOfLocalJobId: reprintOfLocalJobId,
                supersededByDispatchId: supersededByDispatchId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String localJobId,
                required String dispatchId,
                required String organizationId,
                required String restaurantId,
                required String branchId,
                required String deviceId,
                required String orderId,
                Value<String?> serviceRoundId = const Value.absent(),
                required KitchenSpoolDispatchType dispatchType,
                Value<KitchenSpoolJobStatus> status = const Value.absent(),
                required Uint8List encryptedPayloadBlob,
                required int encryptionVersion,
                Value<String?> destinationFingerprint = const Value.absent(),
                Value<String?> destinationDisplayLabel = const Value.absent(),
                Value<String?> transportKind = const Value.absent(),
                Value<String?> paperWidth = const Value.absent(),
                required int payloadVersion,
                required int documentVersion,
                required int rasterVersion,
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<DateTime?> serverClaimExpiresAt = const Value.absent(),
                Value<KitchenServerAckStatus?> pendingServerAckStatus =
                    const Value.absent(),
                Value<int> serverAckAttemptCount = const Value.absent(),
                Value<DateTime?> serverAckNextAttemptAt = const Value.absent(),
                Value<String?> serverAckLastErrorCode = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> transportAcceptedAt = const Value.absent(),
                Value<DateTime?> serverAcknowledgedAt = const Value.absent(),
                Value<DateTime?> reviewedAt = const Value.absent(),
                Value<String?> reprintOfLocalJobId = const Value.absent(),
                Value<String?> supersededByDispatchId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KitchenSpoolJobsCompanion.insert(
                localJobId: localJobId,
                dispatchId: dispatchId,
                organizationId: organizationId,
                restaurantId: restaurantId,
                branchId: branchId,
                deviceId: deviceId,
                orderId: orderId,
                serviceRoundId: serviceRoundId,
                dispatchType: dispatchType,
                status: status,
                encryptedPayloadBlob: encryptedPayloadBlob,
                encryptionVersion: encryptionVersion,
                destinationFingerprint: destinationFingerprint,
                destinationDisplayLabel: destinationDisplayLabel,
                transportKind: transportKind,
                paperWidth: paperWidth,
                payloadVersion: payloadVersion,
                documentVersion: documentVersion,
                rasterVersion: rasterVersion,
                attemptCount: attemptCount,
                nextAttemptAt: nextAttemptAt,
                lastAttemptAt: lastAttemptAt,
                lastErrorCode: lastErrorCode,
                serverClaimExpiresAt: serverClaimExpiresAt,
                pendingServerAckStatus: pendingServerAckStatus,
                serverAckAttemptCount: serverAckAttemptCount,
                serverAckNextAttemptAt: serverAckNextAttemptAt,
                serverAckLastErrorCode: serverAckLastErrorCode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                transportAcceptedAt: transportAcceptedAt,
                serverAcknowledgedAt: serverAcknowledgedAt,
                reviewedAt: reviewedAt,
                reprintOfLocalJobId: reprintOfLocalJobId,
                supersededByDispatchId: supersededByDispatchId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KitchenSpoolJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $KitchenSpoolJobsTable,
      KitchenSpoolJobRow,
      $$KitchenSpoolJobsTableFilterComposer,
      $$KitchenSpoolJobsTableOrderingComposer,
      $$KitchenSpoolJobsTableAnnotationComposer,
      $$KitchenSpoolJobsTableCreateCompanionBuilder,
      $$KitchenSpoolJobsTableUpdateCompanionBuilder,
      (
        KitchenSpoolJobRow,
        BaseReferences<
          _$LocalDatabase,
          $KitchenSpoolJobsTable,
          KitchenSpoolJobRow
        >,
      ),
      KitchenSpoolJobRow,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(_db, _db.outboxOperations);
  $$ProcessedPullLogTableTableManager get processedPullLog =>
      $$ProcessedPullLogTableTableManager(_db, _db.processedPullLog);
  $$MenuCategoriesTableTableManager get menuCategories =>
      $$MenuCategoriesTableTableManager(_db, _db.menuCategories);
  $$MenuItemsTableTableManager get menuItems =>
      $$MenuItemsTableTableManager(_db, _db.menuItems);
  $$ItemSizesTableTableManager get itemSizes =>
      $$ItemSizesTableTableManager(_db, _db.itemSizes);
  $$ItemVariantsTableTableManager get itemVariants =>
      $$ItemVariantsTableTableManager(_db, _db.itemVariants);
  $$ModifiersTableTableManager get modifiers =>
      $$ModifiersTableTableManager(_db, _db.modifiers);
  $$ModifierOptionsTableTableManager get modifierOptions =>
      $$ModifierOptionsTableTableManager(_db, _db.modifierOptions);
  $$PrintJobsTableTableManager get printJobs =>
      $$PrintJobsTableTableManager(_db, _db.printJobs);
  $$KitchenSpoolJobsTableTableManager get kitchenSpoolJobs =>
      $$KitchenSpoolJobsTableTableManager(_db, _db.kitchenSpoolJobs);
}
