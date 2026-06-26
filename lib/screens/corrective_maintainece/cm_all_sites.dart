import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/constants/api_codes.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/corrective_maintenance_screen_mode_enum.dart';
import 'package:app/models/all_site_model.dart';
import 'package:app/models/cm_site_model.dart';
import 'package:app/models/location_model.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';

import '../../commonWidgets/site_card.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_images.dart';
import '../../services/location_service.dart';
import '../../utils/calculate_distance.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'corrective_maintenance_screen.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class CMAllSitesScreen extends StatefulWidget {
  const CMAllSitesScreen({super.key});

  @override
  State<CMAllSitesScreen> createState() => _CMAllSitesScreenState();
}

class _CMAllSitesScreenState extends State<CMAllSitesScreen> {
  List<AllSiteModel> _allSites = [];
  List<AllSiteModel> _nearbySites = [];
  List<AllSiteModel> _filteredSites = [];
  bool _isLoading = true;
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
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final repository = ServiceLocator().sitesRepository;

      // Get current location with fallback to default
      LocationModel location;
      try {
        location = await LocationService.getCurrentLocation();
      } catch (e) {
        // Use default location if GPS fails
        location = LocationModel(latitude: 32.899, longitude: 56.989);

      }

      // Add timeout to prevent indefinite loading
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
          // Populate the appropriate list based on type
          if (type == 'ALL') {
            _allSites = sites;
            _filteredSites = sites;
          } else {
            _nearbySites = sites;
            _filteredSites = sites;
          }
          // Keep the current selected filter based on type
          _selectedFilter = type == 'ALL' ? 'All Sites' : 'Near By Sites';
          _isLoading = false;
        });

        // Initialize downloaded sites state after sites are loaded
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
    }
  }

  void _filterSites(String filter) {
    setState(() {
      _selectedFilter = filter;
      _siteType = filter == 'All Sites' ? 'ALL' : 'nearby';
    });
    _loadSites(_siteType);
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
    // Call API with search text
    _loadSites(_siteType, searchText: query.isEmpty ? '' : query);
  }

  int _getSiteCountForFilter(String filter) {
    if (filter == 'All Sites') {
      return _allSites.length;
    } else if (filter == 'Near By Sites') {
      return _nearbySites.length;
    }
    return 0;
  }

  void _navigateToSite(CMSite site, AllSiteModel? allSiteModel) async {
    try {
      if (!mounted) return;
      // Show loader immediately when site is clicked
      LoaderWidget.showLoader(context);

      final siteLat = allSiteModel?.latitude != null
          ? double.tryParse(allSiteModel!.latitude!)
          : null;
      final siteLng = allSiteModel?.longitude != null
          ? double.tryParse(allSiteModel!.longitude!)
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
        final maxDistanceKm = double.parse(ApiCodes.distanceFromLocation);
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

      // Hide loader before navigation
      LoaderWidget.hideLoader();
      if (!mounted) return;

      // Navigate to corrective maintenance screen with the selected site data
      final parentContext = context;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CorrectiveMaintenanceScreen(
            mode: CMScreenModeEnum.create,
            preloadedSites: [site], // Pass the selected site
            preloadedSiteData: {
              'siteId': site.siteId,
              'siteName': site.siteName,
              'siteCode': site.siteCode,
              'clusterDistrictName': site.clusterDistrictName,
              'circleStateName': site.circleStateName,
              'clientName': site.clientName,
              'oem': site.oem,
            },
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
    // Prevent multiple initializations
    if (_isInitializingDownloadedSites) return;
    _isInitializingDownloadedSites = true;

    try {
      bool hasChanges = false;
      // Check which sites are already downloaded and populate local state
      for (final site in sites) {
        final isDownloaded = await _isSiteDownloaded(site);
        if (isDownloaded && !_downloadedSiteIds.contains(site.siteId)) {
          _downloadedSiteIds.add(site.siteId);
          hasChanges = true;
        }
      }
      // Only trigger UI update if there were actual changes
      if (hasChanges && mounted) {
        setState(() {});
      }
    } finally {
      _isInitializingDownloadedSites = false;
    }
  }

  Future<bool> _isSiteDownloaded(AllSiteModel site) async {
    // Check local state first (for recently downloaded sites)
    if (_downloadedSiteIds.contains(site.siteId)) {
      return true;
    }

    // Check database for existing downloads using CM site data service
    try {
      final cmDownloaded = await ServiceLocator().centralAssetAuditDataService
          .isCMSiteDownloaded(site.siteId);

      return cmDownloaded;
    } catch (e) {
      return false;
    }
  }

  Future<void> _downloadSiteData(AllSiteModel site) async {
    try {
      LoaderWidget.showLoader(context);

      final service = ServiceLocator().centralAssetAuditService;
      bool isDownloaded = false;

      // Use entityId for checklist; when API returns 0, use lastCMSiteReqId so checklist saves and offline open works
      final effectiveEntityId = site.entityId != 0
          ? site.entityId
          : (site.lastCMSiteReqId ?? 0);

      // Save site with effective entity_id so My Tickets opens with correct entityId for checklist lookup
      isDownloaded = await service.downloadCMSiteData(
        site: site,
        siteType: 'correctiveMaintenance',
        entityIdOverride: effectiveEntityId != 0 ? effectiveEntityId : null,
      );
      if (!mounted) return;

      if (isDownloaded) {
        Logger.infoLog(
          '🔄 Starting checklist download for site: ${site.siteName} (ID: ${site.siteId}, entityId: $effectiveEntityId)',
        );

        final checklistDownloaded = await service.downloadCMChecklist(
          siteId: site.siteId,
          entityId: effectiveEntityId != 0 ? effectiveEntityId : site.entityId,
          siteCode: site.siteCode,
          siteName: site.siteName,
        );
        if (!mounted) return;

        Logger.infoLog('📊 Checklist download result: $checklistDownloaded');

        if (!checklistDownloaded) {
          Logger.errorLog(
            '⚠️ Warning: CM site data downloaded but CM checklist failed',
          );
          // Still consider it successful since CM data was downloaded
        } else {
          Logger.infoLog('✅ Checklist data saved successfully to local DB');
        }

        setState(() {
          _downloadedSiteIds.add(site.siteId);
        });

        // Re-initialize downloaded sites state to ensure consistency
        // Use the currently displayed sites list
        _initializeDownloadedSites(
          _filteredSites.isNotEmpty
              ? _filteredSites
              : _siteType == 'ALL'
              ? _allSites
              : _nearbySites,
        );

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
          // Background image that fully covers the screen
          Positioned.fill(
            child: SafeSvgPicture.asset(
              AppImages.home,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          // Content overlay
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
                  "Corrective Maintenance",
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: _searchController,
        onSubmitted: _performSearch,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.black, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search and press enter',
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 16),
          prefixIcon: null, // Remove search icon from left
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _performSearch('');
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.search, color: Colors.black, size: 20),
                  onPressed: () {
                    _performSearch(_searchController.text);
                  },
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
        height: 32, // Fixed height for consistency
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
      final currentList = _selectedFilter == 'All Sites'
          ? _allSites
          : _nearbySites;
      return Center(
        child: Text(
          currentList.isEmpty
              ? 'No sites found'
              : 'No sites found for ${_selectedFilter ?? 'selected filter'}',
          textAlign: TextAlign.center,
          style: const TextStyle(
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
                  // Show location info or open maps
                  Toastbar.showInfoToastbar(
                    'Location: ${site.clusterDistrictName}, ${site.circleStateName}',
                    context,
                  );
                },
                onTap: () => _navigateToSite(CMSite.fromJson(site.toJson()), site),
                onDownloadTap: isDownloaded
                    ? null // Disable download if already downloaded
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
                color: Colors.white.withOpacity(0.7),
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
