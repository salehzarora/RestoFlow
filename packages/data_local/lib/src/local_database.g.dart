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

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $OutboxOperationsTable outboxOperations = $OutboxOperationsTable(
    this,
  );
  late final $ProcessedPullLogTable processedPullLog = $ProcessedPullLogTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    outboxOperations,
    processedPullLog,
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

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(_db, _db.outboxOperations);
  $$ProcessedPullLogTableTableManager get processedPullLog =>
      $$ProcessedPullLogTableTableManager(_db, _db.processedPullLog);
}
