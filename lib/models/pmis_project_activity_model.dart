import 'package:equatable/equatable.dart';

class PmisProjectActivity extends Equatable {
  final String siteName;
  final String moduleName;
  final String subModuleName;
  final String activityName;
  final String? approvalStatus;
  final String? activityStatus;
  final String currentStatus;
  final String status;
  final String plannedStartDt;
  final String plannedEndDt;
  final String? actualStartDt;
  final String? actualEndDt;
  final bool isGeoFenced;
  final String state;
  final String distanceKm;
  final int? distanceM;
  final double? latitude;
  final double? longitude;

  /// Activity ticket id for `pmis/api/v1/project-plan/activity-ticket/{atId}`.
  final int? atId;

  const PmisProjectActivity({
    required this.siteName,
    required this.moduleName,
    required this.subModuleName,
    required this.activityName,
    this.approvalStatus,
    this.activityStatus,
    required this.currentStatus,
    required this.status,
    required this.plannedStartDt,
    required this.plannedEndDt,
    required this.actualStartDt,
    required this.actualEndDt,
    required this.isGeoFenced,
    required this.state,
    required this.distanceKm,
    required this.distanceM,
    this.latitude,
    this.longitude,
    this.atId,
  });

  factory PmisProjectActivity.fromJson(Map<String, dynamic> json) {
    String parseStringFromKeys(List<String> keys) {
      final byLowerKey = <String, dynamic>{
        for (final e in json.entries) e.key.toString().toLowerCase(): e.value,
      };
      for (final key in keys) {
        final value = byLowerKey[key.toLowerCase()];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return '';
    }

    String? nullableStatus(String raw) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final lower = text.toLowerCase();
      if (lower == 'null' || lower == 'n/a' || lower == '-') return null;
      return text;
    }

    int? parseIntNullable(dynamic value) {
      if (value == null) return null;
      return int.tryParse(value.toString());
    }
    double? parseDoubleNullable(dynamic value) {
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    final int? atId = parseIntNullable(
      json['atId'] ??
          json['at_id'] ??
          json['activityTicketId'] ??
          json['activity_ticket_id'],
    );

    // Blue chip: approval_status, else checker_status / checkerStatus.
    var approvalStatus = nullableStatus(
      parseStringFromKeys([
        'approval_status',
        'approvalStatus',
        'approvalstatus',
        'checker_status',
        'checkerStatus',
        'checkerstatus',
      ]),
    );
    final activityStatus = nullableStatus(
      parseStringFromKeys([
        'activity_status',
        'activityStatus',
        'activitystatus',
        'current_status',
        'currentStatus',
        'status',
      ]),
    );
    final currentStatus = (json['current_status'] ?? '').toString();
    final status = (json['status'] ?? '').toString();

    // List API often leaves checker/approval null for Allocated tickets and
    // only fills Unapproved after WIP. Detail always has checkerStatus:
    // Unapproved — mirror that on the card for Allocated.
    if (approvalStatus == null) {
      final isAllocated = [activityStatus, currentStatus, status]
          .whereType<String>()
          .any((s) => s.trim().toUpperCase() == 'ALLOCATED');
      if (isAllocated) {
        approvalStatus = 'Unapproved';
      }
    }

    return PmisProjectActivity(
      siteName: (json['site_name'] ?? '').toString(),
      moduleName: (json['module_name'] ?? '').toString(),
      subModuleName: (json['sub_module_name'] ?? '').toString(),
      activityName: (json['activity_name'] ?? '').toString(),
      approvalStatus: approvalStatus,
      activityStatus: activityStatus,
      currentStatus: currentStatus,
      status: status,
      plannedStartDt: (json['planned_start_dt'] ?? '').toString(),
      plannedEndDt: (json['planned_end_dt'] ?? '').toString(),
      actualStartDt: json['actual_start_dt'] == null
          ? null
          : json['actual_start_dt'].toString(),
      actualEndDt: json['actual_end_dt'] == null ? null : json['actual_end_dt'].toString(),
      isGeoFenced: json['is_geo_fenced'] == true,
      state: (json['state'] ?? '').toString(),
      distanceKm: (json['distance_km'] ?? '').toString(),
      distanceM: parseIntNullable(json['distance_m']),
      latitude: parseDoubleNullable(
        json['latitude'] ?? json['lat'] ?? json['site_latitude'],
      ),
      longitude: parseDoubleNullable(
        json['longitude'] ??
            json['lng'] ??
            json['long'] ??
            json['site_longitude'],
      ),
      atId: atId,
    );
  }

  @override
  List<Object?> get props => [
        siteName,
        moduleName,
        subModuleName,
        activityName,
        approvalStatus,
        activityStatus,
        currentStatus,
        status,
        plannedStartDt,
        plannedEndDt,
        actualStartDt,
        actualEndDt,
        isGeoFenced,
        state,
        distanceKm,
        distanceM,
        latitude,
        longitude,
        atId,
      ];
}

