import 'package:app/models/it_asset_code_model.dart';
import 'package:app/models/it_asset_type_model.dart';
import 'package:app/models/raise_it_ticket_detail_model.dart';
import 'package:app/models/raise_it_ticket_model.dart';
import 'package:app/models/raise_it_ticket_request_model.dart';
import 'package:app/models/raise_it_ticket_status_model.dart';
import 'package:app/models/raise_ticket_assigned_to_model.dart';
import 'package:app/services/api_service.dart';
import 'package:app/utils/logger.dart';

class RaiseItTicketService {
  final ApiService _apiService;

  RaiseItTicketService({required ApiService apiService}) : _apiService = apiService;

  /// GET /api/v1/it-asset/asset-type/dropdown
  Future<ResponseResult<List<ItAssetType>>> getAssetType() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        path: '/api/v1/it-asset/asset-type/dropdown',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage: response.errorMessage ?? 'Failed to load asset types',
          statusCode: response.statusCode,
        );
      }

      final raw = response.data!;

      final assetTypes = <ItAssetType>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          final item = raw[i];
          if (item is Map<String, dynamic>) {
            assetTypes.add(ItAssetType.fromJson(item));
          } else if (item is Map) {
            assetTypes.add(
              ItAssetType.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (e) {
          Logger.errorLog(
            '[RaiseItTicketService] Error parsing asset type at index $i: $e',
          );
        }
      }

      return ResponseResult.success(assetTypes, response.statusCode);
    } catch (e) {
      Logger.errorLog('[RaiseItTicketService] Exception in getAssetType: $e');
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  /// GET /api/v1/it-asset/it-asset/dropdown/{iatmId}
  Future<ResponseResult<ItAssetCodeDropdown>> getAssetCode(int iatmId) async {
    try {
      final response = await _apiService.get<dynamic>(
        path: '/api/v1/it-asset/it-asset/dropdown/$iatmId',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage: response.errorMessage ?? 'Failed to load asset codes',
          statusCode: response.statusCode,
        );
      }

      final dropdown = ItAssetCodeDropdown.fromResponse(response.data);
      return ResponseResult.success(dropdown, response.statusCode);
    } catch (e) {
      Logger.errorLog('[RaiseItTicketService] Exception in getAssetCode: $e');
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  /// GET /api/v1/it-asset/raise-ticket/assigned-to-dropdown
  Future<ResponseResult<List<RaiseTicketAssignedTo>>>
      getRaiseTicketAssignedTo() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        path: '/api/v1/it-asset/raise-ticket/assigned-to-dropdown',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage:
              response.errorMessage ?? 'Failed to load assigned-to list',
          statusCode: response.statusCode,
        );
      }

      final raw = response.data!;
      final assignees = <RaiseTicketAssignedTo>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          final item = raw[i];
          if (item is Map<String, dynamic>) {
            assignees.add(RaiseTicketAssignedTo.fromJson(item));
          } else if (item is Map) {
            assignees.add(
              RaiseTicketAssignedTo.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (e) {
          Logger.errorLog(
            '[RaiseItTicketService] Error parsing assigned-to at index $i: $e',
          );
        }
      }

      return ResponseResult.success(assignees, response.statusCode);
    } catch (e) {
      Logger.errorLog(
        '[RaiseItTicketService] Exception in getRaiseTicketAssignedTo: $e',
      );
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  /// GET /api/v1/it-asset/it-asset-issue-status/dropdown
  Future<ResponseResult<List<RaiseItTicketStatus>>> getRaiseTicketStatus() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        path: '/api/v1/it-asset/it-asset-issue-status/dropdown',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage:
              response.errorMessage ?? 'Failed to load ticket status list',
          statusCode: response.statusCode,
        );
      }

      final raw = response.data!;
      final statuses = <RaiseItTicketStatus>[];
      for (var i = 0; i < raw.length; i++) {
        try {
          final item = raw[i];
          if (item is Map<String, dynamic>) {
            statuses.add(RaiseItTicketStatus.fromJson(item));
          } else if (item is Map) {
            statuses.add(
              RaiseItTicketStatus.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        } catch (e) {
          Logger.errorLog(
            '[RaiseItTicketService] Error parsing ticket status at index $i: $e',
          );
        }
      }

      return ResponseResult.success(statuses, response.statusCode);
    } catch (e) {
      Logger.errorLog(
        '[RaiseItTicketService] Exception in getRaiseTicketStatus: $e',
      );
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  /// GET /api/v1/mobile/ItRaiseTickets
  Future<ResponseResult<List<RaiseItTicket>>> getAllRaiseTickets() async {
    try {
      final response = await _apiService.get<dynamic>(
        path: '/api/v1/mobile/ItRaiseTickets',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage:
              response.errorMessage ?? 'Failed to load raise IT tickets',
          statusCode: response.statusCode,
        );
      }

      final tickets = RaiseItTicket.listFromResponse(response.data);
      Logger.infoLog(
        '[RaiseItTicketService] Loaded ${tickets.length} raise IT ticket(s)',
      );
      return ResponseResult.success(tickets, response.statusCode);
    } catch (e) {
      Logger.errorLog(
        '[RaiseItTicketService] Exception in getAllRaiseTickets: $e',
      );
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  /// GET /api/v1/it-asset/it-asset-issue-ticket/{iaitId}
  Future<ResponseResult<RaiseItTicketDetail>> getRaiseTicketData(
    int iaitId,
  ) async {
    try {
      final response = await _apiService.get<dynamic>(
        path: '/api/v1/it-asset/it-asset-issue-ticket/$iaitId',
      );

      if (!response.isSuccess || response.data == null) {
        return ResponseResult.error(
          errorMessage:
              response.errorMessage ?? 'Failed to load raise IT ticket',
          statusCode: response.statusCode,
        );
      }

      final map = _unwrapDetailMap(response.data);
      if (map == null) {
        return ResponseResult.error(
          errorMessage: 'Invalid raise IT ticket response',
          statusCode: response.statusCode,
        );
      }

      final detail = RaiseItTicketDetail.fromJson(map);
      Logger.infoLog(
        '[RaiseItTicketService] Loaded raise IT ticket iaitId: $iaitId',
      );
      Logger.debugLog(
        '[RaiseItTicketService] Ticket detail JSON keys: ${map.keys.toList()}',
      );
      Logger.debugLog(
        '[RaiseItTicketService] Parsed itAssetIssueAttachmentId='
        '${detail.itAssetIssueAttachmentId}, '
        'itAssetIssueAttachmentName=${detail.itAssetIssueAttachmentName}',
      );
      return ResponseResult.success(detail, response.statusCode);
    } catch (e) {
      Logger.errorLog(
        '[RaiseItTicketService] Exception in getRaiseTicketData: $e',
      );
      return ResponseResult.error(
        errorMessage: 'Exception occurred: ${e.toString()}',
      );
    }
  }

  Map<String, dynamic>? _unwrapDetailMap(dynamic data) {
    final direct = _responseAsMap(data);
    if (direct != null && direct.containsKey('iaitId')) {
      return direct;
    }
    if (direct != null) {
      for (final key in ['data', 'result', 'ticket']) {
        final nested = direct[key];
        final map = _responseAsMap(nested);
        if (map != null && map.containsKey('iaitId')) {
          return map;
        }
      }
    }
    return direct;
  }

  /// POST /api/v1/it-asset/it-asset-issue-ticket
  Future<RaiseItTicketPostResult> postRaiseITTicket(
    RaiseItTicketRequest request,
  ) async {
    try {
      final response = await _apiService.post<dynamic>(
        path: '/api/v1/it-asset/it-asset-issue-ticket',
        data: request.toJson(),
      );

      if (_isPostSuccess(response)) {
        final data = _responseAsMap(response.data);
        if (data != null && data['success'] == false) {
          return RaiseItTicketPostResult(
            success: false,
            errorMessage:
                _extractErrorMessage(data) ?? 'Failed to raise IT ticket',
          );
        }
        Logger.infoLog('[RaiseItTicketService] Raise IT ticket posted successfully');
        return RaiseItTicketPostResult(
          success: true,
          data: data,
        );
      }

      final message = _extractErrorMessage(response.data) ??
          response.errorMessage ??
          'Failed to raise IT ticket';
      Logger.errorLog('[RaiseItTicketService] Post failed: $message');
      return RaiseItTicketPostResult(success: false, errorMessage: message);
    } catch (e) {
      Logger.errorLog(
        '[RaiseItTicketService] Exception in postRaiseITTicket: $e',
      );
      return RaiseItTicketPostResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  bool _isPostSuccess(ResponseResult<dynamic> response) {
    if (response.errorMessage != null) return false;
    final code = response.statusCode;
    return code != null && code >= 200 && code < 300;
  }

  Map<String, dynamic>? _responseAsMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data);
      return map['error']?.toString() ??
          map['message']?.toString() ??
          map['errorMessage']?.toString();
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }
}
