import 'dart:convert';
import 'package:app/services/pending_requests_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:app/utils/logger.dart';

class PendingRequestsRetryService {
  final PendingRequestsService _pendingRequestsService;

  PendingRequestsRetryService({
    required PendingRequestsService pendingRequestsService,
  }) : _pendingRequestsService = pendingRequestsService;

  /// Retry all pending requests when connectivity is restored
  Future<void> retryAllPendingRequests() async {
    try {
      // Check if we have internet connectivity
      final isConnected = await ConnectivityHelper.isConnected();
      if (!isConnected) {
        Logger.debugLog('📵 PendingRequestsRetryService: No internet connection, skipping retry');
        return;
      }

      Logger.infoLog('🔄 PendingRequestsRetryService: Starting retry of pending requests');

      await ServiceLocator().assetAuditPostService.syncAllPendingRequestsFifo();

    } catch (e) {
      Logger.errorLog('❌ PendingRequestsRetryService: Error during retry process: $e');
    }
  }

  /// Retry a single pending request
  Future<void> _retrySingleRequest(Map<String, dynamic> request) async {
    try {
      final requestId = request['request_id'] as String;
      final url = request['url'] as String;
      final requestDataJson = request['request_data'] as String;

      Logger.debugLog('🔄 PendingRequestsRetryService: Retrying request $requestId with URL: $url');

      // Parse the stored JSON data
      final requestData = jsonDecode(requestDataJson) as List<dynamic>;

      // Use AssetAuditPostService to sync the request (handles CM specially)
      await ServiceLocator().assetAuditPostService.syncRequestsWhenUserComesOnline(
        url,
        requestData,
        requestId,
      );

      Logger.infoLog('✅ PendingRequestsRetryService: Successfully synced request $requestId');

    } catch (e) {
      Logger.errorLog('❌ PendingRequestsRetryService: Error retrying request ${request['request_id']}: $e');
      
      // Update request status to failed
      await _pendingRequestsService.updateRequestStatus(
        requestId: request['request_id'] as String,
        status: 'failed',
        errorMessage: e.toString(),
      );
    }
  }

  /// Check and retry pending requests periodically
  Future<void> startPeriodicRetry() async {
    // This could be called from a background service or when the app comes to foreground
    await retryAllPendingRequests();
  }
}
