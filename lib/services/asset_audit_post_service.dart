import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:app/models/location_model.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/upload_dcouments.dart';
import 'package:app/utils.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:app/utils/toastbar.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

/// Service for posting asset audit data with photo ID replacement
/// This service handles replacing local unique_id photo IDs with server_id
/// and adding photo_taken_ts using the images table's created_at timestamp
class AssetAuditPostService {
  /// Post asset audit data with photo ID replacement
  /// This method replaces all photo_id values with server_id from images table
  /// and adds photo_taken_ts using the images table's created_at timestamp
  Future<void> postAssetAuditDataWithPhotoReplacement({
    required List<dynamic> requests,
    required ActivityTypeEnum activityType,
    required bool isLastPage,
  }) async {
    // Prevent posting empty arrays to avoid server errors
    if (requests.isEmpty) {
      Logger.errorLog(
        '❌ AssetAuditPostService: Attempted to post empty array, aborting to prevent server error',
      );
      Logger.errorLog(
        '❌ This indicates a bug in the calling code - empty arrays should be filtered before calling this service',
      );
      return;
    }

    try {
      // Get current location with offline support
      LocationModel finalLocation;

      try {
        finalLocation = await LocationService.getCurrentLocation();
      } catch (e) {
        Logger.infoLog('Error getting location: $e');

        Toastbar.showErrorWithoutContext(
          "Please enable your location first to proceed further.",
        );

        rethrow;
      }
      // Check internet connectivity
      final isConnected = await ConnectivityHelper.isConnected();
      Logger.infoLog("user is connected to internet: $isConnected");

      //create deep copy of requests so that actual data preserves
      List<dynamic> copiedRequests = jsonDecode(jsonEncode(requests));
      if (isConnected) {
        Logger.debugLog(
          "User is connected to the internet, trying to post the data",
        );

        try {
          await _processRequestsForImages(copiedRequests);
          Logger.debugLog("data after processing images: $copiedRequests");
        } catch (e) {
          Logger.errorLog("error in processing images: $e");
        }
      } else {
        Logger.debugLog(
          "User is not connected to the internet, saving data locally",
        );
      }
      DataTransformationHelper.updateMetadataInRequest(
        copiedRequests,
        finalLocation,
      );
      await _postRequestsIfConnectedOrSaveToSqlite(
        copiedRequests,
        isConnected,
        activityType,
        isLastPage,
      );
    } catch (e) {
      Logger.errorLog(
        'AssetAuditPostService: Exception while posting data: $e',
      );

      rethrow;
    }
  }

  // Monotonically increasing suffix to guarantee unique request_id even when two
  // offline saves land in the same millisecond (e.g. quick PM page navigation).
  static int _offlineRequestSeq = 0;

  // Track in-flight sync operations to prevent the SAME pending request from
  // being POSTed by two concurrent sync runs. Without this guard, rapid taps on
  // the Sync button (or auto-sync racing with manual sync) cause the server to
  // receive the same payload N times — visible as N copies of the same record
  // (e.g. 17× duplicated `pclsri_id` / `pclsrd_id` for the same checklist item).
  static final Set<String> _inFlightSyncRequestIds = <String>{};
  static bool _isSyncRunning = false;

  /// Whether an offline-sync sweep is currently in progress.
  /// Callers (sync buttons) should check this and bail out instead of starting
  /// a parallel sweep, otherwise they'd POST the same pending rows again.
  static bool get isSyncInProgress => _isSyncRunning;

  /// Mark a sync sweep as started. Returns true if acquired, false if another
  /// sweep is already running. Pair with [endSyncSweep] in a `finally` block.
  static bool beginSyncSweep() {
    if (_isSyncRunning) return false;
    _isSyncRunning = true;
    return true;
  }

  static void endSyncSweep() {
    _isSyncRunning = false;
  }

  Future<void> _postRequestsIfConnectedOrSaveToSqlite(
    List<dynamic> requests,
    bool isConnected,
    ActivityTypeEnum activityType,
    bool isLastPage,
  ) async {
    String url = '/api/v1/mobile/';
    switch (activityType) {
      case ActivityTypeEnum.assetAudit:
        url += 'AssetAuditSiteResp';
        break;
      case ActivityTypeEnum.preventiveMaintenance:
        url += 'PmResponse';
        break;
      case ActivityTypeEnum.energyReading:
        url += 'EbBillReading';
        break;

      case ActivityTypeEnum.correctiveMaintenance:
        url += 'correctiveMaintenance';
        break;
      case ActivityTypeEnum.siteVisit:
      case ActivityTypeEnum.siteVisitLog:
      case ActivityTypeEnum.siteVisitDocs:
        url = 'api/v1/om-schedule/siteVisitLog';
        break;
      case ActivityTypeEnum.generalInspection:
      case ActivityTypeEnum.generalInspectionSelf:
      case ActivityTypeEnum.generalInspChecklist:
        url = 'api/v1/om-schedule/genInspection';
        break;
      case ActivityTypeEnum.incident:
      case ActivityTypeEnum.incidentSelf:
        url = 'api/v1/om-schedule/incident';
        break;
      case ActivityTypeEnum.assetUpload:
        url += 'AssetAuditSiteResp';
        break;
      case ActivityTypeEnum.projectTicket:
      case ActivityTypeEnum.activityTicket:
        url += 'AssetAuditSiteResp';
        break;
      case ActivityTypeEnum.itAssetIssueTicket:
        Logger.debugLog(
          'IT raise tickets use it-asset API directly, not mobile batch post',
        );
        return;
    }

    if (activityType == ActivityTypeEnum.siteVisit ||
        activityType == ActivityTypeEnum.generalInspection ||
        activityType == ActivityTypeEnum.generalInspectionSelf ||
        activityType == ActivityTypeEnum.generalInspChecklist) {
      // These endpoints don't need the status parameter
      // URL is already set in the switch statement
    } else {
      url += '?status=${isLastPage ? 'COMPLETED' : 'IN-PROGRESS'}';
    }
    if (isConnected) {
      try {
        await _postDataToApi(url, requests);
        return;
      } catch (e) {
        Logger.errorLog("error in posting data: $e");
      }
    }
    Logger.infoLog(
      "User is not connected to the internet, saving data in local db",
    );
    // Ensure uniqueness even when multiple offline saves land in the same ms
    // (was causing PM IN-PROGRESS saves to be overwritten by the COMPLETED one).
    final uniqueSuffix = ++_offlineRequestSeq;
    final requestId =
        'asset_audit_${DateTime.now().millisecondsSinceEpoch}_$uniqueSuffix';
    bool isSaved = await ServiceLocator().pendingRequestService
        .savePendingRequest(
          requestId: requestId,
          url: url,
          headers: {},
          jsonEncodedRequestData: jsonEncode(requests),
        );
    if (isSaved) {
      Logger.infoLog(
        "Data saved to DB successfully (requestId: $requestId, url: $url)",
      );

      Toastbar.showSuccessToastWithoutContext(
        "Data submission failed. Don’t worry—your data has been saved on this device and can be synced when you’re back online.",
      );
    } else {
      Logger.errorLog(
        '❌ Failed to save pending request to SQLite (requestId: $requestId, url: $url)',
      );
      throw Exception('Failed to save data to database');
    }
  }

  Future<void> _postDataToApi(String url, List<dynamic> requests) async {
    Logger.infoLog("User is connected to internet, posting data to API");
    final response;
    if (url.contains("api/v1/mobile/uploadsSelfie")) {
      response = await _uploadSelfieWithoutCache(requests);
    } else if (url.contains("api/v1/om-schedule/siteVisitLog") ||
        url.contains("api/v1/om-schedule/genInspection") ||
        url.contains("api/v1/om-schedule/incidentTicket") ||
        url.contains("api/v1/mobile/assetUpload") ||
        url.contains("/assetUpload")) {
      // These endpoints expect a single object, not an array
      response = await ServiceLocator().apiService.post<dynamic>(
        path: url,
        data: requests.isNotEmpty ? requests.first : {},
      );
    } else {
      response = await ServiceLocator().apiService.post<List<dynamic>>(
        path: url,
        data: DataTransformationHelper.convertListToCamelCase(requests),
      );
    }
    if (response != null && response.isSuccess && response.data != null) {
      Toastbar.showSuccessToastWithoutContext("Data posted successfully");
      Logger.infoLog("Data posted successfully");
      await _syncLocalTicketRowAfterSuccessfulAssetAuditSiteResp(
        url: url,
        requests: requests,
      );
    } else {
      Toastbar.showErrorWithoutContext(
        "Data posted failed",
      );
      throw Exception((response.errorMessage ?? 'Unknown error from server'));
    }
  }

