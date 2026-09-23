import 'dart:convert';
import 'dart:io';

import 'package:app/app_config.dart';
import 'package:app/commonWidgets/activity_ticket_checker_close_pop_up.dart';
import 'package:app/commonWidgets/activity_ticket_close_pop_up.dart';
import 'package:app/commonWidgets/activity_ticket_video_preview_dialog.dart';
import 'package:app/commonWidgets/custom_file_upload_new.dart';
import 'package:app/commonWidgets/custom_form_dropdown.dart';
import 'package:app/commonWidgets/custom_form_field.dart';
import 'package:app/commonWidgets/custom_image_upload_field.dart';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/commonWidgets/safe_file_image.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/models/pmis_activity_ticket_model.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/upload_dcouments.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Main activity ticket flow screen (after approvals / checker list).
/// Renders [PmisActivityTicketDetail.ticketFieldValues] by [subActivityDataType].
class ActivityTicketScreen extends StatefulWidget {
  final int activityTicketId;
  final String breadcrumbText;
  final String activityName;
  final String? summaryCardTitle;
  final PmisActivityTicketDetail detail;

  const ActivityTicketScreen({
    super.key,
    required this.activityTicketId,
    required this.breadcrumbText,
    required this.activityName,
    this.summaryCardTitle,
    required this.detail,
  });

  @override
  State<ActivityTicketScreen> createState() => _ActivityTicketScreenState();
}

class _ActivityTicketScreenState extends State<ActivityTicketScreen> {
  final Map<int, TextEditingController> _textByTfv = {};
  /// Longitude controllers for [COORDINATES] fields (lat lives in [_textByTfv]).
  final Map<int, TextEditingController> _lngByTfv = {};
  final Map<int, String?> _dropdownByTfv = {};
  final Map<int, List<File>> _filesByTfv = {};
  final Map<int, List<Map<String, dynamic>>> _uploadedAttachmentsByTfv = {};
  /// Base64 data URL, local path, or `data:image/...` for [ImageUploadField.externalImageUrl].
  final Map<int, String?> _imageExternalDataByTfv = {};
  /// True while resolving [attachmentId] via `DocumentById` for an IMAGE row.
  final Set<int> _imageLoadingFromServerTfvIds = {};
  /// tfvIds where the user picked a new file this session (real replace).
  final Set<int> _uploadReplacedTfvIds = {};

  /// Upload edits while viewing historic [oldData] (oldData index → current tfvIds).
  final Map<int, Set<int>> _historicUploadReplacedByOldIndex = {};

  /// Field snapshots for historic days edited by Checker / Ticket Manager.
  final Map<int, _AtFieldSnapshot> _historicEditsByIndex = {};

  late List<PmisTicketFieldValue> _sortedFields;
  /// Prevents overlapping GPS taps and disables the button while resolving.
  int? _capturingGpsTfvId;

  /// `-1` = today / [PmisActivityTicketDetail.ticketFieldValues];
  /// `>= 0` = index into [PmisActivityTicketDetail.oldData].
  int _historicPickerIndex = -1;

  /// Stashes edits on the live ticket when opening a historic snapshot.
  _AtFieldSnapshot? _draftWhenLeavingCurrent;

  UploadDcoumentsService get _uploadService =>
      UploadDcoumentsService(apiService: ServiceLocator().apiService);

  static String _normDataType(PmisTicketFieldValue f) =>
      (f.subActivityDataType ?? '').trim().toUpperCase();

  static String _normControlType(PmisTicketFieldValue f) =>
      (f.subActivityControlType ?? '').trim().toUpperCase();

  /// True for VideoRecorder / VIDEO_RECORDER / video recorder control types.
  static bool _isVideoRecorderControl(PmisTicketFieldValue f) {
    final c = _normControlType(f)
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
    return c == 'VIDEORECORDER' || c.contains('VIDEORECORD');
  }

  /// API may use camelCase, snake_case, or PascalCase for the image file id.
  static String? _rawAttachmentIdFromMap(Map<String, dynamic> a) {
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

  /// Longitude if name clearly indicates longitude; latitude if it says
  /// "latitude" (avoids matching "long" inside "latitude").
  static bool _isLongitudeField(PmisTicketFieldValue f) {
    final n = (f.subActivityName ?? '').toLowerCase();
    if (n.contains('longitude')) return true;
    if (n.contains('lng')) return true;
    if (n.contains('latitude')) return false;
    return n.contains('long');
  }

  /// True when a Coordinates row should show both Lat + Lng (and store
  /// `lat, long` in [valText]). Separate fields named Latitude/Longitude stay
  /// single-value.
  static bool _isCombinedCoordinatesField(PmisTicketFieldValue f) {
    if (_normDataType(f) != 'COORDINATES') return false;
    final n = (f.subActivityName ?? '').toLowerCase();
    final isLatOnly = n.contains('latitude') && !n.contains('longitude');
    final isLngOnly = n.contains('longitude') ||
        (n.contains('lng') && !n.contains('latitude')) ||
        (n.contains('long') && !n.contains('latitude'));
    return !isLatOnly && !isLngOnly;
  }

  /// Parses `valText` ("lat, long") or falls back to field latitude/longitude.
  static (String lat, String lng) _initialCoordinates(PmisTicketFieldValue f) {
    final raw = (f.valText?.toString() ?? '').trim();
    if (raw.isNotEmpty) {
      final parts = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length >= 2) return (parts[0], parts[1]);
      if (parts.length == 1) return (parts[0], '');
    }

    bool usable(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return false;
      final n = num.tryParse(s);
      if (n != null && n == 0) return false;
      return s != '0' && s != '0.0' && s != '0.00';
    }

    final lat = (f.latitude ?? '').toString().trim();
    final lng = (f.longitude ?? '').toString().trim();
    return (usable(lat) ? lat : '', usable(lng) ? lng : '');
  }

  static Map<String, dynamic> _configMap(PmisTicketFieldValue f) {
    final c = f.configJson;
    if (c is Map) return Map<String, dynamic>.from(c);
    if (c is String) {
      final trimmed = c.trim();
      if (trimmed.isEmpty) return const <String, dynamic>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    _sortedFields = List<PmisTicketFieldValue>.from(
      widget.detail.ticketFieldValues,
    )..sort((a, b) => (a.seqNo ?? 0).compareTo(b.seqNo ?? 0));

    for (final f in _sortedFields) {
      if (_isCombinedCoordinatesField(f)) {
        final coords = _initialCoordinates(f);
        _textByTfv[f.tfvId] = TextEditingController(text: coords.$1);
        _lngByTfv[f.tfvId] = TextEditingController(text: coords.$2);
      } else {
        _textByTfv[f.tfvId] = TextEditingController(text: _initialText(f));
      }
      final type = _normDataType(f);
      if (type == 'DROPDOWN') {
        final v = f.valText?.toString().trim();
        _dropdownByTfv[f.tfvId] =
            (v != null && v.isNotEmpty) ? v : null;
      }
      if (_isUploadType(type)) {
        _filesByTfv[f.tfvId] = [];
        _uploadedAttachmentsByTfv[f.tfvId] =
            _hydrateAttachmentsForField(f, source: f.attachments);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final f in _sortedFields) {
        final type = _normDataType(f);
        if (type == 'IMAGE') {
          _loadExistingActivityTicketImage(f);
        } else if (type == 'VIDEO' || type == 'PDF') {
          if (_allowsMultipleFiles(f)) {
            // Multi list is attachment-driven; drop any stale prefetch temps.
            _filesByTfv[f.tfvId]?.clear();
          } else {
            _prefetchUploadFieldFromServerIfNeeded(f);
          }
        }
      }
      if (mounted) setState(() {});
    });
  }

  /// First attachment row with a usable server id, else first id from [valText].
  /// For IMAGE rows, prefer the id in [valText] (latest) over older orphan rows.
  static Map<String, dynamic>? _primaryAttachmentMap(PmisTicketFieldValue f) {
    final vt = f.valText?.toString().trim() ?? '';
    final preferredIds = vt
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '0' && e.toLowerCase() != 'null')
        .toList();
    final want = preferredIds.isNotEmpty ? preferredIds.last : '';

    if (want.isNotEmpty) {
      Map<String, dynamic>? matched;
      var bestTa = -1;
      for (final a in f.attachments) {
        if (a['isActive'] == false) continue;
        final id = _rawAttachmentIdFromMap(a) ?? '';
        if (id != want) continue;
        final t = int.tryParse(a['taId']?.toString() ?? '') ?? 0;
        if (t >= bestTa) {
          bestTa = t;
          matched = a;
        }
      }
      if (matched != null) return matched;
      return <String, dynamic>{
        'attachmentId': int.tryParse(want) ?? want,
      };
    }

