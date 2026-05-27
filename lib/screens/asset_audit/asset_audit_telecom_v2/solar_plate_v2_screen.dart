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
import '../../../commonWidgets/custom_remark.dart';
import '../../../commonWidgets/asset_audit_telecom_bottom_buttons.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_images.dart';
import '../../../constants/constants_methods.dart';
import '../../../services/service_locator.dart';
import '../../../utils/logger.dart';
import '../../../services/asset_audit/central_asset_audit_service.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class SolarPlateV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const SolarPlateV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<SolarPlateV2Screen> createState() => _SolarPlateV2ScreenState();
}

class _SolarPlateV2ScreenState extends State<SolarPlateV2Screen> {
  final String _screenName = 'Solar Plates';

  // Service
  late CentralAssetAuditService _service;

  // Data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  // Controllers for each section
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _solarPanelSerialController =
      TextEditingController();

  // State
  bool _isLoadingData = false;
  String? _errorMessage;
  bool _hasFormDataChanges = false;

  // Solar panel data
  List<Map<String, dynamic>> _savedSolarPanels = [];

  String _computeTotalCapacityKw(List<dynamic> panels) {
    double totalWatt = 0;
    for (final panel in panels) {
      // Check capacity field first, then fallback to disabledFieldValue (Solar Panel Watt)
      dynamic cap = panel['capacity'];
      if (cap == null || cap == 0 || cap == '0' || cap == '') {
        cap = panel['disabledFieldValue'];
      }
      
      if (cap != null && cap != '' && cap != 'N/A') {
        final parsed = double.tryParse(cap.toString());
        if (parsed != null && parsed > 0) {
          totalWatt += parsed;
        }
      }
    }
    if (totalWatt == 0) return '0';
    final totalKw = totalWatt / 1000.0;
    return totalKw.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _service = ServiceLocator().centralAssetAuditService;
    _loadData();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _solarPanelSerialController.dispose();
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
        '🔄 Solar Plate V2: Loading data for site ${widget.siteAuditSchId}',
      );

      final data = await _service.getActualDataFromSqlite(
        siteAuditSchId: widget.siteAuditSchId,
      );