  /// After a successful [AssetAuditSiteResp] call, align SQLite with the server
  /// (`?status=COMPLETED` / `IN-PROGRESS`) so [MyTicketsScreen] matches [TicketScreen].
  Future<void> _syncLocalTicketRowAfterSuccessfulAssetAuditSiteResp({
    required String url,
    required List<dynamic> requests,
  }) async {
    if (!url.contains('AssetAuditSiteResp')) return;
    final statusMatch = RegExp(r'[?&]status=([^&]+)').firstMatch(url);
    if (statusMatch == null) return;
    final statusValue = Uri.decodeComponent(statusMatch.group(1)!).trim();
    if (statusValue.isEmpty) return;
    if (requests.isEmpty) return;

    final first = requests.first;
    if (first is! Map) return;
    final firstMap = Map<String, dynamic>.from(first);
    // Asset Upload offline queue uses this URL shape but a different body; skip.
    if (firstMap.containsKey('assetUploadItems')) return;

    String? siteAuditSchId;
    for (final r in requests) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final id = m['site_audit_sch_id'] ?? m['siteAuditSchId'];
      if (id != null && id.toString().trim().isNotEmpty) {
        siteAuditSchId = id.toString().trim();
        break;
      }
    }
    if (siteAuditSchId == null) return;

