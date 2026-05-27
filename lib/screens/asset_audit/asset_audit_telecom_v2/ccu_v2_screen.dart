import 'dart:io';

import 'package:app/app_config.dart';
import 'package:app/commonWidgets/custom_remark.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../../../commonWidgets/asset_audit_telecom_bottom_buttons.dart';
import '../../../commonWidgets/custom_form_appbar.dart';
import '../../../commonWidgets/custom_form_field.dart';
import '../../../commonWidgets/custom_image_upload_field.dart';
import '../../../commonWidgets/simple_asset_audit_form_component.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';
import '../../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../../commonWidgets/custom_dialogs/serial_number_mismatch_dialog.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_images.dart';
import '../../../constants/constants_methods.dart';
import '../../../services/service_locator.dart';
import '../../../utils/logger.dart';
import '../../../utils.dart';
import '../../../services/asset_audit/central_service_initializer.dart';
import '../../../services/asset_audit/central_asset_audit_service.dart';
import '../../../services/asset_audit_post_service.dart';
import '../../../services/image_upload_service.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class CCUV2Screen extends StatefulWidget {
  final String siteType;
  final String auditSchId;
  final String siteAuditSchId;
  final BuildContext parentContext;

  const CCUV2Screen({
    super.key,
    required this.siteType,
    required this.auditSchId,
    required this.siteAuditSchId,
    required this.parentContext,
  });

  @override
  State<CCUV2Screen> createState() => _CCUV2ScreenState();
}

class _CCUV2ScreenState extends State<CCUV2Screen> {
  late CentralAssetAuditService _service;

  // Loading states
  bool _isLoadingData = true;
  String? _errorMessage;

  // Form controllers
  final TextEditingController _hybridCCUMakeController =
      TextEditingController();
  final TextEditingController _cabinetSerialController =
      TextEditingController();
  final TextEditingController _totalRectifierController =
      TextEditingController();
  final TextEditingController _totalMPPTController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  // Rectifier form controllers
  final TextEditingController _rectifierSerialController =
      TextEditingController();
  final TextEditingController _rectifierCapacityController =
      TextEditingController();

  // MPPT form controllers
  final TextEditingController _mpptSerialController = TextEditingController();
  final TextEditingController _mpptCapacityController = TextEditingController();

  // Form data
  bool _hasFormDataChanges = false;

  // Asset audit data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Screen name for navigation
  final String _screenName = 'CCU';

  // Lists to store saved items
  List<Map<String, dynamic>> _savedRectifiers = [];
  List<Map<String, dynamic>> _savedMPPTs = [];

  // Cabinet data
  String? _cabinetPhotoId;
  String? _cabinetImageData;
  bool? isQrCodeScanned = false;
  String? qrCodeScannedTs = null;

  // Rectifier image
  File? _rectifierImage;

  // MPPT image
  File? _mpptImage;

  // MPPT remarks controller
  final TextEditingController _mpptRemarksController = TextEditingController();

  // Rectifier remarks controller
  final TextEditingController _rectifierRemarksController = TextEditingController();

  // Rectifier image photo ID
  String? _rectifierImagePhotoId;

  // MPPT image photo ID
  String? _mpptImagePhotoId;
  String? _mpptImageData;

