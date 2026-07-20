// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kitchen_spool_database.dart';

// ignore_for_file: type=lint
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
  static const VerificationMeta _serverAckTerminalCodeMeta =
      const VerificationMeta('serverAckTerminalCode');
  @override
  late final GeneratedColumn<String> serverAckTerminalCode =
      GeneratedColumn<String>(
        'server_ack_terminal_code',
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
    serverAckTerminalCode,
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
    if (data.containsKey('server_ack_terminal_code')) {
      context.handle(
        _serverAckTerminalCodeMeta,
        serverAckTerminalCode.isAcceptableOrUnknown(
          data['server_ack_terminal_code']!,
          _serverAckTerminalCodeMeta,
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
      serverAckTerminalCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_ack_terminal_code'],
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

  /// KITCHEN-MODE-001C2B: a TERMINAL server verdict on this job's ownership/
  /// import (`not_claim_owner` / `conflict` / `not_found` /
  /// `ambiguous_print_hold`). Non-null means the server refused ownership
  /// permanently: acknowledgement retries STOP and the job can NEVER become
  /// runnable — but the encrypted job and its history are preserved.
  final String? serverAckTerminalCode;

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
    this.serverAckTerminalCode,
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
    if (!nullToAbsent || serverAckTerminalCode != null) {
      map['server_ack_terminal_code'] = Variable<String>(serverAckTerminalCode);
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
      serverAckTerminalCode: serverAckTerminalCode == null && nullToAbsent
          ? const Value.absent()
          : Value(serverAckTerminalCode),
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
      serverAckTerminalCode: serializer.fromJson<String?>(
        json['serverAckTerminalCode'],
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
      'serverAckTerminalCode': serializer.toJson<String?>(
        serverAckTerminalCode,
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
    Value<String?> serverAckTerminalCode = const Value.absent(),
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
    serverAckTerminalCode: serverAckTerminalCode.present
        ? serverAckTerminalCode.value
        : this.serverAckTerminalCode,
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
      serverAckTerminalCode: data.serverAckTerminalCode.present
          ? data.serverAckTerminalCode.value
          : this.serverAckTerminalCode,
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
          ..write('serverAckTerminalCode: $serverAckTerminalCode, ')
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
    serverAckTerminalCode,
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
          other.serverAckTerminalCode == this.serverAckTerminalCode &&
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
  final Value<String?> serverAckTerminalCode;
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
    this.serverAckTerminalCode = const Value.absent(),
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
    this.serverAckTerminalCode = const Value.absent(),
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
    Expression<String>? serverAckTerminalCode,
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
      if (serverAckTerminalCode != null)
        'server_ack_terminal_code': serverAckTerminalCode,
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
    Value<String?>? serverAckTerminalCode,
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
      serverAckTerminalCode:
          serverAckTerminalCode ?? this.serverAckTerminalCode,
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
    if (serverAckTerminalCode.present) {
      map['server_ack_terminal_code'] = Variable<String>(
        serverAckTerminalCode.value,
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
          ..write('serverAckTerminalCode: $serverAckTerminalCode, ')
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

abstract class _$KitchenSpoolDatabase extends GeneratedDatabase {
  _$KitchenSpoolDatabase(QueryExecutor e) : super(e);
  $KitchenSpoolDatabaseManager get managers =>
      $KitchenSpoolDatabaseManager(this);
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
    kitchenSpoolJobs,
    kitchenSpoolRunnableIdx,
    kitchenSpoolDestinationIdx,
    kitchenSpoolUnresolvedIdx,
    kitchenSpoolPendingAckIdx,
    kitchenSpoolRetentionIdx,
    kitchenSpoolOrderSequenceIdx,
  ];
}

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
      Value<String?> serverAckTerminalCode,
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
      Value<String?> serverAckTerminalCode,
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
    extends Composer<_$KitchenSpoolDatabase, $KitchenSpoolJobsTable> {
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

  ColumnFilters<String> get serverAckTerminalCode => $composableBuilder(
    column: $table.serverAckTerminalCode,
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
    extends Composer<_$KitchenSpoolDatabase, $KitchenSpoolJobsTable> {
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

  ColumnOrderings<String> get serverAckTerminalCode => $composableBuilder(
    column: $table.serverAckTerminalCode,
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
    extends Composer<_$KitchenSpoolDatabase, $KitchenSpoolJobsTable> {
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

  GeneratedColumn<String> get serverAckTerminalCode => $composableBuilder(
    column: $table.serverAckTerminalCode,
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
          _$KitchenSpoolDatabase,
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
              _$KitchenSpoolDatabase,
              $KitchenSpoolJobsTable,
              KitchenSpoolJobRow
            >,
          ),
          KitchenSpoolJobRow,
          PrefetchHooks Function()
        > {
  $$KitchenSpoolJobsTableTableManager(
    _$KitchenSpoolDatabase db,
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
                Value<String?> serverAckTerminalCode = const Value.absent(),
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
                serverAckTerminalCode: serverAckTerminalCode,
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
                Value<String?> serverAckTerminalCode = const Value.absent(),
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
                serverAckTerminalCode: serverAckTerminalCode,
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
      _$KitchenSpoolDatabase,
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
          _$KitchenSpoolDatabase,
          $KitchenSpoolJobsTable,
          KitchenSpoolJobRow
        >,
      ),
      KitchenSpoolJobRow,
      PrefetchHooks Function()
    >;

class $KitchenSpoolDatabaseManager {
  final _$KitchenSpoolDatabase _db;
  $KitchenSpoolDatabaseManager(this._db);
  $$KitchenSpoolJobsTableTableManager get kitchenSpoolJobs =>
      $$KitchenSpoolJobsTableTableManager(_db, _db.kitchenSpoolJobs);
}
