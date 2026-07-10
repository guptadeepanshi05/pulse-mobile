import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/models/sqlite/image_model.dart';
import 'package:app/services/asset_audit_post_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'upload_dcouments.dart';
import '../utils/logger.dart';

class ImageUploadService {
  static Database? _database;
  static const String _tableName = 'images';
  static const String _databaseName = 'image_upload.db';
  static const int _databaseVersion = 3;

  final ApiService _apiService;
  final Uuid _uuid = const Uuid();
  static const String _imagesDirName = 'app_data/images';

  /// AA/PM tickets in offline session must keep images local until sync.
  Future<bool> _shouldKeepImageLocalForOfflineTicket(
    String? siteSchId,
    ActivityTypeEnum activityType,
  ) async {
    // During FIFO offline sync, images must upload before the queued API POST.
    if (AssetAuditPostService.isSyncInProgress) return false;
    if (siteSchId == null || siteSchId.trim().isEmpty) return false;
    if (activityType != ActivityTypeEnum.assetAudit &&
        activityType != ActivityTypeEnum.preventiveMaintenance) {
      return false;
    }
    return ServiceLocator().assetAuditPostService.isTicketInOfflineSession(
      siteSchId.trim(),
    );
  }

  ImageUploadService({required ApiService apiService})
    : _apiService = apiService;

