import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

class TicketResponse extends Equatable {
  final int pageNo;
  final int pageSize;
  final int totalRecords;
  final List<Ticket> tickets;

  const TicketResponse({
    required this.pageNo,
    required this.pageSize,
    required this.totalRecords,
    required this.tickets,
  });

  factory TicketResponse.fromJson(Map<String, dynamic> json) {
    int? _readInt(List<String> keys) {
      for (final key in keys) {
        final v = json[key];
        if (v == null) continue;
        final parsed = int.tryParse(v.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    final ticketsList = (json['tickets'] ??
            json['data'] ??
            json['records'] ??
            json['items']) as List<dynamic>?;

    final response = TicketResponse(
      pageNo: _readInt(['pageNo', 'page_no', 'pageNumber', 'page_number']) ?? 1,
      pageSize: _readInt(['pageSize', 'page_size']) ?? 50,
      // 0 here means "unknown" – the cubit falls back to lastBatchSize <
      // pageSize to detect the end when the server doesn't return a total.
      totalRecords:
          _readInt(['totalRecords', 'total_records', 'total', 'totalCount']) ??
              0,
      tickets: ticketsList
              ?.map((ticket) => Ticket.fromJson(ticket as Map<String, dynamic>))
              .toList() ??
          [],
    );

    debugPrint(
      "📦 TicketResponse parsed → pageNo=${response.pageNo}, "
      "pageSize=${response.pageSize}, totalRecords=${response.totalRecords}, "
      "tickets=${response.tickets.length}",
    );
    return response;
  }

  Map<String, dynamic> toJson() {
    return {
      'pageNo': pageNo,
      'pageSize': pageSize,
      'totalRecords': totalRecords,
      'tickets': tickets.map((ticket) => ticket.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [pageNo, pageSize, totalRecords, tickets];
}

class Ticket extends Equatable {
  final int ticketSchId;
  final String pvTicketId;
  final String? siteCode;
  final String? cluster;
  final String? operator;
  final String raisedDt;
  final String? lastModifiedDt;
  final String dueDt;
  final int? auditSchId;
  final double? longitude;
  final double? latitude;
  final String? siteDomainName;
  final String? status;
  final int? totalAssets;
  final int? siteId;
  final String? category;
  final String? issueTitle;
  final String? assignedToName;
  final String? priority;

  const Ticket({
    required this.ticketSchId,
    required this.pvTicketId,
    this.siteCode,
    this.cluster,
    this.operator,
    required this.raisedDt,
    this.lastModifiedDt,
    required this.dueDt,
    this.auditSchId,
    this.longitude,
    this.latitude,
    this.siteDomainName,
    this.status,
    this.totalAssets,
    this.siteId,
    this.category,
    this.issueTitle,
    this.assignedToName,
    this.priority,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    // Helper function to safely convert to double
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (e) {
          debugPrint("⚠️ Warning: Could not parse '$value' to double: $e");
          return null;
        }
      }
      return null;
    }

    // Debug logging for status field
    debugPrint("🔍 Ticket.fromJson: Raw status field = '${json['status']}'");
    debugPrint("🔍 Ticket.fromJson: Status field type = ${json['status'].runtimeType}");
    
    final ticket = Ticket(
      ticketSchId: int.tryParse(json['ticket_sch_id'].toString()) ?? 0,
      pvTicketId: json['pv_ticket_id'] ?? '',
      siteCode: json['site_code'],
      cluster: json['cluster'],
      operator: json['operator'],
      raisedDt: json['raised_dt'] ?? '',
      lastModifiedDt: json['last_modified_dt']?.toString(),
      dueDt: json['due_dt'] ?? '',
      auditSchId: json['audit_sch_id'] != null ? int.tryParse(json['audit_sch_id'].toString()) : null,
      longitude: parseDouble(json['longitude']),
      latitude: parseDouble(json['latitude']),
      siteDomainName: json['site_domain_name'],
      status: json['status'],
      totalAssets: json['total_asset_cnt'] != null ? int.tryParse(json['total_asset_cnt'].toString()) : null,
      siteId: json['site_id'] != null ? int.tryParse(json['site_id'].toString()) : null,
      category: json['category']?.toString() ??
          json['asset_category']?.toString() ??
          json['device_category']?.toString(),
      issueTitle: json['issue_title']?.toString() ??
          json['issueTitle']?.toString() ??
          json['issue']?.toString() ??
          json['problem_summary']?.toString() ??
          json['problemSummary']?.toString() ??
          json['fault_description']?.toString() ??
          json['faultDescription']?.toString(),
      assignedToName: json['assigned_to_name']?.toString() ??
          json['assignedToName']?.toString() ??
          json['assigned_to']?.toString(),
      priority: json['priority']?.toString(),
    );
    
    // Debug logging for final ticket object
    debugPrint("🔍 Ticket.fromJson: Final ticket status = '${ticket.status}'");
    
    return ticket;
  }

  Map<String, dynamic> toJson() {
    return {
      'ticket_sch_id': ticketSchId,
      'pv_ticket_id': pvTicketId,
      'site_code': siteCode,
      'cluster': cluster,
      'operator': operator,
      'raised_dt': raisedDt,
      'last_modified_dt': lastModifiedDt,
      'due_dt': dueDt,
      'audit_sch_id': auditSchId,
      'longitude': longitude,
      'latitude': latitude,
      'site_domain_name': siteDomainName,
      'status': status,
      'total_asset_cnt': totalAssets,
      'site_id': siteId,
      'category': category,
      'issue_title': issueTitle,
      'assigned_to_name': assignedToName,
      'priority': priority,
    };
  }

  @override
  List<Object?> get props => [
        ticketSchId,
        pvTicketId,
        siteCode,
        cluster,
        operator,
        raisedDt,
        lastModifiedDt,
        dueDt,
        auditSchId,
        longitude,
        latitude,
        siteDomainName,
        status,
        totalAssets,
        siteId,
        category,
        issueTitle,
        assignedToName,
        priority,
      ];
}

// Ticket filter parameters
class TicketFilterParams extends Equatable {
  final String activityType; // AA, PM, ER
  final String type; // ALL, IN_PROGRESS, COMPLETED, CLOSED, MISSED_DEADLINE
  final int? pageSize;
  final int? pageNo;

  const TicketFilterParams({
    required this.activityType,
    required this.type,
    this.pageSize,
    this.pageNo,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{
      'ActivityType': activityType,
      'type': type,
    };

    if (pageSize != null) {
      params['pageSize'] = pageSize;
    }
    if (pageNo != null) {
      params['pageNo'] = pageNo;
    }

    return params;
  }

  @override
  List<Object?> get props => [activityType, type, pageSize, pageNo];
}

// Ticket type constants
class TicketType {
  static const String all = 'ALL';
  static const String open = 'IN_PROGRESS';
  static const String completed = 'COMPLETED';
  static const String closed = 'CLOSED';
  static const String missedDeadline = 'MISSED_DEADLINE';
  static const String assignedToMe = 'ASSIGNED_TO_ME';
}
