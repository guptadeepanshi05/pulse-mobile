import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/commonWidgets/site_card.dart';
import 'package:app/constants/api_codes.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/corrective_maintenance_screen_mode_enum.dart';
import 'package:app/models/all_site_model.dart';
import 'package:app/screens/general_inspection/ginspection_detail.dart';
import 'package:app/screens/site_visit/site_visit.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/calculate_distance.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_colors.dart';
import '../constants/app_images.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class SitesInspectionsLogsScreen extends StatefulWidget {
  final String activityType;

  const SitesInspectionsLogsScreen({
    super.key,
    required this.activityType,
  });

  @override
  State<SitesInspectionsLogsScreen> createState() => _SitesInspectionsLogsScreenState();
}

class _SitesInspectionsLogsScreenState extends State<SitesInspectionsLogsScreen> {
  List<AllSiteModel> _sites = [];
  bool _isLoading = true;
  String? _errorMessage;
  final Set<int> _downloadedSiteIds = <int>{};
  bool _isInitializingDownloadedSites = false;

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final repository = ServiceLocator().sitesRepository;

      // Add timeout to prevent indefinite loading
      final sites = await repository
          .getAllSitesData(
            32.899, // Default latitude
            56.989, // Default longitude
            '', // Empty search text
            'ALL', // Get all sites
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
          _sites = sites;
          _isLoading = false;
        });

        // Initialize downloaded sites state after sites are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
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
      final isDownloaded = await ServiceLocator().centralAssetAuditDataService
          .isCMSiteDownloaded(site.siteId);
      return isDownloaded;
    } catch (e) {
      return false;
    }
  }

  Future<void> _downloadSiteData(AllSiteModel site) async {
    try {
      LoaderWidget.showLoader(context);

      // Use the new CM-specific download method
      final service = ServiceLocator().centralAssetAuditService;
      final isDownloaded = await service.downloadCMSiteData(site: site, siteType: widget.activityType);
      if (!mounted) return;

      if (isDownloaded) {
        // Add to local state and trigger UI update
        setState(() {
          _downloadedSiteIds.add(site.siteId);
        });

        // Re-initialize downloaded sites state to ensure consistency
        _initializeDownloadedSites(_sites);

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

  Future<void> _navigateToSite(AllSiteModel site) async {
    if (!mounted) return;
    final parentContext = context;

    try {
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

      try {
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

        final currentLocation = await LocationService.getCurrentLocation();
        if (!mounted) return;

        final distanceInKm = calculateDistance(
          currentLocation.latitude,
          currentLocation.longitude,
          siteLat!,
          siteLng!,
        );

        final maxDistanceKm = double.parse(ApiCodes.distanceFromLocation);
        if (distanceInKm > maxDistanceKm) {
          LoaderWidget.hideLoader();
          if (!mounted) return;
          Toastbar.showErrorToastbar(
            "You are not in the radius of site. Your distance from the site is: ${distanceInKm.toStringAsFixed(2)} km",
            context,
          );
          return;
        }
      } catch (e) {
        LoaderWidget.hideLoader();
        Logger.errorLog('Error calculating distance: $e');
        if (!mounted) return;
        Toastbar.showErrorToastbar(
          "Unable to get your location. Please ensure location services are enabled.",
          context,
        );
        return;
      }

      LoaderWidget.hideLoader();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => widget.activityType == 'Site Access'
              ? SiteVisitScreen(
                  siteData: site,
                  parentContext: parentContext,
                )
              : GInspectionDetailScreen(
                  siteData: site,
                  mode: CMScreenModeEnum.edit,
                  parentContext: parentContext,
                ),
        ),
      );
    } catch (e) {
      if (LoaderWidget.isShowing) {
        LoaderWidget.hideLoader();
      }
      Logger.errorLog('Error in _navigateToSite: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildCustomAppBar(),
      floatingActionButton: _shouldShowFloatingButton() ? _buildFloatingActionButton() : null,
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
              child: _buildBody(),
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
                  "Sites & Inspections Logs",
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    } else if (_errorMessage != null) {
      return _buildErrorWidget(_errorMessage!);
    } else if (_sites.isEmpty) {
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
          children: [
            getHeight(15),
            _buildSitesList(),
            getHeight(20),
          ],
        ),
      );
    }
  }

  Widget _buildSitesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sites.length,
      itemBuilder: (context, index) {
        final site = _sites[index];

        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _sites.length - 1 ? 0 : 5,
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
                onTap: () => _navigateToSite(site),
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
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontFamily: fontFamilyMontserrat,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSites,
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

  bool _shouldShowFloatingButton() {
    return widget.activityType == 'Site Access' || 
           widget.activityType == 'General Inspection';
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _onFloatingButtonPressed,
      backgroundColor: AppColors.primaryGreen,
      child: const Icon(
        Icons.add,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  void _onFloatingButtonPressed() {
    // Handle floating button press
    _showAddSiteDialog();
  }

  void _showAddSiteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add New ${widget.activityType == 'Site Access' ? "Site Visit" : "General Inspection"}'),
          content: Text('This will create a new ${widget.activityType == 'Site Access' ? "Site Visit" : "General Inspection"} entry.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Add your navigation logic here
                Toastbar.showSuccessToastbar('Create new site entry functionality', context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
