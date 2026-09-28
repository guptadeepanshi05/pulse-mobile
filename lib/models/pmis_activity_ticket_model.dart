import 'package:equatable/equatable.dart';

class PmisActivityTicketDetail extends Equatable {
  final int atId;
  final int ppaId;
  final String currentStatus;
  final int? currentStatusCode;
  final String? currentStatusDt;
  final int? makerDesignationMstId;
  final int? makerUserMstId;
  final String? makerAssignedDt;
  final String? plannedStartDt;
  final String? plannedEndDt;
  final String? actualStartDt;
  final String? actualEndDt;
  final bool isActive;
  final String? remarks;
  final List<PmisTicketChecker> ticketCheckers;
  final List<PmisTicketFieldValue> ticketFieldValues;
  final List<PmisTicketAttachment> ticketAttachments;
  final String? makerUserName;
  final String? makerDesignationName;
  final List<PmisOldDataItem> oldData;
  final bool showReviewBtns;
  final String? checkerLvl;
  final String? role;
  /// When true, ticket fields and submit are read-only (API-driven).
  final bool viewOnly;
  final List<Map<String, dynamic>> ticketStatusHistory;
  final bool isRepeating;
  final String? repeatDt;
  final List<PmisAllowedStatus> allowedStatuses;
  final bool startActivity;

  const PmisActivityTicketDetail({
    required this.atId,
    required this.ppaId,
    required this.currentStatus,
    required this.currentStatusCode,
    required this.currentStatusDt,
    required this.makerDesignationMstId,
    required this.makerUserMstId,
    required this.makerAssignedDt,
    required this.plannedStartDt,
    required this.plannedEndDt,
    required this.actualStartDt,
    required this.actualEndDt,
    required this.isActive,
    required this.remarks,
    required this.ticketCheckers,
    required this.ticketFieldValues,
    required this.ticketAttachments,
    required this.makerUserName,
    required this.makerDesignationName,
    required this.oldData,
    required this.showReviewBtns,
    required this.checkerLvl,
    required this.role,
    required this.viewOnly,
    required this.ticketStatusHistory,
    required this.isRepeating,
    required this.repeatDt,
    required this.allowedStatuses,
    required this.startActivity,
  });

