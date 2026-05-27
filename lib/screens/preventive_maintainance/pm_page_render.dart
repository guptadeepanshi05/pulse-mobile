import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/logger.dart';
import 'package:flutter/material.dart';
import '../../constants/app_images.dart';
import '../../constants/constants_strings.dart';
import '../../constants/constants_methods.dart';
import '../../constants/pm_constants.dart';
import 'pm_page_widget.dart';
import 'pm_page_header_solar.dart';
import 'pm_page_header_telecom.dart';
import '../../commonWidgets/custom_form_appbar.dart';
import '../../commonWidgets/custom_dialogs/unsaved_changes_dialog.dart';
import '../../utils/pm_navigation_helper.dart';
import '../../routes/route_generator.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class PMPageRender extends StatefulWidget {
  final Map<String, dynamic> pmData;
  final Function(Map<String, dynamic>)? onDataChanged;
  final bool isLoading;
  final String? errorMessage;
  final BuildContext parentContext;
  /// When true, PM is in view (non-editable) mode.
  final bool isViewMode;

  const PMPageRender({
    super.key,
    required this.pmData,
    this.onDataChanged,
    this.isLoading = false,
    this.errorMessage,
    required this.parentContext,
    this.isViewMode = false,
  });

  @override
  State<PMPageRender> createState() => _PMPageRenderState();
}

