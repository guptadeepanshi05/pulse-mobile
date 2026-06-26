import 'package:app/app_config.dart';
import 'package:app/commonWidgets/cctv_form_component.dart';
import 'package:app/commonWidgets/asset_audit_telecom_bottom_buttons.dart';
import 'package:app/commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import 'package:app/commonWidgets/custom_form_appbar.dart';
import 'package:app/commonWidgets/custom_form_field.dart';
import 'package:app/commonWidgets/custom_remark.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/extensions/string_extension.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/screens/asset_audit/asset_audit_widget_helper/WidgetHelper.dart';
import 'package:app/services/asset_audit/central_asset_audit_service.dart';
import 'package:app/services/asset_audit/central_service_initializer.dart';
import 'package:app/services/asset_audit_post_service.dart';
import 'package:app/services/image_upload_service.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:app/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../../services/service_locator.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';

class CCTVV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const CCTVV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<CCTVV2Screen> createState() => _CCTVV2ScreenState();
}

class _CCTVV2ScreenState extends State<CCTVV2Screen> {
  final String _screenName = 'CCTV';

  // Service
  late CentralAssetAuditService _service;

  // Data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Controllers
  final TextEditingController _cctvSerialController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  // State
  bool _isLoadingData = false;
  String? _errorMessage;
  bool _hasFormDataChanges = false;

  // Section visibility states
  bool _showCCTVDetails = false;

  String hooterAvailableValue = 'No';

  @override
  void initState() {
    super.initState();
    _service = ServiceLocator().centralAssetAuditService;
    _loadData();
  }

  @override
  void dispose() {
    _cctvSerialController.dispose();
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
        '🔄 Surveillance V2: Loading data for site ${widget.siteAuditSchId}',
      );

      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        final cctvItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>? ??
            {};

        // Parse CCTV data
        final cctvAssets = cctvItems['assets'] as List<dynamic>? ?? [];
        final hooterAssets = cctvItems['Hooter'] as List<dynamic>? ?? [];
        final remarksData = cctvItems['remarks'] as List<dynamic>? ?? [];

        // Extract CCTV height from first asset if available
        String? cctvHeight;
        if (cctvAssets.isNotEmpty) {
          final firstAsset = cctvAssets.first as Map<String, dynamic>?;
          cctvHeight =
              firstAsset?['capacity']?.toString() ??
              firstAsset?['height']?.toString() ??
              firstAsset?['cctv_height']?.toString();
        }

        // Map dimension_value to customFieldValue for saved items
        final cctvAssetsWithCustomField = cctvAssets.map((asset) {
          final assetMap = Map<String, dynamic>.from(asset);
          // Map dimension_value to customFieldValue for form component
          if (assetMap['dimension_value'] != null) {
            assetMap['customFieldValue'] = assetMap['dimension_value'];
          }
          return assetMap;
        }).toList();