      if (data != null) {
        final solarPlateItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  _screenName,
                  'TELECOM',
                )]
                as Map<String, dynamic>? ??
            {};

        // Parse Solar Plate data
        final solarPanelAssets =
            solarPlateItems['assets'] as List<dynamic>? ?? [];
        final remarksData = solarPlateItems['remarks'] as List<dynamic>? ?? [];

        final formData = <String, dynamic>{
          'solarPanelMake': solarPanelAssets.isNotEmpty
              ? solarPanelAssets.first['oem_name']?.toString()
              : 'N/A',

          'solarPanelType': solarPanelAssets.isNotEmpty
              ? solarPanelAssets.first['spv_type']?.toString()
              : 'N/A',

          'capacity': solarPanelAssets.isNotEmpty
              ? solarPanelAssets.first['capacity']?.toString()
              : 'N/A',
          'solarPanelAssets': solarPanelAssets
              .where((obj) => obj['photo_id'] != null)
              .toList(),
          'solarPanelCapacity': _computeTotalCapacityKw(
            solarPanelAssets.where((obj) => obj['photo_id'] != null).toList(),
          ),
          'solarPanelAllAssets': solarPanelAssets,
          'remarks': remarksData.isNotEmpty
              ? remarksData.first['item_type_remark']?.toString() ?? ""
              : "",
        };

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
          _savedSolarPanels = List<Map<String, dynamic>>.from(solarPanelAssets);
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeFormControllers(formData);
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'Failed to load Solar Plate data';
        });
      }
    } catch (e) {
      Logger.errorLog('❌ Solar Plate V2: Error loading data: $e');
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Error loading data: $e';
      });
    }
  }

  void _initializeFormControllers(Map<String, dynamic> formData) {
    _remarksController.text = formData['remarks'] ?? '';
    _remarksController.addListener(_onFormChanged);
    Logger.debugLog('📝 Initialized form controllers');
    if (mounted) {
      setState(() {});
    }
  }

  // Callback methods for AssetAuditFormComponent
  void _onSolarPanelItemSaved(List<Map<String, dynamic>> items) {
    setState(() {
      _displayFormData?['solarPanelAssets'] = items;
      _savedSolarPanels = List<Map<String, dynamic>>.from(items);
      // Calculate total capacity from all saved items in the table
      _displayFormData?['solarPanelCapacity'] = _computeTotalCapacityKw(items);
      _hasFormDataChanges = true;
    });
    Logger.debugLog(
      '✅ Solar Panels updated: ${_savedSolarPanels.length} items, Total Capacity: ${_displayFormData?['solarPanelCapacity']} kW',
    );
  }

  // Validation methods for solar panel serial number
  bool _validateSolarPanelSerialNumber(
    String serialNumber,
    bool isQRCodeScanned,
  ) {
    final savedItems =
        _displayFormData?['solarPanelAllAssets'] as List<dynamic>? ?? [];
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedItems,
      isQRCodeScanned,
    );
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 Solar Plate V2: Starting postCurrentScreenData');

      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'TELECOM',
          )];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];
      final finalSolarPanelAssets =
          finalData?['assets'] as List<dynamic>? ?? [];

      // Collect all modified assets
      final modifiedAssetsWithAllProperties = <dynamic>[];

      // Add Solar Panel assets
      final modifiedSolarPanelAssets =
          _displayFormData?['solarPanelAssets'] as List<dynamic>? ?? [];
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(
          finalSolarPanelAssets,
          modifiedSolarPanelAssets,
        ),
      );

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
        '📤 Solar Plate V2: Prepared ${postObject.length} items for posting',
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

      Logger.debugLog('✅ Solar Plate V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog('❌ Solar Plate V2: Error in postCurrentScreenData: $e');
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
        title: 'Solar Plates',
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
                                      'Loading Solar Plate data...',
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
                                  'No Solar Plate data available',
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
        // Solar Panel Make
        CustomFormField(
          label: "Solar Panel Make",
          initialValue: _displayFormData?['solarPanelMake'],
          isEditable: false,
          isRequired: false,
        ),
        getHeight(15),

        CustomFormField(
          label: "Solar Panel Type",
          initialValue: _displayFormData?['solarPanelType'],
          isEditable: false,
          isRequired: false,
        ),
        getHeight(15),

        // Count of Solar Panel
        CustomFormField(
          label: "Count of Solar Panel",
          initialValue: _savedSolarPanels.length.toString(),
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),

        // Solar Panel Details Section
        const Text(
          "Solar Panel Details",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
        getHeight(15),

        // Solar Panel Form Component
        AssetAuditFormComponent(
          componentId: 'solar_panel_component',
          serialLabel: "Solar Panel - Serial Number",
          serialHintText: "Solar Panel Serial Number",
          photoLabel: "Add a Photo",
          disabledFieldLabel: "Solar Panel (Watt)",
          disabledFieldValue:
              null, // Start blank, will be populated on serial lookup
          serialController: _solarPanelSerialController,
          initialSavedItems:
              _displayFormData?['solarPanelAssets'] as List<dynamic>? ?? [],
          onItemSaved: _onSolarPanelItemSaved,
          onStatusChanged: (status) {},
          customValidator: _validateSolarPanelSerialNumber,
          customValidationErrorMessage:
              "Invalid Solar Panel serial number. Please check and try again.",
          siteAuditSchId: widget.siteAuditSchId,
          showTable: true,
          tableTitle: "Solar Panel Items",
          secondDisabledFieldLabel: "Year of Manufacturing",
          secondDisabledFieldValue:
              null, // Start blank, will be populated on serial lookup
          onSerialNumberLookup: (serialNumber) {
            // Look up values from allAssets based on serial number (matching SPV screen implementation)
            final allAssets =
                _displayFormData?['solarPanelAllAssets'] as List<dynamic>? ??
                [];
            final matchingItem = allAssets.where((item) {
              final mfgSerial = item['mfg_serial_no']?.toString() ?? '';
              final nexgenSerial = item['nexgen_serial_no']?.toString() ?? '';
              // Case-insensitive comparison to handle QR scan uppercase
              return mfgSerial.toUpperCase() == serialNumber.toUpperCase() ||
                  nexgenSerial.toUpperCase() == serialNumber.toUpperCase();
            }).firstOrNull;
            if (matchingItem == null) {
              Logger.debugLog(
                'No matching item found for serial number: $serialNumber',
              );
              return null;
            }
            return {
              'capacity': matchingItem['capacity']?.toString() ?? '',
              'manufacturing_year':
                  matchingItem['manufacturing_year']?.toString() ?? '',
            };
          },
        ),
        getHeight(20),

        // Total Capacity of Solar (Kwatt) - Display field
        CustomFormField(
          label: "Total Capacity of Solar (Kwatt)",
          initialValue: _displayFormData?['solarPanelCapacity'] ?? "N/A",
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),

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