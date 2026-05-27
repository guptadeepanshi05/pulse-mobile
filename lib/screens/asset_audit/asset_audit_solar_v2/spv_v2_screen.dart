import 'package:app/commonWidgets/asset_audit_solar_bottom_buttons.dart';
import 'package:app/commonWidgets/custom_remark.dart';
import 'package:app/routes/route_generator.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/asset_audit_validation_helper.dart';
import 'package:app/utils/data_transformation_helper.dart';
import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/svg.dart';
import '../../../commonWidgets/custom_form_appbar.dart';
import '../../../commonWidgets/custom_form_field.dart';
import '../../../commonWidgets/custom_image_upload_field.dart';
import '../../../commonWidgets/custom_buttons/arrow_botton.dart';
import '../../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../../commonWidgets/asset_audit_form_component.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/app_images.dart';
import '../../../constants/constants_methods.dart';
import '../../../utils/logger.dart';
import '../../../models/asset_audit_model.dart';
import '../../../services/service_locator.dart';
import '../../../services/asset_audit_post_service.dart';
import '../../../services/image_upload_service.dart';
import '../../../enum/activity_type_enum.dart';
import '../../../app_config.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class SPVV2Screen extends StatefulWidget {
  final String siteAuditSchId;
  final String siteType;
  final String auditSchId;
  final BuildContext parentContext;

  const SPVV2Screen({
    super.key,
    required this.siteAuditSchId,
    required this.siteType,
    required this.auditSchId,
    required this.parentContext,
  });

  @override
  State<SPVV2Screen> createState() => _SPVV2ScreenState();
}

class _SPVV2ScreenState extends State<SPVV2Screen> {
  String _screenName = 'Solar';
  // Loading states
  bool _isLoadingData = true;
  String? _errorMessage;

  // Form controllers
  final TextEditingController _spvSerialController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _totalCapacityController =
      TextEditingController();

  // Form data
  bool _hasFormDataChanges = false;

  // SPV data
  Map<String, dynamic>? _assetAuditData;
  Map<String, dynamic>? _displayFormData;

