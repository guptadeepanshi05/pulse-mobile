import 'dart:io';

import 'package:app/enum/activity_type_enum.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/screens/asset_audit/asset_audit_widget_helper/WidgetHelper.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../../../commonWidgets/custom_form_appbar.dart';
import '../../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../../commonWidgets/custom_dialogs/serial_number_mismatch_dialog.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';
import '../../../commonWidgets/simple_asset_audit_form_component.dart';
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
import '../../../services/asset_audit/central_service_initializer.dart';
import '../../../services/asset_audit/central_asset_audit_service.dart';
import '../../../services/asset_audit_post_service.dart';
import '../../../services/image_upload_service.dart';
import '../../../app_config.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class BatteryV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const BatteryV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<BatteryV2Screen> createState() => _BatteryV2ScreenState();
}

class _BatteryV2ScreenState extends State<BatteryV2Screen> {
  final String _screenName = 'Battery';

  // Service
  late CentralAssetAuditService _service;

  // Data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Controllers for each section
  final TextEditingController _batteryCabinetSerialController =
      TextEditingController();
  final TextEditingController _cbmsSerialController = TextEditingController();
  final TextEditingController _batterySerialController =
      TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  // State
  bool _isLoadingData = false;
  String? _errorMessage;
  bool _hasFormDataChanges = false;

  // Section visibility states
  bool _showCbmsDetails = false;

  // Battery modules image
  File? _batteryModulesImage;
  String? _batteryModulesPhotoId;
  String? _batteryModulesImageData;

  @override
  void initState() {
    super.initState();
    _service = ServiceLocator().centralAssetAuditService;
    _loadData();
  }

  @override
  void dispose() {
    _batteryCabinetSerialController.dispose();
    _cbmsSerialController.dispose();
    _batterySerialController.dispose();
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

  String? _getBatteryCabinetValue(String key) {
    // Handle special case for image_data
    if (key == 'image_data') {
      return _displayFormData?['batteryCabinetImageData']?.toString();
    }

    final assets = _displayFormData?['batteryCabinetAllAssets'] as List?;
    if (assets?.isNotEmpty == true) {
      return assets!.first[key]?.toString();
    }
    return null;
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoadingData = true;
        _errorMessage = null;
      });

      Logger.debugLog(
        '🔄 Battery V2: Loading data for site ${widget.siteAuditSchId}',
      );

      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        final batteryItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>? ??
            {};

        // Parse Battery data
        final batteryCabinetAssets =
            batteryItems['Battery Cabinet'] as List<dynamic>? ?? [];
        final cbmsAssets = batteryItems['CBMS'] as List<dynamic>? ?? [];
        final batteryAssets = batteryItems['assets'] as List<dynamic>? ?? [];
        final remarksData = batteryItems['remarks'] as List<dynamic>? ?? [];

        // Fetch image data for battery cabinet if photo_id exists
        String? batteryCabinetImageData;
        if (batteryCabinetAssets.isNotEmpty &&
            batteryCabinetAssets.first?['photo_id'] != null) {
          final photoId = batteryCabinetAssets.first!['photo_id'].toString();
          Logger.debugLog(
            '📸 Loading battery cabinet image with photo_id: $photoId',
          );
          try {
            batteryCabinetImageData = await _service.getImageAsDataUrl(photoId);
            Logger.debugLog('✅ Successfully loaded battery cabinet image');
          } catch (e) {
            Logger.errorLog('❌ Error loading battery cabinet image: $e');
          }
        } else {
          Logger.debugLog('📸 No photo_id found for battery cabinet');
        }

