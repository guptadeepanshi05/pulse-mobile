import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/constants/api_codes.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/corrective_maintenance_screen_mode_enum.dart';
import 'package:app/models/all_site_model.dart';
import 'package:app/models/location_model.dart';
import 'package:app/screens/general_inspection/ginspection_detail.dart';
import 'package:app/screens/site_visit/site_visit.dart';
import 'package:app/screens/incident_ticket/incident_detail_screen.dart';
import 'package:app/repositories/asset_upload_respository.dart';
import 'package:app/screens/asset_upload/asset_upload_detail_page.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/location_service.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:app/utils/calculate_distance.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

import '../../commonWidgets/site_card.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_images.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class AllSitesScreen extends StatefulWidget {
  final String ActivityType;

  const AllSitesScreen({super.key, required this.ActivityType});

  @override
  State<AllSitesScreen> createState() => _AllSitesScreenState();
}

class _AllSitesScreenState extends State<AllSitesScreen> {
  List<AllSiteModel> _allSites = [];
  List<AllSiteModel> _nearbySites = [];
  List<AllSiteModel> _filteredSites = [];
  bool _isLoading = true;
  bool _isFetchingSites = false; // Prevent concurrent repeated API calls
  String? _errorMessage;
  String? _selectedFilter;
  String _siteType = 'nearby';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _downloadedSiteIds = <int>{};
  bool _isInitializingDownloadedSites = false;

  @override
  void initState() {
    super.initState();
    _loadSites(_siteType);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSites(String type, {String searchText = ''}) async {
    if (_isFetchingSites) {
      Logger.debugLog('🔁 _loadSites skipped: fetch already in progress');
      return;
    }

    try {
      _isFetchingSites = true;
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      final repository = ServiceLocator().sitesRepository;

      LocationModel location;
      try {
        location = await LocationService.getCurrentLocation();
      } catch (e) {
        location = LocationModel(latitude: 32.899, longitude: 56.989);
      }

      final sites = await repository
          .getAllSitesData(
            location.latitude,
            location.longitude,
            searchText,
            type,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception(
                'Request timeout - please check your internet connection',
              );
            },
          );

      if (mounted) {
        setState(() {
          if (type == 'ALL') {
            _allSites = sites;
            _filteredSites = sites;
          } else {
            _nearbySites = sites;
            _filteredSites = sites;
          }
          _selectedFilter = type == 'ALL' ? 'All Sites' : 'Near By Sites';
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            if (sites.isNotEmpty) {
              _initializeDownloadedSites(sites);
            }
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      _isFetchingSites = false;
    }
  }

  void _filterSites(String filter) {
    setState(() {
      _selectedFilter = filter;
      if (filter == 'All Sites') {
        _siteType = 'ALL';
        // ✅ Don’t load sites, just clear data
        _filteredSites.clear();
        _allSites.clear();
      } else if (filter == 'Near By Sites') {
        _siteType = 'nearby';
        // ✅ Load nearby sites when selected
        _loadSites(_siteType, searchText: _searchQuery);
      }
    });
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
    // No auto load; only load on Enter
  }

  void _performSearchAndLoad(String query) {
    final trimmed = query.trim();

    setState(() {
      _searchQuery = trimmed;
    });

    if (trimmed.isNotEmpty) {
      _loadSites(_siteType, searchText: trimmed);
    } else {
      // If search is empty, reload based on current filter
      if (_siteType == 'ALL') {
        _filteredSites.clear();
        _allSites.clear();
      } else {
        _loadSites(_siteType, searchText: '');
      }
    }
  }

  int _getSiteCountForFilter(String filter) {
    if (filter == 'All Sites') {
      return _allSites.length;
    } else if (filter == 'Near By Sites') {
      return _nearbySites.length;
    }
    return 0;
  }

  void _navigateToSite(AllSiteModel site) async {
    if (!mounted || !context.mounted) return;
    final parentContext = context;

    try {
      // Show loader immediately when site is clicked
      LoaderWidget.showLoader(context);

      final siteLat = site.latitude != null
          ? double.tryParse(site.latitude!)
          : null;
      final siteLng = site.longitude != null
          ? double.tryParse(site.longitude!)
          : null;

      if (!hasValidSiteCoordinates(siteLat, siteLng)) {
        LoaderWidget.hideLoader();
        if (!mounted) return;
        Toastbar.showErrorToastbar(siteNotInRadiusMessage, context);
        return;
      }

      // Check distance from current location to site location
      try {
        // Check location permission first
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (!mounted) return;
          if (permission == LocationPermission.denied) {
            LoaderWidget.hideLoader();
            Toastbar.showErrorToastbar(
              "Location permission is required to access this site.",
              context,
            );
            return;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          LoaderWidget.hideLoader();
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Location Permission Denied'),
                content: const Text(
                  'Location permission is permanently denied. '
                  'Please enable location permission in app settings to access this site.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Open Settings'),
                  ),
                ],
              );
            },
          );

          if (shouldOpenSettings == true) {
            await openAppSettings();
          }
          return;
        }

        // Get current location
        // Note: If location services (GPS) are disabled, calling getCurrentLocation()
        // will trigger Android's system dialog asking to enable location.
        // The user can tap "TURN ON" in the system dialog to enable location directly.
        // This is the standard Android behavior, same as Google Maps.
        final currentLocation = await LocationService.getCurrentLocation();
        if (!mounted) return;

        // Calculate distance in kilometers
        final distanceInKm = calculateDistance(
          currentLocation.latitude,
          currentLocation.longitude,
          siteLat!,
          siteLng!,
        );

        // Check if distance is more than the allowed distance (in meters, converted to km)
        final maxDistanceKm = double.parse(
          ApiCodes.distanceFromLocation,
        ); // Convert meters to km
        if (distanceInKm > maxDistanceKm) {
          // Hide loader before showing toast
          LoaderWidget.hideLoader();
          if (!mounted) return;
          Toastbar.showErrorToastbar(
            "You are not in the radius of site. Your distance from the site is: ${distanceInKm.toStringAsFixed(2)} km",
            context,
          );
          // Prevent site from opening if distance exceeds the allowed radius
          return;
        }
      } catch (e) {
        // If location fetch fails, hide loader and show error
        LoaderWidget.hideLoader();
        Logger.errorLog('Error calculating distance: $e');
        if (!mounted) return;
        Toastbar.showErrorToastbar(
          "Unable to get your location. Please ensure location services are enabled.",
          context,
        );
        return;
      }