class _PMPageRenderState extends State<PMPageRender> {
  int _currentPageIndex = 0;
  late List<String> _availablePages;
  late Map<String, dynamic> _pmData;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _pmData = Map<String, dynamic>.from(widget.pmData);
    _initializeAvailablePages();
  }

  void _initializeAvailablePages() {
    // Use navigation helper to get available screens
    _availablePages = PMNavigationHelper.getAvailableScreens(_pmData);
  }

  String get _currentPageName => _availablePages[_currentPageIndex];
  String get _currentDataKey => _currentPageName == 'Site Info'
      ? 'Header'
      : PMConstants.getDataKeyForPage(_currentPageName);

  /// Determine if this is a solar PM based on data structure
  bool get _isSolarPM {
    // Use the same logic as PMNavigationHelper for consistency
    // First, check site_domain_name from pageHeader (most reliable indicator)
    final pageHeader = _pmData['pageHeader'] as List?;
    if (pageHeader != null && pageHeader.isNotEmpty) {
      final firstHeader = pageHeader.first as Map<String, dynamic>?;
      final siteDomainName = firstHeader?['site_domain_name']?.toString().toLowerCase();
      final siteTypeName = firstHeader?['site_type_name']?.toString().toLowerCase();

      // Check site_domain_name first (most reliable)
      if (siteDomainName != null) {
        if (siteDomainName.contains('solar') || siteDomainName.contains('spv') || siteDomainName.contains('pv')) {
          return true;
        }
        if (siteDomainName.contains('telecom')) {
          return false;
        }
      }
      
      // Check site_type_name as fallback
      if (siteTypeName != null) {
        if (siteTypeName.contains('solar') || siteTypeName.contains('spv') || siteTypeName.contains('pv')) {
          return true;
        }
      }
    }
    
    // If site_domain_name is not available, check for solar-specific page keys
    final responseData = _pmData['responseData'] as Map<String, dynamic>? ?? {};
    
    // Note: "Solar", "Electrical", "Earthing", and "Hygiene" can appear in both, so we check for unique solar keys
    final uniqueSolarKeys = ['SPV', 'Cables', 'Invertor', 'Junction Box', 'Safety', 'Structure', 
                             'Energy Meter', 'WMS', 'Security', 'RMS', 'Transformer', 'BOS', 
                             'Civil & Structures', 'Safety Systems', 'Performance Monitoring', 
                             'Performance'];
    final hasUniqueSolarKeys = uniqueSolarKeys.any((key) => responseData.containsKey(key));
    
    // Check for unique telecom-specific page keys
    final uniqueTelecomKeys = ['Tower', 'Battery', 'CCU', 'SEB', 'DG', 'Fire Extinguisher', 'CT', 'Earthing', 'Hygiene'];
    final hasUniqueTelecomKeys = uniqueTelecomKeys.any((key) => responseData.containsKey(key));

    // If we have unique solar keys but no unique telecom keys, it's solar
    if (hasUniqueSolarKeys && !hasUniqueTelecomKeys) {
      return true;
    }
    
    // If we have unique telecom keys but no unique solar keys, it's telecom
    if (hasUniqueTelecomKeys && !hasUniqueSolarKeys) {
      return false;
    }
    
    // Default to telecom for backward compatibility
    return false;
  }

  /// Build the appropriate site info page based on PM type
  Widget _buildSiteInfoPage() {
    if (_isSolarPM) {
      return PMPageHeaderSolar(
        pageHeader: _pageHeader,
        pmData: _pmData,
        onNext: _onNextPageWrapper,
        isLoading: widget.isLoading,
        errorMessage: widget.errorMessage,
        parentContext: widget.parentContext,
      );
    } else {
      return PMPageHeaderTelecom(
        pageHeader: _pageHeader,
        pmData: _pmData,
        onNext: _onNextPageWrapper,
        isLoading: widget.isLoading,
        errorMessage: widget.errorMessage,
        parentContext: widget.parentContext,
      );
    }
  }

  List<Map<String, dynamic>> get _currentPageData {
    if (_currentPageName == 'Site Info') {
      return []; // Site Info page doesn't have PM items
    }
    final responseData = _pmData['responseData'] as Map<String, dynamic>? ?? {};
    final data = responseData[_currentDataKey] as List? ?? [];
    return data.cast<Map<String, dynamic>>();
  }

  Map<String, dynamic>? get _pageHeader {
    final pageHeader = _pmData['pageHeader'] as List?;
    if (pageHeader?.isNotEmpty == true) {
      return pageHeader!.first as Map<String, dynamic>;
    }
    return null;
  }

  bool get _isFirstPage => _currentPageIndex == 0;
  bool get _isLastPage => _currentPageIndex == _availablePages.length - 1;

  void _onPageDataChanged(
    List<Map<String, dynamic>> updatedData, {
    bool shouldUpdateApi = true,
  }) {
    setState(() {
      _pmData['responseData'][_currentDataKey] = updatedData;
      _hasChanges = true; // Mark that changes have been made
    });
    // Call the optional callback if provided
    widget.onDataChanged?.call(_pmData);
  }

  void _onPreviousPage() {
    if (!_isFirstPage) {
      setState(() {
        _currentPageIndex--;
      });
      // Clear any cached widget state
      _clearWidgetState();
    }
  }

  Future<void> _onNextPage() async {
    // Update data in SQLite before navigating to next page (except for Site Info page)
    LoaderWidget.showLoader(context);

    try {
      // Only update if page has changes
      if (!_isFirstPage && _hasChanges) {
        await _updateDataInSqliteAndCallApi();
      }

      // Navigate to next page if not on last page
      if (!_isLastPage) {
        setState(() {
          _currentPageIndex++;
          Logger.debugLog('Page index updated to: $_currentPageIndex');
        });
        _clearWidgetState();
      }
    } finally {
      // Hide loader
      LoaderWidget.hideLoader();
    }
  }

  // Wrapper method to pass hasChanges parameter
  Future<void> _onNextPageWrapper() async {
    await _onNextPage();
    // Reset changes flag after navigation
    _hasChanges = false;
  }

  Future<void> submitDataWhenExit() async {
    await _updateDataInSqliteAndCallApiWithLoader();
  }

  Future<void> _updateDataInSqliteAndCallApi() async {
    try {
      // Get siteAuditSchId from PM data
      final siteAuditSchId = _pmData['pageHeader']?[0]?['site_audit_sch_id']
          ?.toString();

      if (siteAuditSchId == null) {
        Logger.errorLog(
          '❌ PM save aborted: siteAuditSchId missing in pageHeader',
        );
        return;
      }

      // Read using the data key (e.g. enum value) so it matches how data was stored
      // in _onPageDataChanged. For telecom this equals the display name; for solar
      // pages like "BOS (Balnace of system)" the display name differs from the
      // stored key ("BOS"), so using _currentPageName here would yield null.
      final dataToPost = _pmData['responseData'][_currentDataKey];
      if (dataToPost is! List || dataToPost.isEmpty) {
        Logger.errorLog(
          '❌ PM save aborted: no data to post for page "$_currentPageName" '
          '(dataKey: $_currentDataKey). responseData keys: '
          '${(_pmData['responseData'] as Map?)?.keys.toList()}',
        );
        return;
      }

      Logger.infoLog(
        '📝 PM saving page="$_currentPageName" (dataKey=$_currentDataKey, '
        'items=${dataToPost.length}, isLastPage=$_isLastPage)',
      );

      // Update data in SQLite
      final success = await ServiceLocator().centralAssetAuditService
          .updateDataInSqlite(
            siteAuditSchId: siteAuditSchId,
            updatedData: _pmData,
          );

      if (!success) {
        Logger.errorLog(
          '❌ PM updateDataInSqlite returned false for site $siteAuditSchId, '
          'aborting post to avoid status drift',
        );
        return;
      }

      // Post (or save offline) — now properly awaited end-to-end
      await _postPmDataToApi(dataToPost);

      // Update status in raw_api_data so My Tickets shows correct status (COMPLETED / IN-PROGRESS)
      final newStatus = _isLastPage ? 'COMPLETED' : 'IN-PROGRESS';
      try {
        await ServiceLocator().centralAssetAuditDataService.updateRawApiDataStatus(
          siteAuditSchId: siteAuditSchId,
          status: newStatus,
        );
        Logger.debugLog(
          '✅ PM status updated to $newStatus in SQLite for My Tickets',
        );
      } catch (statusErr) {
        Logger.errorLog('⚠️ Failed to update PM status in SQLite: $statusErr');
      }
    } catch (e) {
      Logger.errorLog('Error in _updateDataInSqliteAndCallApi: $e');
    }
  }

  Future<void> _updateDataInSqliteAndCallApiWithLoader() async {
    try {
      LoaderWidget.showLoader(context);
      await _updateDataInSqliteAndCallApi();
    } catch (e) {
      Logger.errorLog('Error in _updateDataInSqliteAndCallApiWithLoader: $e');
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Future<void> _postPmDataToApi(final dataToPost) async {
    try {
      Logger.infoLog('PM data posting to API');
      // Post data with photo ID replacement
      await ServiceLocator().assetAuditPostService
          .postAssetAuditDataWithPhotoReplacement(
            requests: dataToPost,
            activityType: ActivityTypeEnum.preventiveMaintenance,
            isLastPage: _isLastPage,
          );
      Logger.infoLog('PM data posted successfully to API');
    } catch (e) {
      // Rethrow so the caller can skip the raw_api_data status update — otherwise
      // My Tickets would show COMPLETED/IN-PROGRESS while pending_requests is empty
      // (this was a contributor to the "only CT data syncs" bug).
      Logger.errorLog('Error posting PM data to API: $e');
      rethrow;
    }
  }

  void _clearWidgetState() {
    // Force widget recreation by updating a state variable
    // This ensures all form fields and widgets are cleared

    // Reset changes flag when clearing widget state
    _hasChanges = false;
  }

  // Helper methods for getting page names
  String _getNextPageName() {
    return PMNavigationHelper.getNextScreenName(_pmData, _currentPageName);
  }

  String _getPreviousPageName() {
    return PMNavigationHelper.getPreviousScreenName(_pmData, _currentPageName);
  }

  void _onSave() {
    // Handle save action internally
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PM Data Saved'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _onSubmit() async {
    try {
      // Ensure loader is hidden even on last-page submit.
      LoaderWidget.showLoader(context);

      // Update data in SQLite and post to API
      await _updateDataInSqliteAndCallApi();
    } finally {
      LoaderWidget.hideLoader();
    }

    if (!mounted) return;

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('PM Data Submitted'),
        backgroundColor: Colors.green,
      ),
    );

    // Navigate to home screen
    navigateBackOrToHome(
      context,
      targetContext: widget.parentContext.mounted
          ? widget.parentContext
          : context,
    );
  }

  void _showUnsavedChangesDialog() {
    if (!_hasChanges) {
      navigateBackOrToHome(
        context,
        targetContext: widget.parentContext,
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => UnsavedChangesDialog(
        message:
            'You have unsaved changes. Do you want to save before leaving?',
        onSaveAndExit: () async {
          await submitDataWhenExit();
          widget.onDataChanged?.call(_pmData);
        },
        onDiscard: () {
        },
        siteAuditSchId: null, // You can pass siteAuditSchId if available
        section: 'Preventive Maintenance',
        parentContext: widget.parentContext,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_availablePages.isEmpty) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: true,
        appBar: CustomFormAppbar(
          title: 'Preventive Maintenance',
          onClose: () => _showUnsavedChangesDialog(),
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
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Colors.white,
                    ),
                    getHeight(16),
                    const Text(
                      'No PM Data Available',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: fontFamilyMontserrat,
                      ),
                    ),
                    getHeight(8),
                    const Text(
                      'There are no PM items to display',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontFamily: fontFamilyMontserrat,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show site info page if current page is Site Info
    if (_currentPageName == 'Site Info') {
      return Container(
        key: ValueKey('pm_header_${_currentPageName}_$_currentPageIndex'),
        child: _buildSiteInfoPage(),
      );
    }

    // Show PM section page
    final bool isView = widget.isViewMode;
    return Container(
      key: ValueKey('pm_page_${_currentPageName}_$_currentPageIndex'),
      child: PMPageWidget.forSection(
        pmItems: _currentPageData,
        sectionName: _currentPageName,
        pageTitle: 'Preventive Maintenance',
        leftButtonText: _isFirstPage ? 'Save' : _getPreviousPageName(),
        // In non-editable (view) mode, show "Done" instead of "Submit" on last page.
        rightButtonText: _isLastPage
            ? (isView ? 'Done' : 'Submit')
            : _getNextPageName(),
        onLeftButtonPressed: _isFirstPage ? _onSave : _onPreviousPage,
        onRightButtonPressed: _isLastPage
            ? (isView
                // View mode: do not call any API, just go back to tickets.
                ? () => navigateBackOrToHome(
                      context,
                      targetContext: widget.parentContext,
                    )
                : _onSubmit)
            : _onNextPageWrapper,
        onDataChanged: (data) =>
            _onPageDataChanged(data, shouldUpdateApi: true),
        isLoading: widget.isLoading,
        errorMessage: widget.errorMessage,
        submitDataWhenExit: submitDataWhenExit,
        siteAuditSchId:
            _pmData['pageHeader']?[0]?['site_audit_sch_id']?.toString() ?? '',
        parentContext: widget.parentContext,
        isViewMode: widget.isViewMode,
      ),
    );
  }
}

/// Helper class for PM data structure
class PMDataHelper {
  static Map<String, dynamic> createEmptyPMData() {
    return {'pageHeader': [], 'responseData': {}};
  }

  static Map<String, dynamic>? getPageHeader(Map<String, dynamic> pmData) {
    final pageHeader = pmData['pageHeader'] as List?;
    if (pageHeader?.isNotEmpty == true) {
      return pageHeader!.first as Map<String, dynamic>;
    }
    return null;
  }

  static Map<String, dynamic> getResponseData(Map<String, dynamic> pmData) {
    return pmData['responseData'] as Map<String, dynamic>? ?? {};
  }

  static List<String> getAvailablePages(Map<String, dynamic> pmData) {
    final responseData = getResponseData(pmData);
    final pageOrder = PMConstants.getPageOrder();

    return pageOrder.where((page) {
      final dataKey = PMConstants.getDataKeyForPage(page);
      return responseData.containsKey(dataKey) &&
          responseData[dataKey] is List &&
          (responseData[dataKey] as List).isNotEmpty;
    }).toList();
  }

  static List<Map<String, dynamic>> getPageData(
    Map<String, dynamic> pmData,
    String pageName,
  ) {
    final responseData = getResponseData(pmData);
    final dataKey = PMConstants.getDataKeyForPage(pageName);
    final data = responseData[dataKey] as List? ?? [];
    return data.cast<Map<String, dynamic>>();
  }

  static Map<String, dynamic> updatePageData(
    Map<String, dynamic> pmData,
    String pageName,
    List<Map<String, dynamic>> updatedData,
  ) {
    final updatedPMData = Map<String, dynamic>.from(pmData);
    final dataKey = PMConstants.getDataKeyForPage(pageName);
    updatedPMData['responseData'][dataKey] = updatedData;
    return updatedPMData;
  }
}