        // Extract battery modules photo and remarks from "Overall Dtl of Battery"
        String? batteryModulesImageData;
        final overallDtlItem = batteryAssets
            .where((item) => item['record_type'] == 'Overall Dtl of Battery')
            .firstOrNull;
        if (overallDtlItem != null && overallDtlItem['photo_id'] != null) {
          final photoId = overallDtlItem['photo_id'].toString();
          Logger.debugLog(
            '📸 Loading battery modules image with photo_id: $photoId',
          );
          try {
            batteryModulesImageData = await _service.getImageAsDataUrl(photoId);
            Logger.debugLog('✅ Successfully loaded battery modules image');
          } catch (e) {
            Logger.errorLog('❌ Error loading battery modules image: $e');
          }
        } else {
          Logger.debugLog('No Overall Dtl of Battery item found');
        }

        final formData = <String, dynamic>{
          'cbmsAvailable': cbmsAssets.isNotEmpty ? "Yes" : "No",
          'capacity': batteryAssets.isNotEmpty ? batteryAssets.first['capacity']?.toString() ?? 'N/A' : 'N/A',
          'batteryCabinetAssets': batteryCabinetAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'batteryCabinetAllAssets': batteryCabinetAssets,
          'batteryCabinetAvailable': batteryCabinetAssets.isNotEmpty,
          'batteryCabinetSerial': batteryCabinetAssets.isNotEmpty ? batteryCabinetAssets.first['mfg_serial_no'] : null,
          'batteryCabinetPhotoId': batteryCabinetAssets.isNotEmpty ? batteryCabinetAssets.first['photo_id'] : null,
          'batteryCabinetImageData': batteryCabinetImageData,
          'batteryCabinetOemName': batteryCabinetAssets.isNotEmpty ? batteryCabinetAssets.first['oem_name']?.toString() ?? '' : '',
          'cbmsAssets': cbmsAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'cbmsAllAssets': cbmsAssets,
          // Filter out "Overall Dtl" items from saved items list
          'batteryAssets': batteryAssets
              .where((obj) => 
                  obj['photo_id'] != null && 
                  obj['record_type'] != 'Overall Dtl of Battery')
              .toList(),
          'batteryAllAssets': batteryAssets,
          'batteryModulesImageData': batteryModulesImageData,
          'remarks': remarksData.isNotEmpty
              ? remarksData.first['item_type_remark']?.toString() ?? ""
              : "",
        };