  // Rectifier image data
  String? _rectifierImageData;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadData();
  }

  void _initializeServices() {
    Logger.debugLog('🔧 Initializing Central Asset Audit service for CCU');
    _service = ServiceLocator().centralAssetAuditService;

    Logger.debugLog(
      '✅ Central Asset Audit service initialized successfully for CCU',
    );
  }

  void _onFormChanged() {
    if (!_hasFormDataChanges) {
      setState(() {
        _hasFormDataChanges = true;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoadingData = true;
        _errorMessage = null;
      });

      Logger.debugLog('🔄 Loading CCU data for site ${widget.siteAuditSchId}');

      // Use the actual service to load data
      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        Logger.debugLog('📊 Received CCU data from service');
        Logger.debugLog('📊 Data keys: ${data.keys.toList()}');

        // Extract CCU data
        final ccuData =
            data['responseData']?[AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>?;
        final formData = <String, dynamic>{};

        if (ccuData != null) {
          // Extract CCU Cabinet data
          final ccuCabinet = ccuData['CCU Cabinet'] as List<dynamic>? ?? [];
          if (ccuCabinet.isNotEmpty) {
            final cabinet = ccuCabinet.first as Map<String, dynamic>;
            formData['hybridCCUMake'] =
                cabinet['oem_name']?.toString() ?? "N/A";

            formData['cabinetSerial'] =
                cabinet['mfg_serial_no']?.toString() ?? "";

            formData['ccuCabinetAvailable'] = true;
            _cabinetPhotoId = cabinet['photo_id']?.toString();
            if (_cabinetPhotoId != null) {
              _cabinetImageData = await _service.getImageAsDataUrl(
                _cabinetPhotoId.toString(),
              );
            }
            isQrCodeScanned = cabinet['qr_code_scanned'] as bool? ?? false;
            qrCodeScannedTs = cabinet['qr_code_scanned_ts']?.toString();
            formData['cabinets'] = ccuCabinet;
          } else {
            formData['ccuCabinetAvailable'] = false;
          }

          // Extract Rectifiers data
          final rectifiers = ccuData['CCU Rectifiers'] as List<dynamic>? ?? [];
          formData['totalRectifier'] = rectifiers.length.toString();
          // Filter out "Overall Dtl" items from saved items list
          formData['rectifiers'] = rectifiers
              .where((item) => 
                  item['photo_id'] != null && 
                  item['record_type'] != 'Overall Dtl of CCU Rectifiers')
              .toList();
          formData['allRectifiers'] = rectifiers;

          // Extract rectifier remarks and photo from "Overall Dtl of CCU Rectifiers"
          final overallDtlItem = rectifiers
              .where(
                (item) =>
                    item['record_type'] == 'Overall Dtl of CCU Rectifiers',
              )
              .firstOrNull;
          if (overallDtlItem != null) {
            formData['rectifiersRemarks'] =
                overallDtlItem['item_type_remark']?.toString() ?? '';
            if (overallDtlItem['photo_id'] != null) {
              _rectifierImagePhotoId =
                  overallDtlItem['photo_id']?.toString();
              // Fetch image data for display
              _loadRectifierImage(_rectifierImagePhotoId!);
            }
          } else {
            Logger.debugLog('No Overall Dtl of CCU Rectifiers item found');
          }

          // Extract MPPT data
          final mppts = ccuData['CCU MPPT'] as List<dynamic>? ?? [];
          formData['totalMPPT'] = mppts.length.toString();
          // Filter out "Overall Dtl" items from saved items list
          formData['mppts'] = mppts
              .where((item) => 
                  item['photo_id'] != null && 
                  item['record_type'] != 'Overall Dtl of CCU MPPT')
              .toList();
          formData['allMppts'] = mppts;
          formData['mpptCapacity'] = mppts.isNotEmpty
              ? mppts.first['capacity']
              : 'N/A';

          // Extract MPPT remarks and photo from "Overall Dtl of CCU MPPT"
          final overallMpptDtlItem = mppts
              .where(
                (item) => item['record_type'] == 'Overall Dtl of CCU MPPT',
              )
              .firstOrNull;
          if (overallMpptDtlItem != null) {
            formData['mpptRemarks'] =
                overallMpptDtlItem['item_type_remark']?.toString() ?? '';
            if (overallMpptDtlItem['photo_id'] != null) {
              _mpptImagePhotoId =
                  overallMpptDtlItem['photo_id']?.toString();
              // Fetch image data for display
              _loadMpptImage(_mpptImagePhotoId!);
            }
          } else {
            Logger.debugLog('No Overall Dtl of CCU MPPT item found');
          }

          // Extract remarks
          final remarks = ccuData['remarks'] as List<dynamic>? ?? [];
          if (remarks.isNotEmpty) {
            final remark = remarks.first as Map<String, dynamic>;
            formData['remarks'] = remark['item_type_remark']?.toString() ?? "";
            formData['remarksExist'] = true;
          } else {
            formData['remarksExist'] = false;
          }

          // Initialize saved items
          _savedRectifiers = List<Map<String, dynamic>>.from(
            formData['rectifiers'] ?? [],
          );
          _savedMPPTs = List<Map<String, dynamic>>.from(
            formData['mppts'] ?? [],
          );
        } else {
          Logger.errorLog('❌ No CCU data found!');
        }

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
        });

        // Initialize form controllers
        _initializeFormControllers(formData);

        Logger.debugLog('✅ CCU data loaded successfully');
        Logger.debugLog('📊 Form data: $formData');
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'No data available for this site';
        });
        Logger.errorLog(
          '❌ No data available for site ${widget.siteAuditSchId}',
        );
      }
    } catch (e) {
      Logger.errorLog('❌ Error loading CCU data: $e');
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Failed to load data: $e';
      });
    }
  }

  void _initializeFormControllers(Map<String, dynamic> formData) {
    _hybridCCUMakeController.text = formData['hybridCCUMake']?.toString() ?? "";
    _totalRectifierController.text =
        formData['totalRectifier']?.toString() ?? "";

    if ((formData['totalMPPT'] ?? 0) != 0) {
      _totalMPPTController.text = formData['totalMPPT'].toString();
    }

    // Initialize cabinet serial number controller
    if (_cabinetPhotoId != null) {
      _cabinetSerialController.text =
          formData['cabinetSerial']?.toString() ?? "";
    }

    _remarksController.text = formData['remarks']?.toString() ?? "";
    _remarksController.addListener(_onFormChanged);
    
    // Initialize rectifier remarks controller
    _rectifierRemarksController.text = formData['rectifiersRemarks']?.toString() ?? '';
    _rectifierRemarksController.addListener(_onFormChanged);
    
    // Initialize MPPT remarks controller
    _mpptRemarksController.text = formData['mpptRemarks']?.toString() ?? '';
    _mpptRemarksController.addListener(_onFormChanged);
    
    if (mounted) {
      setState(() {});
    }
  }

  void _onRectifierSaved(List<Map<String, dynamic>> items) {
    setState(() {
      _savedRectifiers = items;
      _hasFormDataChanges = true;
    });
  }

  void _onMPPTSaved(List<Map<String, dynamic>> items) {
    setState(() {
      _savedMPPTs = items;
      _hasFormDataChanges = true;
    });
  }

  void _onCabinetDataChanged(
    String? photoId,
    String? imageData,
    bool? isQRCodeScanned1,
    String? qrCodeScannedTs1,
  ) {
    // Always save photo_id and image data when provided, regardless of serial validation
    // This allows photo to be uploaded before serial number is entered
    if (photoId != null) {
      setState(() {
        _cabinetPhotoId = photoId;
        _cabinetImageData = imageData;
        _hasFormDataChanges = true;
      });
    }

    // Update QR code scan info if provided
    if (isQRCodeScanned1 != null || qrCodeScannedTs1 != null) {
      setState(() {
        isQrCodeScanned = isQRCodeScanned1 ?? false;
        qrCodeScannedTs = qrCodeScannedTs1;
        _hasFormDataChanges = true;
      });
    }

    // Validate serial number only if it's not empty
    if (_cabinetSerialController.text.isNotEmpty) {
      final isValidSerial = _validateCabinetSerialNumber(
        _cabinetSerialController.text,
        isQRCodeScanned1 ?? false,
      );

      if (!isValidSerial) {
        setState(() {
          _cabinetSerialController.text = '';
        });
      }
    }
  }

  /// Load rectifier image data from photo_id
  Future<void> _loadRectifierImage(String photoId) async {
    try {
      final imageData = await _service.getImageAsDataUrl(photoId);
      if (imageData != null && imageData.isNotEmpty) {
        setState(() {
          _rectifierImageData = imageData;
        });
        Logger.debugLog('✅ Rectifier image loaded successfully');
      }
    } catch (e) {
      Logger.errorLog('❌ Error loading rectifier image: $e');
    }
  }

  /// Load MPPT image data from photo_id
  Future<void> _loadMpptImage(String photoId) async {
    try {
      final imageData = await _service.getImageAsDataUrl(photoId);
      if (imageData != null && imageData.isNotEmpty) {
        setState(() {
          _mpptImageData = imageData;
        });
        Logger.debugLog('✅ MPPT image loaded successfully');
      }
    } catch (e) {
      Logger.errorLog('❌ Error loading MPPT image: $e');
    }
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 CCU V2: Starting postCurrentScreenData');

      final finalCCuData =
          _assetAuditData?['responseData']?[AssetAuditNavigationHelper.dataValueForPage(
                _screenName,
                'TELECOM',
              )]
              as Map<String, dynamic>?;

      final modifiedAssetsWithAllProperties = <Map<String, dynamic>>[];

      // ===== CCU Cabinet =====
      final ccuCabinetList = finalCCuData?['CCU Cabinet'];
      if (ccuCabinetList != null &&
          ccuCabinetList is List &&
          ccuCabinetList.isNotEmpty) {
        for (var cabinet in ccuCabinetList) {
          final cabinetMap = Map<String, dynamic>.from(cabinet);

          // Always update photo_id if it exists, regardless of serial number
          if (_cabinetPhotoId != null && _cabinetPhotoId!.isNotEmpty) {
            cabinetMap['photo_id'] = _cabinetPhotoId;
            cabinetMap['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
            Logger.debugLog('✅ Updated CCU Cabinet with photo_id: $_cabinetPhotoId');
          }

          // Update serial number and validate if serial controller has text
          if (_cabinetSerialController.text.isNotEmpty) {
            bool isValid = _validateCabinetSerialNumber(
              _cabinetSerialController.text,
              isQrCodeScanned ?? false,
            );

            if (!isValid) {
              throw Exception("Please select cabinet serial number");
            }

            cabinetMap['mfg_serial_no'] = _cabinetSerialController.text;
            cabinetMap['asset_status'] = 'OK';

            if (isQrCodeScanned ?? false) {
              cabinetMap['qr_code_scanned'] = true;
              cabinetMap['qr_code_scanned_ts'] = qrCodeScannedTs;
            }
          } else if (cabinetMap['mfg_serial_no'] != null && cabinetMap['mfg_serial_no'].toString().isNotEmpty) {
            // If serial number already exists in data but controller is empty, preserve it
            cabinetMap['asset_status'] = cabinetMap['asset_status'] ?? 'OK';
          }

          // Always add cabinet to modified assets if photo_id exists or if it has a serial number
          if ((_cabinetPhotoId != null && _cabinetPhotoId!.isNotEmpty) ||
              (cabinetMap['mfg_serial_no'] != null && cabinetMap['mfg_serial_no'].toString().isNotEmpty)) {
            modifiedAssetsWithAllProperties.add(cabinetMap);
          }
        }
      }

      // ===== CCU Rectifiers =====
      final rectifierList = finalCCuData?['CCU Rectifiers'];
      if (rectifierList != null &&
          rectifierList is List &&
          rectifierList.isNotEmpty) {
        final modifiedRectifiers = _modifyData(rectifierList, _savedRectifiers);
        modifiedAssetsWithAllProperties.addAll(
          modifiedRectifiers.cast<Map<String, dynamic>>(),
        );

        // Update "Overall Dtl of CCU Rectifiers" item with photo and remarks
        final overallDtlItem = rectifierList
            .where(
              (item) => item['record_type'] == 'Overall Dtl of CCU Rectifiers',
            )
            .firstOrNull;
        if (overallDtlItem != null) {
          final overallDtlMap = Map<String, dynamic>.from(overallDtlItem);

          // Update photo_id if rectifier image was uploaded
          if (_rectifierImagePhotoId != null &&
              _rectifierImagePhotoId!.isNotEmpty) {
            overallDtlMap['photo_id'] = _rectifierImagePhotoId;
            overallDtlMap['photo_taken_ts'] =
                Utils.getCurrentDateTimeForAPICall();
            Logger.debugLog(
              '✅ Updated Overall Dtl of CCU Rectifiers with photo_id: $_rectifierImagePhotoId',
            );
          }

          // Update item_type_remark if rectifier remarks were added
          final rectifierRemarks = _rectifierRemarksController.text;
          if (rectifierRemarks.isNotEmpty) {
            overallDtlMap['item_type_remark'] = rectifierRemarks;
            Logger.debugLog(
              '✅ Updated Overall Dtl of CCU Rectifiers with remarks: $rectifierRemarks',
            );
          }

          // Add to modified assets if there are changes
          if ((_rectifierImagePhotoId != null &&
                  _rectifierImagePhotoId!.isNotEmpty) ||
              rectifierRemarks.isNotEmpty) {
            modifiedAssetsWithAllProperties.add(overallDtlMap);
          }

          // Also update in _assetAuditData for local storage
          final overallDtlIndex = rectifierList.indexWhere(
            (item) => item['record_type'] == 'Overall Dtl of CCU Rectifiers',
          );
          if (overallDtlIndex != -1) {
            if (_rectifierImagePhotoId != null &&
                _rectifierImagePhotoId!.isNotEmpty) {
              rectifierList[overallDtlIndex]['photo_id'] =
                  _rectifierImagePhotoId;
              rectifierList[overallDtlIndex]['photo_taken_ts'] =
                  Utils.getCurrentDateTimeForAPICall();
            }
            if (rectifierRemarks.isNotEmpty) {
              rectifierList[overallDtlIndex]['item_type_remark'] =
                  rectifierRemarks;
            }
          }
        } else {
          Logger.debugLog('No Overall Dtl of CCU Rectifiers item found');
        }
      }

      // ===== CCU MPPT =====
      final mpptList = finalCCuData?['CCU MPPT'];
      if (mpptList != null && mpptList is List && mpptList.isNotEmpty) {
        final modifiedMppts = _modifyData(mpptList, _savedMPPTs);
        modifiedAssetsWithAllProperties.addAll(
          modifiedMppts.cast<Map<String, dynamic>>(),
        );

        // Update "Overall Dtl of CCU MPPT" item with photo and remarks
        final overallMpptDtlItem = mpptList
            .where(
              (item) => item['record_type'] == 'Overall Dtl of CCU MPPT',
            )
            .firstOrNull;
        if (overallMpptDtlItem != null) {
          final overallMpptDtlMap = Map<String, dynamic>.from(
            overallMpptDtlItem,
          );

          // Update photo_id if MPPT image was uploaded
          if (_mpptImagePhotoId != null && _mpptImagePhotoId!.isNotEmpty) {
            overallMpptDtlMap['photo_id'] = _mpptImagePhotoId;
            overallMpptDtlMap['photo_taken_ts'] =
                Utils.getCurrentDateTimeForAPICall();
            Logger.debugLog(
              '✅ Updated Overall Dtl of CCU MPPT with photo_id: $_mpptImagePhotoId',
            );
          }

          // Update item_type_remark if MPPT remarks were added
          final mpptRemarks = _mpptRemarksController.text;
          if (mpptRemarks.isNotEmpty) {
            overallMpptDtlMap['item_type_remark'] = mpptRemarks;
            Logger.debugLog(
              '✅ Updated Overall Dtl of CCU MPPT with remarks: $mpptRemarks',
            );
          }

          // Add to modified assets if there are changes
          if ((_mpptImagePhotoId != null && _mpptImagePhotoId!.isNotEmpty) ||
              mpptRemarks.isNotEmpty) {
            modifiedAssetsWithAllProperties.add(overallMpptDtlMap);
          }

          // Also update in _assetAuditData for local storage
          final overallMpptDtlIndex = mpptList.indexWhere(
            (item) => item['record_type'] == 'Overall Dtl of CCU MPPT',
          );
          if (overallMpptDtlIndex != -1) {
            if (_mpptImagePhotoId != null && _mpptImagePhotoId!.isNotEmpty) {
              mpptList[overallMpptDtlIndex]['photo_id'] = _mpptImagePhotoId;
              mpptList[overallMpptDtlIndex]['photo_taken_ts'] =
                  Utils.getCurrentDateTimeForAPICall();
            }
            if (mpptRemarks.isNotEmpty) {
              mpptList[overallMpptDtlIndex]['item_type_remark'] = mpptRemarks;
            }
          }
        } else {
          Logger.debugLog('No Overall Dtl of CCU MPPT item found');
        }
      }

      // ===== Remarks =====
      final remarksList = finalCCuData?['remarks'];
      if (remarksList != null &&
          remarksList is List &&
          remarksList.isNotEmpty) {
        final finalRemarks = Map<String, dynamic>.from(remarksList.first);
        final String remark = _remarksController.text;
        if (remark.isNotEmpty) {
          finalRemarks['item_type_remark'] = remark;
          modifiedAssetsWithAllProperties.add(finalRemarks);
        }
      }

      // ===== Update _assetAuditData with modified data before saving =====
      // Update CCU Cabinet data in _assetAuditData
      if (ccuCabinetList != null &&
          ccuCabinetList is List &&
          ccuCabinetList.isNotEmpty) {
        for (int i = 0; i < ccuCabinetList.length; i++) {
          // Always update photo_id if it exists
          if (_cabinetPhotoId != null && _cabinetPhotoId!.isNotEmpty) {
            ccuCabinetList[i]['photo_id'] = _cabinetPhotoId;
            ccuCabinetList[i]['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
            Logger.debugLog('✅ Updated CCU Cabinet in _assetAuditData with photo_id: $_cabinetPhotoId');
          }

          // Update serial number if controller has text
          if (_cabinetSerialController.text.isNotEmpty) {
            ccuCabinetList[i]['mfg_serial_no'] = _cabinetSerialController.text;
            ccuCabinetList[i]['asset_status'] = 'OK';
            if (isQrCodeScanned ?? false) {
              ccuCabinetList[i]['qr_code_scanned'] = true;
              ccuCabinetList[i]['qr_code_scanned_ts'] = qrCodeScannedTs;
            }
          }
        }
      }

      // Update Rectifiers data in _assetAuditData
      if (rectifierList != null && rectifierList is List) {
        for (var asset in rectifierList) {
          final assetSerialNo = asset['mfg_serial_no']?.toString();
          final modifiedAsset = _savedRectifiers
              .where((ass) => ass['mfg_serial_no']?.toString() == assetSerialNo)
              .firstOrNull;

          if (modifiedAsset != null) {
            asset['qr_code_scanned'] = modifiedAsset['qr_code_scanned'];
            asset['qr_code_scanned_ts'] = modifiedAsset['qr_code_scanned_ts'];
            asset['photo_id'] = modifiedAsset['photo_id'];
            asset['asset_status'] = modifiedAsset['asset_status'];
          }
        }
      }

      // Update MPPT data in _assetAuditData
      if (mpptList != null && mpptList is List) {
        for (var asset in mpptList) {
          final assetSerialNo = asset['mfg_serial_no']?.toString();
          final modifiedAsset = _savedMPPTs
              .where((ass) => ass['mfg_serial_no']?.toString() == assetSerialNo)
              .firstOrNull;

          if (modifiedAsset != null) {
            asset['qr_code_scanned'] = modifiedAsset['qr_code_scanned'];
            asset['qr_code_scanned_ts'] = modifiedAsset['qr_code_scanned_ts'];
            asset['photo_id'] = modifiedAsset['photo_id'];
            asset['asset_status'] = modifiedAsset['asset_status'];
          }
        }
      }

      // Update Remarks in _assetAuditData
      if (remarksList != null &&
          remarksList is List &&
          remarksList.isNotEmpty) {
        final String remark = _remarksController.text;
        if (remark.isNotEmpty) {
          remarksList.first['item_type_remark'] = remark;
        }
      }

      // ===== Update local SQLite with modified data =====
      _service.updateDataInSqlite(
        siteAuditSchId: widget.siteAuditSchId,
        updatedData: _assetAuditData ?? {},
      );

      final postObject = [...modifiedAssetsWithAllProperties];

      await ServiceLocator().assetAuditPostService
          .postAssetAuditDataWithPhotoReplacement(
            requests: postObject,
            isLastPage:
                AssetAuditNavigationHelper.getTelecomNextScreenName(
                  _assetAuditData,
                  _screenName,
                ) ==
                'SUBMIT',
            activityType: ActivityTypeEnum.assetAudit,
          );

      Logger.debugLog('✅ SPV V2: Data posted successfully');
    } catch (e, s) {
      Logger.errorLog('❌ CCU V2: Error in postCurrentScreenData: $e', s);
      rethrow;
    }
  }

  // Future<void> postCurrentScreenData() async {
  //   try {
  //     Logger.debugLog('📤 CCU V2: Starting postCurrentScreenData');

  //     final finalCCuData =
  //         _assetAuditData?['responseData']?[AssetAuditNavigationHelper.dataValueForPage(
  //               _screenName,
  //               'TELECOM',
  //             )]
  //             as Map<String, dynamic>?;
  //     final modifiedAssetsWithAllProperties = [];
  //     final finalCabinet =
  //         finalCCuData?['CCU Cabinet']?.first ?? Map<String, dynamic>;
  //     if (finalCabinet != null &&
  //         _cabinetSerialController.text.isNotEmpty &&
  //         _cabinetPhotoId != null) {
  //       bool isValid = _validateCabinetSerialNumber(
  //         _cabinetSerialController.text,
  //         isQrCodeScanned ?? false,
  //       );
  //       if (!isValid) {
  //         throw new Exception("Please select cabinet serial number");
  //       }
  //       finalCabinet['photo_id'] = _cabinetPhotoId;
  //       finalCabinet['asset_status'] = 'OK';
  //       if (isQrCodeScanned ?? false) {
  //         finalCabinet['qr_code_scanned'] = true;
  //         finalCabinet['qr_code_scanned_ts'] = qrCodeScannedTs;
  //       }
  //       modifiedAssetsWithAllProperties.add(finalCabinet);
  //     }

  //     final modifiedRectifiers = _modifyData(
  //       finalCCuData?['CCU Rectifiers'],
  //       _savedRectifiers,
  //     );

  //     modifiedAssetsWithAllProperties.addAll(modifiedRectifiers);

  //     final modifiedMppts = _modifyData(finalCCuData?['CCU MPPT'], _savedMPPTs);
  //     modifiedAssetsWithAllProperties.addAll(modifiedMppts);

  //     if (finalCCuData?['Remarks'] != null) {
  //       final finalRemarks =
  //           finalCCuData?['Remarks']?.first ?? Map<String, dynamic>;
  //       final String remark = _remarksController.text;
  //       if (remark.isNotEmpty && finalRemarks.isNotEmpty) {
  //         try {
  //           finalRemarks['item_type_remark'] = remark;
  //           modifiedAssetsWithAllProperties.add(finalRemarks);
  //         } catch (e) {
  //           Logger.errorLog('❌ Error updating remarks: $e');
  //         }
  //       }
  //     }

  //     _service.updateDataInSqlite(
  //       siteAuditSchId: widget.siteAuditSchId,
  //       updatedData: _assetAuditData ?? {},
  //     );

  //     // Prepare data for posting
  //     final postObject = [...modifiedAssetsWithAllProperties];

  //     Logger.debugLog(
  //       '📤 SPV V2: Prepared ${postObject.length} items for posting',
  //     );

  //     // Initialize AssetAuditPostService
  //     final apiService = AppConfig.of(context).apiService;
  //     final imageUploadService = ImageUploadService(apiService: apiService);
  //     final postService = AssetAuditPostService(
  //       apiService: apiService,
  //       imageUploadService: imageUploadService,
  //     );

  //     // Post data with photo ID replacement
  //     await postService.postAssetAuditDataWithPhotoReplacement(
  //       requests: postObject,
  //       isLastPage:
  //           AssetAuditNavigationHelper.getTelecomNextScreenName(
  //             _assetAuditData,
  //             _screenName,
  //           ) ==
  //           'SUBMIT',
  //     );

  //     Logger.debugLog('✅ SPV V2: Data posted successfully');
  //   } catch (e) {
  //     Logger.errorLog('❌ CCU V2: Error in postCurrentScreenData: $e');
  //     rethrow;
  //   }
  // }

  static List<dynamic> _modifyData(
    List<dynamic> actualData,
    List<dynamic> modifiedData,
  ) {
    List<dynamic> modifiedDataToReturn = [];
    for (dynamic asset in actualData) {
      try {
        final assetSerialNo = asset['mfg_serial_no']?.toString();
        final modifiedAsset = modifiedData
            .where((ass) => ass['mfg_serial_no']?.toString() == assetSerialNo)
            .firstOrNull;

        if (modifiedAsset != null) {
          asset['qr_code_scanned'] = modifiedAsset['qr_code_scanned'];
          asset['qr_code_scanned_ts'] = modifiedAsset['qr_code_scanned_ts'];
          asset['photo_id'] = modifiedAsset['photo_id'];
          asset['asset_status'] = modifiedAsset['asset_status'];
          modifiedDataToReturn.add(asset);
          Logger.debugLog('✅ Updated asset: $assetSerialNo');
        } else {
          Logger.debugLog(
            '⚠️ No modified asset found for serial: $assetSerialNo',
          );
        }
      } catch (e) {
        Logger.errorLog('❌ Error updating asset: $e');
      }
    }
    return modifiedDataToReturn;
  }

  @override
  void dispose() {
    _hybridCCUMakeController.dispose();
    _cabinetSerialController.dispose();
    _totalRectifierController.dispose();
    _totalMPPTController.dispose();
    _remarksController.dispose();
    _rectifierSerialController.dispose();
    _rectifierCapacityController.dispose();
    _mpptSerialController.dispose();
    _mpptCapacityController.dispose();
    _mpptRemarksController.dispose();
    _rectifierRemarksController.dispose();
    super.dispose();
  }

  // Custom validation function for Cabinet serial number
  bool _validateCabinetSerialNumber(String serialNumber, bool isQRCodeScanned) {
    final cabinets = _displayFormData?['cabinets'] as List<dynamic>?;

    // Check if the serial number matches either nexgen_serial_no or mfg_serial_no
    bool isValid = AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      cabinets,
      isQRCodeScanned,
    );

    // If validation fails, show popup
    if (!isValid && serialNumber.isNotEmpty) {
      _showSerialNumberMismatchDialog(serialNumber);
    } else {
      serialNumber = '';
    }

    return isValid;
  }

  // Custom validation function for Rectifier serial number
  bool _validateRectifierSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final allRectifiers = _displayFormData?['allRectifiers'] as List<dynamic>?;
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      allRectifiers,
      isQRCodeScanned,
    );
  }

  // Custom validation function for mppt serial number
  bool _validateMpptSerialNumber(String serialNumber, bool isQRCodeScanned) {
    final allMppts = _displayFormData?['allMppts'] as List<dynamic>?;
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      allMppts,
      isQRCodeScanned,
    );
  }

  // Show dialog when cabinet serial number doesn't match
  void _showSerialNumberMismatchDialog(String enteredSerialNumber) {
    final cabinets = _displayFormData?['cabinets'] as List<dynamic>?;
    String expectedSerialNumbers = '';

    if (cabinets != null && cabinets.isNotEmpty) {
      final cabinet = cabinets.first as Map<String, dynamic>;
      final nexgenSerial = cabinet['nexgen_serial_no']?.toString() ?? '';
      final mfgSerial = cabinet['mfg_serial_no']?.toString() ?? '';

      if (nexgenSerial.isNotEmpty && mfgSerial.isNotEmpty) {
        expectedSerialNumbers =
            'Expected serial numbers:\n• NexGen: $nexgenSerial\n• MFG: $mfgSerial';
      } else if (nexgenSerial.isNotEmpty) {
        expectedSerialNumbers =
            'Expected serial number:\n• NexGen: $nexgenSerial';
      } else if (mfgSerial.isNotEmpty) {
        expectedSerialNumbers = 'Expected serial number:\n• MFG: $mfgSerial';
      }
    }

    SerialNumberMismatchDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomFormAppbar(
        title: 'CCU',
        onClose: () {
          _showUnsavedChangesDialog();
        },
      ),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: SafeSvgPicture.asset(
              AppImages.home,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 100,
                    ),
                    child: Container(
                      padding: const EdgeInsets.only(
                        top: 20,
                        left: 16,
                        right: 16,
                        bottom: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Show loading indicator
                          if (_isLoadingData)
                            Container(
                              padding: const EdgeInsets.all(20),
                              child: const Center(
                                child: Column(
                                  children: [
                                    CircularProgressIndicator(
                                      color: AppColors.primaryGreen,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Loading CCU data...',
                                      style: TextStyle(
                                        color: AppColors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Show error message
                          if (_errorMessage != null && !_isLoadingData)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.errorColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.errorColor,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: AppColors.errorColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Failed to load CCU data',
                                          style: TextStyle(
                                            color: AppColors.errorColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: AppColors.errorColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: _loadData,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.errorColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),

                          // Show form fields only when data is loaded and no error
                          if (!_isLoadingData && _errorMessage == null)
                            _buildFormFields(),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom button container
                AssetAuditTelecomBottomButtons(
                  isLoading: _isLoadingData,
                  errorMessage: _errorMessage,
                  onNextButtonClick: () async {
                    if (_hasFormDataChanges) {
                      await postCurrentScreenData();
                    }
                  },
                  assetAuditData: _assetAuditData,
                  auditSchId: widget.auditSchId,
                  siteType: widget.siteType,
                  siteAuditSchId: widget.siteAuditSchId,
                  screenName: _screenName,
                  parentContext: widget.parentContext,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    // Calculate Rectifier count only for items with record_type == "Asset"
    final allRectifiers = _displayFormData?['allRectifiers'] as List<dynamic>? ?? [];
    final rectifierCount = allRectifiers
        .where((item) => item['record_type']?.toString() == 'Asset')
        .length
        .toString();

    // Calculate MPPT count only for items with record_type == "Asset"
    final allMppts = _displayFormData?['allMppts'] as List<dynamic>? ?? [];
    final mpptCount = allMppts
        .where((item) => item['record_type']?.toString() == 'Asset')
        .length
        .toString();

    return Column(
      children: [
        // Hybrid CCU Make
        CustomFormField(
          label: "Hybrid CCU Make",
          initialValue: _displayFormData?['hybridCCUMake'] ?? "N/A",
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),
        if (_displayFormData?['ccuCabinetAvailable'] ?? false) ...[
          // Hybrid CCU Count
          CustomFormField(
            label: "Hybrid CCU Count",
            initialValue: (_displayFormData?['cabinets'] as List<dynamic>? ?? []).length.toString(),
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),
          // Cabinet Serial Number and Photo using SimpleAssetAuditFormComponent
          SimpleAssetAuditFormComponent(
            componentId: 'cabinet_component',
            serialLabel: "Cabinet Serial Number",
            serialHintText: "Cabinet Serial Number",
            photoLabel: "Add Photo of Cabinet",
            serialController: _cabinetSerialController,
            initialPhotoId: _cabinetPhotoId,
            initialImageData: _cabinetImageData,
            onDataChanged: _onCabinetDataChanged,
            siteAuditSchId: widget.siteAuditSchId,
          ),
          getHeight(20),
        ],

        // Total Count of Rectifier
        if (_displayFormData?['totalRectifier'] != "0") ...[
          CustomFormField(
            label: "Total Count of Rectifier",
            initialValue: rectifierCount,
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),

          // Photo of all Rectifier
          ImageUploadField(
            label: "Add Photo of all Rectifiers",
            placeholder: "Add Photo",
            isRequired: true,
            externalImageUrl: _rectifierImageData,
            onImageSelected: (image) async {
              if (image != null) {
                setState(() {
                  _rectifierImage = image;
                });
                // Upload image and get photo_id
                try {
                  final photoId = await _service.uploadImage(
                    siteAuditSchId: widget.siteAuditSchId,
                    imageFile: image,
                    isSelfie: false,
                    activityType: ActivityTypeEnum.assetAudit,
                  );
                  if (photoId != null && photoId.isNotEmpty) {
                    setState(() {
                      _rectifierImagePhotoId = photoId;
                      _rectifierImageData = null; // Clear old image data when new image is uploaded
                      _hasFormDataChanges = true;
                    });
                    Logger.debugLog('✅ Rectifier image uploaded with ID: $photoId');
                  }
                } catch (e) {
                  Logger.errorLog('❌ Error uploading rectifier image: $e');
                }
              }
            },
          ),
          getHeight(15),

          // Add Rectifiers Remarks
          CustomRemarksField(
            label: "Add Rectifiers Remarks",
            hintText: "Remarks",
            controller: _rectifierRemarksController,
            initialValue: _displayFormData?['rectifiersRemarks'] ?? '',
          ),
           getHeight(15),

          // Rectifiers Details Section
          Container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Rectifiers Details",
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                AssetAuditFormComponent(
                  componentId: 'rectifier_component',
                  serialLabel: "Rectifier - Serial Number",
                  serialHintText: "Rectifier Serial Number",
                  photoLabel: "Add a Photo",
                  serialController: _rectifierSerialController,
                  initialSavedItems: _savedRectifiers,
                  onItemSaved: _onRectifierSaved,
                  onStatusChanged: (status) {
                    setState(() {
                      _hasFormDataChanges = true;
                    });
                  },
                  customValidator: _validateRectifierSerialNumber,
                  siteAuditSchId: widget.siteAuditSchId,
                  showTable: true,
                  tableTitle: "Rectifiers",
                ),
              ],
            ),
          ),
        ],
        // Total Count of MPPT
        if (_displayFormData?['totalMPPT'] != "0") ...[
          CustomFormField(
            label: "Total Count of MPPT",
            initialValue: mpptCount,
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),

          // Photo of all MPPT
          ImageUploadField(
            label: "Add Photo of all MPPT",
            placeholder: "Add Photo",
            isRequired: true,
            externalImageUrl: _mpptImageData,
            onImageSelected: (image) async {
              if (image != null) {
                setState(() {
                  _mpptImage = image;
                });
                // Upload image and get photo_id
                try {
                  final photoId = await _service.uploadImage(
                    siteAuditSchId: widget.siteAuditSchId,
                    imageFile: image,
                    isSelfie: false,
                    activityType: ActivityTypeEnum.assetAudit,
                  );
                  if (photoId != null && photoId.isNotEmpty) {
                    setState(() {
                      _mpptImagePhotoId = photoId;
                      _mpptImageData = null; // Clear old image data when new image is uploaded
                      _hasFormDataChanges = true;
                    });
                    Logger.debugLog('✅ MPPT image uploaded with ID: $photoId');
                  }
                } catch (e) {
                  Logger.errorLog('❌ Error uploading MPPT image: $e');
                }
              }
            },
          ),
          getHeight(15),

          // Add MPPT Remarks
          CustomRemarksField(
            label: "Add MPPT Remarks",
            hintText: "Remarks",
            controller: _mpptRemarksController,
            initialValue: _displayFormData?['mpptRemarks'] ?? '',
          ),
          getHeight(15),

          // MPPT Details Section
          Container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "MPPT Details",
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                AssetAuditFormComponent(
                  componentId: 'mppt_component',
                  serialLabel: "MPPT - Serial Number",
                  serialHintText: "MPPT Serial Number",
                  photoLabel: "Add a Photo",
                  disabledFieldLabel: "Capacity",
                  disabledFieldValue:
                      _displayFormData?['mpptCapacity']?.toString() ?? 'N/A',
                  serialController: _mpptSerialController,
                  initialSavedItems: _savedMPPTs,
                  onItemSaved: _onMPPTSaved,
                  onStatusChanged: (status) {
                    setState(() {
                      _hasFormDataChanges = true;
                    });
                  },
                  customValidator: _validateMpptSerialNumber,
                  siteAuditSchId: widget.siteAuditSchId,
                  showTable: true,
                  tableTitle: "MPPTs",
                  onSerialNumberLookup: (serialNumber) {
                    // Look up capacity from allMppts based on serial number
                    final allMppts =
                        _displayFormData?['allMppts'] as List<dynamic>? ?? [];
                    final matchingItem = allMppts.where((item) {
                      final mfgSerial =
                          item['mfg_serial_no']?.toString() ?? '';
                      final nexgenSerial =
                          item['nexgen_serial_no']?.toString() ?? '';
                      // Case-insensitive comparison to handle QR scan uppercase
                      return mfgSerial.toUpperCase() ==
                              serialNumber.toUpperCase() ||
                          nexgenSerial.toUpperCase() ==
                              serialNumber.toUpperCase();
                    }).firstOrNull;
                    if (matchingItem == null) {
                      Logger.debugLog(
                        'No matching MPPT found for serial number: $serialNumber',
                      );
                      return null;
                    }
                    return {
                      'capacity':
                          matchingItem['capacity']?.toString() ?? '',
                    };
                  },
                ),
              ],
            ),
          ),
          getHeight(20),
        ],

        if (_displayFormData?['remarksExist'] == true) ...[
          // Add Remarks
          CustomRemarksField(
            label: "Add Remarks",
            hintText: "Remarks",
            controller: _remarksController,
            initialValue: _displayFormData?['remarks'] ?? '',
          ),
        ],
      ],
    );
  }

  void _showUnsavedChangesDialog() {
    if (_hasFormDataChanges) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => UnsavedChangesDialog(
          siteAuditSchId: widget.siteAuditSchId,
          section: "Asset Audit",
          parentContext: widget.parentContext,
          onSaveAndExit: () async {
            await postCurrentScreenData();
          },
          onDiscard: () {},
        ),
      );
    } else {
      navigateBackOrToHome(context, targetContext: widget.parentContext);
    }
  }
}