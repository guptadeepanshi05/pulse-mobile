import 'dart:io';

import 'package:app/enum/activity_type_enum.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../../../commonWidgets/custom_form_appbar.dart';
import '../../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';
import '../../../commonWidgets/custom_form_field.dart';
import '../../../commonWidgets/custom_image_upload_field.dart';
import '../../../commonWidgets/custom_remark.dart';
import '../../../commonWidgets/asset_audit_telecom_bottom_buttons.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_images.dart';
import '../../../constants/constants_methods.dart';
import '../../../services/service_locator.dart';
import '../../../utils/logger.dart';
import '../../../utils.dart';
import '../../../services/asset_audit/central_asset_audit_service.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class SMPSV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const SMPSV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<SMPSV2Screen> createState() => _SMPSV2ScreenState();
}

class _SMPSV2ScreenState extends State<SMPSV2Screen> {
  final String _screenName = 'SMPS';

  // Service
  late CentralAssetAuditService _service;

  // Data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Controllers
  final TextEditingController _remarksController = TextEditingController();

  // State
  bool _isLoadingData = false;
  String? _errorMessage;
  bool _hasFormDataChanges = false;

  // Images
  File? _smpsImage;
  File? _rectifiersImage;
  String? _smpsImagePhotoId;
  String? _rectifiersImagePhotoId;
  String? _smpsImageData;
  String? _rectifiersImageData;