  @override
  void initState() {
    super.initState();
    _loadData();
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

      Logger.debugLog('🔄 Loading SPV data for site ${widget.siteAuditSchId}');

      final data = await ServiceLocator().centralAssetAuditService
          .getActualDataFromSqlite(siteAuditSchId: widget.siteAuditSchId);
      if (data != null) {
        // Extract SPV items
        final spvItems =
            data['responseData'][AssetAuditNavigationHelper.dataValueForPage(
                  'Solar',
                  'SOLAR',
                )]
                as Map<String, dynamic>? ??
            {};

        // Extract form data for display
        final formData = <String, dynamic>{};

        // Extract display data from first item if available
        final firstItem = spvItems['assets'].first;
        formData['spvMake'] = firstItem['oem_name']?.toString() ?? "N/A";
        formData['typeOfSpv'] = firstItem['item_type']?.toString() ?? "N/A";
        formData['totalItems'] = spvItems['assets'].length.toString();
        formData['capacity'] = firstItem['capacity']?.toString() ?? "N/A";
        formData['manufacturing_year'] =
            firstItem['manufacturing_year']?.toString() ?? "N/A";
        formData['remarks'] =
            spvItems['remarks'].first['item_type_remark']?.toString() ?? "";
        formData['assets'] = spvItems['assets']
            .where((obj) => obj['photo_id'] != null)
            .toList();
        formData['allAssets'] = spvItems['assets'];

        setState(() {
          _isLoadingData = false;
          _assetAuditData = data;
          _displayFormData = formData;
        });

        // Set the remarks controller text after the widget is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeFormControllers(formData);
        });
      } else {
        setState(() {
          _isLoadingData = false;
          _errorMessage = 'No SPV data available for this site';
        });
        Logger.errorLog(
          '❌ No SPV data available for site ${widget.siteAuditSchId}',
        );
      }
    } catch (e) {
      Logger.errorLog('❌ Error loading SPV data: $e');
      setState(() {
        _isLoadingData = false;
        _errorMessage = 'Failed to load SPV data: $e';
      });
    }
  }

  // Custom validation function for SPV serial number
  bool _validateSPVSerialNumber(String serialNumber, bool isQrCodeScanned) {
    final savedSpvItems = _displayFormData?['allAssets'] as List<dynamic>;
    return AssetAuditValidationHelper.validateQRCodeSerialNumber(
      serialNumber,
      savedSpvItems,
      isQrCodeScanned,
    );
  }

  // Calculate total capacity from saved items
  double _calculateTotalCapacity(List<Map<String, dynamic>> items) {
    double total = 0.0;
    for (var item in items) {
      // Check both 'capacity' (from API) and 'disabledFieldValue' (from saved form data)
      final capacity = item['capacity'] ?? item['disabledFieldValue'];
      if (capacity != null && capacity.toString().isNotEmpty) {
        try {
          final capacityValue = double.tryParse(capacity.toString()) ?? 0.0;
          total += capacityValue;
        } catch (e) {
          Logger.errorLog('❌ Error parsing capacity: $e');
        }
      }
    }
    Logger.debugLog('📊 Calculated total capacity: $total from ${items.length} items');
    return total;
  }

  // Callback when SPV item is saved
  void _onSPVItemSaved(List<Map<String, dynamic>> items) {
    _displayFormData?['assets'] = [...items];
    
    // Calculate and update total capacity
    final totalCapacity = _calculateTotalCapacity(items);
    _totalCapacityController.text = totalCapacity.toStringAsFixed(2);
    
    setState(() {
      _hasFormDataChanges = true;
    });
    Logger.debugLog('📝 SPV items updated: ${items.length} items');
    Logger.debugLog('📊 Total capacity calculated: $totalCapacity Kwatt');
  }

  // Initialize form controllers with loaded data
  void _initializeFormControllers(Map<String, dynamic> formData) {
    // Set remarks controller text
    final remarks = formData['remarks'] ?? "";
    _remarksController.text = remarks;
    Logger.debugLog('📝 Initialized remarks controller with: $remarks');

    // Calculate total capacity from saved items if available
    final savedItems = formData['assets'] as List<dynamic>? ?? [];
    if (savedItems.isNotEmpty) {
      final itemsList = savedItems
          .map((item) => item as Map<String, dynamic>)
          .toList();
      final totalCapacity = _calculateTotalCapacity(itemsList);
      _totalCapacityController.text = totalCapacity.toStringAsFixed(2);
      Logger.debugLog(
        '📝 Initialized total capacity from saved items: $totalCapacity Kwatt',
      );
    } else {
      // Set total capacity from formData if no saved items
      final totalCapacity = formData['totalCapacity']?.toString() ?? "";
      _totalCapacityController.text = totalCapacity;
      Logger.debugLog(
        '📝 Initialized total capacity controller with: $totalCapacity',
      );
    }

    _remarksController.addListener(_onFormChanged);
    _totalCapacityController.addListener(_onFormChanged);
    // Trigger a rebuild to ensure the UI updates
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> postCurrentScreenData() async {
    try {
      Logger.debugLog('📤 SPV V2: Starting postCurrentScreenData');

      final modifiedAssets =
          _displayFormData?['assets'] as List<dynamic>? ?? [];
      final modifiedAssetsWithAllProperties = [];
      final finalData =
          _assetAuditData?['responseData'][AssetAuditNavigationHelper.dataValueForPage(
            _screenName,
            'SOLAR',
          )];
      final finalAssets = finalData?['assets'] as List<dynamic>? ?? [];
      final finalRemarks = finalData?['remarks'] as List<dynamic>? ?? [];

      Logger.debugLog(
        '📊 Data counts - Modified: ${modifiedAssets.length}, Final: ${finalAssets.length}, Remarks: ${finalRemarks.length}',
      );
      modifiedAssetsWithAllProperties.addAll(
        DataTransformationHelper.modifyData(finalAssets, modifiedAssets),
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
      ServiceLocator().centralAssetAuditService.updateDataInSqlite(
        siteAuditSchId: widget.siteAuditSchId,
        updatedData: _assetAuditData ?? {},
      );

      // Prepare data for posting
      final rawPostObject = [
        ...modifiedAssetsWithAllProperties,
        ...finalRemarks,
      ];

      // Add auditSchId: 0 to each item
      final postObject = rawPostObject.map((item) {
        if (item is Map<String, dynamic>) {
          return {...item};
        }
        return item;
      }).toList();

      Logger.debugLog(
        '📤 SPV V2: Prepared ${postObject.length} items for posting',
      );
      // Post data with photo ID replacement
      await ServiceLocator().assetAuditPostService
          .postAssetAuditDataWithPhotoReplacement(
            requests: postObject,
            isLastPage:
                AssetAuditNavigationHelper.getSolarNextScreenName(
                  _assetAuditData,
                  _screenName,
                ) ==
                'SUBMIT',
            activityType: ActivityTypeEnum.assetAudit,
          );
      Logger.debugLog('✅ SPV V2: Data posted successfully');
    } catch (e) {
      Logger.errorLog('❌ SPV V2: Error in postCurrentScreenData: $e');
    }
  }

  @override
  void dispose() {
    _spvSerialController.dispose();
    _remarksController.dispose();
    _totalCapacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: CustomFormAppbar(
        title: 'Solar Panel',
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
                                      'Loading SPV data...',
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
                                          'Failed to load SPV data',
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

                AssetAuditSolarBottomButtons(
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
      children: [
        // Site information fields (read-only)
        CustomFormField(
          label: "Solar Panel Make",
          initialValue: _displayFormData?['spvMake'] ?? "N/A",
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),
        CustomFormField(
          label: "Type of Solar Panel",
          initialValue: _displayFormData?['typeOfSpv'] ?? "N/A",
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),
        CustomFormField(
          label: "Total Solar Panel Items",
          initialValue: _displayFormData?['totalItems'] ?? "0",
          isRequired: false,
          isEditable: false,
        ),
        getHeight(15),

        // AssetAuditFormComponent for SPV items
        AssetAuditFormComponent(
          componentId: 'spv_component',
          serialLabel: "Solar Panel - Serial Number ",
          serialHintText: "Solar Panel Serial Number",
          photoLabel: "Add a Photo",
          disabledFieldLabel: "Solar Panel (Watt)",
          disabledFieldValue: null, // Will be populated dynamically based on serial number
          serialController: _spvSerialController,
          initialSavedItems:
              _displayFormData?['assets'] as List<dynamic>? ?? [],
          onItemSaved: _onSPVItemSaved,
          onStatusChanged: (status) {},
          customValidator: _validateSPVSerialNumber,
          customValidationErrorMessage:
              "Invalid SPV serial number. Please check and try again.",
          siteAuditSchId: widget.siteAuditSchId,
          showTable: true,
          tableTitle: "Solar Panel Items",
          secondDisabledFieldLabel: "Year of Manufacturing",
          secondDisabledFieldValue: null, // Will be populated dynamically based on serial number
          onSerialNumberLookup: (serialNumber) {
            // Look up values from allAssets based on serial number
            final allAssets =
                _displayFormData?['allAssets'] as List<dynamic>? ?? [];
            final matchingItem = allAssets.where((item) {
              final mfgSerial = item['mfg_serial_no']?.toString() ?? '';
              final nexgenSerial = item['nexgen_serial_no']?.toString() ?? '';
              return mfgSerial == serialNumber || nexgenSerial == serialNumber;
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
        getHeight(15),

        // Total Capacity of Solar (Kwatt)
        CustomFormField(
          label: "Total Capacity of Solar (Kwatt)",
          controller: _totalCapacityController,
          isRequired: false,
          isEditable: false,
          hintText: "Text",
        ),
        getHeight(15),

        // Remarks
        CustomRemarksField(
          label: "Add Remarks",
          hintText: "Remarks",
          controller: _remarksController,
          initialValue: _displayFormData?['remarks'] ?? '',
        ),
        getHeight(15),
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