    Map<String, dynamic>? best;
    var bestTa = -1;
    for (final a in f.attachments) {
      if (a['isActive'] == false) continue;
      final id = _rawAttachmentIdFromMap(a) ?? '';
      if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
      final t = int.tryParse(a['taId']?.toString() ?? '') ?? 0;
      if (t >= bestTa) {
        bestTa = t;
        best = a;
      }
    }
    return best;
  }

  static String? _primaryAttachmentServerId(PmisTicketFieldValue f) {
    final m = _primaryAttachmentMap(f);
    if (m == null) return null;
    final id = _rawAttachmentIdFromMap(m) ?? '';
    if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') return null;
    return id;
  }

  /// Prefer in-memory uploads from this session, then API snapshot on [f].
  Map<String, dynamic>? _primaryAttachmentMapForUi(PmisTicketFieldValue f) {
    final live = _uploadedAttachmentsByTfv[f.tfvId];
    if (live != null) {
      for (final a in live) {
        final id = _rawAttachmentIdFromMap(a) ?? '';
        if (id.isNotEmpty && id != '0' && id.toLowerCase() != 'null') {
          return a;
        }
      }
    }
    return _primaryAttachmentMap(f);
  }

  String? _primaryAttachmentServerIdForUi(PmisTicketFieldValue f) {
    final m = _primaryAttachmentMapForUi(f);
    if (m == null) return null;
    final id = _rawAttachmentIdFromMap(m) ?? '';
    if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') return null;
    return id;
  }

  static String _attachmentDisplayName(
    Map<String, dynamic> a,
    String fallback,
  ) {
    for (final k in <String>[
      'fileName',
      'file_name',
      'attachmentName',
      'attachment_name',
      'origFileName',
      'name',
    ]) {
      final v = a[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return fallback;
  }

  /// Friendly label for a server attachment chip (avoids bare `file_123`).
  String _serverAttachmentLabel(
    PmisTicketFieldValue f,
    Map<String, dynamic> a,
    String id,
  ) {
    final fromApi = _attachmentDisplayName(a, '').trim();
    if (fromApi.isNotEmpty &&
        !fromApi.toLowerCase().startsWith('file_') &&
        fromApi.toLowerCase() != 'attachment') {
      return fromApi;
    }
    final type = _normDataType(f);
    if (type == 'VIDEO') return 'Video $id';
    if (type == 'PDF') return 'PDF $id';
    if (type == 'IMAGE') return 'Image $id';
    return 'File $id';
  }

  static String? _formatActivityTicketImageDisplayString(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('data:image/')) {
      if (cleaned.startsWith('data:image/jpg')) {
        return cleaned.replaceFirst('data:image/jpg', 'data:image/jpeg');
      }
      return cleaned;
    }
    if (cleaned.startsWith('/') ||
        cleaned.startsWith('file://') ||
        cleaned.startsWith(r'file:\')) {
      return cleaned;
    }
    return 'data:image/jpeg;base64,$cleaned';
  }

  /// `GET /api/v1/common/DocumentById/{id}` — binary body.
  Future<Uint8List?> _downloadDocumentByIdBytes(int docId) async {
    if (docId <= 0) return null;
    try {
      final response = await ServiceLocator().apiService.get<Uint8List>(
        path: '/api/v1/common/DocumentById/$docId',
        responseType: ResponseType.bytes,
      );
      if (!response.isSuccess || response.data == null) return null;
      return response.data as Uint8List;
    } catch (e) {
      Logger.errorLog('[ActivityTicket] DocumentById failed ($docId): $e');
      return null;
    }
  }

  static String _bytesToImageDataUrl(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'data:image/png;base64,${base64Encode(bytes)}';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'data:image/gif;base64,${base64Encode(bytes)}';
    }
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  /// Offline local blobs, else numeric [attachmentId] via [DocumentById],
  /// else treat [imageId] as a local unique id string.
  Future<String?> _fetchActivityTicketMediaBase64(String imageId) async {
    if (imageId.isEmpty) return null;
    final imageUpload = ServiceLocator().imageUploadService;
    final central = ServiceLocator().centralAssetAuditService;

    if (imageId.contains('LOCAL_IMAGE_ID')) {
      var imageData = await imageUpload.getImageUsingUniqueId(imageId);
      if (imageData == null || imageData.isEmpty) {
        imageData = await central.getImageAsDataUrl(imageId);
      }
      return imageData;
    }

    final docId = int.tryParse(imageId.trim());
    if (docId != null && docId > 0) {
      final bytes = await _downloadDocumentByIdBytes(docId);
      if (bytes != null && bytes.isNotEmpty) {
        return _bytesToImageDataUrl(bytes);
      }
      return null;
    }

    var imageData = await imageUpload.getImageUsingUniqueId(imageId);
    if (imageData != null && imageData.isNotEmpty) {
      return imageData;
    }
    return await central.getImageAsDataUrl(imageId);
  }

  Future<File?> _localFileFromUniqueId(String id) async {
    if (!id.contains('LOCAL_IMAGE_ID')) return null;
    final path = await ServiceLocator()
        .imageUploadService
        .getStoredFilePathUsingUniqueId(id);
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file;
  }

  static String _extensionForUploadType(String normType, Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return '.pdf';
    }
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return '.mp4';
    }
    if (normType == 'VIDEO') return '.mp4';
    if (normType == 'PDF') return '.pdf';
    return '.bin';
  }

  /// Pull VIDEO/PDF bytes via [DocumentById] into a temp file for preview.
  /// Skipped for multi-file fields — those are listed as server chips instead
  /// (prefetching only the primary id duplicated the UI as at_*.mp4 + file_*).
  Future<void> _prefetchUploadFieldFromServerIfNeeded(PmisTicketFieldValue f) async {
    if (_allowsMultipleFiles(f)) return;

    final prim = _primaryAttachmentMapForUi(f);
    if (prim == null) return;
    final id = _rawAttachmentIdFromMap(prim) ?? '';
    if (id.isEmpty) return;

    final files = _filesByTfv[f.tfvId];
    if (files == null || files.isNotEmpty) return;

    try {
      final localFile = await _localFileFromUniqueId(id.trim());
      if (localFile != null) {
        if (!mounted) return;
        setState(() {
          files
            ..clear()
            ..add(localFile);
        });
        return;
      }

      final docId = int.tryParse(id.trim());
      if (docId == null || docId <= 0) return;
      final bytes = await _downloadDocumentByIdBytes(docId);
      if (bytes == null || bytes.isEmpty || !mounted) return;

      final type = _normDataType(f);
      var ext = p.extension(_attachmentDisplayName(prim, ''));
      if (ext.isEmpty || ext == '.') {
        ext = _extensionForUploadType(type, bytes);
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'at_${widget.detail.atId}_${f.tfvId}_$id$ext'),
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        files
          ..clear()
          ..add(file);
      });
    } catch (_) {
      // Offline / error: server chip + tap-to-open remain available.
    }
  }

  Future<void> _openServerAttachmentFromDocument(
    dynamic attachmentId,
    PmisTicketFieldValue f,
  ) async {
    // Videos / images open in-app; PDFs use the system opener.
    if (_normDataType(f) == 'VIDEO') {
      await _showServerVideoPopup(
        f,
        attachmentId: attachmentId?.toString(),
      );
      return;
    }
    if (_normDataType(f) == 'IMAGE') {
      await _previewServerImage(
        f,
        attachmentId: attachmentId?.toString(),
      );
      return;
    }

    final idStr = attachmentId?.toString().trim() ?? '';
    if (idStr.isEmpty) return;
    final docId = int.tryParse(idStr);
    if (docId == null || docId <= 0) {
      if (mounted) {
        Toastbar.showErrorToastbar('Invalid attachment id', context);
      }
      return;
    }

    if (!mounted) return;
    LoaderWidget.showLoader(context);
    try {
      final bytes = await _downloadDocumentByIdBytes(docId);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        Toastbar.showErrorToastbar(
          'Could not load file (offline or unavailable)',
          context,
        );
        return;
      }
      final prim = _primaryAttachmentMapForUi(f);
      final type = _normDataType(f);
      var ext = prim != null
          ? p.extension(_attachmentDisplayName(prim, ''))
          : '';
      if (ext.isEmpty || ext == '.') {
        ext = _extensionForUploadType(type, bytes);
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'at_open_${widget.detail.atId}_${f.tfvId}_$docId$ext'),
      );
      await file.writeAsBytes(bytes, flush: true);
      await OpenFile.open(file.path);
    } catch (e) {
      if (mounted) {
        Toastbar.showErrorToastbar('Failed to open file: $e', context);
      }
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Future<void> _previewLocalImageFile(File file) async {
    if (!await file.exists()) {
      if (mounted) {
        Toastbar.showErrorToastbar('Image file not found', context);
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: SafeImageFile(
                  file: file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewServerImage(
    PmisTicketFieldValue f, {
    String? attachmentId,
  }) async {
    final idStr =
        (attachmentId ?? _primaryAttachmentServerIdForUi(f))?.trim() ?? '';
    if (idStr.isEmpty) {
      if (mounted) {
        Toastbar.showErrorToastbar('No image to preview', context);
      }
      return;
    }

    if (!mounted) return;
    LoaderWidget.showLoader(context);
    try {
      Uint8List? bytes;
      final localFile = await _localFileFromUniqueId(idStr);
      if (localFile != null) {
        bytes = await localFile.readAsBytes();
      } else {
        final docId = int.tryParse(idStr);
        if (docId == null || docId <= 0) {
          if (mounted) {
            Toastbar.showErrorToastbar('Invalid image id', context);
          }
          return;
        }
        bytes = await _downloadDocumentByIdBytes(docId);
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        Toastbar.showErrorToastbar(
          'Could not load image (offline or unavailable)',
          context,
        );
        return;
      }
      final imageBytes = bytes;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.memory(
                    imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 48,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Toastbar.showErrorToastbar('Failed to open image: $e', context);
      }
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Future<void> _playLocalVideoFile(File file) async {
    if (!await file.exists()) {
      if (mounted) {
        Toastbar.showErrorToastbar('Video file not found', context);
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => ActivityTicketVideoPreviewDialog(videoFile: file),
    );
  }

  Future<void> _showServerVideoPopup(
    PmisTicketFieldValue f, {
    String? attachmentId,
  }) async {
    final idStr = (attachmentId ?? _primaryAttachmentServerIdForUi(f))?.trim();
    if (idStr == null || idStr.isEmpty) {
      if (mounted) {
        Toastbar.showErrorToastbar('No video to play', context);
      }
      return;
    }

    if (!mounted) return;
    LoaderWidget.showLoader(context);
    try {
      File? file = await _localFileFromUniqueId(idStr);
      if (file == null) {
        final docId = int.tryParse(idStr);
        if (docId == null || docId <= 0) {
          if (mounted) {
            Toastbar.showErrorToastbar('No video to play', context);
          }
          return;
        }
        final bytes = await _downloadDocumentByIdBytes(docId);
        if (!mounted) return;
        if (bytes == null || bytes.isEmpty) {
          Toastbar.showErrorToastbar(
            'Could not load video (offline or unavailable)',
            context,
          );
          return;
        }

        final prim = _primaryAttachmentMapForUi(f);
        var ext = prim != null
            ? p.extension(_attachmentDisplayName(prim, ''))
            : '';
        if (ext.isEmpty || ext == '.') {
          ext = _extensionForUploadType('VIDEO', bytes);
        }
        final dir = await getTemporaryDirectory();
        file = File(
          p.join(
            dir.path,
            'at_video_preview_${widget.detail.atId}_${f.tfvId}_$docId$ext',
          ),
        );
        await file.writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;

      LoaderWidget.hideLoader();
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => ActivityTicketVideoPreviewDialog(videoFile: file!),
      );
    } catch (e) {
      if (mounted) {
        Toastbar.showErrorToastbar('Failed to open video: $e', context);
      }
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  /// Loads existing attachment for display (same pattern as PM [ImageUploadField]).
  Future<void> _loadExistingActivityTicketImage(PmisTicketFieldValue f) async {
    final photoId = _primaryAttachmentServerId(f);
    if (photoId == null || photoId.isEmpty) return;

    var showProgress = photoId.contains('LOCAL_IMAGE_ID') ||
        (int.tryParse(photoId.trim()) != null);

    if (showProgress && mounted) {
      setState(() => _imageLoadingFromServerTfvIds.add(f.tfvId));
    }

    try {
      final imageDataLocal = await _fetchActivityTicketMediaBase64(photoId);
      if (!mounted) return;
      final formatted =
          _formatActivityTicketImageDisplayString(imageDataLocal);
      if (!mounted) return;
      setState(() {
        _imageLoadingFromServerTfvIds.remove(f.tfvId);
        if (formatted != null && formatted.isNotEmpty) {
          _imageExternalDataByTfv[f.tfvId] = formatted;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _imageLoadingFromServerTfvIds.remove(f.tfvId));
      }
    }
  }

  String _initialText(PmisTicketFieldValue f) {
    final t = f.valText;
    if (t != null && t.toString().trim().isNotEmpty) {
      return t.toString().trim();
    }
    return '';
  }

  bool _isUploadType(String type) {
    return type == 'IMAGE' || type == 'PDF' || type == 'VIDEO';
  }

  /// Reads [configJson.allowMultipleFiles] (bool or string).
  bool _allowsMultipleFiles(PmisTicketFieldValue f) {
    final raw = _configMap(f)['allowMultipleFiles'];
    if (raw is bool) return raw;
    if (raw == null) return false;
    final s = raw.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  /// Single-file unless [configJson.allowMultipleFiles] is true.
  bool _isSingleFileUploadField(PmisTicketFieldValue f) {
    return !_allowsMultipleFiles(f);
  }

  static int _taIdFromMap(Map<String, dynamic> a) {
    return int.tryParse(a['taId']?.toString() ?? '') ?? 0;
  }

  /// One row per [attachmentId]. Prefers the highest [taId] (newest server row).
  /// Skips inactive rows so replaced/soft-deleted attachments are ignored.
  List<Map<String, dynamic>> _dedupeAttachmentsByAttachmentId(
    List<Map<String, dynamic>> attachments,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    final order = <String>[];
    for (final raw in attachments) {
      final a = Map<String, dynamic>.from(raw);
      if (a['isActive'] == false) continue;
      final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
      if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = a;
        order.add(id);
        continue;
      }
      // Keep the row with the larger taId; if equal, keep the later one.
      if (_taIdFromMap(a) >= _taIdFromMap(existing)) {
        byId[id] = a;
      }
    }
    return [for (final id in order) byId[id]!];
  }

  /// Ids listed in [PmisTicketFieldValue.valText] (comma-separated).
  static List<String> _idsFromValText(PmisTicketFieldValue f) {
    final raw = (f.valText?.toString() ?? '').trim();
    if (raw.isEmpty) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final part in raw.split(',')) {
      final id = part.trim();
      if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
      if (!seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  /// Multi-file GET often returns every id in [valText] but only one row in
  /// [attachments]. Build a full list so the UI / next POST keep all videos.
  List<Map<String, dynamic>> _hydrateAttachmentsForField(
    PmisTicketFieldValue f, {
    List<Map<String, dynamic>>? source,
  }) {
    final fromApi = _dedupeAttachmentsByAttachmentId(
      source ??
          f.attachments.map((m) => Map<String, dynamic>.from(m)).toList(),
    );
    if (_isSingleFileUploadField(f)) {
      return _normalizedLiveAttachmentsForField(f, source: fromApi);
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final a in fromApi) {
      final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
      if (id.isEmpty) continue;
      byId[id] = Map<String, dynamic>.from(a);
    }

    final type = _normDataType(f);
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addId(String id) {
      if (id.isEmpty || !seen.add(id)) return;
      final existing = byId[id];
      if (existing != null) {
        out.add(existing);
        return;
      }
      out.add(<String, dynamic>{
        'fileType': type,
        'latitude': 0,
        'longitude': 0,
        'geoAccuracyM': 0,
        'geoSource': '',
        'capturedDt': '',
        'taggedMmId': null,
        'attachmentId': int.tryParse(id) ?? id,
        'isActive': true,
        'remarks': '',
      });
    }

    for (final id in _idsFromValText(f)) {
      addId(id);
    }
    for (final a in fromApi) {
      addId((_rawAttachmentIdFromMap(a) ?? '').trim());
    }
    return out;
  }

  /// Normalize live attachments for a field: active rows only, dedupe, and for
  /// single-file fields keep only the id that matches [valText] (else newest).
  List<Map<String, dynamic>> _normalizedLiveAttachmentsForField(
    PmisTicketFieldValue f, {
    List<Map<String, dynamic>>? source,
  }) {
    var list = _dedupeAttachmentsByAttachmentId(
      source ??
          (_uploadedAttachmentsByTfv[f.tfvId] ??
              f.attachments
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList()),
    );
    if (list.isEmpty || !_isSingleFileUploadField(f)) return list;

    final preferred = _idsFromValText(f);
    if (preferred.isNotEmpty) {
      final want = preferred.last;
      Map<String, dynamic>? matched;
      var bestTa = -1;
      for (final a in list) {
        if ((_rawAttachmentIdFromMap(a) ?? '').trim() != want) continue;
        final t = _taIdFromMap(a);
        if (t >= bestTa) {
          bestTa = t;
          matched = Map<String, dynamic>.from(a);
        }
      }
      if (matched != null) return [matched];
    }
    // Newest server row wins.
    list.sort((a, b) => _taIdFromMap(a).compareTo(_taIdFromMap(b)));
    return [Map<String, dynamic>.from(list.last)];
  }

  @override
  void dispose() {
    for (final c in _textByTfv.values) {
      c.dispose();
    }
    for (final c in _lngByTfv.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _summaryTitle() {
    final fromWidget = widget.summaryCardTitle?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    final fromApi = widget.detail.makerDesignationName?.trim();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    return widget.activityName;
  }

  static String _formatPlanDate(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    final trimmed = value.trim();
    final match = RegExp(
      r'^(\d{2})/([A-Za-z]{3})/(\d{4})$',
    ).firstMatch(trimmed);
    if (match == null) return trimmed;

    final day = match.group(1)!;
    final rawMonth = match.group(2)!;
    final year = match.group(3)!;
    final month =
        '${rawMonth[0].toUpperCase()}${rawMonth.substring(1).toLowerCase()}';
    return '$day-$month-$year';
  }

  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatDisplayDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}-'
        '${_monthNames[d.month - 1]}-${d.year}';
  }

  static DateTime? _tryParseDisplayDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2})-([A-Za-z]{3})-(\d{4})$').firstMatch(t);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final monTok = m.group(2)!;
    final year = int.tryParse(m.group(3)!);
    if (day == null || year == null) return null;
    final monNorm =
        '${monTok[0].toUpperCase()}${monTok.substring(1).toLowerCase()}';
    final monthIdx = _monthNames.indexOf(monNorm);
    if (monthIdx < 0) return null;
    return DateTime(year, monthIdx + 1, day);
  }

  /// Parses API date strings (ISO, `dd-MMM-yyyy`, `dd/MM/yyyy`, etc.).
  static DateTime? _tryParseFlexibleTicketDate(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final iso = DateTime.tryParse(t);
    if (iso != null) return iso;
    final ddMmm = _tryParseDisplayDate(t);
    if (ddMmm != null) return ddMmm;
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(t);
    if (m != null) {
      final day = int.tryParse(m.group(1)!);
      final month = int.tryParse(m.group(2)!);
      final year = int.tryParse(m.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  bool get _hasHistoricDatePicker => _orderedOldDataIndices().isNotEmpty;

  bool get _isViewingEditableTicket => _historicPickerIndex < 0;

  bool get _hasAssignedRole {
    return widget.detail.role?.trim().isNotEmpty == true;
  }

  String get _normalizedRole {
    return (widget.detail.role ?? '').trim().toUpperCase();
  }

  /// API role/status gate:
  /// maker cannot edit when activity status is completed (case-insensitive).
  bool get _isMakerCompletedReadOnly {
    if (!_hasAssignedRole) return true;
    final activityStatus = widget.detail.currentStatus.trim().toUpperCase();
    return _normalizedRole == 'MAKER' && activityStatus == 'COMPLETED';
  }

  bool get _isTicketManagerRole => _normalizedRole == 'TICKET_MANAGER';

  /// Maker: edit current day only (view previous).
  /// Checker / Ticket Manager: edit current and previous day data.
  bool get _canEditTicketFields {
    if (!_hasAssignedRole) return false;
    if (!_isViewingEditableTicket) {
      return _isCheckerRole;
    }
    if (_isCheckerRole) return true;
    return !_isMakerCompletedReadOnly;
  }

  void _markUploadReplaced(int tfvId) {
    if (_historicPickerIndex >= 0) {
      _historicUploadReplacedByOldIndex
          .putIfAbsent(_historicPickerIndex, () => <int>{})
          .add(tfvId);
      return;
    }
    _uploadReplacedTfvIds.add(tfvId);
  }

  bool _isUploadReplacedForField(int tfvId, {int? historicIndex}) {
    final idx = historicIndex ?? _historicPickerIndex;
    if (idx >= 0) {
      return _historicUploadReplacedByOldIndex[idx]?.contains(tfvId) ?? false;
    }
    return _uploadReplacedTfvIds.contains(tfvId);
  }

  /// Roles that can run checker-style review submission (when that popup is used).
  bool get _isCheckerRole {
    return _normalizedRole.contains('CHECKER') || _isTicketManagerRole;
  }

  /// Close-popup selection:
  /// - CHECKER → checker popup
  /// - TICKET_MANAGER + showReviewBtns true → checker popup
  /// - TICKET_MANAGER + showReviewBtns false → maker popup
  /// - others → maker popup
  bool get _shouldShowCheckerClosePopup {
    if (_normalizedRole.contains('CHECKER')) return true;
    if (_isTicketManagerRole) return widget.detail.showReviewBtns;
    return false;
  }

  PmisAllowedStatus? _findAllowedStatusForCheckerAction(
    ActivityTicketCheckerAction action,
  ) {
    if (action == ActivityTicketCheckerAction.save) return null;
    final keys = action == ActivityTicketCheckerAction.reject
        ? const <String>['reject', 'rejected']
        : const <String>['approve', 'approved', 'accept', 'accepted'];
    for (final status in widget.detail.allowedStatuses) {
      final name = normalizeActivityTicketCloseStatusForCompare(status.statusName);
      final code = normalizeActivityTicketCloseStatusForCompare(status.statusCode);
      for (final key in keys) {
        if (name.contains(key) || code.contains(key)) {
          return status;
        }
      }
    }
    return null;
  }

  ActivityTicketClosePopupResult _mapCheckerCloseToTicketClose(
    ActivityTicketCheckerClosePopupResult checkerClose,
  ) {
    final statusForAction = _findAllowedStatusForCheckerAction(checkerClose.action);
    final statusName = statusForAction?.statusName.trim().isNotEmpty == true
        ? statusForAction!.statusName.trim()
        : widget.detail.currentStatus.trim();
    final statusCode = statusForAction?.statusCode.trim().isNotEmpty == true
        ? statusForAction!.statusCode.trim()
        : widget.detail.currentStatus.trim();
    return ActivityTicketClosePopupResult(
      statusName: statusName,
      statusCode: statusCode,
      statusPsmId: statusForAction?.psmId ?? widget.detail.currentStatusCode,
      repetitionDate: null,
      remarks: checkerClose.remarks,
    );
  }

  List<int> _orderedOldDataIndices() {
    final entries = List.generate(
      widget.detail.oldData.length,
      (i) => MapEntry(i, widget.detail.oldData[i]),
    ).where((entry) {
      final item = entry.value;
      if (item.ticketFieldValues.isEmpty) return false;
      // After Completed–To Be Repeated, old rows get new tfvIds. Do not require
      // id overlap with the current ticket — match by meaningful values only.
      return item.ticketFieldValues.any((f) {
        final valText = f.valText?.toString().trim() ?? '';
        return valText.isNotEmpty || f.attachments.isNotEmpty;
      });
    }).toList();
    entries.sort((a, b) {
      final da = _tryParseFlexibleTicketDate(a.value.actualStartDt);
      final db = _tryParseFlexibleTicketDate(b.value.actualStartDt);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return entries.map((e) => e.key).toList();
  }

  /// Match an old historic field to a current field (tfvId → name+seq → name → seq).
  PmisTicketFieldValue? _matchOldFieldToCurrent(
    PmisTicketFieldValue current,
    List<PmisTicketFieldValue> oldFields,
  ) {
    for (final o in oldFields) {
      if (o.tfvId == current.tfvId) return o;
    }
    final curName = (current.subActivityName ?? '').trim().toLowerCase();
    if (current.seqNo != null && curName.isNotEmpty) {
      for (final o in oldFields) {
        if (o.seqNo != current.seqNo) continue;
        if ((o.subActivityName ?? '').trim().toLowerCase() == curName) {
          return o;
        }
      }
    }
    if (curName.isNotEmpty) {
      for (final o in oldFields) {
        if ((o.subActivityName ?? '').trim().toLowerCase() == curName) {
          return o;
        }
      }
    }
    if (current.seqNo != null) {
      for (final o in oldFields) {
        if (o.seqNo == current.seqNo) return o;
      }
    }
    return null;
  }

  /// Keep current field structure/config; overlay values from one [oldData] row.
  List<PmisTicketFieldValue> _overlayCurrentFieldsWithOldData(
    PmisOldDataItem old,
  ) {
    return [
      for (final current in widget.detail.ticketFieldValues)
        () {
          final matched =
              _matchOldFieldToCurrent(current, old.ticketFieldValues);
          if (matched == null) return current;
          return PmisTicketFieldValue(
            tfvId: current.tfvId,
            valText: matched.valText,
            valNumeric: matched.valNumeric ?? current.valNumeric,
            valInt: matched.valInt ?? current.valInt,
            valDate: matched.valDate ?? current.valDate,
            valJson: matched.valJson.isNotEmpty ? matched.valJson : current.valJson,
            latitude: matched.latitude ?? current.latitude,
            longitude: matched.longitude ?? current.longitude,
            geoAccuracyM: matched.geoAccuracyM ?? current.geoAccuracyM,
            geoSource: matched.geoSource ?? current.geoSource,
            isActive: current.isActive,
            remarks: matched.remarks ?? current.remarks,
            attachments: matched.attachments.isNotEmpty
                ? matched.attachments
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList()
                : current.attachments
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList(),
            subActivityName: current.subActivityName,
            subActivityDataType: current.subActivityDataType,
            subActivityControlType: current.subActivityControlType,
            isRequired: current.isRequired,
            seqNo: current.seqNo,
            minVal: current.minVal,
            maxVal: current.maxVal,
            configJson: current.configJson,
            linkMmId: current.linkMmId,
          );
        }(),
    ];
  }

  String _historicRowLabel(PmisOldDataItem item, int ordinalInMenu) {
    final raw = item.actualStartDt?.trim();
    if (raw == null || raw.isEmpty) {
      return 'Record ${ordinalInMenu + 1}';
    }
    final d = _tryParseFlexibleTicketDate(raw);
    if (d != null) {
      return _formatDisplayDate(d);
    }
    return raw;
  }

  _AtFieldSnapshot _captureFieldSnapshot() {
    return _AtFieldSnapshot(
      textByTfv: {for (final e in _textByTfv.entries) e.key: e.value.text},
      lngByTfv: {for (final e in _lngByTfv.entries) e.key: e.value.text},
      dropdownByTfv: Map<int, String?>.from(_dropdownByTfv),
      uploadedAttachmentsByTfv: {
        for (final e in _uploadedAttachmentsByTfv.entries)
          e.key: e.value.map((m) => Map<String, dynamic>.from(m)).toList(),
      },
      filesByTfv: {
        for (final e in _filesByTfv.entries) e.key: List<File>.from(e.value),
      },
      imageExternalDataByTfv: Map<int, String?>.from(_imageExternalDataByTfv),
    );
  }

  void _applyFieldSnapshot(_AtFieldSnapshot s) {
    for (final e in s.textByTfv.entries) {
      final c = _textByTfv[e.key];
      if (c != null) c.text = e.value;
    }
    for (final e in s.lngByTfv.entries) {
      final c = _lngByTfv[e.key];
      if (c != null) {
        c.text = e.value;
      } else {
        _lngByTfv[e.key] = TextEditingController(text: e.value);
      }
    }
    _dropdownByTfv
      ..clear()
      ..addAll(s.dropdownByTfv);
    _uploadedAttachmentsByTfv
      ..clear()
      ..addAll({
        for (final e in s.uploadedAttachmentsByTfv.entries)
          e.key: e.value.map((m) => Map<String, dynamic>.from(m)).toList(),
      });
    _filesByTfv
      ..clear()
      ..addAll({
        for (final e in s.filesByTfv.entries) e.key: List<File>.from(e.value),
      });
    _imageExternalDataByTfv
      ..clear()
      ..addAll(s.imageExternalDataByTfv);
  }

  void _rebindFields(List<PmisTicketFieldValue> source) {
    _capturingGpsTfvId = null;
    for (final c in _textByTfv.values) {
      c.dispose();
    }
    _textByTfv.clear();
    for (final c in _lngByTfv.values) {
      c.dispose();
    }
    _lngByTfv.clear();
    _dropdownByTfv.clear();
    _filesByTfv.clear();
    _uploadedAttachmentsByTfv.clear();
    _imageExternalDataByTfv.clear();
    _imageLoadingFromServerTfvIds.clear();

    _sortedFields = List<PmisTicketFieldValue>.from(source)
      ..sort((a, b) => (a.seqNo ?? 0).compareTo(b.seqNo ?? 0));

    for (final f in _sortedFields) {
      if (_isCombinedCoordinatesField(f)) {
        final coords = _initialCoordinates(f);
        _textByTfv[f.tfvId] = TextEditingController(text: coords.$1);
        _lngByTfv[f.tfvId] = TextEditingController(text: coords.$2);
      } else {
        _textByTfv[f.tfvId] = TextEditingController(text: _initialText(f));
      }
      final type = _normDataType(f);
      if (type == 'DROPDOWN') {
        final v = f.valText?.toString().trim();
        _dropdownByTfv[f.tfvId] =
            (v != null && v.isNotEmpty) ? v : null;
      }
      if (_isUploadType(type)) {
        _filesByTfv[f.tfvId] = [];
        _uploadedAttachmentsByTfv[f.tfvId] =
            _hydrateAttachmentsForField(f, source: f.attachments);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final f in _sortedFields) {
        final type = _normDataType(f);
        if (type == 'IMAGE') {
          _loadExistingActivityTicketImage(f);
        } else if (type == 'VIDEO' || type == 'PDF') {
          if (_allowsMultipleFiles(f)) {
            _filesByTfv[f.tfvId]?.clear();
          } else {
            _prefetchUploadFieldFromServerIfNeeded(f);
          }
        }
      }
      if (mounted) setState(() {});
    });
  }

  void _onHistoricPickerChanged(int? newIndex) {
    if (newIndex == null) return;
    final prev = _historicPickerIndex;
    if (newIndex == prev) return;

    if (prev < 0 && newIndex >= 0) {
      _draftWhenLeavingCurrent = _captureFieldSnapshot();
    }
    if (prev >= 0 && _isCheckerRole) {
      _historicEditsByIndex[prev] = _captureFieldSnapshot();
    }

    setState(() {
      _historicPickerIndex = newIndex;
      if (newIndex < 0) {
        _rebindFields(widget.detail.ticketFieldValues);
        final draft = _draftWhenLeavingCurrent;
        if (draft != null) {
          _applyFieldSnapshot(draft);
        }
        _draftWhenLeavingCurrent = null;
      } else {
        _rebindFields(
          _overlayCurrentFieldsWithOldData(widget.detail.oldData[newIndex]),
        );
        final priorEdits = _historicEditsByIndex[newIndex];
        if (priorEdits != null) {
          _applyFieldSnapshot(priorEdits);
        }
      }
    });
  }

  Widget _buildHistoricDatePicker() {
    final todayLabel = _formatDisplayDate(DateTime.now());
    final ordered = _orderedOldDataIndices();
    final labels = <String>[todayLabel];
    for (var o = 0; o < ordered.length; o++) {
      final idx = ordered[o];
      labels.add(_historicRowLabel(widget.detail.oldData[idx], o));
    }
    final counts = <String, int>{};
    for (var i = 0; i < labels.length; i++) {
      final base = labels[i];
      final c = (counts[base] ?? 0) + 1;
      counts[base] = c;
      if (c > 1) {
        labels[i] = '$base ($c)';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isCheckerRole
              ? "Choose a date to view or edit that day's activities."
              : "Choose a date to view that day's activities. "
                  'Previous days are view-only for Maker.',
          style: TextStyle(
            color: AppColors.white.withValues(alpha: 0.95),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            fontFamily: poppins,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: _historicPickerIndex,
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF555555)),
              borderRadius: BorderRadius.circular(8),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF555555),
                fontFamily: poppins,
              ),
              items: [
                DropdownMenuItem<int>(
                  value: -1,
                  child: Text(labels[0]),
                ),
                for (var o = 0; o < ordered.length; o++)
                  DropdownMenuItem<int>(
                    value: ordered[o],
                    child: Text(labels[o + 1]),
                  ),
              ],
              onChanged: _onHistoricPickerChanged,
            ),
          ),
        ),
      ],
    );
  }

  List<String> _dropdownItems(PmisTicketFieldValue f) {
    final map = _configMap(f);
    final keys = map.keys.map((k) => k.toString()).toList()..sort();
    return keys;
  }

  Future<void> _pickDate(int tfvId) async {
    if (!_canEditTicketFields) return;
    final now = DateTime.now();
    final initial = _tryParseDisplayDate(_textByTfv[tfvId]!.text) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) {
      setState(() {
        _textByTfv[tfvId]!.text = _formatDisplayDate(d);
      });
    }
  }

  String? _validateNumeric(PmisTicketFieldValue f, String? raw) {
    final req = f.isRequired == true;
    final v = raw?.trim() ?? '';
    if (req && v.isEmpty) return 'Required';
    if (v.isEmpty) return null;
    final n = num.tryParse(v);
    if (n == null) return 'Invalid number';
    final minRaw = f.minVal;
    final maxRaw = f.maxVal;
    final mn = minRaw == null ? null : num.tryParse(minRaw.toString());
    final mx = maxRaw == null ? null : num.tryParse(maxRaw.toString());

    // Backward-compat: older locally persisted payloads used 0 for null bounds.
    final treatBoundsAsUnset = (mn == 0) && (mx == 0);
    if (!treatBoundsAsUnset) {
      if (mn != null && n < mn) return 'Min $mn';
      if (mx != null && n > mx) return 'Max $mx';
    }
    return null;
  }

  Future<void> _captureGps(PmisTicketFieldValue f) async {
    if (!_canEditTicketFields) return;
    if (_capturingGpsTfvId != null) return;
    if (!mounted) return;
    setState(() => _capturingGpsTfvId = f.tfvId);
    LoaderWidget.showLoader(context);
    try {
      final loc = await LocationService.getCurrentLocationForForm();
      if (!mounted) return;
      if (_isCombinedCoordinatesField(f)) {
        _textByTfv[f.tfvId]!.text = loc.latitude.toStringAsFixed(6);
        _lngByTfv[f.tfvId] ??= TextEditingController();
        _lngByTfv[f.tfvId]!.text = loc.longitude.toStringAsFixed(6);
      } else {
        final isLng = _isLongitudeField(f);
        final v = isLng ? loc.longitude : loc.latitude;
        _textByTfv[f.tfvId]!.text = v.toStringAsFixed(6);
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        Toastbar.showErrorToastbar(e.toString(), context);
      }
    } finally {
      LoaderWidget.hideLoader();
      if (mounted) {
        setState(() => _capturingGpsTfvId = null);
      } else {
        _capturingGpsTfvId = null;
      }
    }
  }

  static const int _maxUploadBytes = 2 * 1024 * 1024;

  Future<String?> _uploadTicketFile(File file) async {
    final result = await _uploadService.uploadFile(
      file: file,
      id: '0',
      activityType: 'AT',
    );
    if (result.isSuccess && (result.data ?? '').trim().isNotEmpty) {
      return (result.data ?? '').trim();
    }
    // Offline fallback (same idea as Site Visit): keep media locally and use
    // LOCAL_IMAGE_ID_* in payload, then replace with server id on sync/submit.
    try {
      final localId = await ServiceLocator().imageUploadService.uploadImageFromFilePath(
            file.path,
            ActivityTypeEnum.activityTicket,
            false,
            widget.activityTicketId.toString(),
          );
      if (localId.contains('LOCAL_IMAGE_ID')) {
        return localId;
      }
    } catch (e) {
      Logger.errorLog('[ActivityTicket] local upload fallback failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> _buildAttachmentObject(
    String uploadedId,
    String fileType,
  ) async {
    double latitude = 0;
    double longitude = 0;
    try {
      final location = await LocationService.getCurrentLocation();
      latitude = location.latitude;
      longitude = location.longitude;
    } catch (_) {
      // Keep 0,0 when location isn't available.
    }

    return <String, dynamic>{
      'fileType': fileType,
      'latitude': latitude,
      'longitude': longitude,
      'geoAccuracyM': 0,
      'geoSource': 'MOBILE',
      'capturedDt': _nowForBackend(),
      // Backend FK: 0 is not a valid pmis_module_mst id; Swagger often omits this.
      'taggedMmId': null,
      'attachmentId': int.tryParse(uploadedId) ?? uploadedId,
      'isActive': true,
      'remarks': '',
      // Caller sets [taId] when replacing an existing field attachment row.
    };
  }

  Future<Map<String, dynamic>> _preparePayloadForPost(
    Map<String, dynamic> payload,
  ) async {
    final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );

    Future<void> resolveAttachmentList(dynamic list) async {
      if (list is! List) return;
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final rawId = _rawAttachmentIdFromMap(m)?.trim() ?? '';
        if (rawId.contains('LOCAL_IMAGE_ID')) {
          final sid = await ServiceLocator()
              .imageUploadService
              .getOrUploadPmisDocumentIdFromUniqueId(rawId);
          if (sid != null && sid.isNotEmpty) {
            m['attachmentId'] = int.tryParse(sid) ?? sid;
          }
        }
        list[i] = m;
      }
    }

    Future<void> resolveFieldList(dynamic list) async {
      if (list is! List) return;
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        if (e is! Map) continue;
        final f = Map<String, dynamic>.from(e);
        await resolveAttachmentList(f['attachments']);

        final valText = f['valText']?.toString() ?? '';
        if (valText.isNotEmpty) {
          final out = <String>[];
          for (final part in valText.split(',')) {
            final p = part.trim();
            if (p.isEmpty) continue;
            if (p.contains('LOCAL_IMAGE_ID')) {
              final sid = await ServiceLocator()
                  .imageUploadService
                  .getOrUploadPmisDocumentIdFromUniqueId(p);
              out.add((sid != null && sid.isNotEmpty) ? sid : p);
            } else {
              out.add(p);
            }
          }
          f['valText'] = out.join(',');
        }
        list[i] = f;
      }
    }

    await resolveFieldList(copy['ticketFieldValues']);
    final oldData = copy['oldData'];
    if (oldData is List) {
      for (final item in oldData) {
        if (item is! Map) continue;
        await resolveFieldList(item['ticketFieldValues']);
      }
    }
    await resolveAttachmentList(copy['ticketAttachments']);
    return copy;
  }

  Future<void> _savePendingActivityTicketSync(
    Map<String, dynamic> payload,
  ) async {
    final requestId = 'pmis_activity_ticket_${widget.activityTicketId}';
    final pendingPayload = Map<String, dynamic>.from(payload)
      ..['_localActivityTicketId'] = widget.activityTicketId;
    await ServiceLocator().pendingRequestService.savePendingRequest(
      requestId: requestId,
      url: 'pmis/api/v1/project-plan/activity-ticket',
      headers: const {},
      jsonEncodedRequestData: jsonEncode(<dynamic>[pendingPayload]),
    );
  }

  Future<void> _persistPayloadOfflineToSqlite(
    Map<String, dynamic> payload,
  ) async {
    final schId = widget.activityTicketId.toString();
    final dataService = ServiceLocator().centralAssetAuditDataService;
    final payloadForLocal = Map<String, dynamic>.from(payload)
      ..['_manualOfflineDownloaded'] = false;
    final existing = await dataService.getRawApiData(schId);
    if (existing != null) {
      await dataService.updateRawApiData(
        siteAuditSchId: schId,
        apiData: payloadForLocal,
      );
      return;
    }

    await dataService.saveRawApiData(
      siteAuditSchId: schId,
      siteType: 'Solar',
      auditSchId: '',
      pvTicketId: 'PMIS-${widget.activityTicketId}',
      siteCode: widget.activityName,
      cluster: widget.summaryCardTitle ?? widget.activityName,
      operator: '',
      raisedDt: '',
      dueDt: '',
      status: payload['currentStatus']?.toString() ?? widget.detail.currentStatus,
      activityType: ActivityTypeEnum.activityTicket,
      // Keep local snapshot available; icon now uses `_manualOfflineDownloaded`.
      isDownloaded: true,
      latitude: 0,
      longitude: 0,
      apiData: payloadForLocal,
    );
  }

  bool _fieldHasLocalOfflineAttachment(PmisTicketFieldValue f) {
    final attachments =
        _uploadedAttachmentsByTfv[f.tfvId] ?? const <Map<String, dynamic>>[];
    for (final a in attachments) {
      final id = _rawAttachmentIdFromMap(a) ?? '';
      if (id.contains('LOCAL_IMAGE_ID')) return true;
    }
    final valText = _valTextForField(f);
    for (final p in valText.split(',')) {
      if (p.trim().contains('LOCAL_IMAGE_ID')) return true;
    }
    return false;
  }

  Widget _offlineSavedIndicator(PmisTicketFieldValue f) {
    if (!_fieldHasLocalOfflineAttachment(f)) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Text(
        'Saved locally (offline)',
        style: TextStyle(
          color: Color(0xFFFFD54F),
          fontFamily: poppins,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Upload + build attachment map for image fields; shows loader and toasts.
  Future<Map<String, dynamic>?> _uploadImageFileWithChecks(File file) async {
    final len = await file.length();
    if (len > _maxUploadBytes) {
      if (mounted) {
        Toastbar.showErrorToastbar(
          '${p.basename(file.path)} exceeds 2 MB',
          context,
        );
      }
      return null;
    }
    if (!mounted) return null;
    LoaderWidget.showLoader(context);
    try {
      final uploadedId = await _uploadTicketFile(file);
      if (uploadedId == null) {
        if (mounted) {
          Toastbar.showErrorToastbar(
            'Failed to upload ${p.basename(file.path)}',
            context,
          );
        }
        return null;
      }
      return await _buildAttachmentObject(uploadedId, 'IMAGE');
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Future<void> _handleSingleImageSelection(
    PmisTicketFieldValue f,
    File? file,
  ) async {
    if (!_canEditTicketFields) return;
    final list = _filesByTfv[f.tfvId]!;
    final attachments =
        _uploadedAttachmentsByTfv[f.tfvId] ?? <Map<String, dynamic>>[];
    if (file == null) {
      setState(() {
        list.clear();
        attachments.clear();
        _uploadedAttachmentsByTfv[f.tfvId] = attachments;
        _markUploadReplaced(f.tfvId);
        _imageExternalDataByTfv[f.tfvId] = null;
        _imageLoadingFromServerTfvIds.remove(f.tfvId);
      });
      return;
    }
    // Reuse is irrelevant for POST (API is append-only); still tag the pick.
    final attachment = await _uploadImageFileWithChecks(file);
    if (attachment == null || !mounted) return;
    setState(() {
      list
        ..clear()
        ..add(file);
      attachments
        ..clear()
        ..add(attachment);
      _uploadedAttachmentsByTfv[f.tfvId] = attachments;
      _markUploadReplaced(f.tfvId);
      _imageExternalDataByTfv[f.tfvId] = file.path;
      _imageLoadingFromServerTfvIds.remove(f.tfvId);
    });
  }

  /// Upload widget for PDF / VIDEO / multi-IMAGE.
  /// Attachment rows always use the same tile list (local or server), whether
  /// [allowMultipleFiles] is true or false. The upload box stays empty for pick
  /// / replace; single-file mode still replaces on a new pick.
  Widget _buildTicketFileUpload({
    required PmisTicketFieldValue f,
    required String label,
    required bool req,
    required String fileTypeForAttachment,
    required String acceptedFileTypes,
    List<String>? pickAllowedExtensions,
    String? placeholder,
    bool useVideoPicker = false,
    bool useVideoRecorder = false,
    bool useImagePicker = false,
    bool useImageCamera = false,
  }) {
    final allowMultiple = _allowsMultipleFiles(f);
    final files = _filesByTfv[f.tfvId]!;
    final attachments =
        _uploadedAttachmentsByTfv[f.tfvId] ?? <Map<String, dynamic>>[];
    final isVideo = fileTypeForAttachment == 'VIDEO';

    final uploadWidget = CustomFileUploadNew(
      key: ValueKey<Object>(
        'at_file_${f.tfvId}_$fileTypeForAttachment'
        '_${attachments.length}_multi_$allowMultiple',
      ),
      label: label,
      placeholder: placeholder ??
          (allowMultiple ? 'Add file' : 'Upload a File'),
      isRequired: req && _canEditTicketFields,
      isDisabled: !_canEditTicketFields,
      acceptedFileTypes: acceptedFileTypes,
      maxSizeText: '(Max Size: 2MB)',
      pickAllowedExtensions: pickAllowedExtensions,
      useVideoPicker: useVideoPicker,
      useVideoRecorder: useVideoRecorder,
      useImagePicker: useImagePicker,
      useImageCamera: useImageCamera,
      allowMultipleFiles: allowMultiple,
      // Always keep the box clear — tiles below list every attachment.
      selectedFile: null,
      uploadedFiles: const [],
      serverAttachmentName: null,
      serverAttachmentId: null,
      onFileSelected: (file) async {
        if (!_canEditTicketFields) return;
        final liveAttachments =
            _uploadedAttachmentsByTfv[f.tfvId] ?? <Map<String, dynamic>>[];
        if (file == null) {
          setState(() {
            files.clear();
            liveAttachments.clear();
            _uploadedAttachmentsByTfv[f.tfvId] = liveAttachments;
            _markUploadReplaced(f.tfvId);
            if (fileTypeForAttachment == 'IMAGE') {
              _imageExternalDataByTfv[f.tfvId] = null;
            }
          });
          return;
        }

        final len = await file.length();
        if (len > _maxUploadBytes) {
          if (!mounted) return;
          Toastbar.showErrorToastbar(
            '${p.basename(file.path)} exceeds 2 MB',
            context,
          );
          return;
        }

        if (!mounted) return;
        setState(() {
          if (allowMultiple) {
            files.add(file);
          } else {
            files
              ..clear()
              ..add(file);
          }
        });

        LoaderWidget.showLoader(context);
        try {
          final uploadedId = await _uploadTicketFile(file);
          if (uploadedId == null) {
            if (!mounted) return;
            Toastbar.showErrorToastbar(
              'Failed to upload ${p.basename(file.path)}',
              context,
            );
            setState(() {
              files.remove(file);
              if (!allowMultiple) {
                liveAttachments.clear();
                _uploadedAttachmentsByTfv[f.tfvId] = liveAttachments;
              }
            });
            return;
          }
          final attachment = await _buildAttachmentObject(
            uploadedId,
            fileTypeForAttachment,
          );
          attachment['_localPath'] = file.path;
          if (!mounted) return;
          setState(() {
            if (allowMultiple) {
              liveAttachments.add(attachment);
            } else {
              liveAttachments
                ..clear()
                ..add(attachment);
            }
            _uploadedAttachmentsByTfv[f.tfvId] = liveAttachments;
            _markUploadReplaced(f.tfvId);
            if (fileTypeForAttachment == 'IMAGE') {
              _imageExternalDataByTfv[f.tfvId] = file.path;
            }
          });
        } finally {
          LoaderWidget.hideLoader();
        }
      },
      onFileDeleted: (_) {},
    );

    final rows = <Widget>[];
    final seenIds = <String>{};
    final isImage = fileTypeForAttachment == 'IMAGE';

    for (final a in attachments) {
      if (a['isActive'] == false) continue;

      final localPath = a['_localPath']?.toString();
      if (localPath != null && localPath.isNotEmpty) {
        rows.add(
          _buildAttachmentTile(
            isVideo: isVideo,
            isImage: isImage,
            title: p.basename(localPath),
            onOpen: () async {
              if (isVideo) {
                await _playLocalVideoFile(File(localPath));
              } else if (isImage) {
                await _previewLocalImageFile(File(localPath));
              } else {
                await OpenFile.open(localPath);
              }
            },
            onDelete: () {
              setState(() {
                files.removeWhere((e) => e.path == localPath);
                final live = _uploadedAttachmentsByTfv[f.tfvId] ??
                    <Map<String, dynamic>>[];
                live.removeWhere(
                  (e) => e['_localPath']?.toString() == localPath,
                );
                _uploadedAttachmentsByTfv[f.tfvId] = live;
                _markUploadReplaced(f.tfvId);
                if (fileTypeForAttachment == 'IMAGE') {
                  _imageExternalDataByTfv[f.tfvId] = null;
                }
              });
            },
          ),
        );
        continue;
      }

      final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
      if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
      if (!seenIds.add(id)) continue;
      rows.add(
        _buildAttachmentTile(
          isVideo: isVideo,
          isImage: isImage,
          title: _serverAttachmentLabel(f, a, id),
          onOpen: () => _openServerAttachmentFromDocument(
            int.tryParse(id) ?? id,
            f,
          ),
          onDelete: () {
            setState(() {
              final live = _uploadedAttachmentsByTfv[f.tfvId] ??
                  <Map<String, dynamic>>[];
              live.removeWhere(
                (e) => (_rawAttachmentIdFromMap(e) ?? '').trim() == id,
              );
              _uploadedAttachmentsByTfv[f.tfvId] = live;
              _markUploadReplaced(f.tfvId);
              if (fileTypeForAttachment == 'IMAGE') {
                _imageExternalDataByTfv[f.tfvId] = null;
              }
            });
          },
        ),
      );
    }

    if (rows.isEmpty) return uploadWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        uploadWidget,
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  /// Shared white tile used for every video / PDF / multi-image attachment.
  Widget _buildAttachmentTile({
    required bool isVideo,
    bool isImage = false,
    required String title,
    required VoidCallback? onOpen,
    required VoidCallback onDelete,
  }) {
    final IconData leadingIcon;
    if (isVideo) {
      leadingIcon = Icons.play_circle_outline;
    } else if (isImage) {
      leadingIcon = Icons.image_outlined;
    } else {
      leadingIcon = Icons.attach_file;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          leading: Icon(
            leadingIcon,
            color: AppColors.color555555,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: onOpen != null
                  ? AppColors.textBlueAccent
                  : AppColors.color555555,
              decoration:
                  onOpen != null ? TextDecoration.underline : TextDecoration.none,
              fontFamily: fontFamilyMontserrat,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _canEditTicketFields
              ? IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  onPressed: onDelete,
                )
              : null,
          onTap: onOpen,
        ),
      ),
    );
  }

  /// Backward-compatible alias used by older call sites.
  Widget _buildSingleTicketFileUpload({
    required PmisTicketFieldValue f,
    required String label,
    required bool req,
    required String fileTypeForAttachment,
    required String acceptedFileTypes,
    List<String>? pickAllowedExtensions,
    String? placeholder,
    bool useVideoPicker = false,
    bool useVideoRecorder = false,
    bool useImagePicker = false,
    bool useImageCamera = false,
  }) {
    return _buildTicketFileUpload(
      f: f,
      label: label,
      req: req,
      fileTypeForAttachment: fileTypeForAttachment,
      acceptedFileTypes: acceptedFileTypes,
      pickAllowedExtensions: pickAllowedExtensions,
      placeholder: placeholder,
      useVideoPicker: useVideoPicker,
      useVideoRecorder: useVideoRecorder,
      useImagePicker: useImagePicker,
      useImageCamera: useImageCamera,
    );
  }

  String _valTextForField(PmisTicketFieldValue f) {
    final type = _normDataType(f);
    if (type == 'DROPDOWN') {
      return (_dropdownByTfv[f.tfvId] ?? '').trim();
    }
    if (_isCombinedCoordinatesField(f)) {
      final lat = (_textByTfv[f.tfvId]?.text ?? '').trim();
      final lng = (_lngByTfv[f.tfvId]?.text ?? '').trim();
      if (lat.isEmpty && lng.isEmpty) return '';
      return '$lat, $lng';
    }
    if (_isUploadType(type)) {
      // Unchanged upload: keep every known id (valText ∪ attachments).
      if (!_isUploadReplacedForField(f.tfvId)) {
        if (_isSingleFileUploadField(f)) {
          final apiPrimary = _normalizedLiveAttachmentsForField(
            f,
            source: f.attachments,
          );
          if (apiPrimary.isNotEmpty) {
            return (_rawAttachmentIdFromMap(apiPrimary.first) ?? '').trim();
          }
          final parts = _idsFromValText(f);
          return parts.isEmpty ? '' : parts.last;
        }
        final ids = <String>[];
        final seen = <String>{};
        for (final id in _idsFromValText(f)) {
          if (seen.add(id)) ids.add(id);
        }
        final hydrated = _hydrateAttachmentsForField(f);
        for (final a in hydrated) {
          final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
          if (id.isEmpty || id == '0' || !seen.add(id)) continue;
          ids.add(id);
        }
        return ids.join(',');
      }

      final attachments = _normalizedLiveAttachmentsForField(f);
      if (attachments.isEmpty) return '';
      final ids = <String>[];
      final seen = <String>{};
      for (final a in attachments) {
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        if (id.isEmpty || id == '0' || !seen.add(id)) continue;
        ids.add(id);
      }
      if (_isSingleFileUploadField(f) && ids.length > 1) {
        return ids.last;
      }
      return ids.join(',');
    }
    return _textByTfv[f.tfvId]!.text.trim();
  }

  String _formatBackendDate(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  String _nowForBackend() => _formatBackendDate(DateTime.now());

  String? _normalizeDateString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return raw;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw;
    return _formatBackendDate(parsed);
  }

  bool _isTicketFieldModified(
    PmisTicketFieldValue original, {
    required String updatedValText,
    required List<Map<String, dynamic>> updatedAttachments,
    int? historicIndex,
  }) {
    final type = _normDataType(original);
    if (_isUploadType(type)) {
      // Image/PDF/VIDEO: modified ONLY if the user picked/cleared a file this
      // session. Resending the same attachment object makes the API insert a
      // duplicate taId on every plain Submit.
      return _isUploadReplacedForField(
        original.tfvId,
        historicIndex: historicIndex,
      );
    }
    final oldVal = (original.valText?.toString() ?? '').trim();
    return oldVal != updatedValText.trim();
  }

  Map<String, dynamic> _mapChecker(PmisTicketChecker c) {
    return <String, dynamic>{
      'tcId': c.tcId,
      'levelNo': c.levelNo,
      'designationMstId': c.designationMstId ?? 0,
      'checkerUserMstId': c.checkerUserMstId ?? 0,
      'decisionStatus': c.decisionStatus ?? '',
      'decisionBy': c.decisionBy ?? '',
      'decisionDt': _normalizeDateString(c.decisionDt),
      'decisionRemarks': c.decisionRemarks ?? '',
      'latitude': c.latitude ?? '0',
      'longitude': c.longitude ?? '0',
      'geoAccuracyM': c.geoAccuracyM ?? '0',
      'geoSource': c.geoSource ?? '',
      'isActive': c.isActive,
      'remarks': c.remarks ?? '',
      'decisionByName': c.decisionByName ?? '',
      'checkerUserName': c.checkerUserName ?? '',
      'designationName': c.designationName ?? '',
    };
  }

  List<Map<String, dynamic>> _mapTicketCheckersForPost({
    ActivityTicketCheckerClosePopupResult? checkerClose,
    double? checkerLatitude,
    double? checkerLongitude,
  }) {
    if (checkerClose == null || widget.detail.ticketCheckers.isEmpty) {
      return widget.detail.ticketCheckers.map(_mapChecker).toList();
    }

    final checkerLevel = int.tryParse((widget.detail.checkerLvl ?? '').trim());
    var targetIdx = -1;
    if (checkerLevel != null) {
      for (var i = 0; i < widget.detail.ticketCheckers.length; i++) {
        if (widget.detail.ticketCheckers[i].levelNo == checkerLevel) {
          targetIdx = i;
          break;
        }
      }
    }
    if (targetIdx < 0) targetIdx = 0;

    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.detail.ticketCheckers.length; i++) {
      final c = widget.detail.ticketCheckers[i];
      final mapped = _mapChecker(c);
      if (i == targetIdx) {
        mapped['remarks'] = checkerClose.remarks;
        mapped['isModified'] = true;
        if (checkerLatitude != null && checkerLongitude != null) {
          mapped['latitude'] = checkerLatitude;
          mapped['longitude'] = checkerLongitude;
          mapped['geoSource'] = 'MOBILE';
        }
        if (checkerClose.action == ActivityTicketCheckerAction.saveAndApprove) {
          mapped['decisionStatus'] = 'Approved';
          mapped['decisionRemarks'] = 'Approved';
        } else if (checkerClose.action == ActivityTicketCheckerAction.reject) {
          mapped['decisionStatus'] = 'Rejected';
          mapped['decisionRemarks'] = 'Rejected';
        }
      }
      out.add(mapped);
    }
    return out;
  }

  Map<String, dynamic> _mapFieldValue(
    PmisTicketFieldValue f, {
    required String valText,
    required List<Map<String, dynamic>> attachments,
    required bool isModified,
  }) {
    var latitude = f.latitude ?? '0';
    var longitude = f.longitude ?? '0';
    if (_isCombinedCoordinatesField(f)) {
      final parts = valText
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) latitude = parts[0];
      if (parts.length >= 2) longitude = parts[1];
    }

    return <String, dynamic>{
      'tfvId': f.tfvId,
      'valText': valText,
      'valNumeric': f.valNumeric,
      'valInt': f.valInt,
      'valDate': _normalizeDateString(f.valDate?.toString()),
      'valJson': f.valJson,
      'latitude': latitude,
      'longitude': longitude,
      'geoAccuracyM': f.geoAccuracyM ?? '0',
      'geoSource': f.geoSource ?? '',
      'isActive': f.isActive,
      'remarks': f.remarks ?? '',
      'attachments': attachments.map(_normalizeAttachmentDate).toList(),
      'subActivityName': f.subActivityName ?? '',
      'subActivityDataType': f.subActivityDataType ?? '',
      'subActivityControlType': f.subActivityControlType ?? '',
      'isRequired': f.isRequired ?? false,
      'seqNo': f.seqNo ?? 0,
      // Preserve nullable bounds. Null means "no min/max validation".
      'minVal': f.minVal,
      'maxVal': f.maxVal,
      'configJson': _configMap(f),
      'linkMmId': f.linkMmId ?? 0,
      'isModified': isModified,
    };
  }

  List<Map<String, dynamic>> _attachmentsForUploadFieldPost(
    PmisTicketFieldValue f,
    String valText,
  ) {
    final type = _normDataType(f);
    if (!_isUploadType(type)) {
      return f.attachments.map((m) => Map<String, dynamic>.from(m)).toList();
    }

    // No new file this session → echo existing rows (not []). Some backends
    // replace the attachments collection whenever the ticket is posted, so an
    // empty array would wipe previously uploaded videos/PDFs/images.
    if (!_isUploadReplacedForField(f.tfvId)) {
      final live = _uploadedAttachmentsByTfv[f.tfvId];
      final source = (live != null && live.isNotEmpty)
          ? live
          : _hydrateAttachmentsForField(f, source: f.attachments);
      final out = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final a in source) {
        if (a['isActive'] == false) continue;
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
        if (!seen.add(id)) continue;
        final copy = Map<String, dynamic>.from(a);
        copy.remove('_localPath');
        // Explicitly not a mutation — avoids duplicate inserts on plain submit.
        copy['isModified'] = false;
        out.add(copy);
      }
      return out;
    }

    var ids = valText
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '0')
        .toList();
    final seenIds = <String>{};
    ids = [
      for (final id in ids)
        if (seenIds.add(id)) id,
    ];
    if (_isSingleFileUploadField(f) && ids.length > 1) {
      ids = [ids.last];
    }

    // ---- Multi-file: keep remaining, insert new, soft-delete removed ----
    if (!_isSingleFileUploadField(f)) {
      final out = <Map<String, dynamic>>[];
      final currentIdSet = ids.toSet();
      final alreadyOnServer = <String>{..._idsFromValText(f)};
      for (final a in f.attachments) {
        if (a['isActive'] == false) continue;
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        if (id.isEmpty || id == '0') continue;
        alreadyOnServer.add(id);
      }

      // Soft-delete originals that the user removed.
      final seenTa = <int>{};
      for (final a in f.attachments) {
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        final t = _taIdFromMap(a);
        if (t <= 0 || !seenTa.add(t)) continue;
        if (id.isNotEmpty && currentIdSet.contains(id)) continue;
        final stale = Map<String, dynamic>.from(a);
        stale['isActive'] = false;
        stale['isModified'] = true;
        out.add(stale);
      }

      final live = _normalizedLiveAttachmentsForField(f);
      final liveById = <String, Map<String, dynamic>>{};
      for (final a in live) {
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        if (id.isEmpty || id == '0') continue;
        liveById[id] = Map<String, dynamic>.from(a);
      }

      for (final id in ids) {
        if (alreadyOnServer.contains(id)) {
          // Already stored on the ticket — do not resend (avoids duplicate insert).
          continue;
        }
        final liveRow = liveById[id];
        final row = liveRow ??
            <String, dynamic>{
              'fileType': type,
              'latitude': 0,
              'longitude': 0,
              'geoAccuracyM': 0,
              'geoSource': 'MOBILE',
              'capturedDt': _nowForBackend(),
              'taggedMmId': null,
              'attachmentId': int.tryParse(id) ?? id,
              'isActive': true,
              'remarks': '',
            };
        row['attachmentId'] = int.tryParse(id) ?? id;
        row['fileType'] = row['fileType'] ?? type;
        row['isActive'] = true;
        row['isModified'] = true;
        row['capturedDt'] = _nowForBackend();
        row.remove('taId'); // new insert
        row.remove('_localPath');
        out.add(row);
      }
      return out;
    }

    // ---- Single-file replace (existing behavior) ----
    final keepTaId = _canonicalTaIdForField(f);
    final out = <Map<String, dynamic>>[];
    final seenTa = <int>{};

    // Soft-delete every existing row except the canonical taId we will update.
    for (final a in f.attachments) {
      final t = _taIdFromMap(a);
      if (t <= 0 || !seenTa.add(t)) continue;
      if (keepTaId > 0 && t == keepTaId) continue;
      final stale = Map<String, dynamic>.from(a);
      stale['isActive'] = false;
      stale['isModified'] = true;
      out.add(stale);
    }

    if (ids.isEmpty) {
      // Cleared — also deactivate the canonical row.
      if (keepTaId > 0) {
        Map<String, dynamic>? keepRow;
        for (final a in f.attachments) {
          if (_taIdFromMap(a) == keepTaId) {
            keepRow = Map<String, dynamic>.from(a);
            break;
          }
        }
        if (keepRow != null) {
          keepRow['isActive'] = false;
          keepRow['isModified'] = true;
          out.add(keepRow);
        }
      }
      return out;
    }

    final id = ids.last;
    final live = _normalizedLiveAttachmentsForField(f);
    final liveRow =
        live.isNotEmpty ? Map<String, dynamic>.from(live.first) : null;

    Map<String, dynamic>? canonicalRow;
    for (final a in f.attachments) {
      if (_taIdFromMap(a) == keepTaId) {
        canonicalRow = Map<String, dynamic>.from(a);
        break;
      }
    }

    final row = liveRow ??
        canonicalRow ??
        <String, dynamic>{
          'fileType': type,
          'latitude': 0,
          'longitude': 0,
          'geoAccuracyM': 0,
          'geoSource': 'MOBILE',
          'capturedDt': _nowForBackend(),
          'taggedMmId': null,
          'attachmentId': int.tryParse(id) ?? id,
          'isActive': true,
          'remarks': '',
        };
    row['attachmentId'] = int.tryParse(id) ?? id;
    row['fileType'] = row['fileType'] ?? type;
    row['isActive'] = true;
    row['isModified'] = true;
    row['capturedDt'] = _nowForBackend();
    // UPDATE the oldest/canonical taId in place — do not omit taId (that inserts).
    if (keepTaId > 0) {
      row['taId'] = keepTaId;
    } else {
      row.remove('taId');
    }
    out.add(row);
    return out;
  }

  /// Oldest non-zero [taId] for this field — stable row to UPDATE on replace.
  int _canonicalTaIdForField(PmisTicketFieldValue f) {
    var best = 0;
    void consider(Iterable<Map<String, dynamic>> rows) {
      for (final a in rows) {
        if (a['isActive'] == false) continue;
        final t = _taIdFromMap(a);
        if (t <= 0) continue;
        if (best == 0 || t < best) best = t;
      }
    }

    consider(f.attachments);
    final live = _uploadedAttachmentsByTfv[f.tfvId];
    if (live != null) consider(live);
    return best;
  }

  /// Current ticket field that corresponds to an historic [oldField].
  PmisTicketFieldValue? _matchCurrentFieldForOld(PmisTicketFieldValue oldField) {
    for (final current in widget.detail.ticketFieldValues) {
      if (_matchOldFieldToCurrent(current, [oldField]) != null) {
        return current;
      }
    }
    return null;
  }

  String _valTextFromSnapshot(PmisTicketFieldValue f, _AtFieldSnapshot s) {
    final type = _normDataType(f);
    if (type == 'DROPDOWN') {
      return (s.dropdownByTfv[f.tfvId] ?? '').trim();
    }
    if (_isCombinedCoordinatesField(f)) {
      final lat = (s.textByTfv[f.tfvId] ?? '').trim();
      final lng = (s.lngByTfv[f.tfvId] ?? '').trim();
      if (lat.isEmpty && lng.isEmpty) return '';
      return '$lat, $lng';
    }
    if (_isUploadType(type)) {
      final attachments = s.uploadedAttachmentsByTfv[f.tfvId] ?? const [];
      if (attachments.isEmpty) return '';
      final ids = <String>[];
      final seen = <String>{};
      for (final a in attachments) {
        final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
        if (id.isEmpty || id == '0' || !seen.add(id)) continue;
        ids.add(id);
      }
      if (_isSingleFileUploadField(f) && ids.length > 1) return ids.last;
      return ids.join(',');
    }
    return (s.textByTfv[f.tfvId] ?? '').trim();
  }

  List<Map<String, dynamic>> _attachmentsFromSnapshot(
    PmisTicketFieldValue f,
    _AtFieldSnapshot s, {
    required bool replaced,
  }) {
    if (!_isUploadType(_normDataType(f))) {
      return f.attachments.map((m) => Map<String, dynamic>.from(m)).toList();
    }
    final live = s.uploadedAttachmentsByTfv[f.tfvId];
    final source = (live != null && live.isNotEmpty)
        ? live
        : _hydrateAttachmentsForField(f, source: f.attachments);
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final a in source) {
      if (a['isActive'] == false) continue;
      final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
      if (id.isEmpty || id == '0' || id.toLowerCase() == 'null') continue;
      if (!seen.add(id)) continue;
      final copy = Map<String, dynamic>.from(a);
      copy.remove('_localPath');
      copy['isModified'] = replaced;
      if (replaced) {
        copy.remove('taId');
        copy['capturedDt'] = _nowForBackend();
      }
      out.add(copy);
    }
    return out;
  }

  Map<String, dynamic> _mapOldData(
    PmisOldDataItem item, {
    _AtFieldSnapshot? edits,
    Set<int> uploadReplacedCurrentTfvIds = const <int>{},
  }) {
    var anyModified = item.isModified ?? false;
    final mappedFields = <Map<String, dynamic>>[];

    for (final oldField in item.ticketFieldValues) {
      final current = _matchCurrentFieldForOld(oldField);
      var valText = oldField.valText?.toString() ?? '';
      var attachments = oldField.attachments
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      var isModified = false;

      if (edits != null && current != null) {
        final type = _normDataType(current);
        if (_isUploadType(type)) {
          final replaced =
              uploadReplacedCurrentTfvIds.contains(current.tfvId);
          if (replaced) {
            valText = _valTextFromSnapshot(current, edits);
            attachments = _attachmentsFromSnapshot(
              current,
              edits,
              replaced: true,
            );
            // Keep old field identity (tfvId) on the historic row.
            for (final a in attachments) {
              a['fileType'] = a['fileType'] ?? type;
            }
            isModified = true;
          }
        } else {
          final next = _valTextFromSnapshot(current, edits);
          if (next.trim() != valText.trim()) {
            valText = next;
            isModified = true;
          }
        }
      }

      anyModified = anyModified || isModified;
      mappedFields.add(
        _mapFieldValue(
          oldField,
          valText: valText,
          attachments: attachments,
          isModified: isModified,
        ),
      );
    }

    return <String, dynamic>{
      'actualStartDt': _normalizeDateString(item.actualStartDt),
      'actualEndDt': _normalizeDateString(item.actualEndDt),
      'ticketFieldValues': mappedFields,
      'makerUserName': item.makerUserName ?? '',
      'isModified': anyModified,
    };
  }

  Map<String, dynamic> _buildPostPayload(
    ActivityTicketClosePopupResult close, {
    ActivityTicketCheckerClosePopupResult? checkerClose,
    double? checkerLatitude,
    double? checkerLongitude,
  }) {
    // Persist in-progress historic edits before reading them for POST.
    if (_historicPickerIndex >= 0 && _isCheckerRole) {
      _historicEditsByIndex[_historicPickerIndex] = _captureFieldSnapshot();
    }

    final viewingHistoric = _historicPickerIndex >= 0;
    final currentDraft =
        viewingHistoric ? _draftWhenLeavingCurrent : null;

    final updatedValTextByTfv = <int, String>{};
    final updatedAttachmentsByTfv = <int, List<Map<String, dynamic>>>{};
    final modifiedFieldIds = <int>{};

    for (final f in widget.detail.ticketFieldValues) {
      late final String valText;
      late final List<Map<String, dynamic>> attachments;

      if (viewingHistoric) {
        // Current-day payload must come from the stashed today draft, not the
        // historic overlay currently on screen.
        if (currentDraft != null) {
          final replaced = _uploadReplacedTfvIds.contains(f.tfvId);
          if (_isUploadType(_normDataType(f))) {
            valText = replaced
                ? _valTextFromSnapshot(f, currentDraft)
                : () {
                    final hydrated = _hydrateAttachmentsForField(
                      f,
                      source: f.attachments,
                    );
                    if (_isSingleFileUploadField(f)) {
                      if (hydrated.isNotEmpty) {
                        return (_rawAttachmentIdFromMap(hydrated.first) ?? '')
                            .trim();
                      }
                      final parts = _idsFromValText(f);
                      return parts.isEmpty ? '' : parts.last;
                    }
                    final ids = <String>[];
                    final seen = <String>{};
                    for (final id in _idsFromValText(f)) {
                      if (seen.add(id)) ids.add(id);
                    }
                    for (final a in hydrated) {
                      final id = (_rawAttachmentIdFromMap(a) ?? '').trim();
                      if (id.isEmpty || id == '0' || !seen.add(id)) continue;
                      ids.add(id);
                    }
                    return ids.join(',');
                  }();
            attachments = replaced
                ? _attachmentsFromSnapshot(f, currentDraft, replaced: true)
                : _hydrateAttachmentsForField(f, source: f.attachments)
                    .map((a) {
                      final copy = Map<String, dynamic>.from(a);
                      copy.remove('_localPath');
                      copy['isModified'] = false;
                      return copy;
                    })
                    .toList();
          } else {
            valText = _valTextFromSnapshot(f, currentDraft);
            attachments =
                f.attachments.map((m) => Map<String, dynamic>.from(m)).toList();
          }
        } else {
          valText = f.valText?.toString() ?? '';
          attachments =
              f.attachments.map((m) => Map<String, dynamic>.from(m)).toList();
        }
      } else {
        valText = _valTextForField(f);
        attachments = _attachmentsForUploadFieldPost(f, valText);
      }

      updatedValTextByTfv[f.tfvId] = valText;
      updatedAttachmentsByTfv[f.tfvId] = attachments;
      if (_isTicketFieldModified(
        f,
        updatedValText: valText,
        updatedAttachments: attachments,
        historicIndex: -1,
      )) {
        modifiedFieldIds.add(f.tfvId);
      }
    }
    final isAllocatedToWipTransition =
        widget.detail.currentStatus.trim().toUpperCase() == 'ALLOCATED' &&
            close.currentStatus.trim().toUpperCase() == 'WIP';
    final actualStartDt = isAllocatedToWipTransition &&
            (widget.detail.actualStartDt?.trim().isEmpty ?? true)
        ? _nowForBackend()
        : _normalizeDateString(widget.detail.actualStartDt);
    final isCheckerSubmission = checkerClose != null && _isCheckerRole;
    final payloadCurrentStatus = isCheckerSubmission
        ? widget.detail.currentStatus
        : close.currentStatus;
    final payloadCurrentStatusId = isCheckerSubmission
        ? widget.detail.currentStatusCode
        : close.currentStatusId;

    // `currentStatusCode` must be the API string (e.g. "WIP"), not psmId.
    // `currentStatusId` remains the numeric psmId from allowedStatuses.
    String? resolvedStatusCodeString = isCheckerSubmission
        ? null
        : (close.currentStatusCode.trim().isNotEmpty
            ? close.currentStatusCode.trim()
            : null);
    int? resolvedStatusNumeric = payloadCurrentStatusId;

    final targetStatusText = isCheckerSubmission
        ? widget.detail.currentStatus
        : close.currentStatus;
    final normalizedTarget =
        normalizeActivityTicketCloseStatusForCompare(targetStatusText);
    for (final status in widget.detail.allowedStatuses) {
      final nameNorm =
          normalizeActivityTicketCloseStatusForCompare(status.statusName);
      final codeNorm =
          normalizeActivityTicketCloseStatusForCompare(status.statusCode);
      final matchesText =
          normalizedTarget == nameNorm || normalizedTarget == codeNorm;
      final matchesId = resolvedStatusNumeric != null &&
          status.psmId != null &&
          status.psmId == resolvedStatusNumeric;
      if (!matchesText && !matchesId) continue;

      resolvedStatusNumeric ??= status.psmId;
      if (resolvedStatusCodeString == null ||
          resolvedStatusCodeString.isEmpty) {
        resolvedStatusCodeString = status.statusCode.trim();
      }
      break;
    }

    final payloadCurrentStatusNumeric = resolvedStatusNumeric ?? 0;
    final payloadCurrentStatusCodeString =
        (resolvedStatusCodeString != null &&
                resolvedStatusCodeString.isNotEmpty)
            ? resolvedStatusCodeString
            : (isCheckerSubmission
                ? widget.detail.currentStatus
                : close.currentStatusCode);
    final payloadParentRemarks = isCheckerSubmission
        ? (widget.detail.remarks ?? '')
        : close.remarks;
    final selectedStatusNormalized = normalizeActivityTicketCloseStatusForCompare(
      isCheckerSubmission ? widget.detail.currentStatus : close.currentStatus,
    );
    final actualEndDt = !isCheckerSubmission && selectedStatusNormalized == 'completed'
        ? _nowForBackend()
        : _normalizeDateString(widget.detail.actualEndDt);

    return <String, dynamic>{
      'atId': widget.activityTicketId,
      'ppaId': widget.detail.ppaId,
      'currentStatus': payloadCurrentStatus,
      'currentStatusCode': payloadCurrentStatusCodeString,
      'currentStatusId': payloadCurrentStatusNumeric,
      'currentStatusDt': _nowForBackend(),
      'makerDesignationMstId': widget.detail.makerDesignationMstId ?? 0,
      'makerUserMstId': widget.detail.makerUserMstId ?? 0,
      'makerAssignedDt': _normalizeDateString(widget.detail.makerAssignedDt),
      'plannedStartDt': _normalizeDateString(widget.detail.plannedStartDt),
      'plannedEndDt': _normalizeDateString(widget.detail.plannedEndDt),
      'actualStartDt': actualStartDt,
      'actualEndDt': actualEndDt,
      'isActive': widget.detail.isActive,
      'remarks': payloadParentRemarks,
      'ticketCheckers': _mapTicketCheckersForPost(
        checkerClose: checkerClose,
        checkerLatitude: checkerLatitude,
        checkerLongitude: checkerLongitude,
      ),
      'ticketFieldValues': widget.detail.ticketFieldValues.map((f) {
        final valText = updatedValTextByTfv[f.tfvId] ?? '';
        final updatedAttachments =
            updatedAttachmentsByTfv[f.tfvId] ?? const <Map<String, dynamic>>[];
        return _mapFieldValue(
          f,
          valText: valText,
          attachments: updatedAttachments,
          isModified: modifiedFieldIds.contains(f.tfvId),
        );
      }).toList(),
      'ticketAttachments': widget.detail.ticketAttachments
          .map((a) => _normalizeAttachmentDate(Map<String, dynamic>.from(a.raw)))
          .toList(),
      'makerUserName': widget.detail.makerUserName ?? '',
      'makerDesignationName': widget.detail.makerDesignationName ?? '',
      'oldData': [
        for (var i = 0; i < widget.detail.oldData.length; i++)
          _mapOldData(
            widget.detail.oldData[i],
            edits: _historicEditsByIndex[i],
            uploadReplacedCurrentTfvIds:
                _historicUploadReplacedByOldIndex[i] ?? const <int>{},
          ),
      ],
      'showReviewBtns': widget.detail.showReviewBtns,
      'checkerLvl': widget.detail.checkerLvl ?? '',
      'role': _normalizedRole,
      'ticketStatusHistory': widget.detail.ticketStatusHistory.map((e) {
        final mapped = Map<String, dynamic>.from(e);
        mapped['changedDt'] = _normalizeDateString(
          mapped['changedDt']?.toString(),
        );
        return mapped;
      }).toList(),
      'allowedStatuses': widget.detail.allowedStatuses
          .map((e) => e.toJson())
          .toList(),
      // Close dialog: currentStatus, repeatDt, remarks, isRepeatNature (see ActivityTicketClosePopupResult).
      'isRepeatNature': close.isRepeatNature,
      'isRepeating': close.isRepeatNature,
      'repeatDt': close.repeatDt,
    };
  }

  Map<String, dynamic> _normalizeAttachmentDate(Map<String, dynamic> attachment) {
    final normalized = Map<String, dynamic>.from(attachment);
    normalized.remove('_localPath');
    normalized['capturedDt'] = _normalizeDateString(
      normalized['capturedDt']?.toString(),
    );
    final taggedRaw = normalized['taggedMmId'];
    final tagged =
        taggedRaw == null ? null : int.tryParse(taggedRaw.toString());
    if (tagged == null || tagged == 0) {
      normalized['taggedMmId'] = null;
    }
    return normalized;
  }

  bool _validateAll() {
    for (final f in _sortedFields) {
      final type = _normDataType(f);
      final req = f.isRequired == true;

      if (type == 'NUMERIC') {
        final err = _validateNumeric(f, _textByTfv[f.tfvId]!.text);
        if (err != null) {
          Toastbar.showErrorToastbar(
            '${f.subActivityName}: $err',
            context,
          );
          return false;
        }
        continue;
      }

      if (type == 'TEXT' || type == 'DATE') {
        if (req && _textByTfv[f.tfvId]!.text.trim().isEmpty) {
          Toastbar.showErrorToastbar(
            '${f.subActivityName} is required',
            context,
          );
          return false;
        }
      }

      if (type == 'COORDINATES') {
        if (_isCombinedCoordinatesField(f)) {
          final lat = (_textByTfv[f.tfvId]?.text ?? '').trim();
          final lng = (_lngByTfv[f.tfvId]?.text ?? '').trim();
          if (req && (lat.isEmpty || lng.isEmpty)) {
            Toastbar.showErrorToastbar(
              '${f.subActivityName}: Latitude and Longitude are required',
              context,
            );
            return false;
          }
        } else if (req && _textByTfv[f.tfvId]!.text.trim().isEmpty) {
          Toastbar.showErrorToastbar(
            '${f.subActivityName} is required',
            context,
          );
          return false;
        }
      }

      if (type == 'DROPDOWN' && req) {
        final v = (_dropdownByTfv[f.tfvId] ?? '').trim();
        if (v.isEmpty) {
          Toastbar.showErrorToastbar(
            '${f.subActivityName} is required',
            context,
          );
          return false;
        }
      }

      if (_isUploadType(type) && req) {
        final files = _filesByTfv[f.tfvId];
        final hasPickedLocal = files != null && files.isNotEmpty;
        final hasExistingAttachmentIds = _valTextForField(f).trim().isNotEmpty;
        if (!hasPickedLocal && !hasExistingAttachmentIds) {
          Toastbar.showErrorToastbar(
            '${f.subActivityName} is required',
            context,
          );
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();
    ActivityTicketClosePopupResult? close;
    ActivityTicketCheckerClosePopupResult? checkerCloseResult;
    double? checkerLatitude;
    double? checkerLongitude;
    if (_shouldShowCheckerClosePopup) {
      if (!_validateAll()) return;
      final checkerClose = await showActivityTicketCheckerClosePopup(
        context,
        showReviewBtns: widget.detail.showReviewBtns,
      );
      if (checkerClose == null) return;
      checkerCloseResult = checkerClose;
      close = _mapCheckerCloseToTicketClose(checkerClose);
      try {
        final checkerLocation = await LocationService.getCurrentLocationForForm();
        checkerLatitude = checkerLocation.latitude;
        checkerLongitude = checkerLocation.longitude;
      } catch (_) {
        // Keep existing checker latitude/longitude if live location is unavailable.
      }
    } else {
      close = await showActivityTicketClosePopup(
        context,
        initialStatus: widget.detail.currentStatus,
        initialRemarks: widget.detail.remarks,
        statusOptions: widget.detail.allowedStatuses
            .where(
              (e) => e.statusName.trim().isNotEmpty && e.statusCode.trim().isNotEmpty,
            )
            .map(
              (e) => ActivityTicketCloseStatusOption(
                statusName: e.statusName.trim(),
                statusCode: e.statusCode.trim(),
                psmId: e.psmId,
              ),
            )
            .toList(),
        role: _normalizedRole,
        currentStatusId: widget.detail.currentStatusCode,
        currentStatusCode: widget.detail.currentStatusCode,
      );
    }
    if (!mounted) return;
    if (close == null) return;
    // Require all ticket fields for Completed and Completed – To Be Repeated.
    final shouldValidateAllFields =
        !_shouldShowCheckerClosePopup && close.isRepeatNature;
    if (shouldValidateAllFields && !_validateAll()) return;

    final postPayload = _buildPostPayload(
      close,
      checkerClose: checkerCloseResult,
      checkerLatitude: checkerLatitude,
      checkerLongitude: checkerLongitude,
    );
    final payloadJson = const JsonEncoder.withIndent('  ').convert(postPayload);
    Logger.infoLog('[AT_POST_REQUEST_START]');
    const chunkSize = 900;
    for (int i = 0; i < payloadJson.length; i += chunkSize) {
      final end = (i + chunkSize < payloadJson.length)
          ? i + chunkSize
          : payloadJson.length;
      final chunk = payloadJson.substring(i, end);
      Logger.infoLog(chunk);
    }
    Logger.infoLog('[AT_POST_REQUEST_END]');


    var shouldRedirectToActivities = false;
    LoaderWidget.showLoader(context);
    try {
      final isOnline = await ConnectivityHelper.isConnected();
      if (!isOnline) {
        await _persistPayloadOfflineToSqlite(postPayload);
        await _savePendingActivityTicketSync(postPayload);
        if (!mounted) return;
        Toastbar.showSuccessToastbar(
          'Activity ticket saved locally (offline mode)',
          context,
        );
        shouldRedirectToActivities = true;
        return;
      }

      final payloadToPost = await _preparePayloadForPost(postPayload);
      if (!mounted) return;
      final repository = AppConfig.of(context).pmisActivityTicketRepository;
      final response = await repository.postActivityTicket(payload: payloadToPost);
      final responseJson = const JsonEncoder.withIndent('  ')
          .convert(response.data ?? <String, dynamic>{});
      Logger.infoLog('[AT_POST_RESPONSE_START]');
      for (int i = 0; i < responseJson.length; i += chunkSize) {
        final end = (i + chunkSize < responseJson.length)
            ? i + chunkSize
            : responseJson.length;
        final chunk = responseJson.substring(i, end);
        Logger.infoLog(chunk);
      }
      Logger.infoLog('[AT_POST_RESPONSE_END]');

      if (!mounted) return;
      if (response.isSuccess) {
        await _persistPayloadOfflineToSqlite(payloadToPost);
        await ServiceLocator().pendingRequestService.deleteRequest(
          'pmis_activity_ticket_${widget.activityTicketId}',
        );
        if (!mounted) return;
        Toastbar.showSuccessToastbar('Activity ticket saved', context);
        shouldRedirectToActivities = true;
      } else {
        await _persistPayloadOfflineToSqlite(postPayload);
        await _savePendingActivityTicketSync(postPayload);
        if (!mounted) return;
        Toastbar.showErrorToastbar(
          response.errorMessage ??
              'Failed to save on server. Saved locally (offline mode)',
          context,
        );
      }
    } catch (e) {
      await _persistPayloadOfflineToSqlite(postPayload);
      await _savePendingActivityTicketSync(postPayload);
      if (mounted) {
        Toastbar.showErrorToastbar(
          'Save failed online. Saved locally (offline mode)',
          context,
        );
      }
    } finally {
      LoaderWidget.hideLoader();
    }
    if (shouldRedirectToActivities && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _buildField(PmisTicketFieldValue f) {
    final type = _normDataType(f);
    final label = f.subActivityName?.trim().isNotEmpty == true
        ? f.subActivityName!.trim()
        : 'Field';
    final req = f.isRequired == true;
    final editable = _canEditTicketFields;

    switch (type) {
      case 'TEXT':
        return CustomFormField(
          label: label,
          controller: _textByTfv[f.tfvId],
          hintText: label,
          isRequired: req && editable,
          isEditable: editable,
          inputType: InputType.text,
          inputBorderRadius: 8,
        );
      case 'NUMERIC':
        return CustomFormField(
          label: label,
          controller: _textByTfv[f.tfvId],
          hintText: label,
          isRequired: req && editable,
          isEditable: editable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          maxDecimalDigits: 6,
          validator: (v) => _validateNumeric(f, v),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}$')),
          ],
          inputBorderRadius: 8,
        );
      case 'DATE':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(label: label, isRequired: req && editable),
            const SizedBox(height: 5),
            InkWell(
              onTap: editable ? () => _pickDate(f.tfvId) : null,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppColors.color555555,
                  ),
                ),
                child: Text(
                  _textByTfv[f.tfvId]!.text.isEmpty
                      ? 'DD-MMM-YYYY'
                      : _textByTfv[f.tfvId]!.text,
                  style: TextStyle(
                    fontFamily: fontFamilyMontserrat,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: _textByTfv[f.tfvId]!.text.isEmpty
                        ? AppColors.color555555.withValues(alpha: 0.5)
                        : AppColors.color555555,
                  ),
                ),
              ),
            ),
          ],
        );
      case 'DROPDOWN':
        final items = _dropdownItems(f);
        if (items.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldLabel(label: label, isRequired: req && editable),
              const SizedBox(height: 8),
              const Text(
                'No options configured',
                style: TextStyle(
                  color: AppColors.white,
                  fontFamily: poppins,
                  fontSize: 14,
                ),
              ),
            ],
          );
        }
        return CustomDropdown(
          key: ValueKey<int>(f.tfvId),
          label: label,
          items: items,
          initialValue: _dropdownByTfv[f.tfvId],
          isRequired: req && editable,
          isDisabled: !editable,
          onChanged: (v) => setState(() => _dropdownByTfv[f.tfvId] = v),
        );
      case 'IMAGE':
        final allowMultiple = _allowsMultipleFiles(f);
        final pickFromGallery = _normControlType(f) == 'UPLOAD';
        if (allowMultiple) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTicketFileUpload(
                f: f,
                label: label,
                req: req,
                fileTypeForAttachment: 'IMAGE',
                acceptedFileTypes: '(Images)',
                pickAllowedExtensions: const [
                  'jpg',
                  'jpeg',
                  'png',
                  'gif',
                  'webp',
                  'bmp',
                ],
                useImagePicker: pickFromGallery,
                useImageCamera: !pickFromGallery,
                placeholder: 'Add image',
              ),
              _offlineSavedIndicator(f),
            ],
          );
        }
        final ext = _imageExternalDataByTfv[f.tfvId];
        final loadingServer =
            _imageLoadingFromServerTfvIds.contains(f.tfvId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImageUploadField(
              key: ValueKey<String>(
                'at_img_${f.tfvId}_${ext?.length ?? 0}_${_filesByTfv[f.tfvId]?.length ?? 0}',
              ),
              label: label,
              placeholder: 'Upload a File',
              isRequired: req && editable,
              isDisabled: !editable,
              uploadBoxHeight: 168,
              uploadBorderRadius: 8,
              onImageSelected: (file) => _handleSingleImageSelection(f, file),
              externalImageUrl: ext,
              externalImageLoading: loadingServer,
              pickFromGallery: pickFromGallery,
            ),
            _offlineSavedIndicator(f),
          ],
        );
      case 'PDF':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTicketFileUpload(
              f: f,
              label: label,
              req: req,
              fileTypeForAttachment: 'PDF',
              acceptedFileTypes: _allowsMultipleFiles(f)
                  ? '(PDF — multiple allowed)'
                  : '(PDF only)',
              pickAllowedExtensions: const ['pdf'],
              placeholder: _allowsMultipleFiles(f) ? 'Add PDF' : 'Add PDF',
            ),
            _offlineSavedIndicator(f),
          ],
        );
      case 'VIDEO':
        final useVideoRecorder = _isVideoRecorderControl(f);
        final allowMultiple = _allowsMultipleFiles(f);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTicketFileUpload(
              f: f,
              label: label,
              req: req,
              fileTypeForAttachment: 'VIDEO',
              acceptedFileTypes: useVideoRecorder
                  ? (allowMultiple
                      ? '(Record videos — multiple allowed)'
                      : '(Record video)')
                  : (allowMultiple
                      ? '(Videos — multiple allowed)'
                      : '(Video only)'),
              pickAllowedExtensions: null,
              useVideoPicker: !useVideoRecorder,
              useVideoRecorder: useVideoRecorder,
              placeholder: useVideoRecorder
                  ? (allowMultiple ? 'Record video' : 'Record video')
                  : (allowMultiple ? 'Add video' : 'Add video'),
            ),
            _offlineSavedIndicator(f),
          ],
        );
      case 'COORDINATES':
        final isGps =
            (f.subActivityControlType ?? '').trim().toUpperCase() ==
                'GPSBUTTON';
        final numberKeyboard = const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        );
        final numberFormatters = <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,8}$')),
        ];
        if (_isCombinedCoordinatesField(f)) {
          _lngByTfv[f.tfvId] ??= TextEditingController();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomFormField(
                label: '$label - Latitude',
                controller: _textByTfv[f.tfvId],
                hintText: 'Latitude',
                isRequired: req && editable,
                isEditable: editable,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                inputBorderRadius: 8,
              ),
              const SizedBox(height: 12),
              CustomFormField(
                label: '$label - Longitude',
                controller: _lngByTfv[f.tfvId],
                hintText: 'Longitude',
                isRequired: req && editable,
                isEditable: editable,
                keyboardType: numberKeyboard,
                inputFormatters: numberFormatters,
                inputBorderRadius: 8,
              ),
              if (isGps) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: !editable || _capturingGpsTfvId != null
                        ? null
                        : () => _captureGps(f),
                    icon: const Icon(Icons.my_location, color: AppColors.white),
                    label: const Text(
                      'Use current location',
                      style: TextStyle(
                        color: AppColors.white,
                        fontFamily: poppins,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomFormField(
              label: label,
              controller: _textByTfv[f.tfvId],
              hintText: _isLongitudeField(f) ? 'Longitude' : 'Latitude',
              isRequired: req && editable,
              isEditable: editable,
              keyboardType: numberKeyboard,
              inputFormatters: numberFormatters,
              inputBorderRadius: 8,
            ),
            if (isGps) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: !editable || _capturingGpsTfvId != null
                      ? null
                      : () => _captureGps(f),
                  icon: const Icon(Icons.my_location, color: AppColors.white),
                  label: const Text(
                    'Use current location',
                    style: TextStyle(
                      color: AppColors.white,
                      fontFamily: poppins,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      default:
        return CustomFormField(
          label: label,
          controller: _textByTfv[f.tfvId],
          hintText: label,
          isRequired: req && editable,
          isEditable: editable,
          inputType: InputType.text,
          inputBorderRadius: 8,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = _sortedFields;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SafeSvgPicture.asset(AppImages.home, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A3A47).withValues(alpha: 0.88),
                    const Color(0xFF0F6B5C).withValues(alpha: 0.82),
                    const Color(0xFF2E8B57).withValues(alpha: 0.76),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TicketFlowHeader(
                  title: widget.activityName,
                  breadcrumb: widget.breadcrumbText,
                  onBack: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_hasHistoricDatePicker) ...[
                          _buildHistoricDatePicker(),
                          const SizedBox(height: 16),
                        ],
                        if (fields.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.06,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Text(
                              'No checklist fields for this ticket',
                              style: TextStyle(
                                fontFamily: poppins,
                                fontSize: 14,
                                color: AppColors.color555555,
                              ),
                            ),
                          )
                        else
                          Opacity(
                            opacity: _isViewingEditableTicket ? 1.0 : 0.88,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final f in fields)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _buildField(f),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDAF0E7),
                            foregroundColor: const Color(0xFF0A5D4A),
                            disabledBackgroundColor: const Color(0xFFDAF0E7)
                                .withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Back',
                            style: TextStyle(
                              fontFamily: poppins,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDAF0E7),
                            foregroundColor: const Color(0xFF0A5D4A),
                            disabledBackgroundColor: const Color(0xFFDAF0E7)
                                .withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _canEditTicketFields ? _onSubmit : null,
                          child: const Text(
                            'Submit',
                            style: TextStyle(
                              fontFamily: poppins,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AtFieldSnapshot {
  final Map<int, String> textByTfv;
  final Map<int, String> lngByTfv;
  final Map<int, String?> dropdownByTfv;
  final Map<int, List<Map<String, dynamic>>> uploadedAttachmentsByTfv;
  final Map<int, List<File>> filesByTfv;
  final Map<int, String?> imageExternalDataByTfv;

  _AtFieldSnapshot({
    required this.textByTfv,
    required this.lngByTfv,
    required this.dropdownByTfv,
    required this.uploadedAttachmentsByTfv,
    required this.filesByTfv,
    required this.imageExternalDataByTfv,
  });
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isRequired;

  const _FieldLabel({required this.label, required this.isRequired});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              fontFamily: fontFamilyMontserrat,
            ),
          ),
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.red,
                fontFamily: fontFamilyMontserrat,
              ),
            ),
        ],
      ),
    );
  }
}

class _TicketFlowHeader extends StatelessWidget {
  final String title;
  final String breadcrumb;
  final VoidCallback onBack;

  const _TicketFlowHeader({
    required this.title,
    required this.breadcrumb,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_sharp,
                  color: AppColors.white,
                  size: 24,
                ),
                onPressed: onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                alignment: Alignment.centerLeft,
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: poppins,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, right: 8),
            child: Text(
              breadcrumb,
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: poppins,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketSummaryCard extends StatelessWidget {
  final String title;
  final String planStart;
  final String planEnd;
  final String actualStart;
  final String actualEnd;

  const _TicketSummaryCard({
    required this.title,
    required this.planStart,
    required this.planEnd,
    required this.actualStart,
    required this.actualEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: fontFamilyMontserrat,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.locationColor,
            ),
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.black.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _planLine('Plan Start', planStart),
                    const SizedBox(height: 10),
                    _planLine('Actual Start', actualStart),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _planLine('Plan End', planEnd),
                    const SizedBox(height: 10),
                    _planLine('Actual End', actualEnd),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: poppins,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.3,
        ),
        children: [
          TextSpan(
            text: '$label : ',
            style: TextStyle(
              color: AppColors.color555555.withValues(alpha: 0.85),
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppColors.color555555,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
