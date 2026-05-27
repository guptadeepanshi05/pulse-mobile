import 'package:app/enum/activity_type_enum.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/screens/asset_audit/asset_audit_widget_helper/WidgetHelper.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../../../commonWidgets/asset_audit_telecom_bottom_buttons.dart';
import '../../../commonWidgets/custom_form_appbar.dart';
import '../../../commonWidgets/custom_form_field.dart';
import '../../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';
import '../../../commonWidgets/custom_remark.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_images.dart';
import '../../../constants/constants_methods.dart';
import '../../../services/service_locator.dart';
import '../../../utils/logger.dart';
import '../../../services/asset_audit/central_service_initializer.dart';
import '../../../services/asset_audit/central_asset_audit_service.dart';
import '../../../services/asset_audit_post_service.dart';
import '../../../services/image_upload_service.dart';
import '../../../app_config.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class FireExtinguisherTelecomV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const FireExtinguisherTelecomV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<FireExtinguisherTelecomV2Screen> createState() =>
      _FireExtinguisherTelecomV2ScreenState();
}

class _FireExtinguisherTelecomV2ScreenState
    extends State<FireExtinguisherTelecomV2Screen> {
  final String _screenName = 'Fire Extinguisher';

  // Service
  late CentralAssetAuditService _service;

  // Data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Controllers for each section
  final TextEditingController _fireExtinguisherSerialController =
      TextEditingController();
  final TextEditingController _floodLightSerialController =
      TextEditingController();
  final TextEditingController _sandBucketSerialController =
      TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  // State
  bool _isLoadingData = false;
  String? _errorMessage;
  bool _hasFormDataChanges = false;

  // Section visibility states
  bool _showFireExtinguisherDetails = false;
  bool _showFloodLightDetails = false;
  bool _showSandBucketDetails = false;

  @override
  void initState() {
    super.initState();
    _service = ServiceLocator().centralAssetAuditService;
    _loadData();
  }

  @override
  void dispose() {
    _fireExtinguisherSerialController.dispose();
    _floodLightSerialController.dispose();
    _sandBucketSerialController.dispose();
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
        '🔄 Fire Extinguisher V2: Loading data for site ${widget.siteAuditSchId}',
      );

      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        final fireExtinguisherItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>? ??
            {};

        // Parse Fire Extinguisher data
        final fireExtinguisherAssets =
            fireExtinguisherItems['assets'] as List<dynamic>? ?? [];
        final floodLightAssets =
            fireExtinguisherItems['Flood Light'] as List<dynamic>? ?? [];
        final sandBucketAssets =
            fireExtinguisherItems['Sand Bucket'] as List<dynamic>? ?? [];
        final remarksData =
            fireExtinguisherItems['remarks'] as List<dynamic>? ?? [];

        final formData = <String, dynamic>{
          'fireExtinguisherAvailable': fireExtinguisherAssets.isNotEmpty
              ? "Yes"
              : "No",
          'fireExtinguisherCount': fireExtinguisherAssets.length.toString(),
          'floodLightAvailable': floodLightAssets.isNotEmpty ? "Yes" : "No",
          'sandBucketCount': sandBucketAssets.length.toString(),
          'capacity': fireExtinguisherAssets.isNotEmpty
              ? fireExtinguisherAssets.first['capacity']?.toString() ?? 'N/A'
              : 'N/A',
          'fireExtinguisherAssets': fireExtinguisherAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'fireExtinguisherAllAssets': fireExtinguisherAssets,
          'floodLightAssets': floodLightAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'floodLightAllAssets': floodLightAssets,
          'sandBucketAssets': sandBucketAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'sandBucketAllAssets': sandBucketAssets,
          'remarks': remarksData.isNotEmpty
              ? remarksData.first['item_type_remark']?.toString() ?? ""
              : "",
        };

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
          _showFireExtinguisherDetails = fireExtinguisherAssets.isNotEmpty;
          _showFloodLightDetails = floodLightAssets.isNotEmpty;
          _showSandBucketDetails = sandBucketAssets.isNotEmpty;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeFormControllers(formData);
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'Failed to load Fire Extinguisher data';
        });
      }
    } catch (e) {
      Logger.errorLog('❌ Fire Extinguisher V2: Error loading data: $e');
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
  }

  // Callback methods for each AssetAuditFormComponent
  void _onFireExtinguisherItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['fireExtinguisherAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  void _onFloodLightItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['floodLightAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  void _onSandBucketItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['sandBucketAssets'] = [...items];
    setState(() {
      _hasFormDataChanges = true;
    });
  }

  // Validation methods for each section
  bool _validateFireExtinguisherSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['fireExtinguisherAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  bool _validateFloodLightSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['floodLightAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  bool _validateSandBucketSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['sandBucketAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog(
        '📤 Fire Extinguisher V2: Starting postCurrentScreenData',
      );

      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'TELECOM',
          )];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];
      final finalFireExtinguisherAssets =
          finalData['assets'] as List<dynamic>? ?? [];
      final finalFloodLightAssets =
          finalData['Flood Light'] as List<dynamic>? ?? [];
      final finalSandBucketAssets =
          finalData['Sand Bucket'] as List<dynamic>? ?? [];

      // Collect all modified assets
      final modifiedAssetsWithAllProperties = <dynamic>[];

      // Add Fire Extinguisher assets
      final modifiedFireExtinguisherAssets =
          _displayFormData?['fireExtinguisherAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalFireExtinguisherAssets,
          modifiedFireExtinguisherAssets,
        ),
      );

      // Add Flood Light assets
      final modifiedFloodLightAssets =
          _displayFormData?['floodLightAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalFloodLightAssets,
          modifiedFloodLightAssets,
        ),
      );

      // Add Flood Light assets
      final modifiedSandBucketAssets =
          _displayFormData?['sandBucketAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalSandBucketAssets,
          modifiedSandBucketAssets,
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
        '📤 Fire Extinguisher V2: Prepared ${postObject.length} items for posting',
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

      Logger.debugLog('✅ Fire Extinguisher V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog(
        '❌ Fire Extinguisher V2: Error in postCurrentScreenData: $e',
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomFormAppbar(
        title: 'Fire Extinguisher',
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
                                      'Loading Fire Extinguisher data...',
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
                                  'No Fire Extinguisher data available',
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
        // Fire Extinguisher Available
        WidgetHelper.buildDisabledRadioField(
          label: "Fire Extinguisher Available",
          isRequired: false,
          initialSelectedValue:
              _displayFormData?['fireExtinguisherAvailable'] ?? "No",
        ),
        getHeight(15),

        // Fire Extinguisher Details Section (only show if available)
        if (_showFireExtinguisherDetails) ...[
          // Count of Fire Extinguisher
          CustomFormField(
            label: "Count of Fire Extinguisher",
            initialValue:
                _displayFormData?['fireExtinguisherCount']?.toString() ?? "0",
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),

          const Text(
            "Fire Extinguisher Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),

          // Fire Extinguisher Form Component
          AssetAuditFormComponent(
            componentId: 'fire_extinguisher_component',
            serialLabel: "Fire Extinguisher - Serial Number",
            serialHintText: "Fire Extinguisher Serial Number",
            photoLabel: "Add a Photo",
            disabledFieldLabel: "Capacity of Fire Extinguisher (In Kg)",
            serialController: _fireExtinguisherSerialController,
            initialSavedItems:
                _displayFormData?['fireExtinguisherAssets'] as List<dynamic>? ??
                [],
            onItemSaved: _onFireExtinguisherItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateFireExtinguisherSerialNumber,
            customValidationErrorMessage:
                "Invalid Fire Extinguisher serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "Fire Extinguisher Items",
            onSerialNumberLookup: (serialNumber) {
              // Look up capacity from fireExtinguisherAllAssets based on serial number
              final allAssets =
                  _displayFormData?['fireExtinguisherAllAssets']
                      as List<dynamic>? ??
                  [];
              final matchingAsset = allAssets
                  .where(
                    (asset) =>
                        asset['mfg_serial_no']?.toString().toUpperCase() ==
                            serialNumber.toUpperCase() ||
                        asset['nexgen_serial_no']?.toString().toUpperCase() ==
                            serialNumber.toUpperCase(),
                  )
                  .firstOrNull;
              if (matchingAsset != null && matchingAsset['capacity'] != null) {
                return {'capacity': matchingAsset['capacity'].toString()};
              }
              return null;
            },
          ),
          getHeight(15),
        ],

        // Flood Light Availability
        WidgetHelper.buildDisabledRadioField(
          label: "Flood Light Availability",
          isRequired: false,
          initialSelectedValue:
              _displayFormData?['floodLightAvailable'] ?? "No",
        ),
        getHeight(15),

        // Flood Light Details Section (only show if available)
        if (_showFloodLightDetails) ...[
          const Text(
            "Flood Light Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          getHeight(15),

          // Flood Light Form Component
          AssetAuditFormComponent(
            componentId: 'flood_light_component',
            serialLabel: "Flood Light - Serial Number",
            serialHintText: "Flood Light Serial Number",
            photoLabel: "Add a Photo",
            serialController: _floodLightSerialController,
            initialSavedItems:
                _displayFormData?['floodLightAssets'] as List<dynamic>? ?? [],
            onItemSaved: _onFloodLightItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateFloodLightSerialNumber,
            customValidationErrorMessage:
                "Invalid Flood Light serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "Flood Light Items",
          ),
          getHeight(15),
        ],
        if (_showSandBucketDetails) ...[
          // Count of Sand Buckets
          CustomFormField(
            label: "Count of Sand Buckets",
            initialValue:
                _displayFormData?['sandBucketCount']?.toString() ?? "0",
            isRequired: false,
            isEditable: false,
          ),
          getHeight(15),

          // Sand Bucket Details Section (only show if available)
          const Text(
            "Sand Bucket Details",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),

          // Sand Bucket Form Component
          AssetAuditFormComponent(
            componentId: 'sand_bucket_component',
            serialLabel: "Sand Buckets - Serial Number",
            serialHintText: "Sand Buckets Serial Number",
            photoLabel: "Add a Photo",
            serialController: _sandBucketSerialController,
            initialSavedItems:
                _displayFormData?['sandBucketAssets'] as List<dynamic>? ?? [],
            onItemSaved: _onSandBucketItemSaved,
            onStatusChanged: (status) {},
            customValidator: _validateSandBucketSerialNumber,
            customValidationErrorMessage:
                "Invalid Sand Bucket serial number. Please check and try again.",
            siteAuditSchId: widget.siteAuditSchId,
            showTable: true,
            tableTitle: "Sand Bucket Items",
          ),
          getHeight(15),
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