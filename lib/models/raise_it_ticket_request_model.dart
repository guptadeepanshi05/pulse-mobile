class RaiseItTicketCommentRequest {
  final int? iaitcId;
  final String? comments;
  final int? itAssetAttachmentId;
  final bool? isActive;
  final String? remarks;
  final String? attachmentName;
  final String? commentedByName;
  final String? commentedDt;

  const RaiseItTicketCommentRequest({
    this.iaitcId,
    this.comments,
    this.itAssetAttachmentId,
    this.isActive,
    this.remarks,
    this.attachmentName,
    this.commentedByName,
    this.commentedDt,
  });

  factory RaiseItTicketCommentRequest.fromJson(Map<String, dynamic> json) {
    return RaiseItTicketCommentRequest(
      iaitcId: _intOrNull(json['iaitcId']),
      comments: _strOrNull(json['comments']),
      itAssetAttachmentId: _intOrNull(json['itAssetAttachmentId']),
      isActive: json['isActive'] as bool?,
      remarks: _strOrNull(json['remarks']),
      attachmentName: _strOrNull(json['attachmentName']),
      commentedByName: _strOrNull(json['commentedByName']),
      commentedDt: _strOrNull(
        json['commentedDt'] ?? json['createdDt'] ?? json['modifiedDt'],
      ),
    );
  }

  static String? _strOrNull(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() {
    return {
      'iaitcId': iaitcId ?? 0,
      'comments': comments ?? '',
      if (itAssetAttachmentId != null && itAssetAttachmentId! > 0)
        'itAssetAttachmentId': itAssetAttachmentId,
      'isActive': isActive ?? true,
      if (remarks != null && remarks!.trim().isNotEmpty) 'remarks': remarks,
      if (attachmentName != null && attachmentName!.trim().isNotEmpty)
        'attachmentName': attachmentName,
      if (commentedByName != null && commentedByName!.trim().isNotEmpty)
        'commentedByName': commentedByName,
      if (commentedDt != null && commentedDt!.trim().isNotEmpty)
        'commentedDt': commentedDt,
    };
  }
}

class RaiseItTicketRequest {
  final int? iaitId;
  final int iatmId;
  final int iamId;
  final String issueTitle;
  final String issueDescription;
  final String priority;
  final int? iaismId;
  final String assignedToId;
  final int? closedById;
  final String? closedDt;
  final String? closedRemarks;
  final bool? isActive;
  final String? remarks;
  final List<RaiseItTicketCommentRequest>? ticketComments;
  final String? ticketNumber;
  final String assignedToName;
  final String? closedByName;
  final String? ticketStatus;
  final int? itAssetIssueAttachmentId;

  const RaiseItTicketRequest({
    this.iaitId,
    required this.iatmId,
    required this.iamId,
    required this.issueTitle,
    required this.issueDescription,
    required this.priority,
    this.iaismId,
    required this.assignedToId,
    this.closedById,
    this.closedDt,
    this.closedRemarks,
    this.isActive,
    this.remarks,
    this.ticketComments,
    this.ticketNumber,
    this.assignedToName = '',
    this.closedByName,
    this.ticketStatus,
    this.itAssetIssueAttachmentId,
  });

  Map<String, dynamic> toJson() {
    return {
      'iaitId': iaitId ?? 0,
      'iatmId': iatmId,
      'iamId': iamId,
      'issueTitle': issueTitle,
      'issueDescription': issueDescription,
      'priority': priority,
      if (iaismId != null) 'iaismId': iaismId,
      'assignedToId': assignedToId,
      if (closedById != null) 'closedById': closedById,
      if (closedDt != null) 'closedDt': closedDt,
      if (closedRemarks != null) 'closedRemarks': closedRemarks,
      if (isActive != null) 'isActive': isActive,
      if (remarks != null) 'remarks': remarks,
      if (ticketComments != null && ticketComments!.isNotEmpty)
        'ticketComments': ticketComments!.map((c) => c.toJson()).toList(),
      if (ticketNumber != null) 'ticketNumber': ticketNumber,
      'assignedToName': assignedToName,
      if (closedByName != null) 'closedByName': closedByName,
      if (ticketStatus != null) 'ticketStatus': ticketStatus,
      if (itAssetIssueAttachmentId != null && itAssetIssueAttachmentId! > 0)
        'itAssetIssueAttachmentId': itAssetIssueAttachmentId,
    };
  }
}

class RaiseItTicketPostResult {
  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? data;

  const RaiseItTicketPostResult({
    required this.success,
    this.errorMessage,
    this.data,
  });
}