    try {
      final dataService = ServiceLocator().centralAssetAuditDataService;
      await dataService.updateRawApiDataStatus(
        siteAuditSchId: siteAuditSchId,
        status: statusValue,
      );
      Logger.debugLog(
        '✅ My Tickets: raw_api_data.status → $statusValue for $siteAuditSchId (after AssetAuditSiteResp)',
      );
      await _mergePageHeaderStatusIntoStoredApiData(
        siteAuditSchId: siteAuditSchId,
        status: statusValue,
      );
    } catch (e) {
      Logger.errorLog(
        '⚠️ My Tickets status sync after AssetAuditSiteResp failed: $e',
      );
    }
  }

  Future<void> _mergePageHeaderStatusIntoStoredApiData({
    required String siteAuditSchId,
    required String status,
  }) async {
    try {
      final dataService = ServiceLocator().centralAssetAuditDataService;
      final raw = await dataService.getRawApiData(siteAuditSchId);
      if (raw == null) return;
      final api = Map<String, dynamic>.from(raw.apiData);
      final ph = api['pageHeader'];
      if (ph is! List || ph.isEmpty) return;
      final head = ph.first;
      if (head is! Map) return;
      final updatedHeader = Map<String, dynamic>.from(head);
      updatedHeader['status'] = status;
      final newPh = List<dynamic>.from(ph);
      newPh[0] = updatedHeader;
      api['pageHeader'] = newPh;
      await dataService.updateRawApiData(
        siteAuditSchId: siteAuditSchId,
        apiData: api,
      );
    } catch (e) {
      Logger.errorLog('⚠️ Could not merge pageHeader.status into api_data: $e');
    }
  }

  Future<dynamic> _uploadSelfieWithoutCache(List<dynamic> requests) async {
    try {
      Uint8List imageBytes;
      dynamic decodedRequest = requests.first;
      String imageData = decodedRequest['selfie'];
      if (imageData.startsWith('data:image/')) {
        // Remove data URL prefix
        final base64String = imageData.split(',')[1];
        imageBytes = base64Decode(base64String);
      } else {
        // Assume it's raw base64
        imageBytes = base64Decode(imageData);
      }

      // Create a temporary file for upload
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      // Create multipart file
      final multipartFile = await MultipartFile.fromFile(
        tempFile.path,
        filename: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      decodedRequest['selfie'] = multipartFile;
      final response = await ServiceLocator().apiService
          .post<Map<String, dynamic>>(
            path: "api/v1/mobile/uploadsSelfie",
            data: decodedRequest,
            useFormDataFormat: true,
          );
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<void> syncRequestsWhenUserComesOnline(
    String url,
    List<dynamic> requests,
    String requestId,
  ) async {
    // Guard: if this same pending request is already being processed by another
    // sync sweep (rapid Sync taps, screen switches, auto-sync, etc.), skip it.
    // Otherwise the server receives the same payload twice -> duplicate
    // `pclsri_id` / `pclsrd_id` rows for one logical checklist response.
    if (_inFlightSyncRequestIds.contains(requestId)) {
      Logger.infoLog(
        '⏭️ Skipping sync for $requestId — already in-flight in another sweep',
      );
      return;
    }
    _inFlightSyncRequestIds.add(requestId);
    try {
      List<dynamic> copiedRequests = jsonDecode(jsonEncode(requests));

      // Special handling for CM requests
      if (url.contains('/correctiveMaintenance')) {
        await _syncCMRequestWhenOnline(copiedRequests, requestId);
        return;
      } else if (url.contains('/cmRemarks/upload')) {
        // Handle remarks upload separately
        await _syncCMRemarksRequestWhenOnline(copiedRequests, requestId);
        return;
      } else if (url.contains('/incidentTicket')) {
        // Special handling for incident tickets - expects single object, not array
        await _syncIncidentTicketRequestWhenOnline(copiedRequests, requestId);
        return;
      } else if (url.contains('pmis/api/v1/project-plan/activity-ticket')) {
        // PMIS activity ticket sync from offline pending requests.
        await _syncPmisActivityTicketRequestWhenOnline(copiedRequests, requestId);
        return;
      } else if (url.contains('api/v1/mobile/assetUpload') || url.contains('assetUpload')) {
        // Special handling for asset upload - expects single object, not array
        await _syncAssetUploadRequestWhenOnline(copiedRequests, requestId);
        return;
      } else {
        await _processRequestsForImages(copiedRequests);
        await _postDataToApi(url, copiedRequests);
        await ServiceLocator().pendingRequestService.deleteRequest(requestId);
      }
    } catch (e) {
      Logger.errorLog(e.toString());
      rethrow;
    } finally {
      _inFlightSyncRequestIds.remove(requestId);
    }
  }

  Future<void> _syncPmisActivityTicketRequestWhenOnline(
    List<dynamic> requests,
    String requestId,
  ) async {
    try {
      if (requests.isEmpty) {
        Logger.errorLog('PMIS activity ticket requests list is empty!');
        return;
      }
      final first = requests.first;
      final request = first is Map<String, dynamic>
          ? first
          : Map<String, dynamic>.from(first as Map);
      final localAtId = int.tryParse(
        request['_localActivityTicketId']?.toString() ?? '',
      );
      request.remove('_localActivityTicketId');

      Future<void> replaceLocalIds(dynamic node) async {
        if (node is Map<String, dynamic>) {
          for (final entry in node.entries.toList()) {
            final key = entry.key;
            final value = entry.value;
            if (key == 'attachmentId' &&
                value != null &&
                value.toString().contains('LOCAL_IMAGE_ID')) {
              final sid = await ServiceLocator().imageUploadService
                  .getOrUploadPmisDocumentIdFromUniqueId(value.toString());
              if (sid != null && sid.toString().trim().isNotEmpty) {
                node[key] = int.tryParse(sid.toString()) ?? sid.toString();
              }
            } else if (key == 'valText' &&
                value is String &&
                value.contains('LOCAL_IMAGE_ID')) {
              final replaced = <String>[];
              for (final part in value.split(',')) {
                final p = part.trim();
                if (!p.contains('LOCAL_IMAGE_ID')) {
                  replaced.add(p);
                  continue;
                }
                final sid = await ServiceLocator().imageUploadService
                    .getOrUploadPmisDocumentIdFromUniqueId(p);
                replaced.add((sid != null && sid.isNotEmpty) ? sid : p);
              }
              node[key] = replaced.join(',');
            } else {
              await replaceLocalIds(value);
            }
          }
        } else if (node is List) {
          for (final item in node) {
            await replaceLocalIds(item);
          }
        }
      }

      await replaceLocalIds(request);

      final response = await ServiceLocator().apiService.post<dynamic>(
        path: 'pmis/api/v1/project-plan/activity-ticket',
        data: request,
        useFormDataFormat: false,
      );

      if (response.isSuccess) {
        try {
          final atId = localAtId ?? int.tryParse(request['atId']?.toString() ?? '');
          if (atId != null && atId > 0) {
            final schId = atId.toString();
            await ServiceLocator().centralAssetAuditDataService.updateRawApiData(
              siteAuditSchId: schId,
              apiData: request,
            );
            final status = request['currentStatus']?.toString().trim() ?? '';
            if (status.isNotEmpty) {
              await ServiceLocator().centralAssetAuditDataService
                  .updateRawApiDataStatus(
                siteAuditSchId: schId,
                status: status,
              );
            }
          }
        } catch (e) {
          Logger.errorLog('⚠️ PMIS sync local row update failed: $e');
        }
        await ServiceLocator().pendingRequestService.deleteRequest(requestId);
        Toastbar.showSuccessToastWithoutContext(
          'PMIS activity ticket synced successfully',
        );
      } else {
        throw Exception(response.errorMessage ?? 'Unknown error from server');
      }
    } catch (e) {
      Logger.errorLog('Error syncing PMIS activity ticket request: $e');
      rethrow;
    }
  }

  Future<void> _syncIncidentTicketRequestWhenOnline(
    List<dynamic> requests,
    String requestId,
  ) async {
    try {
      Logger.infoLog("Syncing incident ticket request when online");

      if (requests.isEmpty) {
        Logger.errorLog("Incident ticket requests list is empty!");
        return;
      }

      final request = requests.first;
      Logger.infoLog("Processing incident ticket request: ${request.keys}");

      // Process images in the request (convert LOCAL_IMAGE_ID to server ID)
      // This will update the request object in place
      await _processRequestsForImages([request]);

      Logger.infoLog("Processed incident ticket data after image processing");

      // Post to API - send as single object (not array)
      final response = await ServiceLocator().apiService.post<dynamic>(
        path: '/api/v1/om-schedule/incidentTicket',
        data: request, // Send single object, not array
      );

      if (response.isSuccess && response.data != null) {
        Logger.infoLog("Incident ticket synced successfully: ${response.data}");
        Toastbar.showSuccessToastWithoutContext(
          "Incident ticket synced successfully",
        );

        final Map<String, dynamic>? reqMap = request is Map<String, dynamic>
            ? request
            : (request is Map ? Map<String, dynamic>.from(request) : null);
        if (reqMap != null) {
          final tid =
              int.tryParse(reqMap['incidentTicketId']?.toString() ?? '') ?? 0;
          final st = reqMap['status']?.toString().trim() ?? '';
          await ServiceLocator().centralAssetAuditService
              .syncIncidentTicketLocalRow(
            incidentTicketId: tid,
            status: st,
          );
        }

        // Delete from pending requests on success
        await ServiceLocator().pendingRequestService.deleteRequest(requestId);
      } else {
        throw Exception(response.errorMessage ?? 'Unknown error from server');
      }
    } catch (e) {
      Logger.errorLog("Error syncing incident ticket request: $e");
      rethrow;
    }
  }

  Future<void> _syncAssetUploadRequestWhenOnline(
    List<dynamic> requests,
    String requestId,
  ) async {
    try {
      Logger.infoLog("Syncing asset upload request when online");

      if (requests.isEmpty) {
        Logger.errorLog("Asset upload requests list is empty!");
        return;
      }

      final request = requests.first as Map<String, dynamic>;
      Logger.infoLog("Processing asset upload request: ${request.keys}");

      // Process makerSelfieImageId - replace LOCAL_IMAGE_ID with server ID
      final makerSelfieImageId = request['makerSelfieImageId'];
      if (makerSelfieImageId != null &&
          makerSelfieImageId.toString().startsWith('LOCAL_IMAGE_ID_')) {
        Logger.debugLog(
          '🔄 Processing makerSelfieImageId: $makerSelfieImageId',
        );

        final imageModel = await ServiceLocator().imageUploadService
            .getServerIdFromUniqueIdTryUploading(makerSelfieImageId.toString());

        if (imageModel != null && imageModel.serverId != null) {
          final serverId = int.tryParse(imageModel.serverId.toString()) ?? 0;
          request['makerSelfieImageId'] = serverId;
          Logger.debugLog(
            '✅ makerSelfieImageId replaced with server ID: $serverId',
          );
        } else {
          Logger.errorLog(
            '❌ Failed to upload selfie image: $makerSelfieImageId',
          );
          request['makerSelfieImageId'] = null;
        }
      }

      // Process assetUploadItems[].assetUploadItemImages[].photoId
      final assetUploadItems = request['assetUploadItems'] as List<dynamic>?;
      if (assetUploadItems != null) {
        for (final item in assetUploadItems) {
          if (item is Map<String, dynamic>) {
            final assetUploadItemImages =
                item['assetUploadItemImages'] as List<dynamic>?;
            if (assetUploadItemImages != null) {
              for (final image in assetUploadItemImages) {
                if (image is Map<String, dynamic>) {
                  final photoId = image['photoId'];
                  if (photoId != null &&
                      photoId.toString().startsWith('LOCAL_IMAGE_ID_')) {
                    Logger.debugLog(
                      '🔄 Processing asset image photoId: $photoId',
                    );

                    final imageModel = await ServiceLocator().imageUploadService
                        .getServerIdFromUniqueIdTryUploading(
                          photoId.toString(),
                        );

                    if (imageModel != null && imageModel.serverId != null) {
                      final serverId =
                          int.tryParse(imageModel.serverId.toString()) ?? 0;
                      image['photoId'] = serverId;
                      Logger.debugLog(
                        '✅ Asset image photoId replaced with server ID: $serverId',
                      );
                    } else {
                      Logger.errorLog(
                        '❌ Failed to upload asset image: $photoId',
                      );
                      image['photoId'] = null;
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Post to API - send as single object (not array)
      final response = await ServiceLocator().apiService.post<dynamic>(
        path: 'api/v1/mobile/assetUpload',
        data: request, // Send single object, not array
      );

      if (response.isSuccess && response.data != null) {
        Logger.infoLog("Asset upload synced successfully: ${response.data}");
        Toastbar.showSuccessToastWithoutContext(
          "Asset upload synced successfully",
        );

        // Delete from pending requests on success
        await ServiceLocator().pendingRequestService.deleteRequest(requestId);
      } else {

        Toastbar.showErrorWithoutContext(
          "Asset upload failed: ${response.errorMessage}",
        );
        throw Exception(response.errorMessage ?? 'Unknown error from server');
        
      }
    } catch (e) {
      Logger.errorLog("Error syncing asset upload request: $e");
      Toastbar.showErrorWithoutContext(
        "Asset upload failed: ${e.toString()}",
      );
      rethrow;
    }
  }

  Future<void> _syncCMRequestWhenOnline(
    List<dynamic> requests,
    String requestId,
  ) async {
    try {
      Logger.infoLog("Syncing CM request when online");

      if (requests.isEmpty) {
        Logger.errorLog("CM requests list is empty!");
        return;
      }

      final request = requests.first as Map<String, dynamic>;
      Logger.infoLog("Processing CM request: ${request.keys}");

      // Convert to camelCase first (creates a deep copy), then process images on that copy.
      // We must replace LOCAL_IMAGE_ID on the same object we send, else the copy still has old values.
      final processedData = DataTransformationHelper.convertKeysToCamelCase(
        request,
      );

      // Upload all LOCAL_IMAGE_ID photos and replace with server IDs in processedData (the payload we send).
      await _processCMRequestForImages(processedData);
      // FSR document: same as app screen — UploadDocuments before POST, ids stay on JSON body (no post-create FSR multipart).
      await _processCMFsrUploadDocumentsBeforePost(processedData);

      // Extract image IDs before removing them from the request
      final customerPhotoId =
          processedData['customer_photo_id'] ??
          processedData['customerPhotoId'];
      final customerAttachmentId =
          processedData['customer_attachment_id'] ??
          processedData['customerAttachmentId'];

      // Extract original file info for customer attachment (to preserve filename)
      // Support both snake_case (raw stored) and camelCase (after convertKeysToCamelCase)
      final customerOriginalFilePath =
          processedData['customer_original_file_path'] ??
          processedData['customerOriginalFilePath'];
      final customerOriginalFileName =
          processedData['customer_original_file_name'] ??
          processedData['customerOriginalFileName'];

      // Extract attachment name if present, or use original filename
      final customerAttachmentName =
          processedData['customer_attachmen_name'] ??
          processedData['customer_attachment_name'] ??
          customerOriginalFileName;

      Logger.infoLog(
        "Extracted image IDs - customerPhotoId: $customerPhotoId, customerAttachmentId: $customerAttachmentId",
      );
      Logger.infoLog(
        "Extracted attachment names - customerAttachmentName: $customerAttachmentName",
      );

      // Remove image IDs and file info from the request data before creating CM ticket
      processedData.remove('customer_photo_id');
      processedData.remove('customerPhotoId');
      processedData.remove('customer_attachment_id');
      processedData.remove('customerAttachmentId');
      processedData.remove('customer_original_file_path');
      processedData.remove('customer_original_file_name');
      processedData.remove('customer_attachmen_name');
      processedData.remove('customer_attachment_name');
      processedData.remove('fsr_original_file_path');
      processedData.remove('fsrOriginalFilePath');
      processedData.remove('fsr_original_file_name');
      processedData.remove('fsrOriginalFileName');

      // Preserve attachment name in request data if we have it (for API to store the correct name)
      if (customerAttachmentName != null &&
          customerAttachmentName.toString().trim().isNotEmpty) {
        processedData['customer_attachmen_name'] = customerAttachmentName
            .toString()
            .trim();
        processedData['customer_attachment_name'] = customerAttachmentName
            .toString()
            .trim();
      }

      // Create CM ticket using the repository
      final response = await ServiceLocator().cmRepository
          .createCorrectiveMaintenance(processedData);

      Logger.infoLog("CM ticket creation response received: ${response.keys}");

      if (response.containsKey('cmSiteReqId')) {
        final cmSiteReqId = response['cmSiteReqId'] as int;

        Logger.infoLog("CM ticket created with ID: $cmSiteReqId");

        // Upload customer photo and attachments using the extracted IDs
        Logger.infoLog("About to call _uploadCMImagesAndAttachments...");
        Logger.infoLog(
          "customerPhotoId: $customerPhotoId, customerAttachmentId: $customerAttachmentId",
        );
        await _uploadCMImagesAndAttachments(
          customerPhotoId,
          customerAttachmentId,
          cmSiteReqId,
          customerOriginalFilePath: customerOriginalFilePath,
          customerOriginalFileName: customerOriginalFileName,
        );

        // Check for and sync remarks if present
        final cmRemark =
            processedData['cmRemark'] ?? processedData['cm_remark'] ?? '';
        final cmStatus =
            processedData['cmStatus'] ?? processedData['cm_status'] ?? '';
        final cmAttachmentId =
            processedData['cmRemarksFile'] ??
            processedData['cm_remarks_file'] ??
            processedData['cmAttachmentId'] ??
            processedData['cm_attachment_id'];

        if ((cmRemark.toString().trim().isNotEmpty ||
                cmStatus.toString().trim().isNotEmpty) &&
            cmAttachmentId != null &&
            cmAttachmentId.toString().trim().isNotEmpty) {
          Logger.infoLog(
            "Syncing CM remarks with attachment ID: $cmAttachmentId",
          );

          // Get attachment file - try original file first, then reconstruct from ImageUploadService
          File? attachmentFile;
          String?
          attachmentFileName; // Store the filename to pass to saveRemarks

          // Check if original file path is stored (preserves extension and filename)
          // Handle both camelCase and snake_case
          final originalFilePath =
              processedData['originalFilePath'] ??
              processedData['original_file_path'];
          final originalFileName =
              processedData['originalFileName'] ??
              processedData['original_file_name'];

          if (originalFilePath != null &&
              originalFilePath.toString().trim().isNotEmpty) {
            final originalFile = File(originalFilePath.toString());
            if (await originalFile.exists()) {
              Logger.infoLog("Using original file: $originalFilePath");
              attachmentFile = originalFile;
              // Use original filename if available, otherwise use file path
              attachmentFileName =
                  originalFileName?.toString().trim() ??
                  originalFile.path.split('/').last;
            } else {
              Logger.infoLog(
                "Original file not found, will reconstruct from ImageUploadService",
              );
            }
          }

          // If original file not available, reconstruct from ImageUploadService
          if (attachmentFile == null) {
            Logger.infoLog(
              "Retrieving attachment data from ImageUploadService...",
            );
            final attachmentData = await ServiceLocator().imageUploadService
                .getImageUsingUniqueId(cmAttachmentId.toString());

            if (attachmentData != null) {
              Logger.infoLog(
                "Attachment data retrieved, converting to File...",
              );

              // Decode base64 and write to file first to detect file type
              final bytes = base64Decode(attachmentData);

              // Use original filename if available, otherwise detect from binary data
              String fileName;
              if (originalFileName != null &&
                  originalFileName.toString().trim().isNotEmpty) {
                // Sanitize filename to remove invalid characters but preserve name and extension
                final originalName = originalFileName.toString().trim();
                // Remove invalid path characters but keep the name structure
                fileName = originalName.replaceAll(
                  RegExp(r'[<>:"/\\|?*]'),
                  '_',
                );

                // If original filename doesn't have extension, detect from binary data
                if (!fileName.contains('.')) {
                  final detectedExt = _detectFileExtensionFromBytes(bytes);
                  if (detectedExt != null) {
                    fileName = '$fileName$detectedExt';
                    Logger.infoLog(
                      "Added detected extension $detectedExt to filename: $fileName",
                    );
                  }
                }
                Logger.infoLog("Using original filename: $fileName");
              } else {
                // Detect file type from binary data
                final detectedExt = _detectFileExtensionFromBytes(bytes);
                final fileExtension =
                    detectedExt ?? '.pdf'; // Default to PDF if can't detect
                fileName =
                    'cm_remarks_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
                Logger.infoLog(
                  "Original filename not available, detected type: $fileExtension, using generated name: $fileName",
                );
              }

              // Create temporary file with correct filename
              final tempDir = Directory.systemTemp;
              final tempFile = File('${tempDir.path}/$fileName');

              await tempFile.writeAsBytes(bytes);

              attachmentFile = tempFile;
              attachmentFileName =
                  fileName; // Store filename for passing to saveRemarks
              Logger.infoLog(
                "Remarks attachment File created with filename: $fileName",
              );
            } else {
              Logger.errorLog(
                "Failed to retrieve attachment data for ID: $cmAttachmentId",
              );
            }
          }

          if (attachmentFile != null) {
            Logger.infoLog("Remarks attachment File ready, uploading...");

            // Call saveRemarks from repository
            await ServiceLocator().cmRepository.saveRemarks(
              cmSiteReqId,
              cmRemark.toString().trim(),
              cmStatus.toString().trim(),
              attachmentFile,
              originalFileName: attachmentFileName,
            );
            Logger.infoLog("CM remarks uploaded successfully");
          } else {
            Logger.errorLog("Failed to create File for remarks attachment");
          }
        }

        Logger.infoLog("_uploadCMImagesAndAttachments completed");

        // Delete the pending request
        await ServiceLocator().pendingRequestService.deleteRequest(requestId);
        Logger.infoLog("CM sync completed successfully");
      } else {
        Logger.errorLog(
          "Response does not contain cmSiteReqId, response keys: ${response.keys}",
        );
        throw Exception("Failed to create CM ticket");
      }
    } catch (e) {
      Logger.errorLog("Error syncing CM request: $e");
      Logger.errorLog("Stack trace: ${StackTrace.current}");
      rethrow;
    }
  }

  Future<void> _uploadCMImagesAndAttachments(
    dynamic customerPhotoId,
    dynamic customerAttachmentId,
    int cmSiteReqId, {
    dynamic customerOriginalFilePath,
    dynamic customerOriginalFileName,
    dynamic fsrAttachmentId,
    dynamic fsrOriginalFilePath,
    dynamic fsrOriginalFileName,
  }) async {
    try {
      Logger.infoLog(
        "_uploadCMImagesAndAttachments called with cmSiteReqId: $cmSiteReqId",
      );
      Logger.infoLog(
        "customerPhotoId: $customerPhotoId, customerAttachmentId: $customerAttachmentId, fsrAttachmentId: $fsrAttachmentId",
      );

      File? customerPhoto;
      File? attachment;
      File? fsrAttachment;

      // Check for customer photo ID
      if (customerPhotoId != null && customerPhotoId is String) {
        Logger.infoLog("Retrieving customer photo with ID: $customerPhotoId");
        // Get image data from ImageUploadService
        final imageData = await ServiceLocator().imageUploadService
            .getImageUsingUniqueId(customerPhotoId);
        if (imageData != null) {
          Logger.infoLog(
            "Image data retrieved for customer photo, converting to File...",
          );
          customerPhoto = await Utils.buildImageFromBytesData(imageData);
          Logger.infoLog("Customer photo File created successfully");
        } else {
          Logger.errorLog(
            "Failed to retrieve image data for customer photo ID: $customerPhotoId",
          );
        }
      }

      // Check for attachment ID
      if (customerAttachmentId != null && customerAttachmentId is String) {
        Logger.infoLog("Retrieving attachment with ID: $customerAttachmentId");

        // Try to use original file first if available
        if (customerOriginalFilePath != null &&
            customerOriginalFilePath.toString().trim().isNotEmpty) {
          final originalFile = File(customerOriginalFilePath.toString());
          if (await originalFile.exists()) {
            Logger.infoLog(
              "Using original customer attachment file: $customerOriginalFilePath",
            );
            attachment = originalFile;
          } else {
            Logger.infoLog(
              "Original customer attachment file not found, will reconstruct from ImageUploadService",
            );
          }
        }

        // If original file not available, reconstruct from ImageUploadService
        if (attachment == null) {
          final attachmentData = await ServiceLocator().imageUploadService
              .getImageUsingUniqueId(customerAttachmentId);
          if (attachmentData != null) {
            Logger.infoLog("Attachment data retrieved, converting to File...");

            // Use original filename if available, otherwise generate one
            String fileName;
            if (customerOriginalFileName != null &&
                customerOriginalFileName.toString().trim().isNotEmpty) {
              // Sanitize filename to remove invalid characters but preserve name and extension
              final originalName = customerOriginalFileName.toString().trim();
              fileName = originalName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
              Logger.infoLog(
                "Using original customer attachment filename: $fileName",
              );
            } else {
              // Fallback: generate filename with proper extension
              String fileExtension = '.pdf'; // Default for documents
              fileName =
                  'customer_attachment_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
              Logger.infoLog(
                "Original customer attachment filename not available, using generated name: $fileName",
              );
            }

            // Create temporary file with original filename
            final tempDir = Directory.systemTemp;
            final tempFile = File('${tempDir.path}/$fileName');

            // Decode base64 and write to file
            final bytes = base64Decode(attachmentData);
            await tempFile.writeAsBytes(bytes);

            attachment = tempFile;
            Logger.infoLog(
              "Customer attachment File created with filename: $fileName",
            );
          } else {
            Logger.errorLog(
              "Failed to retrieve image data for attachment ID: $customerAttachmentId",
            );
          }
        }
      }

      // FSR: accept String (LOCAL_*) or int (document id from UploadDocuments / API). Plain `is String` skipped int ids and dropped sync upload.
      if (fsrAttachmentId != null) {
        final idStr = fsrAttachmentId.toString().trim();
        if (idStr.isNotEmpty) {
          Logger.infoLog("Retrieving FSR attachment with ID: $idStr");

          // Try to use original file first if available
          if (fsrOriginalFilePath != null &&
              fsrOriginalFilePath.toString().trim().isNotEmpty) {
            final originalFile = File(fsrOriginalFilePath.toString());
            if (await originalFile.exists()) {
              Logger.infoLog(
                "Using original FSR attachment file: $fsrOriginalFilePath",
              );
              fsrAttachment = originalFile;
            } else {
              Logger.infoLog(
                "Original FSR attachment file not found, will reconstruct from local store or DocumentById",
              );
            }
          }

          if (fsrAttachment == null) {
            if (idStr.contains('LOCAL_IMAGE_ID')) {
              final attachmentData = await ServiceLocator().imageUploadService
                  .getImageUsingUniqueId(idStr);
              if (attachmentData != null) {
                Logger.infoLog(
                  "FSR attachment data retrieved, converting to File...",
                );

                String fileName;
                if (fsrOriginalFileName != null &&
                    fsrOriginalFileName.toString().trim().isNotEmpty) {
                  final originalName = fsrOriginalFileName.toString().trim();
                  fileName = originalName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
                  Logger.infoLog(
                    "Using original FSR attachment filename: $fileName",
                  );
                } else {
                  const fileExtension = '.pdf';
                  fileName =
                      'fsr_attachment_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
                  Logger.infoLog(
                    "Original FSR attachment filename not available, using generated name: $fileName",
                  );
                }

                final tempDir = Directory.systemTemp;
                final tempFile = File('${tempDir.path}/$fileName');
                final bytes = base64Decode(attachmentData);
                await tempFile.writeAsBytes(bytes);
                fsrAttachment = tempFile;
                Logger.infoLog(
                  "FSR attachment File created with filename: $fileName",
                );
              } else {
                Logger.errorLog(
                  "Failed to retrieve data for FSR local id: $idStr",
                );
              }
            } else {
              final docId = int.tryParse(idStr);
              if (docId != null && docId > 0) {
                try {
                  final nameForSave = (fsrOriginalFileName != null &&
                          fsrOriginalFileName.toString().trim().isNotEmpty)
                      ? fsrOriginalFileName.toString().trim()
                      : 'fsr_$docId';
                  final path = await ServiceLocator().cmRepository
                      .downloadDocument(docId, nameForSave);
                  fsrAttachment = File(path);
                  Logger.infoLog(
                    "FSR document id $docId saved to temp path for upload: $path",
                  );
                } catch (e) {
                  Logger.errorLog(
                    "Failed to download FSR for document id $idStr: $e",
                  );
                }
              } else {
                Logger.errorLog(
                  "Unrecognized FSR attachment id (not LOCAL_ and not numeric): $idStr",
                );
              }
            }
          }
        }
      }

      // Upload if files exist
      if (customerPhoto != null ||
          attachment != null ||
          fsrAttachment != null) {
        Logger.infoLog("Uploading CM images with cmSiteReqId: $cmSiteReqId");
        Logger.infoLog(
          "customerPhoto: ${customerPhoto != null ? 'exists' : 'null'}, attachment: ${attachment != null ? 'exists' : 'null'}, fsrAttachment: ${fsrAttachment != null ? 'exists' : 'null'}",
        );
        await ServiceLocator().cmRepository.saveCustomerPhotoAndAttachments(
          cmSiteReqId,
          customerPhoto,
          attachment,
          fsrAttachment,
        );
        Logger.infoLog("CM images uploaded successfully");
      } else {
        Logger.infoLog("No images to upload for CM - all are null");
      }
    } catch (e) {
      Logger.errorLog("Error uploading CM images: $e");
      Logger.errorLog("Stack trace: ${StackTrace.current}");
      // Don't throw - images might not be critical
    }
  }

  /// Syncs CM remarks request when user comes online
  /// Handles the /api/v1/mobile/cmRemarks/upload endpoint separately
  Future<void> _syncCMRemarksRequestWhenOnline(
    List<dynamic> requests,
    String requestId,
  ) async {
    try {
      Logger.infoLog("Syncing CM remarks request when online");

      if (requests.isEmpty) {
        Logger.errorLog("CM remarks requests list is empty!");
        return;
      }

      // Get the first request (remarks are saved as single object)
      final request = requests.first;
      Logger.infoLog("Processing CM remarks request: ${request.keys}");

      // Extract required fields - handle both camelCase and snake_case
      final cmId = request['cmId'] ?? request['cm_id'];
      final cmRemark = request['cmRemark'] ?? request['cm_remark'] ?? '';
      final cmStatus = request['cmStatus'] ?? request['cm_status'] ?? '';

      // Extract attachment ID - can be cmRemarksFile or cmAttachmentId
      dynamic attachmentId =
          request['cmRemarksFile'] ??
          request['cm_remarks_file'] ??
          request['cmAttachmentId'] ??
          request['cm_attachment_id'];

      // Extract original file info - handle both camelCase and snake_case
      final originalFilePath =
          request['originalFilePath'] ?? request['original_file_path'];
      final originalFileName =
          request['originalFileName'] ?? request['original_file_name'];

      Logger.infoLog(
        "Extracted CM remarks data - cmId: $cmId, cmRemark: $cmRemark, cmStatus: $cmStatus, attachmentId: $attachmentId",
      );
      Logger.infoLog(
        "Extracted original file info - originalFilePath: $originalFilePath, originalFileName: $originalFileName",
      );

      if (cmId == null) {
        Logger.errorLog("CM remarks request missing cmId");
        throw Exception("CM remarks request missing cmId");
      }

      // Convert cmId to int if it's a string
      int cmSiteReqId;
      if (cmId is int) {
        cmSiteReqId = cmId;
      } else if (cmId is String) {
        cmSiteReqId = int.parse(cmId);
      } else {
        throw Exception("Invalid cmId format: $cmId");
      }

      // Get attachment file if attachment ID is provided
      File? attachmentFile;
      String? attachmentFileName; // Store the filename to pass to saveRemarks
      if (attachmentId != null && attachmentId.toString().trim().isNotEmpty) {
        Logger.infoLog("Retrieving remarks attachment with ID: $attachmentId");

        // Try to use original file first if available
        if (originalFilePath != null &&
            originalFilePath.toString().trim().isNotEmpty) {
          final originalFile = File(originalFilePath.toString());
          if (await originalFile.exists()) {
            Logger.infoLog("Using original remarks file: $originalFilePath");
            attachmentFile = originalFile;
            // Use original filename if available, otherwise use file path
            attachmentFileName =
                originalFileName?.toString().trim() ??
                originalFile.path.split('/').last;
          } else {
            Logger.infoLog(
              "Original remarks file not found, will reconstruct from ImageUploadService",
            );
          }
        }

        // If original file not available, reconstruct from ImageUploadService
        if (attachmentFile == null) {
          final attachmentData = await ServiceLocator().imageUploadService
              .getImageUsingUniqueId(attachmentId.toString());

          if (attachmentData != null) {
            Logger.infoLog("Attachment data retrieved, converting to File...");

            // Decode base64 and write to file first to detect file type
            final bytes = base64Decode(attachmentData);

            // Use original filename if available, otherwise detect from binary data
            String fileName;
            if (originalFileName != null &&
                originalFileName.toString().trim().isNotEmpty) {
              // Sanitize filename to remove invalid characters but preserve name and extension
              final originalName = originalFileName.toString().trim();
              fileName = originalName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

              // If original filename doesn't have extension, detect from binary data
              if (!fileName.contains('.')) {
                final detectedExt = _detectFileExtensionFromBytes(bytes);
                if (detectedExt != null) {
                  fileName = '$fileName$detectedExt';
                  Logger.infoLog(
                    "Added detected extension $detectedExt to filename: $fileName",
                  );
                }
              }
              Logger.infoLog("Using original filename: $fileName");
            } else {
              // Detect file type from binary data
              final detectedExt = _detectFileExtensionFromBytes(bytes);
              final fileExtension =
                  detectedExt ?? '.pdf'; // Default to PDF if can't detect
              fileName =
                  'cm_remarks_${DateTime.now().millisecondsSinceEpoch}$fileExtension';
              Logger.infoLog(
                "Original filename not available, detected type: $fileExtension, using generated name: $fileName",
              );
            }

            // Create temporary file with correct filename
            final tempDir = Directory.systemTemp;
            final tempFile = File('${tempDir.path}/$fileName');

            await tempFile.writeAsBytes(bytes);

            attachmentFile = tempFile;
            attachmentFileName =
                fileName; // Store filename for passing to saveRemarks
            Logger.infoLog(
              "Remarks attachment File created with filename: $fileName",
            );
          } else {
            Logger.errorLog(
              "Failed to retrieve attachment data for ID: $attachmentId",
            );
            throw Exception(
              "Failed to retrieve attachment file for ID: $attachmentId",
            );
          }
        }
      }

      // Validate that we have either remark text or attachment
      if (cmRemark.toString().trim().isEmpty && attachmentFile == null) {
        Logger.errorLog(
          "CM remarks request missing both remark text and attachment",
        );
        throw Exception(
          "CM remarks request must have either remark text or attachment",
        );
      }

      // Call saveRemarks from repository
      if (attachmentFile != null) {
        Logger.infoLog(
          "Uploading CM remarks with cmSiteReqId: $cmSiteReqId, filename: $attachmentFileName",
        );
        await ServiceLocator().cmRepository.saveRemarks(
          cmSiteReqId,
          cmRemark.toString().trim(),
          cmStatus.toString().trim(),
          attachmentFile,
          originalFileName: attachmentFileName,
        );
        Logger.infoLog("CM remarks uploaded successfully");
      } else {
        // If no attachment but we have remark text, we still need to upload
        // But saveRemarks requires a file. We might need to create an empty file or handle differently
        Logger.infoLog(
          "CM remarks has text but no attachment - saveRemarks requires a file",
        );
        Logger.infoLog("Skipping remarks upload - attachment required by API");
      }

      // Delete the pending request on success
      await ServiceLocator().pendingRequestService.deleteRequest(requestId);
      Logger.infoLog("CM remarks sync completed successfully");
    } catch (e) {
      Logger.errorLog("Error syncing CM remarks request: $e");
      Logger.errorLog("Stack trace: ${StackTrace.current}");
      rethrow;
    }
  }

  /// Detect file extension from binary data using magic bytes
  /// Similar to the method in cm_repository.dart
  String? _detectFileExtensionFromBytes(Uint8List data) {
    if (data.length < 4) return null;

    // Check magic bytes for common file types
    // JPEG: FF D8 FF
    if (data.length >= 3 &&
        data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF) {
      return '.jpg';
    }

    // PNG: 89 50 4E 47
    if (data.length >= 4 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return '.png';
    }

    // PDF: 25 50 44 46 (starts with "%PDF")
    if (data.length >= 4 &&
        data[0] == 0x25 &&
        data[1] == 0x50 &&
        data[2] == 0x44 &&
        data[3] == 0x46) {
      return '.pdf';
    }

    // DOCX: 50 4B 03 04 (ZIP file format, which DOCX uses)
    if (data.length >= 4 &&
        data[0] == 0x50 &&
        data[1] == 0x4B &&
        data[2] == 0x03 &&
        data[3] == 0x04) {
      try {
        final dataString = String.fromCharCodes(data.take(1000));
        if (dataString.contains('word/') || dataString.contains('xl/')) {
          return dataString.contains('word/') ? '.docx' : '.xlsx';
        }
        return '.zip';
      } catch (e) {
        return '.docx';
      }
    }

    // DOC (older Word format): D0 CF 11 E0
    if (data.length >= 4 &&
        data[0] == 0xD0 &&
        data[1] == 0xCF &&
        data[2] == 0x11 &&
        data[3] == 0xE0) {
      return '.doc';
    }

    // GIF: 47 49 46 38
    if (data.length >= 4 &&
        data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x38) {
      return '.gif';
    }

    // WebP: Check for RIFF...WEBP
    if (data.length >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return '.webp';
    }

    return null; // Could not detect
  }

  Future<void> _processRequestsForImages(List<dynamic> requests) async {
    for (dynamic request in requests) {
      await _processRequestForImages(request);
    }
  }

  /// Replaces photo_id with server_id and adds photo_taken_ts
  Future<dynamic> _processRequestForImages(dynamic request) async {
    Logger.infoLog("Processing request for images: $request");

    try {
      // Check if request is a List, if so, process each item
      if (request is List) {
        for (int i = 0; i < request.length; i++) {
          request[i] = await _processSingleRequest(request[i]);
        }
        return request;
      }

      // Process single request
      return await _processSingleRequest(request);
    } catch (e) {
      Logger.errorLog("Error processing asset audit request: $e");
      return request;
    }
  }

  Future<dynamic> _processSingleRequest(dynamic request) async {
    try {
      // Check if request is a Map
      if (request is! Map) {
        return request; // Not a Map, return as-is
      }

      // add code here to check for IMAGE CONTAIED IN PM reyqest IN "response_images": [
      //   {
      //     "photo_id": "LOCAL_IMAGE..",
      //     "pclsri_id": 16,
      //     "photo_taken_ts": "2025-12-31T15:03:52.399"
      //   },
      //   {
      //     "photo_id": "LOCAL_IMAGE..",
      //     "pclsri_id": 21,
      //     "photo_taken_ts": "2025-12-31T16:18:36.428"
      //   }
      // ],

      // First, process nested objects/arrays recursively
      if (request.containsKey("giId")) {
        await _processNestedObjects(request);
      }
      // Process site visit image fields (officialIdImageId, aadharCardImageId, leavingStatusImageId)
      if (request.containsKey("visitingPersonName") ||
          request.containsKey("visitingPersonId") ||
          request.containsKey("svlId")) {
        // This is a site visit request - process all image fields
        // Pass the original request object so changes are reflected
        await _processSiteVisitImageFields(request);
      }

      // Check both snake_case and camelCase field names
      dynamic photoId;

      // Handle response_images array (for PM and similar requests)
      if (request.containsKey("response_images") ||
          request.containsKey("asset_upload_item_images")) {
        final responseImages = request['response_images'];
        if (responseImages != null && responseImages is List) {
          // Process each image in the response_images array
          for (int i = 0; i < responseImages.length; i++) {
            final responseImage = responseImages[i];
            if (responseImage is Map<String, dynamic>) {
              final currentPhotoId =
                  responseImage['photo_id'] ?? responseImage['photoId'];

              // Only process LOCAL_IMAGE_ID entries (skip already uploaded server IDs)
              if (currentPhotoId != null &&
                  currentPhotoId.toString().startsWith('LOCAL_IMAGE_ID_')) {
                // This is a unique_id, get the server_id using ImageUploadService
                final imageModel = await ServiceLocator().imageUploadService
                    .getServerIdFromUniqueIdTryUploading(
                      currentPhotoId.toString(),
                    );

                if (imageModel != null) {
                  final serverId = imageModel.serverId;
                  final timestamp = Utils.getTmeFromMSForAPICall(
                    imageModel.createdAt,
                  );

                  // Update the photo_id in this specific response_images item
                  responseImage['photo_id'] = serverId;
                  // Also update camelCase version if it exists
                  if (responseImage.containsKey('photoId')) {
                    responseImage['photoId'] = serverId;
                  }

                  // Update timestamp if available
                  if (timestamp != null) {
                    responseImage['photo_taken_ts'] = timestamp;
                  }

                  Logger.debugLog(
                    "✅ Uploaded LOCAL_IMAGE_ID $currentPhotoId -> server_id $serverId in response_images[$i]",
                  );
                } else {
                  Logger.debugLog(
                    "❌ FAILED to get server_id for LOCAL_IMAGE_ID: $currentPhotoId in response_images[$i]",
                  );
                }
              } else {
                // Already a server ID (numeric), skip upload
                Logger.debugLog(
                  "⏭️ Skipping response_images[$i] - already has server_id: $currentPhotoId",
                );
              }
            }
          }
          // Update the request with the modified response_images array
          request['response_images'] = responseImages;
          // Also update camelCase version for backward compatibility
          request['responseImages'] = responseImages;
        }
        // After processing response_images, return early (don't process single photo_id)
        return request;
      }

      // Handle single photo_id fields (for other request types)
      if (request.containsKey("energyReadingId")) {
        photoId = request['ebAttachmentFileId'];
      } else if (request.containsKey("visitingPersonName") ||
          request.containsKey("visitingPersonId")) {
        photoId = request['visitingPersonImageId'];
      } else if (request.containsKey("gispId")) {
        photoId = request['respPhotoId'];
      } else if (request.containsKey("incidentImgId")) {
        photoId = request['incidentImgId'];
      } else {
        photoId = request['photo_id'] ?? request['photoId'];
      }

      // If no photo_id or photo_id is null/empty/0, return the request as-is
      if (photoId == null ||
          photoId.toString().isEmpty ||
          photoId == 0 ||
          photoId == "0") {
        return request;
      }

      // Check if photo_id is a unique_id (contains LOCAL_IMAGE_ID - do not send to API)
      final photoIdStr = photoId.toString();
      if (photoIdStr.contains('LOCAL_IMAGE_ID')) {
        // Only try upload for full format LOCAL_IMAGE_ID_*; otherwise set 0 so we never send local id
        if (photoIdStr.startsWith('LOCAL_IMAGE_ID_')) {
          final imageModel = await ServiceLocator().imageUploadService
              .getServerIdFromUniqueIdTryUploading(photoIdStr);
          if (imageModel != null ) {
            final serverId = imageModel.serverId;
            final timestamp = Utils.getTmeFromMSForAPICall(imageModel.createdAt);

            if (request.containsKey("energyReadingId")) {
              request['ebAttachmentFileId'] = serverId;
            } else if (request.containsKey("visitingPersonName") ||
                request.containsKey("visitingPersonId") ||
                request.containsKey("svlId")) {
              request['visitingPersonImageId'] = serverId;
            } else if (request.containsKey("gispId")) {
              request['respPhotoId'] = serverId;
            } else if (request.containsKey("incidentImgId")) {
              request['incidentImgId'] = serverId;
            } else {
              request['photo_id'] = serverId;
            }

            if (timestamp != null) {
              request['photo_taken_ts'] = timestamp;
            }
          } else {
            Logger.debugLog(
              "FAILED to get server_id for LOCAL_IMAGE_ID: $photoId - setting to 0 so we do not send local id",
            );
            if (request.containsKey("visitingPersonName") ||
                request.containsKey("visitingPersonId") ||
                request.containsKey("svlId")) {
              request['visitingPersonImageId'] = null;
            } else if (request.containsKey("energyReadingId")) {
              request['ebAttachmentFileId'] = null;
            } else if (request.containsKey("gispId")) {
              request['respPhotoId'] = null;
            } else if (request.containsKey("incidentImgId")) {
              request['incidentImgId'] = null;
            } else {
              request['photo_id'] = null;
            }
          }
        } else {
          Logger.debugLog(
            "photo_id contains LOCAL_IMAGE_ID but not replaceable: $photoIdStr - setting to 0",
          );
          if (request.containsKey("visitingPersonName") ||
              request.containsKey("visitingPersonId") ||
              request.containsKey("svlId")) {
            request['visitingPersonImageId'] = null;
          } else if (request.containsKey("energyReadingId")) {
            request['ebAttachmentFileId'] = null;
          } else if (request.containsKey("gispId")) {
            request['respPhotoId'] = null;
          } else if (request.containsKey("incidentImgId")) {
            request['incidentImgId'] = null;
          } else {
            request['photo_id'] = null;
          }
        }
      } else {
        // This is already a server_id, just add photo_taken_ts if not present
        if (request['photo_taken_ts'] == null ||
            request['photo_taken_ts'].toString().isEmpty) {
          final currentTime = Utils.getCurrentDateTimeForAPICall();
          request['photo_taken_ts'] = currentTime;
        }
        return request;
      }
    } catch (e) {
      Logger.errorLog("Error processing single request: $e");

      return request;
    }
    Logger.infoLog("processAssetAuditRequest COMPLETED - returning: $request");

    return request;
  }

  /// Recursively process nested objects and arrays for image IDs
  Future<void> _processNestedObjects(dynamic obj) async {
    if (obj is Map<String, dynamic>) {
      // Process each value in the map
      for (String key in obj.keys) {
        final value = obj[key];

        if (value is List) {
          // Process each item in the list
          for (int i = 0; i < value.length; i++) {
            if (value[i] is Map<String, dynamic>) {
              // Recursively process nested objects
              await _processNestedObjects(value[i]);
              // Also process this object for image IDs
              await _processImageIdInObject(value[i]);
            }
          }
        } else if (value is Map<String, dynamic>) {
          // Recursively process nested maps
          await _processNestedObjects(value);
        }
      }
    }
  }

  /// Uploads FSR when still a local id: `api/v1/common/UploadDocuments`, then sets
  /// [fsrAttachmentId] / [fsr_attachment_id] on the request (same as Identification/TimeStamp on the screen).
  /// Non-local values (server doc id) are left unchanged.
  Future<void> _processCMFsrUploadDocumentsBeforePost(
    Map<String, dynamic> request,
  ) async {
    final fsrRaw =
        request['fsrAttachmentId'] ?? request['fsr_attachment_id'];
    if (fsrRaw == null) return;
    final idStr = fsrRaw.toString().trim();
    if (idStr.isEmpty || idStr == '0') return;
    if (!idStr.contains('LOCAL_IMAGE_ID')) return;

    File? tempToDelete;
    try {
      File? fileToUpload;
      final pathRaw = request['fsr_original_file_path'] ??
          request['fsrOriginalFilePath'];
      if (pathRaw != null && pathRaw.toString().trim().isNotEmpty) {
        final f = File(pathRaw.toString());
        if (await f.exists()) {
          fileToUpload = f;
        }
      }

      if (fileToUpload == null) {
        final attachmentData = await ServiceLocator()
            .imageUploadService
            .getImageUsingUniqueId(idStr);
        if (attachmentData == null) {
          Logger.errorLog('❌ CM sync FSR: no local data for $idStr');
          request['fsrAttachmentId'] = null;
          request['fsr_attachment_id'] = null;
          return;
        }
        final nameCandidate = request['fsr_original_file_name'] ??
            request['fsrOriginalFileName'] ??
            request['fsr_attachment_name'] ??
            request['fsrAttachmentName'];
        final fileName = (nameCandidate != null &&
                nameCandidate.toString().trim().isNotEmpty)
            ? nameCandidate
                .toString()
                .trim()
                .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
            : 'fsr_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final tempFile =
            File('${Directory.systemTemp.path}/$fileName');
        await tempFile.writeAsBytes(base64Decode(attachmentData));
        fileToUpload = tempFile;
        tempToDelete = tempFile;
      }

      final uploadService = UploadDcoumentsService(
        apiService: ServiceLocator().apiService,
      );
      final result = await uploadService.uploadFile(
        file: fileToUpload,
        id: '0',
        activityType: ActivityTypeEnum.correctiveMaintenance.value,
      );

      final docId = (result.isSuccess ? (result.data ?? '') : '')
          .toString()
          .trim();
      if (docId.isNotEmpty && docId != '0') {
        request['fsrAttachmentId'] = docId;
        request['fsr_attachment_id'] = docId;
        final attachName = fileToUpload.path.split('/').last;
        final hasName = (request['fsrAttachmentName'] ?? '')
                .toString()
                .trim()
                .isNotEmpty ||
            (request['fsr_attachment_name'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
        if (!hasName) {
          request['fsrAttachmentName'] = attachName;
          request['fsr_attachment_name'] = attachName;
        }
        Logger.debugLog('✅ CM sync: FSR uploaded via UploadDocuments (pre-POST)');
      } else {
        Logger.errorLog('❌ CM sync: FSR UploadDocuments failed or empty docId');
        request['fsrAttachmentId'] = null;
        request['fsr_attachment_id'] = null;
      }
    } finally {
      if (tempToDelete != null) {
        try {
          await tempToDelete.delete();
        } catch (_) {}
      }
    }
  }

  /// Process CM request: upload all LOCAL_IMAGE_ID and replace with server IDs
  /// (top-level photo fields + nested checklist/impacted item response_images).
  /// FSR is handled by [_processCMFsrUploadDocumentsBeforePost]. Customer photo and
  /// customer attachment stay as local ids here and are uploaded after create via
  /// [_uploadCMImagesAndAttachments] / correctiveMaintenance upload.
  Future<void> _processCMRequestForImages(Map<String, dynamic> request) async {
    final imageUploadService = ServiceLocator().imageUploadService;

    // 1) Top-level image fields that are sent in the JSON body (replace with server ID).
    // Exclude customer_photo_id, customer_attachment_id, fsr (FSR is processed pre-POST).
    final topLevelFields = [
      'identification_img_id',
      'identificationImgId',
      'timestamp_img_id',
      'timestampImgId',
    ];
    for (final key in topLevelFields) {
      if (!request.containsKey(key)) continue;
      final value = request[key];
      if (value == null ||
          value.toString().trim().isEmpty ||
          !value.toString().startsWith('LOCAL_IMAGE_ID_')) {
        continue;
      }
      // Same as online CM screen: document ids come from UploadDocuments only (not mobile/uploads).
      final docIdStr = await imageUploadService
          .uploadCmStoredUniqueIdViaUploadDocuments(value.toString());
      if (docIdStr != null && docIdStr.isNotEmpty) {
        final parsed = int.tryParse(docIdStr);
        request[key] = parsed ?? docIdStr;
        Logger.debugLog('✅ CM sync: $key -> UploadDocuments doc id');
      } else {
        Logger.errorLog('❌ CM sync: UploadDocuments failed for $key: $value');
        request[key] = null;
      }
    }

    // 2) Nested checklist: process cmCheckListSiteRespImagesList and response_images per item
    List<dynamic>? checklistList;
    // Support all key variants we use in offline/online flows
    if (request['cmCheckListSiteRespList'] is List) {
      checklistList = request['cmCheckListSiteRespList'] as List<dynamic>;
    } else if (request['cm_check_list_site_resp_list'] is List) {
      checklistList = request['cm_check_list_site_resp_list'] as List<dynamic>;
    } else if (request['checkListSiteRespList'] is List) {
      checklistList = request['checkListSiteRespList'] as List<dynamic>;
    } else if (request['check_list_site_resp_list'] is List) {
      checklistList = request['check_list_site_resp_list'] as List<dynamic>;
    }

    if (checklistList != null) {
      for (final item in checklistList) {
        if (item is! Map<String, dynamic>) continue;
        await _processCMChecklistItemImages(item, imageUploadService);
        final impactedList = item['cm_impacted_item_list'] ??
            item['cmImpactedItemList'] as List<dynamic>?;
        if (impactedList != null) {
          for (final child in impactedList) {
            if (child is Map<String, dynamic>) {
              await _processCMChecklistItemImages(child, imageUploadService);
            }
          }
        }
      }
    }
  }

  /// Process all image lists in a checklist/impacted item: cmCheckListSiteRespImagesList and response_images.
  Future<void> _processCMChecklistItemImages(
    Map<String, dynamic> obj,
    dynamic imageUploadService,
  ) async {
    // API payload uses cmCheckListSiteRespImagesList (list of { photoId, cclsriId, photoTakenTs, ... })
    final imagesList = obj['cm_check_list_site_resp_images_list'] ??
        obj['cmCheckListSiteRespImagesList'] as List<dynamic>?;
    if (imagesList != null) {
      await _processCMPhotoIdList(imagesList, imageUploadService, 'cmCheckListSiteRespImagesList');
    }
    // Legacy / alternate key: response_images (list of { photo_id / photoId })
    await _processCMResponseImagesInMap(obj, imageUploadService);
  }

  /// Process a list of maps that have photoId or photo_id (e.g. cmCheckListSiteRespImagesList).
  Future<void> _processCMPhotoIdList(
    List<dynamic> list,
    dynamic imageUploadService,
    String contextLabel,
  ) async {
    for (int i = 0; i < list.length; i++) {
      final entry = list[i];
      if (entry is! Map<String, dynamic>) continue;
      final photoId = entry['photo_id'] ?? entry['photoId'];
      if (photoId == null ||
          !photoId.toString().startsWith('LOCAL_IMAGE_ID_')) {
        continue;
      }
      final imageModel = await imageUploadService
          .getServerIdFromUniqueIdTryUploading(photoId.toString());
      if (imageModel != null && imageModel.serverId != null) {
        final serverId = imageModel.serverId is int
            ? imageModel.serverId
            : int.tryParse(imageModel.serverId.toString());
        entry['photo_id'] = serverId;
        entry['photoId'] = serverId;
        // Format photoTakenTs as dd/MM/yyyy as required by backend
        if (imageModel.createdAt != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(imageModel.createdAt!);
          final ts = DateFormat('dd/MM/yyyy').format(dt);
          entry['photo_taken_ts'] = ts;
          entry['photoTakenTs'] = ts;
        }
        Logger.debugLog('✅ CM sync: $contextLabel[$i] photoId replaced with server ID');
      } else {
        Logger.errorLog('❌ CM sync: failed to upload $contextLabel[$i]: $photoId');
        entry['photo_id'] = null;
        entry['photoId'] = null;
      }
    }
  }

  /// Process response_images / responseImages in a single map (checklist or impacted item).
  Future<void> _processCMResponseImagesInMap(
    Map<String, dynamic> obj,
    dynamic imageUploadService,
  ) async {
    final list = obj['response_images'] ?? obj['responseImages'];
    if (list == null || list is! List) return;
    for (int i = 0; i < list.length; i++) {
      final entry = list[i];
      if (entry is! Map<String, dynamic>) continue;
      final photoId = entry['photo_id'] ?? entry['photoId'];
      if (photoId == null ||
          !photoId.toString().startsWith('LOCAL_IMAGE_ID_')) {
        continue;
      }
      final imageModel = await imageUploadService
          .getServerIdFromUniqueIdTryUploading(photoId.toString());
      if (imageModel != null && imageModel.serverId != null) {
        final serverId = imageModel.serverId is int
            ? imageModel.serverId
            : int.tryParse(imageModel.serverId.toString());
        entry['photo_id'] = serverId;
        entry['photoId'] = serverId;
        // Format photoTakenTs as dd/MM/yyyy as required by backend
        if (imageModel.createdAt != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(imageModel.createdAt!);
          final ts = DateFormat('dd/MM/yyyy').format(dt);
          entry['photo_taken_ts'] = ts;
        }
        Logger.debugLog('✅ CM sync: response_images[$i] replaced with server ID');
      } else {
        Logger.errorLog('❌ CM sync: failed to upload response_images[$i]: $photoId');
        entry['photo_id'] = null;
        entry['photoId'] = null;
      }
    }
  }

  /// Process image ID in a specific object
  Future<void> _processImageIdInObject(Map<String, dynamic> obj) async {
    try {
      // Check for respPhotoId (General Inspection checklist items)
      if (obj.containsKey('respPhotoId')) {
        final photoId = obj['respPhotoId']?.toString();
        if (photoId != null &&
            photoId.isNotEmpty &&
            photoId.startsWith('LOCAL_IMAGE_ID_')) {
          final imageModel = await ServiceLocator().imageUploadService
              .getServerIdFromUniqueIdTryUploading(photoId);

          if (imageModel != null) {
            final serverId = imageModel.serverId;

            obj['respPhotoId'] = serverId;

            final timestamp = Utils.getTmeFromMSForAPICall(
              imageModel.createdAt,
            );
            if (timestamp != null) {
              obj['photo_taken_ts'] = timestamp;
            }
          } else {
            Logger.debugLog(
              "FAILED to get server_id for respPhotoId: $photoId",
            );
          }
        }
      }

      // Check for other photo ID fields
      if (obj.containsKey('photo_id')) {
        final photoId = obj['photo_id']?.toString();
        if (photoId != null &&
            photoId.isNotEmpty &&
            photoId.startsWith('LOCAL_IMAGE_ID_')) {
          final imageModel = await ServiceLocator().imageUploadService
              .getServerIdFromUniqueIdTryUploading(photoId);

          if (imageModel != null) {
            final serverId = imageModel.serverId;

            obj['photo_id'] = serverId;

            final timestamp = Utils.getTmeFromMSForAPICall(
              imageModel.createdAt,
            );
            if (timestamp != null) {
              obj['photo_taken_ts'] = timestamp;
            }
          } else {
            Logger.debugLog("FAILED to get server_id for photo_id: $photoId");
          }
        }
      }
    } catch (e) {
      Logger.errorLog("Error processing image ID in object: $e");
    }
  }

  /// Process site visit specific image fields (officialIdImageId, aadharCardImageId, leavingStatusImageId)
  /// Modifies the request object in place
  Future<void> _processSiteVisitImageFields(
    Map<dynamic, dynamic> request,
  ) async {
    try {
      Logger.debugLog('🔄 Processing site visit image fields...');

      // List of site visit image fields to process
      final imageFields = [
        'officialIdImageId',
        'aadharCardImageId',
        'leavingStatusImageId',
      ];

      for (final fieldName in imageFields) {
        if (request.containsKey(fieldName)) {
          final imageId = request[fieldName];

          Logger.debugLog('📸 Found $fieldName: $imageId');

          // Skip if null, empty, or 0
          if (imageId == null ||
              imageId.toString().isEmpty ||
              imageId == 0 ||
              imageId == '0') {
            Logger.debugLog('⏭️ Skipping $fieldName (null/empty/0)');
            continue;
          }

          // Check if it's a LOCAL_IMAGE_ID - never send to API
          final imageIdStr = imageId.toString();
          if (imageIdStr.contains('LOCAL_IMAGE_ID')) {
            if (imageIdStr.startsWith('LOCAL_IMAGE_ID_')) {
              Logger.debugLog('🔄 Processing $fieldName: $imageId');

              final imageModel = await ServiceLocator().imageUploadService
                  .getServerIdFromUniqueIdTryUploading(imageIdStr);

              if (imageModel != null && imageModel.serverId != null) {
                final serverId =
                    int.tryParse(imageModel.serverId.toString()) ?? 0;
                request[fieldName] = serverId;
                Logger.debugLog(
                  '✅ $fieldName replaced with server ID: $serverId (was: $imageId)',
                );
              } else {
                Logger.errorLog(
                  '❌ Failed to upload image for $fieldName: $imageId - setting to 0',
                );
                request[fieldName] = 0;
              }
            } else {
              Logger.debugLog(
                '⚠️ $fieldName contains LOCAL_IMAGE_ID but not replaceable - setting to 0',
              );
              request[fieldName] = 0;
            }
          } else {
            // Already a server ID, ensure it's an integer
            final serverId = int.tryParse(imageIdStr) ?? 0;
            request[fieldName] = serverId;
            Logger.debugLog('✅ $fieldName already has server ID: $serverId');
          }
        } else {
          Logger.debugLog('⚠️ Field $fieldName not found in request');
        }
      }

      Logger.debugLog('✅ Site visit image fields processing completed');
    } catch (e) {
      Logger.errorLog("❌ Error processing site visit image fields: $e");
      Logger.errorLog("❌ Stack trace: ${StackTrace.current}");
    }
  }
}