  @override
  void initState() {
    super.initState();
    _service = ServiceLocator().centralAssetAuditService;
    _loadData();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
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

      Logger.debugLog(
        '🔄 SMPS V2: Loading data for site ${widget.siteAuditSchId}',
      );

      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        final smpsItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>? ??
            {};

        // Parse different asset type

        final smpsAssets = smpsItems['assets'] as List<dynamic>? ?? [];
        final smpsRectifiers =
            smpsItems['SMPS Rectifiers'] as List<dynamic>? ?? [];
        final smpsCabinet = smpsItems['SMPS Cabinet'] as List<dynamic>? ?? [];
        final remarksData = smpsItems['remarks'] as List<dynamic>? ?? [];

        // Extract SMPS photo from "Overall Dtl of SMPS"
        String? smpsImageData;
        final overallSMPSDtlItem = smpsAssets
            .where((item) => item['record_type'] == 'Overall Dtl of SMPS')
            .firstOrNull;
        if (overallSMPSDtlItem != null &&
            overallSMPSDtlItem['photo_id'] != null) {
          final photoId = overallSMPSDtlItem['photo_id'].toString();
          Logger.debugLog('📸 Loading SMPS image with photo_id: $photoId');
          try {
            smpsImageData = await _service.getImageAsDataUrl(photoId);
            _smpsImagePhotoId = photoId;
            _smpsImageData = smpsImageData;
            Logger.debugLog('✅ Successfully loaded SMPS image');
          } catch (e) {
            Logger.errorLog('❌ Error loading SMPS image: $e');
          }
        } else {
          Logger.debugLog('No Overall Dtl of SMPS item found');
        }

        // Extract Rectifiers photo from "Overall Dtl of SMPS Rectifiers"
        String? rectifiersImageData;
        final overallRectifiersDtlItem = smpsRectifiers
            .where(
              (item) =>
                  item['record_type'] == 'Overall Dtl of SMPS Rectifiers',
            )
            .firstOrNull;
        if (overallRectifiersDtlItem != null &&
            overallRectifiersDtlItem['photo_id'] != null) {
          final photoId = overallRectifiersDtlItem['photo_id'].toString();
          Logger.debugLog(
            '📸 Loading SMPS Rectifiers image with photo_id: $photoId',
          );
          try {
            rectifiersImageData = await _service.getImageAsDataUrl(photoId);
            _rectifiersImagePhotoId = photoId;
            _rectifiersImageData = rectifiersImageData;
            Logger.debugLog('✅ Successfully loaded SMPS Rectifiers image');
          } catch (e) {
            Logger.errorLog('❌ Error loading SMPS Rectifiers image: $e');
          }
        } else {
          Logger.debugLog('No Overall Dtl of SMPS Rectifiers item found');
        }

        final formData = <String, dynamic>{
          'smpsMake': smpsAssets.isNotEmpty
              ? smpsAssets.first['oem_name']?.toString() ?? 'N/A'
              : 'N/A',
          // Count excluding "Overall Dtl" items
          'smpsCount': smpsAssets
              .where((obj) => obj['record_type'] != 'Overall Dtl of SMPS')
              .length
              .toString(),
          'smpsRectifiersCount': smpsRectifiers
              .where((obj) => obj['record_type'] != 'Overall Dtl of SMPS Rectifiers')
              .length
              .toString(),
          // Filter out "Overall Dtl" items from saved items list
          'smpsAssets': smpsAssets
              .where((obj) => 
                  obj['photo_id'] != null && 
                  obj['record_type'] != 'Overall Dtl of SMPS')
              .toList(),
          'smpsAllAssets': smpsAssets,
          'smpsRectifiers': smpsRectifiers
              .where((obj) => 
                  obj['photo_id'] != null && 
                  obj['record_type'] != 'Overall Dtl of SMPS Rectifiers')
              .toList(),
          'smpsRectifiersAllAssets': smpsRectifiers,
          'smpsCabinet': smpsCabinet
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'smpsCabinetAvailable': smpsCabinet.isNotEmpty,
          'smpsCabinetAllAssets': smpsCabinet,
          'remarks': remarksData.isNotEmpty
              ? remarksData.first['item_type_remark']?.toString() ?? ''
              : '',
        };

        setState(() {
          _assetAuditData = data;
          _displayFormData = formData;
          _isLoadingData = false;
        });

        _initializeFormControllers(formData);
        Logger.debugLog('✅ SMPS V2: Data loaded successfully');
      } else {
        setState(() {
          _errorMessage = 'No data available for this site';
          _isLoadingData = false;
        });
      }
    } catch (e) {
      Logger.errorLog('❌ SMPS V2: Error loading data: $e');
      setState(() {
        _errorMessage = 'Error loading data: $e';
        _isLoadingData = false;
      });
    }
  }

  void _initializeFormControllers(Map<String, dynamic> formData) {
    _remarksController.text = formData['remarks'] ?? '';
    Logger.debugLog('📝 Initialized form controllers');
    // Add listeners for form changes
    _remarksController.addListener(_onFormChanged);
    if (mounted) {
      setState(() {});
    }
  }

  // Callback methods for AssetAuditFormComponent
  void _onSMPSRectifierItemSaved(List<Map<String, dynamic>> items) {
    setState(() {
      _displayFormData?['smpsRectifiers'] = items;
      _hasFormDataChanges = true;
    });
  }

  void _onSMPSCabinetItemSaved(List<Map<String, dynamic>> items) {
    setState(() {
      _displayFormData?['smpsCabinet'] = items;
      _hasFormDataChanges = true;
    });
  }

  // Validation methods
  bool _validateCabinetSerialNumber(String serialNumber, bool isQRCodeScanned) {
    final savedItems =
        _displayFormData?['smpsCabinetAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  bool _validateRectifierSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['smpsRectifiersAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 SMPS V2: Starting postCurrentScreenData');

      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'TELECOM',
          )];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];
      final finalSMPSRectifiers =
          finalData?['SMPS Rectifiers'] as List<dynamic>? ?? [];
      final finalSMPSCabinet =
          finalData?['SMPS Cabinet'] as List<dynamic>? ?? [];
      final finalSMPSAssets = finalData?['assets'] as List<dynamic>? ?? [];

      Logger.debugLog(
        '📊 SMPS V2: Data counts - Rectifiers: ${finalSMPSRectifiers.length}, Assets: ${finalSMPSAssets.length}, Cabinet: ${finalSMPSCabinet.length}',
      );

      // Log all record_types to debug
      Logger.debugLog('📊 SMPS Rectifiers record_types: ${finalSMPSRectifiers.map((e) => e['record_type']).toList()}');
      Logger.debugLog('📊 SMPS Assets record_types: ${finalSMPSAssets.map((e) => e['record_type']).toList()}');

      // Collect all modified assets
      final modifiedAssetsWithAllProperties = <dynamic>[];

      // Add SMPS Rectifiers
      final modifiedSMPSRectifiers =
          _displayFormData?['smpsRectifiers'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalSMPSRectifiers,
          modifiedSMPSRectifiers,
        ),
      );

      // Update "Overall Dtl of SMPS Rectifiers" item with photo
      final overallRectifiersDtlItem = finalSMPSRectifiers
          .where(
            (item) => item['record_type'] == 'Overall Dtl of SMPS Rectifiers',
          )
          .firstOrNull;
      if (overallRectifiersDtlItem != null) {
        final overallRectifiersDtlMap = Map<String, dynamic>.from(
          overallRectifiersDtlItem,
        );

        // Update photo_id if rectifiers image was uploaded
        if (_rectifiersImagePhotoId != null &&
            _rectifiersImagePhotoId!.isNotEmpty) {
          overallRectifiersDtlMap['photo_id'] = _rectifiersImagePhotoId;
          overallRectifiersDtlMap['photo_taken_ts'] =
              Utils.getCurrentDateTimeForAPICall();
          Logger.debugLog(
            '✅ Updated Overall Dtl of SMPS Rectifiers with photo_id: $_rectifiersImagePhotoId',
          );

          // Add to modified assets when photo is uploaded
          modifiedAssetsWithAllProperties.add(overallRectifiersDtlMap);
        }

        // Also update in _assetAuditData for local storage
        final overallRectifiersDtlIndex = finalSMPSRectifiers.indexWhere(
          (item) => item['record_type'] == 'Overall Dtl of SMPS Rectifiers',
        );
        if (overallRectifiersDtlIndex != -1) {
          if (_rectifiersImagePhotoId != null &&
              _rectifiersImagePhotoId!.isNotEmpty) {
            finalSMPSRectifiers[overallRectifiersDtlIndex]['photo_id'] =
                _rectifiersImagePhotoId;
            finalSMPSRectifiers[overallRectifiersDtlIndex]['photo_taken_ts'] =
                Utils.getCurrentDateTimeForAPICall();
          }
        }
      } else {
        Logger.debugLog('No Overall Dtl of SMPS Rectifiers item found');
      }

      // Add SMPS Cabinet
      final modifiedSMPSCabinet =
          _displayFormData?['smpsCabinet'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalSMPSCabinet,
          modifiedSMPSCabinet,
        ),
      );

      // Update "Overall Dtl of SMPS" item with photo
      final overallSMPSDtlItem = finalSMPSAssets
          .where((item) => item['record_type'] == 'Overall Dtl of SMPS')
          .firstOrNull;
      if (overallSMPSDtlItem != null) {
        final overallSMPSDtlMap = Map<String, dynamic>.from(
          overallSMPSDtlItem,
        );

        // Update photo_id if SMPS image was uploaded
        if (_smpsImagePhotoId != null && _smpsImagePhotoId!.isNotEmpty) {
          overallSMPSDtlMap['photo_id'] = _smpsImagePhotoId;
          overallSMPSDtlMap['photo_taken_ts'] =
              Utils.getCurrentDateTimeForAPICall();
          Logger.debugLog(
            '✅ Updated Overall Dtl of SMPS with photo_id: $_smpsImagePhotoId',
          );

          // Add to modified assets when photo is uploaded
          modifiedAssetsWithAllProperties.add(overallSMPSDtlMap);
        }

        // Also update in _assetAuditData for local storage
        final overallSMPSDtlIndex = finalSMPSAssets.indexWhere(
          (item) => item['record_type'] == 'Overall Dtl of SMPS',
        );
        if (overallSMPSDtlIndex != -1) {
          if (_smpsImagePhotoId != null && _smpsImagePhotoId!.isNotEmpty) {
            finalSMPSAssets[overallSMPSDtlIndex]['photo_id'] =
                _smpsImagePhotoId;
            finalSMPSAssets[overallSMPSDtlIndex]['photo_taken_ts'] =
                Utils.getCurrentDateTimeForAPICall();
          }
        }
      } else {
        Logger.debugLog('No Overall Dtl of SMPS item found');
      }

      // Update remarks in-memory too so SQLite/open-back shows latest value.
      final String remark = _remarksController.text;
      try {
        if (finalRemarks.isNotEmpty) {
          finalRemarks.first['item_type_remark'] = remark;
        } else if (remark.isNotEmpty) {
          // Some payloads do not include `remarks` list initially.
          // Create a minimal local row so reopen can read from SQLite.
          finalData?['remarks'] = <Map<String, dynamic>>[
            <String, dynamic>{'item_type_remark': remark},
          ];
        }
        if (remark.isNotEmpty) {
          _displayFormData?['remarks'] = remark;
          Logger.debugLog('✅ Updated remarks: $remark');
        }
      } catch (e) {
        Logger.errorLog('❌ Error updating remarks: $e');
      }

      // Always include "Overall Dtl" items if they exist to prevent empty array
      // Check if "Overall Dtl of SMPS Rectifiers" is already in the list
      bool hasRectifiersDtl = modifiedAssetsWithAllProperties.any(
        (item) => item['record_type'] == 'Overall Dtl of SMPS Rectifiers',
      );
      
      if (!hasRectifiersDtl) {
        // Find "Overall Dtl of SMPS Rectifiers" item using where().firstOrNull pattern
        dynamic overallRectifiersDtlItem;
        try {
          final foundItems = finalSMPSRectifiers.where(
            (item) => item['record_type'] == 'Overall Dtl of SMPS Rectifiers',
          ).toList();
          if (foundItems.isNotEmpty) {
            overallRectifiersDtlItem = foundItems.first;
          }
        } catch (e) {
          Logger.debugLog('⚠️ Error finding Overall Dtl of SMPS Rectifiers: $e');
        }
        
        if (overallRectifiersDtlItem != null) {
          final rectifiersDtlMap = Map<String, dynamic>.from(overallRectifiersDtlItem);
          // Preserve any updates made earlier (photo_id, photo_taken_ts)
          if (_rectifiersImagePhotoId != null && _rectifiersImagePhotoId!.isNotEmpty) {
            rectifiersDtlMap['photo_id'] = _rectifiersImagePhotoId;
            rectifiersDtlMap['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
          }
          modifiedAssetsWithAllProperties.add(rectifiersDtlMap);
          Logger.debugLog('✅ Added Overall Dtl of SMPS Rectifiers to post');
        } else {
          Logger.debugLog('⚠️ Overall Dtl of SMPS Rectifiers item not found in ${finalSMPSRectifiers.length} items');
          // Log the items to debug
          for (var item in finalSMPSRectifiers) {
            Logger.debugLog('  - Item record_type: ${item['record_type']}');
          }
        }
      }

      // Check if "Overall Dtl of SMPS" is already in the list
      bool hasSMPSDtl = modifiedAssetsWithAllProperties.any(
        (item) => item['record_type'] == 'Overall Dtl of SMPS',
      );
      
      if (!hasSMPSDtl) {
        // Find "Overall Dtl of SMPS" item using where().firstOrNull pattern
        dynamic overallSMPSDtlItem;
        try {
          final foundItems = finalSMPSAssets.where(
            (item) => item['record_type'] == 'Overall Dtl of SMPS',
          ).toList();
          if (foundItems.isNotEmpty) {
            overallSMPSDtlItem = foundItems.first;
          }
        } catch (e) {
          Logger.debugLog('⚠️ Error finding Overall Dtl of SMPS: $e');
        }
        
        if (overallSMPSDtlItem != null) {
          final smpsDtlMap = Map<String, dynamic>.from(overallSMPSDtlItem);
          // Preserve any updates made earlier (photo_id, photo_taken_ts)
          if (_smpsImagePhotoId != null && _smpsImagePhotoId!.isNotEmpty) {
            smpsDtlMap['photo_id'] = _smpsImagePhotoId;
            smpsDtlMap['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
          }
          modifiedAssetsWithAllProperties.add(smpsDtlMap);
          Logger.debugLog('✅ Added Overall Dtl of SMPS to post');
        } else {
          Logger.debugLog('⚠️ Overall Dtl of SMPS item not found in ${finalSMPSAssets.length} items');
          // Log the items to debug
          for (var item in finalSMPSAssets) {
            Logger.debugLog('  - Item record_type: ${item['record_type']}');
          }
        }
      }

      Logger.debugLog(
        '📊 SMPS V2: After adding Overall Dtl items - modifiedAssetsWithAllProperties: ${modifiedAssetsWithAllProperties.length}',
      );

      // Update local data
      final updated = await _service.updateDataInSqlite(
        siteAuditSchId: widget.siteAuditSchId,
        updatedData: _assetAuditData ?? {},
      );
      if (!updated) {
        throw Exception('Failed to update local SQLite data');
      }

      // Prepare data for posting
      var postObject = [...modifiedAssetsWithAllProperties, ...finalRemarks];

      Logger.debugLog(
        '📤 SMPS V2: Prepared ${postObject.length} items for posting',
      );
      Logger.debugLog(
        '📤 SMPS V2: modifiedAssetsWithAllProperties: ${modifiedAssetsWithAllProperties.length}, finalRemarks: ${finalRemarks.length}',
      );

      // Final check: If still empty, try one more time to add "Overall Dtl" items
      if (postObject.isEmpty) {
        Logger.debugLog('⚠️ SMPS V2: postObject is empty, attempting to add Overall Dtl items as fallback');
        
        // Try to add "Overall Dtl of SMPS Rectifiers" directly from finalSMPSRectifiers
        for (var item in finalSMPSRectifiers) {
          if (item['record_type'] == 'Overall Dtl of SMPS Rectifiers') {
            final rectifiersDtlMap = Map<String, dynamic>.from(item);
            if (_rectifiersImagePhotoId != null && _rectifiersImagePhotoId!.isNotEmpty) {
              rectifiersDtlMap['photo_id'] = _rectifiersImagePhotoId;
              rectifiersDtlMap['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
            }
            modifiedAssetsWithAllProperties.add(rectifiersDtlMap);
            Logger.debugLog('✅ Fallback: Added Overall Dtl of SMPS Rectifiers');
            break;
          }
        }
        
        // Try to add "Overall Dtl of SMPS" directly from finalSMPSAssets
        for (var item in finalSMPSAssets) {
          if (item['record_type'] == 'Overall Dtl of SMPS') {
            final smpsDtlMap = Map<String, dynamic>.from(item);
            if (_smpsImagePhotoId != null && _smpsImagePhotoId!.isNotEmpty) {
              smpsDtlMap['photo_id'] = _smpsImagePhotoId;
              smpsDtlMap['photo_taken_ts'] = Utils.getCurrentDateTimeForAPICall();
            }
            modifiedAssetsWithAllProperties.add(smpsDtlMap);
            Logger.debugLog('✅ Fallback: Added Overall Dtl of SMPS');
            break;
          }
        }
        
        // Rebuild postObject after fallback additions
        postObject = [...modifiedAssetsWithAllProperties, ...finalRemarks];
        
        if (postObject.isEmpty) {
          Logger.errorLog('❌ SMPS V2: Still empty after fallback, skipping API call to prevent server error');
          Logger.debugLog('❌ SMPS V2: modifiedAssetsWithAllProperties: ${modifiedAssetsWithAllProperties.length}, finalRemarks: ${finalRemarks.length}');
          return;
        } else {
          Logger.debugLog('✅ SMPS V2: Fallback added items, now have ${postObject.length} items');
        }
      }

      // Final safety check - absolutely prevent empty array posting
      if (postObject.isEmpty) {
        Logger.errorLog('❌ SMPS V2: CRITICAL - postObject is empty right before API call, aborting!');
        Logger.errorLog('❌ SMPS V2: This should never happen - check logic above');
        return;
      }

      Logger.debugLog('📤 SMPS V2: About to post ${postObject.length} items');
      Logger.debugLog('📤 SMPS V2: postObject content: ${postObject.map((e) => e['record_type'] ?? 'no record_type').toList()}');
      
      await ServiceLocator().assetAuditPostService.postAssetAuditDataWithPhotoReplacement(
        requests: postObject,
        isLastPage: AssetAuditNavigationHelper.getTelecomNextScreenName(_assetAuditData, _screenName) == 'SUBMIT',
        activityType: ActivityTypeEnum.assetAudit,
      );
      Logger.debugLog('SMPS V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog('SMPS V2: Error in postCurrentScreenData: $e');
      // Don't rethrow to prevent screen from losing data
      // Show error to user instead
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting data: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
            if (_hasFormDataChanges) {
              await postCurrentScreenData();
            }
          },
          onDiscard: () {},
        ),
      );
    } else {
      navigateBackOrToHome(
        context,
        targetContext: widget.parentContext,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomFormAppbar(
        title: 'SMPS',
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
                  child: _isLoadingData
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryGreen,
                          ),
                        )
                      : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _loadData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.only(
                            bottom:
                                MediaQuery.of(context).viewInsets.bottom + 100,
                          ),
                          child: Container(
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 16,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // SMPS Make (readonly)
                                CustomFormField(
                                  label: "SMPS Make",
                                  hintText:
                                      _displayFormData?['smpsMake'] ?? "N/A",
                                  isRequired: false,
                                  isEditable: false,
                                ),
                                getHeight(15),

                                // Count of SMPS (readonly) - Always show
                                CustomFormField(
                                  label: "Count of SMPS",
                                  hintText:
                                      _displayFormData?['smpsCount'] ?? "0",
                                  isRequired: false,
                                  isEditable: false,
                                ),
                                getHeight(15),

                                // Photo of SMPS - Always show
                                ImageUploadField(
                                  label: "Add Photo of SMPS",
                                  placeholder: "Add Photo",
                                  isRequired: true,
                                  externalImageUrl: _smpsImageData,
                                  onImageSelected: (image) async {
                                    if (image != null) {
                                      setState(() {
                                        _smpsImage = image;
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
                                            _smpsImagePhotoId = photoId;
                                            _smpsImageData = null; // Clear old image data when new image is uploaded
                                            _hasFormDataChanges = true;
                                          });
                                          Logger.debugLog('✅ SMPS image uploaded with ID: $photoId');
                                        }
                                      } catch (e) {
                                        Logger.errorLog('❌ Error uploading SMPS image: $e');
                                      }
                                    }
                                  },
                                ),
                                getHeight(15),

                                if (_displayFormData?['smpsCabinetAvailable'] ??
                                    false) ...[
                                  // SMPS Cabinet Section
                                  AssetAuditFormComponent(
                                    componentId: 'smps_cabinet_component',
                                    serialLabel: "Cabinet - Serial Number",
                                    serialHintText: "Cabinet Serial Number",
                                    photoLabel:
                                        "Add Photo of Cabinet Serial Number",
                                    serialController: TextEditingController(),
                                    initialSavedItems:
                                        _displayFormData?['smpsCabinet']
                                            as List<dynamic>? ??
                                        [],
                                    onItemSaved: _onSMPSCabinetItemSaved,
                                    onStatusChanged: (status) {},
                                    customValidator:
                                        _validateCabinetSerialNumber,
                                    customValidationErrorMessage:
                                        "Invalid SMPS Cabinet serial number. Please check and try again.",
                                    siteAuditSchId: widget.siteAuditSchId,
                                    showTable: true,
                                    tableTitle: "SMPS Cabinet",
                                  ),
                                  getHeight(20),
                                ],

                                // Count of SMPS Rectifiers (readonly) - Always show
                                CustomFormField(
                                  label: "Count of Rectifiers",
                                  hintText:
                                      _displayFormData?['smpsRectifiersCount'] ??
                                      "0",
                                  isRequired: false,
                                  isEditable: false,
                                ),
                                getHeight(15),

                                // Photo of all Rectifier - Always show
                                ImageUploadField(
                                  label: "Add Photo of all Rectifier",
                                  placeholder: "Add Photo",
                                  isRequired: true,
                                  externalImageUrl: _rectifiersImageData,
                                  onImageSelected: (image) async {
                                    if (image != null) {
                                      setState(() {
                                        _rectifiersImage = image;
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
                                            _rectifiersImagePhotoId = photoId;
                                            _rectifiersImageData = null; // Clear old image data when new image is uploaded
                                            _hasFormDataChanges = true;
                                          });
                                          Logger.debugLog('✅ SMPS Rectifiers image uploaded with ID: $photoId');
                                        }
                                      } catch (e) {
                                        Logger.errorLog('❌ Error uploading SMPS Rectifiers image: $e');
                                      }
                                    }
                                  },
                                ),
                                getHeight(15),

                                // SMPS Rectifiers Section - Always show
                                AssetAuditFormComponent(
                                  componentId: 'smps_rectifiers_component',
                                  serialLabel: "Rectifier - Serial Number",
                                  serialHintText: "Rectifier Serial Number",
                                  photoLabel: "Add a Photo",
                                  serialController: TextEditingController(),
                                  initialSavedItems:
                                      _displayFormData?['smpsRectifiers']
                                          as List<dynamic>? ??
                                      [],
                                  onItemSaved: _onSMPSRectifierItemSaved,
                                  onStatusChanged: (status) {},
                                  customValidator:
                                      _validateRectifierSerialNumber,
                                  customValidationErrorMessage:
                                      "Invalid SMPS Rectifiers serial number. Please check and try again.",
                                  siteAuditSchId: widget.siteAuditSchId,
                                  showTable: true,
                                  tableTitle: "SMPS Rectifiers",
                                ),
                                getHeight(20),

                                // Add Remarks
                                CustomRemarksField(
                                  label: "Add Remarks",
                                  hintText: "Remarks",
                                  controller: _remarksController,
                                ),
                                getHeight(20),
                              ],
                            ),
                          ),
                        ),
                ),

                // Bottom buttons using your specific format
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
}
