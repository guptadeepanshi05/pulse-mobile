import 'package:app/models/raise_it_ticket_request_model.dart';

class RaiseItTicketDetail {
  final int iaitId;
  final int iatmId;
  final int iamId;
  final String issueTitle;
  final String issueDescription;
  final String priority;
  final int? iaismId;
  final int? assignedToId;
  final int? closedById;
  final String? closedDt;
  final String? closedRemarks;
  final bool isActive;
  final String? remarks;
  final List<RaiseItTicketCommentRequest> ticketComments;
  final String ticketNumber;
  final String assignedToName;
  final String? closedByName;
  final String? ticketStatus;
  final int? itAssetIssueAttachmentId;
  final String? itAssetIssueAttachmentName;

  const RaiseItTicketDetail({
    required this.iaitId,
    required this.iatmId,
    required this.iamId,
    this.issueTitle = '',
    this.issueDescription = '',
    this.priority = '',
    this.iaismId,
    this.assignedToId,
    this.closedById,
    this.closedDt,
    this.closedRemarks,
    this.isActive = true,
    this.remarks,
    this.ticketComments = const [],
    this.ticketNumber = '',
    this.assignedToName = '',
    this.closedByName,
    this.ticketStatus,
    this.itAssetIssueAttachmentId,
    this.itAssetIssueAttachmentName,
  });

  factory RaiseItTicketDetail.fromJson(Map<String, dynamic> json) {
    return RaiseItTicketDetail(
      iaitId: _intVal(json['iaitId']),
      iatmId: _intVal(json['iatmId']),
      iamId: _intVal(json['iamId']),
      issueTitle: _str(json['issueTitle']),
      issueDescription: _str(json['issueDescription']),
      priority: _str(json['priority']),
      iaismId: _intOrNull(json['iaismId']),
      assignedToId: _intOrNull(json['assignedToId']),
      closedById: _intOrNull(json['closedById']),
      closedDt: _strOrNull(json['closedDt']),
      closedRemarks: _strOrNull(json['closedRemarks']),
      isActive: json['isActive'] == true,
      remarks: _strOrNull(json['remarks']),
      ticketComments: _parseComments(json['ticketComments']),
      ticketNumber: _str(json['ticketNumber']),
      assignedToName: _str(json['assignedToName']),
      closedByName: _strOrNull(json['closedByName']),
      ticketStatus: _strOrNull(json['ticketStatus']),
      itAssetIssueAttachmentId: _intOrNull(json['itAssetIssueAttachmentId']),
      itAssetIssueAttachmentName:
          _strOrNull(json['itAssetIssueAttachmentName']),
    );
  }

  static List<RaiseItTicketCommentRequest> _parseComments(dynamic raw) {
    if (raw is! List) return [];
    final comments = <RaiseItTicketCommentRequest>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        comments.add(RaiseItTicketCommentRequest.fromJson(item));
      } else if (item is Map) {
        comments.add(
          RaiseItTicketCommentRequest.fromJson(
            Map<String, dynamic>.from(item),
          ),
        );
      }
    }
    return comments;
  }

  static String _str(dynamic value) {
    if (value == null) return '';
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    return s;
  }

  static String? _strOrNull(dynamic value) {
    final s = _str(value);
    return s.isEmpty ? null : s;
  }

  static int _intVal(dynamic value) {
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }
}