      // For Site Visit, check if we have stored API data with organisation list
      if (widget.ActivityType == 'SV') {
        try {
          final service = ServiceLocator().centralAssetAuditService;
          final storedData = await service.getDataFromSqlite(
            siteAuditSchId: site.siteId.toString(),
          );
          if (!mounted) return;

          if (storedData != null && storedData.apiData.isNotEmpty) {
            // Use stored API data to create AllSiteModel with all fields
            final apiData = storedData.apiData;
            final siteData = AllSiteModel(
              siteId: apiData['siteId'] ?? site.siteId,
              entityId: site.entityId,
              siteCode: apiData['siteCode'] ?? site.siteCode,
              siteName: apiData['siteName'] ?? site.siteName,
              clusterDistrictId: site.clusterDistrictId,
              clusterDistrictName:
                  apiData['cluster'] ?? site.clusterDistrictName,
              circleStateId: site.circleStateId,
              circleStateName: apiData['circle'] ?? site.circleStateName,
              clientId: site.clientId,
              clientName: apiData['client'] ?? site.clientName,
              oem: site.oem,
              oemId: site.oemId,
              self: site.self,
              selfId: site.selfId,
              siteDomainName: site.siteDomainName,
              distanceKM: site.distanceKM,
              infraEngineerName:
                  apiData['infraDistrictEngineerName'] ??
                  site.infraEngineerName,
              infraEngineerPhone:
                  apiData['infraDistrictEngineerContactNo'] ??
                  site.infraEngineerPhone,
              ownerName: apiData['ownerName'] ?? site.ownerName,
              ownerPhone: apiData['ownerContactNo'] ?? site.ownerPhone,
              siteVisitLogId: apiData['svlId']?.toString(),
              siteVisitLogDate: apiData['visitDate']?.toString(),
              purposeOfVisit: apiData['purposeOfVisit']?.toString(),
              visitingPersonImageId: apiData['visitingPersonImageId']
                  ?.toString(),
              officialIdImageId: apiData['officialIdImageId']?.toString(),
              aadharCardImageId: apiData['aadharCardImageId']?.toString(),
              leavingStatusImageId: apiData['leavingStatusImageId']?.toString(),
              visitorName:
                  apiData['visitorName']?.toString() ??
                  apiData['visitor_name']?.toString(),
              visitorContactNo:
                  apiData['visitorContactNo']?.toString() ??
                  apiData['visitor_contact_no']?.toString(),
              organisationName:
                  apiData['organisationName']?.toString() ??
                  apiData['organisation_name']?.toString() ??
                  apiData['organizationName']?.toString() ??
                  apiData['organization_name']?.toString(),
              orgId: apiData['orgId'] != null
                  ? (apiData['orgId'] is int
                        ? apiData['orgId'] as int
                        : int.tryParse(apiData['orgId'].toString()))
                  : null,
              roleDesignation:
                  apiData['roleDesignation']?.toString() ??
                  apiData['role_designation']?.toString(),
              reportingManager:
                  apiData['reportingManager']?.toString() ??
                  apiData['reporting_manager']?.toString(),
            );

            // Extract organisation list from API response if available
            final organisationList = apiData['organisationList'] != null
                ? (apiData['organisationList'] as List)
                      .map((org) => Map<String, dynamic>.from(org))
                      .toList()
                : null;

            // Hide loader before navigation
            LoaderWidget.hideLoader();
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SiteVisitScreen(
                    siteData: siteData,
                    parentContext: parentContext,
                    preloadedOrganisationList: organisationList,
                    siteAuditSchIdForStorage: site.siteId.toString(),
                    clearStoredDataAfterSubmit: true,
                  ),
                ),
              );
            }
            return;
          }
        } catch (e) {
          // Fall through to use basic site data
        }
      }

      // For Asset Upload, call getUploadedAssets before navigating
      if (widget.ActivityType == 'AU' ||
          widget.ActivityType == 'Asset Upload') {
        try {
          // Loader is already shown at the beginning of the function
          final repository = AssetUploadRepository(ServiceLocator().apiService);
          final result = await repository.getUploadedAssets(
            siteId: site.siteId,
          );
          if (!mounted) return;

          if (result.isSuccess && result.data != null) {
            Logger.debugLog(
              '✅ Successfully fetched uploaded assets for site ${site.siteId}',
            );

            // Parse response structure - check if data is wrapped or direct
            Map<String, dynamic>? responseData;
            if (result.data!.containsKey('data')) {
              // Response has data wrapper: { data: { assetUpload: ..., siteDetails: ... } }
              responseData = result.data!['data'] as Map<String, dynamic>?;
              Logger.debugLog('📦 Found data wrapper, extracting inner data');
            } else {
              // Response might be direct: { assetUpload: ..., siteDetails: ... }
              responseData = result.data;
              Logger.debugLog('📦 Using data directly (no wrapper)');
            }

            // Extract data if available
            String? preloadedSelfieImageId;
            int? preloadedAuId;
            List<Map<String, dynamic>>? preloadedAssetItems;
            AllSiteModel? enhancedSiteData;

            if (responseData != null) {
              // Try both camelCase and snake_case field names
              final assetUploadData =
                  responseData['assetUpload'] ??
                  responseData['asset_upload'] as Map<String, dynamic>?;
              final siteDetailsData =
                  responseData['siteDetails'] ??
                  responseData['site_details'] as Map<String, dynamic>?;

              if (assetUploadData != null) {
                // Extract maker_selfie_image_id from assetUploadData (try both formats)
                final makerSelfieImageId =
                    assetUploadData['maker_selfie_image_id'] ??
                    assetUploadData['makerSelfieImageId'];

                // Extract auId from assetUploadData (try both formats)
                final auId =
                    assetUploadData['au_id'] ??
                    assetUploadData['auId'] ??
                    assetUploadData['id'];

                // Extract asset_upload_item array (try both formats)
                final assetUploadItems =
                    (assetUploadData['asset_upload_item'] ??
                            assetUploadData['assetUploadItem'] ??
                            [])
                        as List<dynamic>? ??
                    [];

                preloadedSelfieImageId = makerSelfieImageId?.toString();
                preloadedAuId = auId != null
                    ? (auId is int ? auId : int.tryParse(auId.toString()))
                    : null;

                // Convert asset_upload_item to format expected by AssetUploadDetailPage
                preloadedAssetItems = assetUploadItems
                    .map((item) {
                      if (item is Map<String, dynamic>) {
                        return Map<String, dynamic>.from(item);
                      }
                      return <String, dynamic>{};
                    })
                    .where((item) => item.isNotEmpty)
                    .toList();

                if (preloadedAssetItems.isEmpty) {
                  preloadedAssetItems = null;
                }

                Logger.debugLog(
                  '📦 Extracted data - auId: $preloadedAuId, selfieId: $preloadedSelfieImageId, items: ${preloadedAssetItems?.length ?? 0}',
                );
              }

              // Enhance site data with siteDetails if available
              if (siteDetailsData != null) {
                enhancedSiteData = AllSiteModel(
                  siteId: siteDetailsData['site_id'] ?? site.siteId,
                  entityId: siteDetailsData['entity_id'] ?? site.entityId,
                  siteCode:
                      siteDetailsData['site_code']?.toString() ?? site.siteCode,
                  siteName:
                      siteDetailsData['site_name']?.toString() ?? site.siteName,
                  clusterDistrictId: site.clusterDistrictId,
                  clusterDistrictName:
                      siteDetailsData['cluster']?.toString() ??
                      site.clusterDistrictName,
                  circleStateId: site.circleStateId,
                  circleStateName:
                      siteDetailsData['circle']?.toString() ??
                      site.circleStateName,
                  clientId: site.clientId,
                  clientName:
                      siteDetailsData['client']?.toString() ?? site.clientName,
                  svlId: null,
                  oem: site.oem,
                  oemId: site.oemId,
                  self: site.self,
                  selfId: site.selfId,
                  siteDomainName: site.siteDomainName,
                  distanceKM: site.distanceKM,
                  infraEngineerName:
                      siteDetailsData['infra_district_engineer_name']
                          ?.toString(),
                  infraEngineerPhone:
                      siteDetailsData['infra_district_engineer_contact_no']
                          ?.toString(),
                  ownerName: siteDetailsData['owner_name']?.toString(),
                  ownerPhone: siteDetailsData['owner_contact_no']?.toString(),
                  siteVisitLogId: null,
                  siteVisitLogDate: null,
                  purposeOfVisit: null,
                  visitingPersonImageId: null,
                  checklistItems: null,
                );
              }
            }

            // Hide loader before navigation
            LoaderWidget.hideLoader();
            // Navigate with the fetched data
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssetUploadDetailPage(
                    siteData: enhancedSiteData ?? site,
                    parentContext: parentContext,
                    preloadedSelfieImageId: preloadedSelfieImageId,
                    preloadedAssetItems: preloadedAssetItems,
                    preloadedAuId: preloadedAuId,
                    mode: CMScreenModeEnum
                        .create, // Mode will be auto-detected based on preloadedAuId
                    siteAuditSchIdForStorage: site.siteId.toString(),
                  ),
                ),
              );
            }
          } else {
            // Even if fetch fails, still navigate (might be a new site with no assets)
            Logger.debugLog(
              '⚠️ Failed to fetch uploaded assets, navigating anyway: ${result.errorMessage}',
            );
            LoaderWidget.hideLoader();
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssetUploadDetailPage(
                    siteData: site,
                    parentContext: parentContext,
                    mode: CMScreenModeEnum
                        .create, // Create mode when coming from all sites
                    siteAuditSchIdForStorage: site.siteId.toString(),
                  ),
                ),
              );
            }
          }
        } catch (e) {
          LoaderWidget.hideLoader();
          Logger.errorLog('❌ Error fetching uploaded assets: $e');
          // Still navigate even if there's an error
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetUploadDetailPage(
                  siteData: site,
                  parentContext: parentContext,
                  mode: CMScreenModeEnum
                      .create, // Create mode when coming from all sites
                  siteAuditSchIdForStorage: site.siteId.toString(),
                ),
              ),
            );
          }
        }
        return;
      }

      // Use basic site data if no stored data available
      // Hide loader before navigation
      LoaderWidget.hideLoader();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => widget.ActivityType == 'SV'
              ? SiteVisitScreen(
                  siteData: site,
                  parentContext: parentContext,
                  siteAuditSchIdForStorage: site.siteId.toString(),
                  clearStoredDataAfterSubmit: true,
                )
              : widget.ActivityType == 'GI'
              ? GInspectionDetailScreen(
                  siteData: site,
                  mode: CMScreenModeEnum.create,
                  parentContext: parentContext,
                )
              : IncidentDetilScreen(
                  siteData: site,
                  mode: CMScreenModeEnum.create,
                  parentContext: parentContext,
                ),
        ),
      );
    } catch (e) {
      // Hide loader on error
      if (LoaderWidget.isShowing) {
        LoaderWidget.hideLoader();
      }
      Logger.errorLog('Error in _navigateToSite: $e');
    }
  }

  void _initializeDownloadedSites(List<AllSiteModel> sites) async {
    if (_isInitializingDownloadedSites) return;
    _isInitializingDownloadedSites = true;

    try {
      // Snapshot: `sites` is often the same instance as `_allSites` / `_filteredSites`.
      // Those lists can be `.clear()`-ed from filter/search while this async loop runs,
      // which causes "Concurrent modification during iteration".
      final sitesSnapshot = List<AllSiteModel>.from(sites);
      bool hasChanges = false;
      for (final site in sitesSnapshot) {
        final isDownloaded = await _isSiteDownloaded(site);
        if (isDownloaded && !_downloadedSiteIds.contains(site.siteId)) {
          _downloadedSiteIds.add(site.siteId);
          hasChanges = true;
        }
      }
      if (hasChanges && mounted) {
        setState(() {});
      }
    } finally {
      _isInitializingDownloadedSites = false;
    }
  }

  Future<bool> _isSiteDownloaded(AllSiteModel site) async {
    if (_downloadedSiteIds.contains(site.siteId)) {
      return true;
    }

    try {
      final dataService = ServiceLocator().centralAssetAuditDataService;

      // For Asset Upload, check AU-specific downloaded table
      if (widget.ActivityType == 'AU' ||
          widget.ActivityType == 'Asset Upload') {
        final auDownloaded = await dataService.isAUSiteDownloaded(site.siteId);
        return auDownloaded;
      }

      // For Site Visit, check SV-specific table (downloads save to sv_sites_data, not cm_sites_data)
      if (widget.ActivityType == 'SV') {
        final svDownloaded = await dataService.isSVSiteDownloaded(site.siteId);
        return svDownloaded;
      }

      // Incident: site row lives in incident_sites_data (not cm_sites_data). Match download flow:
      // site data is required; checklist is best-effort but does not block "downloaded" UI.
      if (widget.ActivityType == 'Incident') {
        final incidentSiteDownloaded = await dataService
            .isIncidentSiteDownloaded(site.siteId);
        return incidentSiteDownloaded;
      }

      // GI: site row lives in gi_sites_data (not cm_sites_data). Checklist is best-effort.
      if (widget.ActivityType == 'GI') {
        final giSiteDownloaded = await dataService.isGISiteDownloaded(
          site.siteId,
        );
        return giSiteDownloaded;
      }

      // Default flow: check CM site data first
      final cmDownloaded = await dataService.isCMSiteDownloaded(site.siteId);

      if (!cmDownloaded) {
        return false;
      }

      // For other activity types, CM site data is sufficient
      return cmDownloaded;
    } catch (e) {
      Logger.errorLog('Error checking site download status: $e');
      return false;
    }
  }

  Future<void> _downloadSiteData(AllSiteModel site) async {
    try {
      LoaderWidget.showLoader(context);

      final service = ServiceLocator().centralAssetAuditService;
      bool isDownloaded = false;

      // Always download CM site data first

      if (widget.ActivityType == 'SV') {
        isDownloaded = await service.downloadSVSiteData(site: site);
      } else if (widget.ActivityType == 'GI') {
        isDownloaded = await service.downloadGISiteData(site: site);
      } else if (widget.ActivityType == 'Incident') {
        isDownloaded = await service.downloadIncidentSiteData(site: site);
      } else if (widget.ActivityType == 'AU' ||
          widget.ActivityType == 'Asset Upload') {
        // downloadAssetUploadSiteData now handles fetching and saving both site data and API data
        isDownloaded = await service.downloadAssetUploadSiteData(site: site);
      }
      if (!mounted) return;

      if (isDownloaded) {
        // If CM site data downloaded successfully, also download checklist data
        if (widget.ActivityType == 'GI') {
          final giDownloaded = await service.downloadGIChecklist(
            siteId: site.siteId,
            siteCode: site.siteCode,
            siteName: site.siteName,
            siteDomainId: 1, // Default site domain ID
          );
          if (!mounted) return;

          if (!giDownloaded) {
            // Still consider it successful since CM data was downloaded
          }
        } else if (widget.ActivityType == 'Incident') {
          final incidentDownloaded = await service.downloadIncidentChecklist(
            siteId: site.siteId,
            siteCode: site.siteCode,
            siteName: site.siteName,
          );
          if (!mounted) return;

          if (!incidentDownloaded) {
            // Still consider it successful since CM data was downloaded
          }
        }

        setState(() {
          _downloadedSiteIds.add(site.siteId);
        });

        final toScanForDownloaded = _filteredSites.isNotEmpty
            ? _filteredSites
            : (_nearbySites.isNotEmpty ? _nearbySites : _allSites);
        _initializeDownloadedSites(toScanForDownloaded);

        if (!mounted) return;
        Toastbar.showSuccessToastbar(
          'Site data downloaded successfully',
          context,
        );
      } else {
        if (!mounted) return;
        Toastbar.showErrorToastbar('Failed to download site data', context);
      }
    } catch (e) {
      if (!mounted) return;
      Toastbar.showErrorToastbar('Error downloading site data: $e', context);
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildCustomAppBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeSvgPicture.asset(
              AppImages.home,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          SafeArea(
            child: Container(
              height: MediaQuery.of(context).size.height,
              child: Column(
                children: [
                  _buildFilterBar(),
                  _buildSearchBar(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildCustomAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 10, top: 12, right: 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_sharp,
                  color: AppColors.backgroundColorapp,
                  size: 25,
                ),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "All Sites",
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    fontFamily: poppins,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _searchController,
            onChanged: _performSearch,
            onSubmitted: (value) {
              _performSearchAndLoad(value);
            },
            style: const TextStyle(color: Colors.black, fontSize: 16),
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              hintText: 'Search',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.blue,
                            size: 20,
                          ),
                          onPressed: () {
                            _performSearchAndLoad(_searchController.text);
                          },
                          tooltip: 'Search',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: Colors.grey,
                            size: 20,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              // ✅ For All Sites: clear data and show nothing
                              if (_siteType == 'ALL') {
                                _filteredSites.clear();
                                _allSites.clear();
                              } else {
                                // ✅ For Nearby: reload nearby sites
                                _loadSites(_siteType, searchText: '');
                              }
                            });
                          },
                          tooltip: 'Clear',
                        ),
                      ],
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.search,
                        color: Colors.black,
                        size: 20,
                      ),
                      onPressed: () {
                        _performSearchAndLoad(_searchController.text);
                      },
                      tooltip: 'Search',
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.grey, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.grey, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
            ),
          ),
        ),
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Press Enter to search',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final filters = ['Near By Sites', 'All Sites'];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final count = _getSiteCountForFilter(filter);
          final isSelected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8, left: 8),
            child: _buildFilterButton(
              filter: filter,
              count: count,
              isSelected: isSelected,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterButton({
    required String filter,
    required int count,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _filterSites(filter),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.myTicketsSelected : AppColors.myTickets,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Center(
          child: Text(
            '$filter ($count)',
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.dashboardTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    } else if (_errorMessage != null) {
      return _buildErrorWidget(_errorMessage!);
    } else if (_filteredSites.isEmpty) {
      return const Center(
        child: Text(
          'No sites found',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else {
      return SingleChildScrollView(
        child: Column(
          children: [getHeight(5), _buildSiteList(), getHeight(10)],
        ),
      );
    }
  }

  Widget _buildSiteList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredSites.length,
      itemBuilder: (context, index) {
        final site = _filteredSites[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _filteredSites.length - 1 ? 0 : 5,
          ),
          child: FutureBuilder<bool>(
            future: _isSiteDownloaded(site),
            builder: (context, snapshot) {
              final isDownloaded = snapshot.data ?? false;
              return SiteCard(
                site: site,
                isDownloaded: isDownloaded,
                onDirectionTap: () {
                  if (site.longitude != null && site.latitude != null) {
                    // Convert String to double
                    final lat = double.tryParse(site.latitude!);
                    final lng = double.tryParse(site.longitude!);

                    if (lat != null && lng != null) {
                      // Open Google Maps with directions to the site
                      LocationService.openDirectionsToSite(
                        siteLat: lat,
                        siteLng: lng,
                        siteName: site.siteName,
                        context: context,
                      );
                    } else {
                      // Show a message if conversion failed
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Directions are not available for this site',
                          ),
                          backgroundColor: AppColors.errorColor,
                        ),
                      );
                    }
                  } else {
                    // Show a message to the user
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Directions are not available for this site',
                        ),
                        backgroundColor: AppColors.errorColor,
                      ),
                    );
                  }
                },
                onTap: () => _navigateToSite(site),
                onDownloadTap: isDownloaded
                    ? null
                    : () => _downloadSiteData(site),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildErrorWidget(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.errorColor,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Error loading sites',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontFamily: fontFamilyMontserrat,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadSites(_siteType, searchText: _searchQuery),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