        // Store battery modules photo_id if exists
        final overallDtlItemForStore = batteryAssets
            .where((item) => item['record_type'] == 'Overall Dtl of Battery')
            .firstOrNull;
        if (overallDtlItemForStore != null &&
            overallDtlItemForStore['photo_id'] != null) {
          _batteryModulesPhotoId =
              overallDtlItemForStore['photo_id'].toString();
          _batteryModulesImageData = batteryModulesImageData;
        }

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
          _showCbmsDetails = cbmsAssets.isNotEmpty;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeFormControllers(formData);
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'Failed to load Battery data';
        });
      }
    } catch (e) {
      Logger.errorLog('❌ Battery V2: Error loading data: $e');
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  void _initializeFormControllers(Map<String, dynamic> formData) {
    final remarks = formData['remarks'] ?? "";
    _remarksController.text = remarks;
    _remarksController.addListener(_onFormChanged);
    Logger.debugLog('📝 Initialized remarks controller with: $remarks');
    if (mounted) {
      setState(() {});
    }

    // Initialize cabinet serial number controller
    if (formData['batteryCabinetPhotoId'] != null) {
      _batteryCabinetSerialController.text =
          formData['batteryCabinetSerial'] ?? "";
      Logger.debugLog(
        '📝 Initialized battery cabinet serial controller with existing photo_id: ${formData['batteryCabinetPhotoId']}',
      );
    } else {
      _batteryCabinetSerialController.text = "";
      Logger.debugLog(
        '📝 Initialized battery cabinet serial controller as empty (no existing photo)',
      );
    }
  }

  // Callback methods for each AssetAuditFormComponent
  void _onBatteryCabinetItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['batteryCabinetAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  void _onCbmsItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['cbmsAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  void _onBatteryItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['batteryAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  // Validation methods for each section
  bool _validateBatteryCabinetSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['batteryCabinetAllAssets'] as List<dynamic>? ?? [];

    final isValid = AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );

    // If validation fails, show popup
    if (!isValid && serialNumber.isNotEmpty) {
      _showBatteryCabinetSerialNumberMismatchDialog(serialNumber);
    } else {
      serialNumber = '';
    }

    return isValid;
  }

  // Show dialog when battery cabinet serial number doesn't match
  void _showBatteryCabinetSerialNumberMismatchDialog(
    String enteredSerialNumber,
  ) {
    SerialNumberMismatchDialog.show(context);
  }

  bool _validateCbmsSerialNumber(String serialNumber, bool isQRCodeScanned) {
    final savedItems =
        _displayFormData?['cbmsAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  bool _validateBatterySerialNumber(String serialNumber, bool isQRCodeScanned) {
    final savedItems =
        _displayFormData?['batteryAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 Battery V2: Starting postCurrentScreenData');

      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'TELECOM',
          )];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];
      final finalBatteryCabinetAssets =
          finalData?['Battery Cabinet'] as List<dynamic>? ?? [];
      final finalCbmsAssets = finalData?['CBMS'] as List<dynamic>? ?? [];
      final finalBatteryAssets = finalData?['assets'] as List<dynamic>? ?? [];

      // Collect all modified assets
      final modifiedAssetsWithAllProperties = <dynamic>[];

      // Add Battery Cabinet assets
      final modifiedBatteryCabinetAssets =
          _displayFormData?['batteryCabinetAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalBatteryCabinetAssets,
          modifiedBatteryCabinetAssets,
        ),
      );

      // Add CBMS assets
      final modifiedCbmsAssets =
          _displayFormData?['cbmsAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalCbmsAssets,
          modifiedCbmsAssets,
        ),
      );

      // Add Battery assets
      final modifiedBatteryAssets =
          _displayFormData?['batteryAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalBatteryAssets,
          modifiedBatteryAssets,
        ),
      );

      // Update "Overall Dtl of Battery" item with photo
      final overallDtlItem = finalBatteryAssets
          .where((item) => item['record_type'] == 'Overall Dtl of Battery')
          .firstOrNull;
      if (overallDtlItem != null) {
        final overallDtlMap = Map<String, dynamic>.from(overallDtlItem);

        // Update photo_id if battery modules image was uploaded
        if (_batteryModulesPhotoId != null &&
            _batteryModulesPhotoId!.isNotEmpty) {
          overallDtlMap['photo_id'] = _batteryModulesPhotoId;
          overallDtlMap['photo_taken_ts'] =
              Utils.getCurrentDateTimeForAPICall();
          Logger.debugLog(
            '✅ Updated Overall Dtl of Battery with photo_id: $_batteryModulesPhotoId',
          );
        }

        // Add to modified assets if there are changes
        if (_batteryModulesPhotoId != null &&
            _batteryModulesPhotoId!.isNotEmpty) {
          modifiedAssetsWithAllProperties.add(overallDtlMap);
        }

        // Also update in _assetAuditData for local storage
        final overallDtlIndex = finalBatteryAssets.indexWhere(
          (item) => item['record_type'] == 'Overall Dtl of Battery',
        );
        if (overallDtlIndex != -1) {
          if (_batteryModulesPhotoId != null &&
              _batteryModulesPhotoId!.isNotEmpty) {
            finalBatteryAssets[overallDtlIndex]['photo_id'] =
                _batteryModulesPhotoId;
            finalBatteryAssets[overallDtlIndex]['photo_taken_ts'] =
                Utils.getCurrentDateTimeForAPICall();
          }
        }
      } else {
        Logger.debugLog('No Overall Dtl of Battery item found');
      }

      // Update remarks
      final String remark = _remarksController.text;
      if (remark.isNotEmpty && finalRemarks.isNotEmpty) {
        try {
          finalRemarks.first['item_type_remark'] = remark;
          Logger.debugLog('✅ Updated remarks: $remark');
        } catch (e) {
          Logger.errorLog('❌ Error updating remarks: $e');
        }
      }

      // Update local data
      _service.updateDataInSqlite(
        siteAuditSchId: widget.siteAuditSchId,
        updatedData: _assetAuditData ?? {},
      );

      // Prepare data for posting
      final postObject = [...modifiedAssetsWithAllProperties, ...finalRemarks];

      Logger.debugLog(
        '📤 Battery V2: Prepared ${postObject.length} items for posting',
      );
      // Post data with photo ID replacement
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

      Logger.debugLog('✅ Battery V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog('❌ Battery V2: Error in postCurrentScreenData: $e');
      rethrow;
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
            await postCurrentScreenData();
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
        title: 'Battery',
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
                                      'Loading Battery data...',
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
                                color: AppColors.errorColor.withOpacity(0.1),
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
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.errorColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
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

                          // Show form when data is loaded
                          if (!_isLoadingData &&
                              _errorMessage == null &&
                              _displayFormData != null)
                            _buildFormFields(),

                          // Show message when no data
                          if (!_isLoadingData &&
                              _errorMessage == null &&
                              _displayFormData == null)
                            Container(
                              padding: const EdgeInsets.all(20),
                              child: const Center(
                                child: Text(
                                  'No Battery data available',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
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

  Widget _buildFormFields() {
    // Calculate Battery Modules count only for items with record_type == "Asset"
    final allBatteries = _displayFormData?['batteryAllAssets'] as List<dynamic>? ?? [];
    final batteryCountInt = allBatteries
        .where((item) => item['record_type']?.toString() == 'Asset')
        .length;
    final batteryCount = batteryCountInt.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CBMS Availability
        WidgetHelper.buildDisabledRadioField(
          label: "CBMS Available",
          isRequired: false,
          initialSelectedValue: _displayFormData?['cbmsAvailable'] ?? "No",
        ),
        getHeight(15),

        // CBMS Details Section (only show if available)
        if (_showCbmsDetails) ...[
          const Text(
            "CBMS Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          getHeight(15),

          // CBMS Form Component
          AssetAuditFormComponent(
            componentId: 'cbms_component',
            serialLabel: "CBMS - Serial Number",
            serialHintText: "CBMS Serial Number",
            photoLabel: "Add a Photo",
            serialController: _cbmsSerialController,
            initialSavedItems:
                _displayFormData?['cbmsAssets'] as List<dynamic>? ?? [],
            onItemSaved: _onCbmsItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateCbmsSerialNumber,
            customValidationErrorMessage:
                "Invalid CBMS serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "CBMS Items",
          ),
          getHeight(20),
        ],
        if (_displayFormData?['batteryCabinetAvailable'] || false) ...[
          // Battery Make field
          CustomFormField(
            label: "Battery Make",
            initialValue: _displayFormData?['batteryCabinetOemName']?.toString() ?? '',
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),
          const Text(
            "Battery Cabinet Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          getHeight(15),
          // Battery Cabinet Form Component
          SimpleAssetAuditFormComponent(
            componentId: 'battery_cabinet_component',
            serialLabel: "Battery Cabinet - Serial Number",
            serialHintText: "Battery Cabinet Serial Number",
            photoLabel: "Add a Photo",
            serialController: _batteryCabinetSerialController,
            initialSerialValue: _getBatteryCabinetValue('mfg_serial_no'),
            initialPhotoId: _getBatteryCabinetValue('photo_id'),
            initialImageData: _getBatteryCabinetValue('image_data'),
            onDataChanged: (photoId, imageData, isQRCodeScanned, qrCodeScannedTs) {
              // Update the battery cabinet data
              if ((_displayFormData?['batteryCabinetAllAssets'] as List?)
                      ?.isNotEmpty ==
                  true) {
                final cabinet =
                    (_displayFormData!['batteryCabinetAllAssets'] as List)
                        .first;

                // Validate battery cabinet serial number and capture the result
                final isValidSerial = _validateBatteryCabinetSerialNumber(
                  _batteryCabinetSerialController.text,
                  isQRCodeScanned ?? false,
                );

                // Only update cabinet data if serial number is valid
                if (isValidSerial) {
                  cabinet['photo_id'] = photoId;
                  cabinet['image_data'] = imageData;
                  cabinet['qr_code_scanned'] = isQRCodeScanned;
                  cabinet['qr_code_scanned_ts'] = qrCodeScannedTs;
                  cabinet['asset_status'] = 'OK';
                  _onBatteryCabinetItemSaved([cabinet]);
                } else {
                  _batteryCabinetSerialController.text = '';
                }
              }
            },
            siteAuditSchId: widget.siteAuditSchId,
          ),
          getHeight(20),
        ],
        // Count of Battery Modules (only items with record_type == "Asset")
        CustomFormField(
          label: "Count of Battery Modules",
          initialValue: batteryCount,
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),

        // Photo of Battery Modules
        ImageUploadField(
          label: "Add Photo of Battery Modules",
          placeholder: "Add Photo",
          isRequired: true,
          externalImageUrl: _batteryModulesImageData,
          onImageSelected: (image) async {
            if (image != null) {
              setState(() {
                _batteryModulesImage = image;
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
                    _batteryModulesPhotoId = photoId;
                    _batteryModulesImageData = null; // Clear old image data when new image is uploaded
                    _hasFormDataChanges = true;
                  });
                  Logger.debugLog('✅ Battery modules image uploaded with ID: $photoId');
                }
              } catch (e) {
                Logger.errorLog('❌ Error uploading battery modules image: $e');
              }
            }
          },
        ),
        getHeight(15),

        // Battery Details Section - only show if batteryCount > 0
        if (batteryCountInt > 0) ...[
          const Text(
            "Battery Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),

          // Battery Form Component
          AssetAuditFormComponent(
            componentId: 'battery_component',
            serialLabel: "Battery - Serial Number",
            serialHintText: "Battery Serial Number",
            photoLabel: "Add a Photo",
            disabledFieldLabel: "Capacity",
            disabledFieldValue:
                _displayFormData?['capacity']?.toString() ?? 'N/A',
            serialController: _batterySerialController,
            initialSavedItems:
                _displayFormData?['batteryAssets'] as List<dynamic>? ?? [],
            onItemSaved: _onBatteryItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateBatterySerialNumber,
            customValidationErrorMessage:
                "Invalid Battery serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "Battery Items",
            onSerialNumberLookup: (serialNumber) {
              // Look up capacity from batteryAllAssets based on serial number
              final allBatteries =
                  _displayFormData?['batteryAllAssets'] as List<dynamic>? ?? [];
              final matchingItem = allBatteries.where((item) {
                final mfgSerial = item['mfg_serial_no']?.toString() ?? '';
                final nexgenSerial = item['nexgen_serial_no']?.toString() ?? '';
                // Case-insensitive comparison to handle QR scan uppercase
                return mfgSerial.toUpperCase() == serialNumber.toUpperCase() ||
                    nexgenSerial.toUpperCase() == serialNumber.toUpperCase();
              }).firstOrNull;
              if (matchingItem == null) {
                Logger.debugLog(
                  'No matching Battery found for serial number: $serialNumber',
                );
                return null;
              }
              return {
                'capacity': matchingItem['capacity']?.toString() ?? '',
              };
            },
          ),
          getHeight(20),
        ],

        // Remarks using CustomRemarksField
        CustomRemarksField(
          label: "Add Remarks",
          hintText: "Remarks",
          controller: _remarksController,
        ),
      ],
    );
  }
}