  /// Initialize the database
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize the database
  Future<Database> _initDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);

      Logger.debugLog('Initializing ImageUploadService database at: $path');

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      Logger.errorLog('Error initializing ImageUploadService database: $e');
      rethrow;
    }
  }

  /// Create the images table
  Future<void> _onCreate(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $_tableName (
          unique_id TEXT PRIMARY KEY,
          server_id TEXT,
          image_data TEXT NOT NULL,
          is_selfie INTEGER DEFAULT 0,
          activity_type TEXT NOT NULL,
          sch_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      // Create index for server_id for faster lookups
      await db.execute('''
        CREATE INDEX idx_server_id ON $_tableName(server_id)
      ''');
      Logger.debugLog('✅ Images table created successfully');
    } catch (e) {
      Logger.errorLog('❌ Error creating images table: $e');
      rethrow;
    }
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < newVersion) {
      // Drop existing tables
      await db.execute('DROP TABLE IF EXISTS $_tableName');
      // Recreate tables with current schema
      await _onCreate(db, newVersion);
      Logger.debugLog(
        '✅ Database upgraded from version $oldVersion to $newVersion',
      );
    }
  }

  /// Generate a unique ID for local images
  String _generateUniqueId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _uuid.v4().substring(0, 8);
    return 'LOCAL_IMAGE_ID_${timestamp}_$random';
  }

  Future<Directory> _getImagesDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${appDir.path}/$_imagesDirName');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  bool _looksLikeStoredPath(String value) {
    return value.startsWith('/') || value.startsWith('file://');
  }

  String _normalizeStoredPath(String value) {
    if (value.startsWith('file://')) {
      return value.replaceFirst('file://', '');
    }
    return value;
  }

  Future<String> _persistImageDataToFile({
    required String uniqueId,
    required String imageData,
  }) async {
    final dir = await _getImagesDirectory();
    final filePath = '${dir.path}/$uniqueId.jpg';
    final file = File(filePath);

    Uint8List imageBytes;
    if (imageData.startsWith('data:image/')) {
      imageBytes = base64Decode(imageData.split(',')[1]);
    } else {
      imageBytes = base64Decode(imageData);
    }
    await file.writeAsBytes(imageBytes, flush: true);
    return file.path;
  }

  Future<String> _persistImageFileToAppData({
    required String uniqueId,
    required String sourcePath,
  }) async {
    final dir = await _getImagesDirectory();
    final targetPath = '${dir.path}/$uniqueId.jpg';
    final source = File(sourcePath);
    final target = File(targetPath);
    if (await source.exists()) {
      await source.copy(targetPath);
      return target.path;
    }
    throw Exception('Source image file missing: $sourcePath');
  }

  Future<String?> _readStoredImageDataAsBase64(String? storedValue) async {
    if (storedValue == null || storedValue.isEmpty) return null;
    if (!_looksLikeStoredPath(storedValue)) {
      return storedValue; // legacy base64 in DB
    }
    try {
      final path = _normalizeStoredPath(storedValue);
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 1. Upload image - Save to SQLite and try to upload to server
  ///
  Future<String> uploadImage(
    String imageData,
    ActivityTypeEnum activityType,
    bool isSelfie,
    String? siteSchId,
  ) async {
    try {
      final uniqueId = _generateUniqueId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final storedPath = await _persistImageDataToFile(
        uniqueId: uniqueId,
        imageData: imageData,
      );

      // Save image to SQLite first
      await _saveImageToSQLite(
        uniqueId: uniqueId,
        imageData: storedPath,
        isSelfie: isSelfie,
        activityType: activityType,
        schId: siteSchId,
        serverId: null,
        createdAt: now,
        updatedAt: now,
      );

      Logger.debugLog('Image saved to SQLite with ID: $uniqueId');

      if (await _shouldKeepImageLocalForOfflineTicket(siteSchId, activityType)) {
        Logger.infoLog(
          'Image kept as LOCAL_IMAGE_ID — ticket $siteSchId is in offline session',
        );
        return uniqueId;
      }

      // Try to upload to server
      String finalId = uniqueId; // Default to local ID
      try {
        final serverId = await _uploadToServer(
          imageData,
          activityType,
          siteSchId ?? '',
          isSelfie,
        );
        if (serverId != null) {
          // Update server_id in SQLite
          await _updateServerId(uniqueId, serverId);
          Logger.debugLog(
            'Image uploaded to server with ID for uniqueId: $serverId, $uniqueId',
          );
          finalId = serverId; // Return server ID instead of local ID
        } else {
          Logger.debugLog(
            'Server upload failed, but image saved locally with ID: $uniqueId',
          );
        }
      } catch (e) {
        Logger.errorLog('Server upload failed: $e');
      }
      return finalId;
    } catch (e) {
      Logger.errorLog('Error in uploadImage: $e');
      rethrow;
    }
  }

  /// Upload image directly from local file path to reduce memory pressure.
  Future<String> uploadImageFromFilePath(
    String imageFilePath,
    ActivityTypeEnum activityType,
    bool isSelfie,
    String? siteSchId,
  ) async {
    try {
      final uniqueId = _generateUniqueId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final storedPath = await _persistImageFileToAppData(
        uniqueId: uniqueId,
        sourcePath: imageFilePath,
      );

      await _saveImageToSQLite(
        uniqueId: uniqueId,
        imageData: storedPath,
        isSelfie: isSelfie,
        activityType: activityType,
        schId: siteSchId,
        serverId: null,
        createdAt: now,
        updatedAt: now,
      );

      if (await _shouldKeepImageLocalForOfflineTicket(siteSchId, activityType)) {
        Logger.infoLog(
          'Image kept as LOCAL_IMAGE_ID — ticket $siteSchId is in offline session',
        );
        return uniqueId;
      }

      String finalId = uniqueId;
      try {
        final serverId = await _uploadFileToServer(
          imageFilePath: storedPath,
          activityType: activityType,
          siteSchId: siteSchId ?? '',
          isSelfie: isSelfie,
        );
        if (serverId != null) {
          await _updateServerId(uniqueId, serverId);
          finalId = serverId;
        }
      } catch (e) {
        Logger.errorLog('Server upload failed (file path): $e');
      }
      return finalId;
    } catch (e) {
      Logger.errorLog('Error in uploadImageFromFilePath: $e');
      rethrow;
    }
  }

  /// **Corrective Maintenance only.** Persists Identification / Time Stamp / FSR file locally
  /// **without** calling `api/v1/mobile/uploads`. Server ids must come from `UploadDocuments`
  /// (`uploadCmStoredUniqueIdViaUploadDocuments` or the CM screen).
  Future<String> persistCmDocumentLocalWithoutMobileUploads(String filePath) async {
    final uniqueId = _generateUniqueId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final storedPath = await _persistImageFileToAppData(
      uniqueId: uniqueId,
      sourcePath: filePath,
    );

    await _saveImageToSQLite(
      uniqueId: uniqueId,
      imageData: storedPath,
      isSelfie: false,
      activityType: ActivityTypeEnum.correctiveMaintenance,
      schId: null,
      serverId: null,
      createdAt: now,
      updatedAt: now,
    );

    Logger.debugLog(
      'persistCmDocumentLocalWithoutMobileUploads: local id=$uniqueId (CM, no mobile/uploads)',
    );
    return uniqueId;
  }

  /// **Corrective Maintenance only.** Resolves a locally persisted id to a **docId** from
  /// `api/v1/common/UploadDocuments` — never `api/v1/mobile/uploads`.
  Future<String?> uploadCmStoredUniqueIdViaUploadDocuments(String uniqueId) async {
    try {
      final imageModel = await _getByUniqueIdFromSQLite(uniqueId);
      if (imageModel == null || imageModel.imageData == null) {
        Logger.errorLog(
          'uploadCmStoredUniqueIdViaUploadDocuments: no SQLite row for $uniqueId',
        );
        return null;
      }
      final existing = imageModel.serverId?.toString().trim();
      if (existing != null &&
          existing.isNotEmpty &&
          !existing.startsWith('LOCAL_IMAGE_ID')) {
        return existing;
      }
      if (!await ConnectivityHelper.isConnected()) {
        Logger.debugLog(
          'uploadCmStoredUniqueIdViaUploadDocuments: offline, skip $uniqueId',
        );
        return null;
      }

      final path = _normalizeStoredPath(imageModel.imageData!);
      final file = File(path);
      if (!await file.exists()) {
        Logger.errorLog(
          'uploadCmStoredUniqueIdViaUploadDocuments: missing file $path',
        );
        return null;
      }

      final uploadService = UploadDcoumentsService(apiService: _apiService);
      final result = await uploadService.uploadFile(
        file: file,
        id: '0',
        activityType: ActivityTypeEnum.correctiveMaintenance.value,
      );

      final docId =
          (result.isSuccess ? (result.data ?? '') : '').toString().trim();
      if (docId.isEmpty || docId == '0') {
        Logger.errorLog(
          'UploadDocuments failed for CM local id $uniqueId: ${result.errorMessage}',
        );
        return null;
      }
      await _updateServerId(uniqueId, docId);
      Logger.debugLog(
        'uploadCmStoredUniqueIdViaUploadDocuments: $uniqueId -> docId $docId',
      );
      return docId;
    } catch (e, st) {
      Logger.errorLog('uploadCmStoredUniqueIdViaUploadDocuments: $e\n$st');
      return null;
    }
  }

  /// 2. Get server ID - Check SQLite first, upload if needed
  Future<ImageModel?> getServerIdFromUniqueIdTryUploading(
    String uniqueId,
  ) async {
    try {
      Logger.debugLog('Getting server ID for unique ID: $uniqueId');
      // Check if server_id exists in SQLite
      final imageModel = await _getByUniqueIdFromSQLite(uniqueId);
      if (imageModel == null) {
        Logger.errorLog('Image data not found for unique ID: $uniqueId');
        return null;
      }
      if (imageModel.serverId != null) {
        return imageModel;
      }
      if (imageModel.imageData == null) {
        Logger.errorLog('Image data not found for unique ID: $uniqueId');
        return null;
      }
      if (imageModel.schId != null &&
          imageModel.schId!.trim().isNotEmpty &&
          await _shouldKeepImageLocalForOfflineTicket(
            imageModel.schId,
            imageModel.activityType,
          )) {
        Logger.infoLog(
          'Skipping image server upload — ticket ${imageModel.schId} is in offline session',
        );
        return imageModel;
      }
      if (await ConnectivityHelper.isConnected()) {
        Logger.debugLog(
          'Server ID not found in SQLite, uploading image to server $uniqueId',
        );
        // Upload to server
        final uploadBase64 = await _readStoredImageDataAsBase64(
          imageModel.imageData,
        );
        if (uploadBase64 == null || uploadBase64.isEmpty) {
          Logger.errorLog('Image bytes/path missing for unique ID: $uniqueId');
          return null;
        }
        final newServerId = await _uploadToServer(
          uploadBase64,
          imageModel.activityType,
          imageModel.schId ?? "",
          imageModel.isSelfie,
        );
        if (newServerId != null) {
          Logger.debugLog(
            'Upload successful for unique_id: $uniqueId, got server ID: $newServerId',
          );
          await _updateServerId(uniqueId, newServerId);
          final imageModel = await _getByUniqueIdFromSQLite(uniqueId);
          return imageModel;
        } else {
          Logger.errorLog(
            'Failed to upload image to server - newServerId is null',
          );
        }
      }
    } catch (e) {
      Logger.errorLog('Error in getServerIdFromUniqueIdTryUploading: $e');
    }
    return null;
  }

  /// 3. Download image using server ID
  Future<String?> downloadImageUsingServerId(
    String serverId,
    ActivityTypeEnum activityType,
    String schId,
  ) async {
    try {
      // Download image from server first
      final imageData = await downloadFromServer(serverId);
      if (imageData == null || imageData.isEmpty) return null;

      // Check if record with this server_id already exists
      final existingRecord = await getImagesByServerId(serverId);
      if (existingRecord != null) {
        // Update existing record with new image data
        final storedPath = await _persistImageDataToFile(
          uniqueId: existingRecord.uniqueId,
          imageData: imageData,
        );
        await _updateImageData(existingRecord.uniqueId, storedPath);
        return existingRecord.uniqueId;
      } else {
        // Create new record
        final uniqueId = _generateUniqueId();
        final now = DateTime.now().millisecondsSinceEpoch;
        final storedPath = await _persistImageDataToFile(
          uniqueId: uniqueId,
          imageData: imageData,
        );

        await _saveImageToSQLite(
          uniqueId: uniqueId,
          imageData: storedPath,
          serverId: serverId,
          isSelfie: false,
          activityType: activityType,
          createdAt: now,
          updatedAt: now,
        );

        Logger.debugLog(
          '✅ Image downloaded and saved with unique ID: $uniqueId',
        );
        return uniqueId;
      }
    } catch (e) {
      Logger.errorLog('❌ Error in downloadImageUsingServerId: $e');
      return null;
    }
  }

  /// PMIS / common document id: `GET /api/v1/common/DocumentById/{id}` (bytes).
  /// Persists like other offline media so [getImageUsingUniqueId] works for activity tickets.
  Future<String?> downloadPmisDocumentByServerId(
    String serverId,
    ActivityTypeEnum activityType,
    String schId,
  ) async {
    try {
      final response = await _apiService.get<Uint8List>(
        path: '/api/v1/common/DocumentById/$serverId',
        responseType: ResponseType.bytes,
      );
      if (!response.isSuccess || response.data == null) return null;
      final bytes = response.data as Uint8List;
      if (bytes.isEmpty) return null;

      final b64 = base64Encode(bytes);

      final existingRecord = await getImagesByServerId(serverId);
      if (existingRecord != null) {
        final storedPath = await _persistImageDataToFile(
          uniqueId: existingRecord.uniqueId,
          imageData: b64,
        );
        await _updateImageData(existingRecord.uniqueId, storedPath);
        return existingRecord.uniqueId;
      }

      final uniqueId = _generateUniqueId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final storedPath = await _persistImageDataToFile(
        uniqueId: uniqueId,
        imageData: b64,
      );

      await _saveImageToSQLite(
        uniqueId: uniqueId,
        imageData: storedPath,
        serverId: serverId,
        isSelfie: false,
        activityType: activityType,
        schId: schId,
        createdAt: now,
        updatedAt: now,
      );

      Logger.debugLog(
        '✅ PMIS document saved with unique ID: $uniqueId (server $serverId)',
      );
      return uniqueId;
    } catch (e) {
      Logger.errorLog('❌ downloadPmisDocumentByServerId: $e');
      return null;
    }
  }

  /// 4. Get image data using unique ID
  Future<String?> getImageUsingUniqueId(String uniqueId) async {
    Logger.debugLog('🖼️ getImageUsingUniqueId called with uniqueId: $uniqueId');
    final result = await _getByUniqueIdFromSQLite(uniqueId);
    if (result != null) {
      final imageData = await _readStoredImageDataAsBase64(result.imageData);
      Logger.debugLog(
        '🖼️ getImageUsingUniqueId: Found image data, length: ${imageData?.length ?? 0}',
      );
      return imageData;
    }
    Logger.debugLog('🖼️ getImageUsingUniqueId: No image data found for uniqueId: $uniqueId');
    return null;
  }

  /// Resolves server photo id or `LOCAL_IMAGE_ID_*` to base64 for offline/online display.
  Future<String?> resolveImageBase64ForPhotoRef(String photoRef) async {
    final ref = photoRef.trim();
    if (ref.isEmpty) return null;

    if (ref.startsWith('LOCAL_IMAGE_ID')) {
      return getImageUsingUniqueId(ref);
    }

    final cached = await getImagesByServerId(ref);
    if (cached != null) {
      final uniqueId = cached.uniqueId.trim();
      if (uniqueId.isNotEmpty) {
        final base64 = await getImageUsingUniqueId(uniqueId);
        if (base64 != null && base64.isNotEmpty) return base64;
      }
      return _readStoredImageDataAsBase64(cached.imageData);
    }

    return getImageUsingUniqueId(ref);
  }

  /// Returns stored local file path for a unique id when available.
  /// Useful for offline VIDEO/PDF playback where base64 is not needed.
  Future<String?> getStoredFilePathUsingUniqueId(String uniqueId) async {
    final result = await _getByUniqueIdFromSQLite(uniqueId);
    final stored = result?.imageData;
    if (stored == null || stored.isEmpty) return null;
    if (!_looksLikeStoredPath(stored)) return null;
    final normalized = _normalizeStoredPath(stored);
    final file = File(normalized);
    if (await file.exists()) return file.path;
    return null;
  }

  /// PMIS helper: upload a locally stored `LOCAL_IMAGE_ID_*` file via
  /// `api/v1/common/UploadDocuments` and return `docId`.
  /// Avoids the mobile uploads endpoint for PMIS ticket attachments.
  Future<String?> getOrUploadPmisDocumentIdFromUniqueId(String uniqueId) async {
    try {
      final imageModel = await _getByUniqueIdFromSQLite(uniqueId);
      final existingServerId = imageModel?.serverId?.trim();
      if (existingServerId != null && existingServerId.isNotEmpty) {
        return existingServerId;
      }

      if (!await ConnectivityHelper.isConnected()) {
        return null;
      }

      final filePath = await getStoredFilePathUsingUniqueId(uniqueId);
      if (filePath == null || filePath.isEmpty) {
        Logger.errorLog(
          '❌ PMIS UploadDocuments: local file missing for $uniqueId',
        );
        return null;
      }

      final multipartFile = await MultipartFile.fromFile(
        filePath,
        filename: basename(filePath),
      );

      final result = await _apiService.post<Map<String, dynamic>>(
        path: 'api/v1/common/UploadDocuments',
        data: const <String, dynamic>{
          'activityType': 'AT',
          'docId': '0',
        },
        files: [multipartFile],
        useFormDataFormat: true,
      );

      if (!result.isSuccess || result.data == null) {
        Logger.errorLog(
          '❌ PMIS UploadDocuments failed for $uniqueId: ${result.errorMessage}',
        );
        return null;
      }

      final docId = result.data?['docId']?.toString().trim() ?? '';
      if (docId.isEmpty || docId == '0') return null;
      await _updateServerId(uniqueId, docId);
      return docId;
    } catch (e) {
      Logger.errorLog('❌ getOrUploadPmisDocumentIdFromUniqueId: $e');
      return null;
    }
  }

  /// Save image to SQLite
  Future<void> _saveImageToSQLite({
    required String uniqueId,
    required String? imageData,
    required String? serverId,
    required ActivityTypeEnum activityType,
    required bool isSelfie,
    String? schId,
    required int createdAt,
    required int updatedAt,
  }) async {
    try {
      final db = await database;
      await db.insert(_tableName, {
        'unique_id': uniqueId,
        'server_id': serverId,
        'image_data': imageData,
        'is_selfie': isSelfie ? 1 : 0,
        'activity_type': activityType.value,
        'sch_id': schId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        Logger.errorLog('Database was closed, reinitializing...');
        _database = null; // Force reinitialization
        final db = await database;

        await db.insert(_tableName, {
          'unique_id': uniqueId,
          'server_id': serverId,
          'image_data': imageData,
          'is_selfie': isSelfie ? 1 : 0,
          'activity_type': activityType.value,
          'sch_id': schId,
          'created_at': createdAt,
          'updated_at': updatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        rethrow;
      }
    }
  }

  /// Get server ID from SQLite
  Future<ImageModel?> _getByUniqueIdFromSQLite(String uniqueId) async {
    Logger.debugLog('_getServerIdFromSQLite called with uniqueId: $uniqueId');

    try {
      final db = await database;
      Logger.debugLog('Executing database query...');

      // First try to find by unique_id
      List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'unique_id = ?',
        whereArgs: [uniqueId],
        limit: 1,
      );

      Logger.debugLog('🔍 SQLite query by unique_id result: $maps');

      // If not found by unique_id and the ID looks like a server ID (numeric), try server_id
      if (maps.isEmpty && int.tryParse(uniqueId) != null) {

        maps = await db.query(
          _tableName,
          where: 'server_id = ?',
          whereArgs: [uniqueId],
          limit: 1,
        );

        Logger.debugLog('🔍 SQLite query by server_id result: $maps');
      }

      if (maps.isNotEmpty) {
        final data = maps.first;

        return convertDataToModel(data);
      } else {

        Logger.debugLog(
          'Image not found in sqlite with unique id or server id: $uniqueId',
        );
      }
    } catch (e) {

      if (e.toString().contains('database_closed')) {
        Logger.errorLog('Database was closed, reinitializing...');
        _database = null; // Force reinitialization
        final db = await database;

        // Try unique_id first
        List<Map<String, dynamic>> maps = await db.query(
          _tableName,
          where: 'unique_id = ?',
          whereArgs: [uniqueId],
          limit: 1,
        );

        // If not found and ID is numeric, try server_id
        if (maps.isEmpty && int.tryParse(uniqueId) != null) {
          maps = await db.query(
            _tableName,
            where: 'server_id = ?',
            whereArgs: [uniqueId],
            limit: 1,
          );
        }

        if (maps.isNotEmpty) {
          final data = maps.first;
          return convertDataToModel(data);
        }
      } else {

        Logger.errorLog('Exception in _getByUniqueIdFromSQLite: $e');
      }
    }
    return null;
  }

  ImageModel convertDataToModel(data) {
    return ImageModel(
      uniqueId: data['unique_id'],
      createdAt: data['created_at'],
      serverId: data['server_id'],
      imageData: data['image_data'],
      isSelfie: data['is_selfie'] == 1,
      schId: data['sch_id'],
      activityType: ActivityTypeEnum.fromString(data['activity_type']),
    );
  }

  /// Update image data for existing record
  Future<void> _updateImageData(String uniqueId, String? imageData) async {
    try {
      final db = await database;
      await db.update(
        _tableName,
        {
          'image_data': imageData,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'unique_id = ?',
        whereArgs: [uniqueId],
      );
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        Logger.errorLog('Database was closed, reinitializing...');
        _database = null; // Force reinitialization
        final db = await database;

        await db.update(
          _tableName,
          {
            'image_data': imageData,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'unique_id = ?',
          whereArgs: [uniqueId],
        );
      } else {
        rethrow;
      }
    }
  }

  /// Update server ID in SQLite
  Future<void> _updateServerId(String uniqueId, String serverId) async {
    try {
      final db = await database;
      Logger.debugLog(
        'Updating SQLite: uniqueId=$uniqueId, serverId=$serverId',
      );

      final result = await db.update(
        _tableName,
        {
          'server_id': serverId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'unique_id = ?',
        whereArgs: [uniqueId],
      );

      Logger.debugLog('SQLite update result: $result rows affected');
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        Logger.errorLog('Database was closed, reinitializing...');
        _database = null; // Force reinitialization
        final db = await database;

        final result = await db.update(
          _tableName,
          {
            'server_id': serverId,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'unique_id = ?',
          whereArgs: [uniqueId],
        );

        Logger.debugLog(
          'SQLite update result (after retry): $result rows affected',
        );
      } else {
        rethrow;
      }
    }
  }

  /// Upload image to server
  Future<String?> _uploadToServer(
    String imageData,
    ActivityTypeEnum activityType,
    String siteSchId,
    bool isSelfie,
  ) async {
    try {
      // Convert base64 string to bytes for file upload
      Uint8List imageBytes;
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
      ResponseResult? response = null;
      if (isSelfie) {
        if (await ConnectivityHelper.isConnected()) {
          response = await _apiService.post<Map<String, dynamic>>(
            path: "api/v1/mobile/uploadsSelfie",
            data: {'selfie': multipartFile, 'imgId': '0', 'SchId': siteSchId},
            useFormDataFormat: true,
          );
        }
        if (response == null || !response.isSuccess) {
          await ServiceLocator().pendingRequestService.savePendingRequest(
            requestId: 'IMAGE-${DateTime.timestamp()}',
            url: "api/v1/mobile/uploadsSelfie",
            headers: {},
            jsonEncodedRequestData: jsonEncode([
              {'selfie': imageData, 'imgId': '0', 'SchId': siteSchId},
            ]),
          );
        }
      } else {
        if (await ConnectivityHelper.isConnected() &&
            !await _shouldKeepImageLocalForOfflineTicket(siteSchId, activityType)) {
          response = await _apiService.post<Map<String, dynamic>>(
            path: 'api/v1/mobile/uploads',
            data: {
              'imgFile': multipartFile,
              'activityType': activityType.value,
              'schId': siteSchId,
            },
            useFormDataFormat: true,
          );
        } else {
          Logger.debugLog(
            'Skipping api/v1/mobile/uploads (offline or ticket offline session); image kept as LOCAL_IMAGE_ID',
          );
        }
      }

      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (response != null && response.isSuccess && response.data != null) {
        Logger.debugLog('📤 API Response: ${response.data}');

        final photoId =
            response.data!['imgId']?.toString() ??
            response.data!['photoId']?.toString() ??
            response.data!['id']?.toString();

        Logger.debugLog('🔍 Extracted photo ID: $photoId');

        if (photoId != null && photoId.isNotEmpty) {

          Logger.debugLog('✅ Image uploaded to server with ID: $photoId');
          return photoId;
        } else {
          Logger.errorLog(
            '❌ No photo ID returned in response: ${response.data}',
          );
          Logger.errorLog('❌ Tried keys: imgId, photoId, id');
          return null;
        }
      } else {
        if (await ConnectivityHelper.isConnected()) {
          Logger.errorLog('❌ Failed to upload image: ${response?.errorMessage}');
        }
        return null;
      }
    } catch (e) {
      Logger.errorLog('❌ Error uploading to server: $e');
      return null;
    }
  }

  Future<String?> _uploadFileToServer({
    required String imageFilePath,
    required ActivityTypeEnum activityType,
    required String siteSchId,
    required bool isSelfie,
  }) async {
    try {
      final multipartFile = await MultipartFile.fromFile(
        imageFilePath,
        filename: 'image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      ResponseResult? response = null;
      if (isSelfie) {
        if (await ConnectivityHelper.isConnected()) {
          response = await _apiService.post<Map<String, dynamic>>(
            path: "api/v1/mobile/uploadsSelfie",
            data: {'selfie': multipartFile, 'imgId': '0', 'SchId': siteSchId},
            useFormDataFormat: true,
          );
        }
      } else {
        if (await ConnectivityHelper.isConnected() &&
            !await _shouldKeepImageLocalForOfflineTicket(siteSchId, activityType)) {
          response = await _apiService.post<Map<String, dynamic>>(
            path: 'api/v1/mobile/uploads',
            data: {
              'imgFile': multipartFile,
              'activityType': activityType.value,
              'schId': siteSchId,
            },
            useFormDataFormat: true,
          );
        } else {
          Logger.debugLog(
            'Skipping api/v1/mobile/uploads (offline or ticket offline session); image kept as LOCAL_IMAGE_ID',
          );
        }
      }

      if (response != null && response.isSuccess && response.data != null) {
        final photoId =
            response.data!['imgId']?.toString() ??
            response.data!['photoId']?.toString() ??
            response.data!['id']?.toString();
        if (photoId != null && photoId.isNotEmpty) {
          return photoId;
        }
      }
      return null;
    } catch (e) {
      Logger.errorLog('Error in _uploadFileToServer: $e');
      return null;
    }
  }

  /// Download image from server
  Future<String?> downloadFromServer(String serverId) async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        path: '/api/v1/mobile/allImageList?imgIds=$serverId',
      );

      if (response.isSuccess && response.data != null) {
        final imageData = response.data?.first['imageData'] as String?;
        if (imageData != null && imageData.isNotEmpty) {
          // Return the base64 string directly
          Logger.debugLog('✅ Image downloaded from server as base64 string');
          return imageData;
        } else {
          Logger.errorLog('❌ Empty image data received from server');
          return null;
        }
      } else {
        Logger.errorLog(' Failed to download image: ${response.errorMessage}');
        return null;
      }
    } catch (e) {
      Logger.errorLog('❌ Error downloading from server: $e');
      return null;
    }
  }

  /// Get images by server ID
  Future<ImageModel?> getImagesByServerId(String serverId) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        _tableName,
        where: 'server_id = ?',
        whereArgs: [serverId],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      Logger.debugLog('🔍 SQLite query result: $maps');

      if (maps.isNotEmpty) {
        final data = maps.first;
        return convertDataToModel(data);
      } else {
        Logger.debugLog('Image not found in sqlite with unique id');
      }
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        Logger.errorLog('Database was closed, reinitializing...');
        _database = null; // Force reinitialization
        final db = await database;

        final List<Map<String, dynamic>> maps = await db.query(
          _tableName,
          where: 'server_id = ?',
          whereArgs: [serverId],
          orderBy: 'created_at DESC',
          limit: 1,
        );

        if (maps.isNotEmpty) {
          final data = maps.first;
          return convertDataToModel(data);
        }
      } else {
        Logger.errorLog('Error in getImagesByServerId: $e');
      }
    }
    return null;
  }

  /// Clear all images
  Future<void> clearAllImages() async {
    final db = await database;
    try {
      final dir = await _getImagesDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      Logger.errorLog('Failed to clear local image files: $e');
    }
    await db.delete(_tableName);
    Logger.debugLog('✅ All images cleared');
  }

  /// Drop and recreate database with all tables
  Future<void> dropAndRecreateDatabase() async {
    try {
      Logger.debugLog('Dropping and recreating ImageUploadService database');

      // Close existing database connection
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // Get database path
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);

      // Delete the database file
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        Logger.debugLog('🗑️ ImageUploadService database file deleted');
      }

      // Recreate database by calling _initDatabase
      _database = await _initDatabase();
      Logger.debugLog(
        '✅ ImageUploadService database recreated with all tables',
      );
    } catch (e) {
      Logger.errorLog(
        '❌ Error dropping and recreating ImageUploadService database: $e',
      );
      // Reset database instance to force recreation on next access
      _database = null;
      rethrow;
    }
  }

  /// Get database statistics
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;
    final totalImages =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_tableName'),
        ) ??
        0;
    final uploadedImages =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_tableName WHERE server_id IS NOT NULL',
          ),
        ) ??
        0;
    final localImages = totalImages - uploadedImages;

    return {
      'total_images': totalImages,
      'uploaded_images': uploadedImages,
      'local_images': localImages,
      'upload_percentage': totalImages > 0
          ? (uploadedImages / totalImages * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      Logger.debugLog('✅ ImageUploadService database closed');
    }
  }
}