  factory PmisActivityTicketDetail.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    int? parseIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final raw = v.toString().trim();
      if (raw.isEmpty) return null;
      return int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
    }
    bool parseBool(dynamic v) =>
        v == true || v?.toString().toLowerCase() == 'true' || v == 1;
    String? parseStringNullable(dynamic v) => v == null ? null : v.toString();
    dynamic pick(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }
    int? parseFirstIntByKeys(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final parsed = parseIntNullable(m[k]);
        if (parsed != null) return parsed;
      }
      return null;
    }

    final checkers = (pick(json, ['ticketCheckers', 'ticket_checkers'])
                as List<dynamic>? ??
            [])
        .map((e) => PmisTicketChecker.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final fieldValues = (pick(json, ['ticketFieldValues', 'ticket_field_values'])
                as List<dynamic>? ??
            [])
        .map((e) => PmisTicketFieldValue.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final attachments = (pick(json, ['ticketAttachments', 'ticket_attachments'])
                as List<dynamic>? ??
            [])
        .map((e) => PmisTicketAttachment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final oldDataRaw = pick(json, ['oldData', 'old_data']);
    final List<dynamic> oldDataList;
    if (oldDataRaw == null) {
      oldDataList = const [];
    } else if (oldDataRaw is List) {
      oldDataList = oldDataRaw;
    } else if (oldDataRaw is Map) {
      oldDataList = [oldDataRaw];
    } else {
      oldDataList = const [];
    }
    final oldDataItems = oldDataList
        .map((e) => PmisOldDataItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final statusHistory =
        (pick(json, ['ticketStatusHistory', 'ticket_status_history'])
                    as List<dynamic>? ??
                [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final allowedStatusesRaw = pick(json, ['allowedStatuses', 'allowed_statuses']);
    final allowedStatuses = <PmisAllowedStatus>[];
    if (allowedStatusesRaw is List) {
      for (final item in allowedStatusesRaw) {
        if (item is Map) {
          final parsed = PmisAllowedStatus.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (parsed.statusCode.isNotEmpty || parsed.statusName.isNotEmpty) {
            allowedStatuses.add(parsed);
          }
        } else {
          final raw = item.toString().trim();
          if (raw.isEmpty) continue;
          allowedStatuses.add(
            PmisAllowedStatus(
              psmId: null,
              statusCode: raw,
              statusName: raw,
            ),
          );
        }
      }
    } else {
      for (final raw in (allowedStatusesRaw?.toString() ?? '').split(',')) {
        final value = raw.trim();
        if (value.isEmpty) continue;
        allowedStatuses.add(
          PmisAllowedStatus(
            psmId: null,
            statusCode: value,
            statusName: value,
          ),
        );
      }
    }

    return PmisActivityTicketDetail(
      atId: parseInt(json['atId']),
      ppaId: parseInt(json['ppaId']),
      currentStatus: (json['currentStatus'] ?? '').toString(),
      currentStatusCode: parseFirstIntByKeys(
        json,
        const <String>[
          'currentStatusCode',
          'current_status_code',
          'statusCodeId',
          'currentStatusId',
          'current_status_id',
          'statusId',
          'status_id',
          'psmId',
          'psm_id',
        ],
      ),
      currentStatusDt: parseStringNullable(json['currentStatusDt']),
      makerDesignationMstId: parseIntNullable(json['makerDesignationMstId']),
      makerUserMstId: parseIntNullable(json['makerUserMstId']),
      makerAssignedDt: parseStringNullable(json['makerAssignedDt']),
      plannedStartDt: parseStringNullable(json['plannedStartDt']),
      plannedEndDt: parseStringNullable(json['plannedEndDt']),
      actualStartDt: parseStringNullable(json['actualStartDt']),
      actualEndDt: parseStringNullable(json['actualEndDt']),
      isActive: parseBool(json['isActive']),
      remarks: parseStringNullable(json['remarks']),
      ticketCheckers: checkers,
      ticketFieldValues: fieldValues,
      ticketAttachments: attachments,
      makerUserName: parseStringNullable(json['makerUserName']),
      makerDesignationName: parseStringNullable(json['makerDesignationName']),
      oldData: oldDataItems,
      showReviewBtns: parseBool(json['showReviewBtns']),
      checkerLvl: parseStringNullable(json['checkerLvl']),
      role: parseStringNullable(json['role']),
      viewOnly: parseBool(
        pick(json, const <String>['viewOnly', 'view_only']),
      ),
      ticketStatusHistory: statusHistory,
      isRepeating: parseBool(json['isRepeating']),
      repeatDt: parseStringNullable(json['repeatDt']),
      allowedStatuses: allowedStatuses,
      startActivity: parseBool(
        pick(json, const <String>['startActivity', 'start_activity']),
      ),
    );
  }

  @override
  List<Object?> get props => [
        atId,
        ppaId,
        currentStatus,
        currentStatusCode,
        currentStatusDt,
        makerDesignationMstId,
        makerUserMstId,
        makerAssignedDt,
        plannedStartDt,
        plannedEndDt,
        actualStartDt,
        actualEndDt,
        isActive,
        remarks,
        ticketCheckers,
        ticketFieldValues,
        ticketAttachments,
        makerUserName,
        makerDesignationName,
        oldData,
        showReviewBtns,
        checkerLvl,
        role,
        viewOnly,
        ticketStatusHistory,
        isRepeating,
        repeatDt,
        allowedStatuses,
        startActivity,
      ];
}

class PmisAllowedStatus extends Equatable {
  final int? psmId;
  final String statusCode;
  final String statusName;

  const PmisAllowedStatus({
    required this.psmId,
    required this.statusCode,
    required this.statusName,
  });

  factory PmisAllowedStatus.fromJson(Map<String, dynamic> json) {
    int? parseIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      final raw = v.toString().trim();
      if (raw.isEmpty) return null;
      return int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
    }

    final code = (json['statusCode'] ?? json['status_code'] ?? '')
        .toString()
        .trim();
    final name = (json['statusName'] ?? json['status_name'] ?? code)
        .toString()
        .trim();

    return PmisAllowedStatus(
      psmId: parseIntNullable(
        json['psmId'] ??
            json['psm_id'] ??
            json['psmID'] ??
            json['statusMstId'] ??
            json['status_mst_id'] ??
            json['statusId'] ??
            json['status_id'] ??
            json['id'],
      ),
      statusCode: code,
      statusName: name.isEmpty ? code : name,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'psmId': psmId,
        'statusCode': statusCode,
        'statusName': statusName,
      };

  @override
  List<Object?> get props => [psmId, statusCode, statusName];
}

class PmisTicketChecker extends Equatable {
  final int tcId;
  final int levelNo;
  final int? designationMstId;
  final int? checkerUserMstId;
  final String? decisionStatus;
  final String? decisionBy;
  final String? decisionDt;
  final String? decisionRemarks;
  final String? latitude;
  final String? longitude;
  final String? geoAccuracyM;
  final String? geoSource;
  final bool isActive;
  final String? remarks;
  final String? decisionByName;
  final String? checkerUserName;
  final String? designationName;

  const PmisTicketChecker({
    required this.tcId,
    required this.levelNo,
    required this.designationMstId,
    required this.checkerUserMstId,
    required this.decisionStatus,
    required this.decisionBy,
    required this.decisionDt,
    required this.decisionRemarks,
    required this.latitude,
    required this.longitude,
    required this.geoAccuracyM,
    required this.geoSource,
    required this.isActive,
    required this.remarks,
    required this.decisionByName,
    required this.checkerUserName,
    required this.designationName,
  });

  factory PmisTicketChecker.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    int? parseIntNullable(dynamic v) => v == null ? null : int.tryParse(v.toString());
    bool parseBool(dynamic v) =>
        v == true || v?.toString().toLowerCase() == 'true' || v == 1;
    String? s(dynamic v) => v == null ? null : v.toString();

    return PmisTicketChecker(
      tcId: parseInt(json['tcId']),
      levelNo: parseInt(json['levelNo']),
      designationMstId: parseIntNullable(json['designationMstId']),
      checkerUserMstId: parseIntNullable(json['checkerUserMstId']),
      decisionStatus: s(json['decisionStatus']),
      decisionBy: s(json['decisionBy']),
      decisionDt: s(json['decisionDt']),
      decisionRemarks: s(json['decisionRemarks']),
      latitude: s(json['latitude']),
      longitude: s(json['longitude']),
      geoAccuracyM: s(json['geoAccuracyM']),
      geoSource: s(json['geoSource']),
      isActive: parseBool(json['isActive']),
      remarks: s(json['remarks']),
      decisionByName: s(json['decisionByName']),
      checkerUserName: s(json['checkerUserName']),
      designationName: s(json['designationName']),
    );
  }

  @override
  List<Object?> get props => [
        tcId,
        levelNo,
        designationMstId,
        checkerUserMstId,
        decisionStatus,
        decisionBy,
        decisionDt,
        decisionRemarks,
        latitude,
        longitude,
        geoAccuracyM,
        geoSource,
        isActive,
        remarks,
        decisionByName,
        checkerUserName,
        designationName,
      ];
}

/// PMIS may send mixed shapes; only include real maps so [fromJson] never throws.
List<Map<String, dynamic>> _ticketFieldAttachmentsFromJson(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

class PmisTicketFieldValue extends Equatable {
  final int tfvId;
  final dynamic valText;
  final dynamic valNumeric;
  final dynamic valInt;
  final dynamic valDate;
  final Map<String, dynamic> valJson;
  final String? latitude;
  final String? longitude;
  final String? geoAccuracyM;
  final String? geoSource;
  final bool isActive;
  final String? remarks;
  final List<Map<String, dynamic>> attachments;
  final String? subActivityName;
  final String? subActivityDataType;
  final String? subActivityControlType;
  final bool? isRequired;
  final int? seqNo;
  final dynamic minVal;
  final dynamic maxVal;
  final dynamic configJson;
  final int? linkMmId;

  const PmisTicketFieldValue({
    required this.tfvId,
    required this.valText,
    required this.valNumeric,
    required this.valInt,
    required this.valDate,
    required this.valJson,
    required this.latitude,
    required this.longitude,
    required this.geoAccuracyM,
    required this.geoSource,
    required this.isActive,
    required this.remarks,
    required this.attachments,
    required this.subActivityName,
    required this.subActivityDataType,
    required this.subActivityControlType,
    required this.isRequired,
    required this.seqNo,
    required this.minVal,
    required this.maxVal,
    required this.configJson,
    required this.linkMmId,
  });

  factory PmisTicketFieldValue.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    int? parseIntNullable(dynamic v) => v == null ? null : int.tryParse(v.toString());
    bool parseBool(dynamic v) =>
        v == true || v?.toString().toLowerCase() == 'true' || v == 1;
    String? s(dynamic v) => v == null ? null : v.toString();
    dynamic pick(List<String> keys) {
      for (final k in keys) {
        if (json.containsKey(k)) return json[k];
      }
      return null;
    }

    return PmisTicketFieldValue(
      tfvId: parseInt(pick(['tfvId', 'tfv_id'])),
      valText: pick(['valText', 'val_text']),
      valNumeric: pick(['valNumeric', 'val_numeric']),
      valInt: pick(['valInt', 'val_int']),
      valDate: pick(['valDate', 'val_date']),
      valJson: (pick(['valJson', 'val_json']) is Map)
          ? Map<String, dynamic>.from(pick(['valJson', 'val_json']) as Map)
          : const <String, dynamic>{},
      latitude: s(pick(['latitude'])),
      longitude: s(pick(['longitude'])),
      geoAccuracyM: s(pick(['geoAccuracyM', 'geo_accuracy_m'])),
      geoSource: s(pick(['geoSource', 'geo_source'])),
      isActive: parseBool(pick(['isActive', 'is_active'])),
      remarks: s(pick(['remarks'])),
      attachments: _ticketFieldAttachmentsFromJson(
        pick(['attachments', 'attachment_list']),
      ),
      subActivityName: s(pick(['subActivityName', 'sub_activity_name'])),
      subActivityDataType: s(
        pick(['subActivityDataType', 'sub_activity_data_type']),
      ),
      subActivityControlType: s(
        pick(['subActivityControlType', 'sub_activity_control_type']),
      ),
      isRequired: pick(['isRequired', 'is_required']) as bool?,
      seqNo: parseIntNullable(pick(['seqNo', 'seq_no'])),
      minVal: pick(['minVal', 'min_val']),
      maxVal: pick(['maxVal', 'max_val']),
      configJson: pick(['configJson', 'config_json']),
      linkMmId: parseIntNullable(pick(['linkMmId', 'link_mm_id'])),
    );
  }

  @override
  List<Object?> get props => [
        tfvId,
        valText,
        valNumeric,
        valInt,
        valDate,
        valJson,
        latitude,
        longitude,
        geoAccuracyM,
        geoSource,
        isActive,
        remarks,
        attachments,
        subActivityName,
        subActivityDataType,
        subActivityControlType,
        isRequired,
        seqNo,
        minVal,
        maxVal,
        configJson,
        linkMmId,
      ];
}

class PmisTicketAttachment extends Equatable {
  final Map<String, dynamic> raw;

  const PmisTicketAttachment({required this.raw});

  factory PmisTicketAttachment.fromJson(Map<String, dynamic> json) =>
      PmisTicketAttachment(raw: json);

  @override
  List<Object?> get props => [raw];
}

class PmisOldDataItem extends Equatable {
  final String? actualStartDt;
  final String? actualEndDt;
  final List<PmisTicketFieldValue> ticketFieldValues;
  final String? makerUserName;
  final bool? isModified;

  const PmisOldDataItem({
    required this.actualStartDt,
    required this.actualEndDt,
    required this.ticketFieldValues,
    required this.makerUserName,
    required this.isModified,
  });

  factory PmisOldDataItem.fromJson(Map<String, dynamic> json) {
    String? s(dynamic v) => v == null ? null : v.toString();
    return PmisOldDataItem(
      actualStartDt: s(json['actualStartDt'] ?? json['actual_start_dt']),
      actualEndDt: s(json['actualEndDt'] ?? json['actual_end_dt']),
      ticketFieldValues: ((json['ticketFieldValues'] ??
                      json['ticket_field_values']) as List<dynamic>? ??
              [])
          .map((e) => PmisTicketFieldValue.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      makerUserName: s(json['makerUserName'] ?? json['maker_user_name']),
      isModified: (json['isModified'] ?? json['is_modified']) as bool?,
    );
  }

  @override
  List<Object?> get props =>
      [actualStartDt, actualEndDt, ticketFieldValues, makerUserName, isModified];
}

/// Attachment id from a PMIS `attachments` map (supports common API key variants).
String? pmisAttachmentIdString(Map<String, dynamic> a) {
  final v = a['attachmentId'] ??
      a['attachment_id'] ??
      a['AttachmentId'] ??
      a['attachmentID'] ??
      a['imgId'] ??
      a['ImgId'] ??
      a['imageId'] ??
      a['ImageId'] ??
      a['photoId'] ??
      a['PhotoId'];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Distinct positive ids for `GET /api/v1/common/DocumentById/{id}` from
/// IMAGE / VIDEO / PDF field rows on the current ticket payload.
List<int> collectPmisActivityTicketDocumentIds(PmisActivityTicketDetail detail) {
  final ids = <int>{};

  void collectFromField(PmisTicketFieldValue f) {
    final t = (f.subActivityDataType ?? '').trim().toUpperCase();
    if (t != 'IMAGE' && t != 'VIDEO' && t != 'PDF') return;
    for (final a in f.attachments) {
      final raw = pmisAttachmentIdString(a);
      if (raw == null) continue;
      final id = int.tryParse(raw);
      if (id != null && id > 0) ids.add(id);
    }
    final vt = f.valText?.toString().trim() ?? '';
    if (vt.isEmpty) return;
    for (final part in vt.split(',')) {
      final id = int.tryParse(part.trim());
      if (id != null && id > 0) ids.add(id);
    }
  }

  for (final f in detail.ticketFieldValues) {
    collectFromField(f);
  }
  for (final old in detail.oldData) {
    for (final f in old.ticketFieldValues) {
      collectFromField(f);
    }
  }
  for (final ta in detail.ticketAttachments) {
    final raw = pmisAttachmentIdString(ta.raw);
    if (raw == null) continue;
    final id = int.tryParse(raw);
    if (id != null && id > 0) ids.add(id);
  }
  return ids.toList()..sort();
}