        final formData = <String, dynamic>{
          'hooterAvailable': hooterAssets.isNotEmpty,
          'cctvAvailable': cctvAssets.isNotEmpty ? "Yes" : "No",
          'cctvCount': cctvAssets.length.toString(),
          'cctvHeight': cctvHeight ?? 'N/A',
          'cctvAssets': cctvAssetsWithCustomField
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'cctvAllAssets': cctvAssetsWithCustomField,
          'remarksAvailable': remarksData.isNotEmpty,
          'remarks': remarksData.isNotEmpty
              ? remarksData.first['item_type_remark']?.toString() ?? ""
              : "",
        };

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
          hooterAvailableValue = hooterAssets.isNotEmpty
              ? (hooterAssets.first?['asset_status']?.toString() ?? 'No')
              : 'No';
          _showCCTVDetails = cctvAssets.isNotEmpty;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeFormControllers(formData);
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'Failed to load Surveillance data';
        });
      }
    } catch (e) {
      Logger.errorLog('❌ Surveillance V2: Error loading data: $e');
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  void _initializeFormControllers(Map<String, dynamic> formData) {
    final remarks = formData['remarks'] ?? "";
    _remarksController.text = remarks;
    // Add listeners for form changes
    _remarksController.addListener(_onFormChanged);
    Logger.debugLog('📝 Initialized remarks controller with: $remarks');
    if (mounted) {
      setState(() {});
    }
  }

  // Callback method for AssetAuditFormComponent
  void _onCCTVItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['cctvAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  // Validation method
  bool _validateCCTVSerialNumber(String serialNumber, bool isQRCodeScanned) {
    final savedItems =
        _displayFormData?['cctvAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 Surveillance V2: Starting postCurrentScreenData');

      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'TELECOM',
          )];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];
      final finalCCTVAssets = finalData?['assets'] as List<dynamic>? ?? [];
      final finalHooterData = finalData?['Hooter'] as List<dynamic>? ?? [];

      // Collect modified assets
      final modifiedAssetsWithAllProperties = <dynamic>[];

      //update hooter
      if (finalHooterData.isNotEmpty) {
        finalHooterData.first['asset_status'] = hooterAvailableValue;
        modifiedAssetsWithAllProperties.add(finalHooterData.first);
      }

      // Add CCTV assets
      final modifiedCCTVAssets =
          _displayFormData?['cctvAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalCCTVAssets,
          modifiedCCTVAssets,
        ),
      );

      // Update remarks in-memory too so SQLite/open-back shows latest value.
      final String remark = _remarksController.text;
      if (finalRemarks.isNotEmpty) {
        try {
          finalRemarks.first['item_type_remark'] = remark;
          if (remark.isNotEmpty) {
            Logger.debugLog('✅ Updated remarks: $remark');
          }
        } catch (e) {
          Logger.errorLog('❌ Error updating remarks: $e');
        }
      }

      // Update local data
      final updated = await _service.updateDataInSqlite(
        siteAuditSchId: widget.siteAuditSchId,
        updatedData: _assetAuditData ?? {},
      );
      if (!updated) {
        throw Exception('Failed to update local SQLite data');
      }

      // Prepare data for posting
      final postObject = [...modifiedAssetsWithAllProperties, ...finalRemarks];

      Logger.debugLog(
        '📤 Surveillance V2: Prepared ${postObject.length} items for posting',
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

      Logger.debugLog('✅ Surveillance V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog('❌ Surveillance V2: Error in postCurrentScreenData: $e');
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
            if (_hasFormDataChanges) {
              await postCurrentScreenData();
            }
          },
          onDiscard: () {},
        ),
      );
    } else {
      navigateBackOrToHome(context, targetContext: widget.parentContext);
    }
  }

  void _onHooterValueChanged(String value) {
    setState(() {
      hooterAvailableValue = value;
      _hasFormDataChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomFormAppbar(
        title: 'Surveillance',
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
                                      'Loading Surveillance data...',
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
                                  'No Surveillance data available',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_displayFormData?['hooterAvailable'] || false) ...[
          WidgetHelper.buildRadioField(
            label: "Hooter Available",
            isRequired: true,
            initialSelectedValue: hooterAvailableValue.capitalize() ?? "No",
            onChanged: _onHooterValueChanged,
          ),
          getHeight(15),
        ],

        // CCTV Available
        WidgetHelper.buildDisabledRadioField(
          label: "CCTV Available",
          isRequired: false,
          initialSelectedValue: _displayFormData?['cctvAvailable'] ?? "No",
        ),
        getHeight(15),

        // CCTV Details Section (only show if available)
        if (_showCCTVDetails) ...[
          // Count of CCTV
          CustomFormField(
            label: "Count of CCTV",
            initialValue: _displayFormData?['cctvCount']?.toString() ?? "0",
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),

          const Text(
            "CCTV Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          getHeight(15),

          // CCTV Form Component
          CctvFormComponent(
            componentId: 'cctv_component',
            serialLabel: "CCTV - Serial Number",
            serialHintText: "CCTV Serial Number",
            photoLabel: "Add a Photo",
            serialController: _cctvSerialController,
            initialSavedItems:
                _displayFormData?['cctvAssets'] as List<dynamic>? ?? [],
            onItemSaved: _onCCTVItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateCCTVSerialNumber,
            customValidationErrorMessage:
                "Invalid CCTV serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "CCTV Items",
            customFieldLabel: "CCTV Height (in Meter)",
            customFieldValue:
                _displayFormData?['dimension_value']?.toString() ?? 'N/A',
          ),
          getHeight(15),
        ],

        if (_displayFormData?['remarksAvailable']! ?? false) ...[
          // Remarks using CustomRemarksField
          CustomRemarksField(
            label: "Add Remarks",
            hintText: "Remarks",
            controller: _remarksController,
          ),
        ],
      ],
    );
  }
}
