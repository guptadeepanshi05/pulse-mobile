import 'dart:convert';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/constants/api_codes.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/enum/corrective_maintenance_screen_mode_enum.dart';
import 'package:app/models/sqlite/raw_api_data_model.dart';
import 'package:app/models/screen_permission.dart';
import 'package:app/screens/corrective_maintainece/corrective_maintenance_screen.dart';
import 'package:app/models/all_site_model.dart';
import 'package:app/screens/general_inspection/ginspection_detail.dart';
import 'package:app/screens/incident_ticket/incident_detail_screen.dart';
import 'package:app/screens/site_visit/all_sites.dart';
import 'package:app/screens/site_visit/site_visit.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/asset_audit_post_service.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/map_api_field_reader.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/ticket_cubit.dart';
import '../bloc/ticket_state.dart';
import '../commonWidgets/ticket_card.dart';
import '../constants/app_colors.dart';
import '../constants/app_images.dart';
import '../models/ticket_model.dart';
import '../repositories/asset_upload_respository.dart';
import '../services/location_service.dart';
import '../utils/calculate_distance.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'asset_upload/asset_upload_detail_page.dart';
import 'energy_reading/energy_reading_screen.dart';
import 'preventive_maintainance/pm_page_render.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class TicketScreen extends StatefulWidget {
  final String auditName;
  final String status;
  final ScreenPermission? permission;

  const TicketScreen({
    super.key,
    required this.auditName,
    required this.status,
    this.permission,
  });

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen>
    with WidgetsBindingObserver {
  late String _currentTicketType;
  late ActivityTypeEnum _currentActivityType;
  final Set<int> _downloadedTicketIds = <int>{};
  // In-memory cache of "is this ticket downloaded" answers per ticketSchId.
  // Lets [_isTicketDownloaded] return a [SynchronousFuture] on rebuild so the
  // per-card FutureBuilder doesn't re-query SQLite (and flicker) every frame.
  final Map<int, bool> _downloadedCache = <int, bool>{};
  bool _isInitializingDownloadedTickets = false;
  bool _hasLoadedOnce =
      false; // Track if tickets have been loaded at least once
  DateTime?
      _lastRefreshTime; // Track last refresh time to prevent too frequent refreshes
  bool _wasRouteActive = true; // Track if route was previously active

  // Pagination: fixed page size; current page is tracked inside [TicketCubit].
  static const int _pageSize = 50;
  // Distance from list bottom (in px) that triggers the next page fetch.
  static const double _loadMoreThreshold = 300.0;
  // Show the back-to-top FAB once the user has scrolled past this many pixels.
  static const double _showScrollToTopAfter = 500.0;
  final ScrollController _scrollController = ScrollController();
  // Whether the scroll-to-top FAB should be visible. Driven by [_onScroll].
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    _currentTicketType = _getInitialTicketTypeFromStatus(widget.status);
    _currentActivityType = _getActivityTypeFromAuditName(widget.auditName);
    Logger.debugLog(
      '📋 TicketScreen initialized - ActivityType: $_currentActivityType, AuditName: ${widget.auditName}',
    );

    _loadTickets();
    _hasLoadedOnce = true;
    _lastRefreshTime = DateTime.now();

    // Initialize downloaded tickets state after a short delay to ensure tickets are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        final currentState = context.read<TicketCubit>().state;
        if (currentState is TicketSuccess &&
            currentState.ticketResponse.tickets.isNotEmpty) {
          _initializeDownloadedTickets(currentState.ticketResponse.tickets);
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Resolve the activity type string sent to the API. Incident tickets use a
  /// different code than the enum value.
  String get _apiActivityType => _currentActivityType == ActivityTypeEnum.incident
      ? 'IT'
      : _currentActivityType.value;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMoreTickets();
    }

    // Toggle the back-to-top FAB visibility. setState only when the value
    // actually changes so we don't rebuild on every pixel of scroll.
    final shouldShow = position.pixels > _showScrollToTopAfter;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _loadMoreTickets() {
    if (!mounted) return;
    final cubit = context.read<TicketCubit>();
    final currentState = cubit.state;
    if (currentState is! TicketSuccess) return;
    if (currentState.isLoadingMore || currentState.hasReachedMax) return;

    cubit.loadMoreTickets(
      activityType: _apiActivityType,
      ticketType: _currentTicketType,
      pageSize: _pageSize,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh when app comes back to foreground, but only if this screen is visible
    if (state == AppLifecycleState.resumed && _hasLoadedOnce && mounted) {
      // Check if this route is currently active before refreshing
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        _refreshTicketsIfNeeded();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when returning to this screen from another page
    if (_hasLoadedOnce && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final route = ModalRoute.of(context);
          final isRouteActive = route != null && route.isCurrent;
          
          // If route just became active again (was inactive, now active), refresh
          if (isRouteActive && !_wasRouteActive) {
            _wasRouteActive = true;
            _refreshTickets();
          } else if (isRouteActive) {
            _wasRouteActive = true;
            // Also refresh if route is active (handles case when coming back)
            _refreshTicketsIfNeeded();
          } else {
            _wasRouteActive = false;
          }
        }
      });
    }
  }

  void _refreshTicketsIfNeeded() {
    // Prevent too frequent refreshes (at least 500ms between refreshes)
    final now = DateTime.now();
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!).inMilliseconds < 500) {
      return;
    }

    _refreshTickets();
  }

  void _refreshTickets() {
    final now = DateTime.now();
    _lastRefreshTime = now;
    // Drop cached "not downloaded" answers so any newly downloaded tickets
    // (e.g., grabbed from a sub-screen workflow) are re-detected from SQLite.
    // Keep confirmed "true" entries to avoid a tick icon flicker on refresh.
    _downloadedCache.removeWhere((_, isDownloaded) => isDownloaded == false);
    _loadTickets();

    // Re-initialize downloaded tickets state after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        final currentState = context.read<TicketCubit>().state;
        if (currentState is TicketSuccess) {
          _initializeDownloadedTickets(currentState.ticketResponse.tickets);
        }
      }
    });
  }

  void _loadTickets() {
    context.read<TicketCubit>().getTickets(
      activityType: _apiActivityType,
      ticketType: _currentTicketType,
      pageSize: _pageSize,
      pageNo: 1,
    );
  }

  void _initializeDownloadedTickets(List<Ticket> tickets) async {
    // Prevent multiple initializations
    if (_isInitializingDownloadedTickets) return;
    _isInitializingDownloadedTickets = true;

    try {
      bool hasChanges = false;
      // Check which tickets are already downloaded and populate local state
      for (final ticket in tickets) {
        final isDownloaded = await _isTicketDownloaded(ticket);
        // _isTicketDownloaded already memoises; we just need to flip the
        // tracked set + trigger a rebuild for newly-discovered downloads.
        if (isDownloaded &&
            !_downloadedTicketIds.contains(ticket.ticketSchId)) {
          _downloadedTicketIds.add(ticket.ticketSchId);
          hasChanges = true;
        }
      }
      // Only trigger UI update if there were actual changes
      if (hasChanges && mounted) {
        setState(() {});
      }
    } finally {
      _isInitializingDownloadedTickets = false;
    }
  }

  ActivityTypeEnum _getActivityTypeFromAuditName(String auditName) {
    switch (auditName) {
      case "Asset Audit":
        return ActivityTypeEnum.assetAudit;
      case "AU":
      case "Asset Upload":
        return ActivityTypeEnum.assetUpload;
      case "PM":
        return ActivityTypeEnum.preventiveMaintenance;
      case "ER":
        return ActivityTypeEnum.energyReading;
      case "SV":
        return ActivityTypeEnum.siteVisit;
      case "GI":
        return ActivityTypeEnum.generalInspection;
      case "Incident":
        return ActivityTypeEnum.incident;
      default:
        return ActivityTypeEnum.correctiveMaintenance;
    }
  }

  String _getInitialTicketTypeFromStatus(String status) {
    switch (status.toLowerCase()) {
      case 'allocated':
        return TicketType.all;
      case 'in progress':
        return TicketType.open;
      case 'due':
        return TicketType.open;
      case 'completed':
        return TicketType.completed;
      case 'closed':
        return TicketType.closed;
      case 'missed deadline':
        return TicketType.missedDeadline;
      case 'assigned_to_me':
        return TicketType.assignedToMe;
      default:
        return TicketType.all;
    }
  }

  String _getStatusFromTicketType(String ticketType) {
    switch (ticketType) {
      case TicketType.open:
        return 'In Progress';
      case TicketType.completed:
        return 'Completed';
      case TicketType.closed:
        return 'Closed';
      case TicketType.missedDeadline:
        return 'Missed Deadline';
      case TicketType.all:
      default:
        return 'Allocated';
    }
  }

  /// CM ticket status badge: OPEN = orange, CLOSED = grey.
  Color? _getCmStatusColor(String status) {
    if (_currentActivityType != ActivityTypeEnum.correctiveMaintenance) {
      return null;
    }
    switch (status.trim().toLowerCase()) {
      case 'open':
        return Colors.orange;
      case 'closed':
      case 'close':
        return Colors.grey;
      default:
        return null;
    }
  }

  Future<void> _navigateToWorkflow(Ticket? ticket) async {
    if (ticket == null) return;

    try {
      // Show loader immediately when ticket is clicked
      LoaderWidget.showLoader(context);

      // Check distance from current location to ticket location
      if (ticket.latitude != null && ticket.longitude != null) {
        try {
          // Check location permission first
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
            if (!mounted) return;
            if (permission == LocationPermission.denied) {
              LoaderWidget.hideLoader();
              Toastbar.showErrorToastbar(
                "Location permission is required to access this ticket.",
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
                    'Please enable location permission in app settings to access this ticket.',
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
            ticket.latitude!,
            ticket.longitude!,
          );

           
          // Check if distance is more than the allowed distance (in km)
          final maxDistanceKm = double.parse(ApiCodes.distanceFromLocation) ; // Convert meters to km
          if (distanceInKm > maxDistanceKm) {

         
            // Hide loader before showing toast
            LoaderWidget.hideLoader();
            if (!mounted) return;
            Toastbar.showErrorToastbar(
              "You are not in the radius of site. Your distance from the site is: ${distanceInKm.toStringAsFixed(2)} km",
              context,
            );
            // Prevent ticket from opening if distance exceeds the allowed radius
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
      }
      // Determine site type - check if it's solar or telecom
      final siteType = ticket.siteDomainName ?? 'Solar';

      final service = ServiceLocator().centralAssetAuditService;

      // Try to get data from local database first
      RawApiDataModel? data = await service.getDataFromSqlite(
        siteAuditSchId: ticket.ticketSchId.toString(),
      );
      if (!mounted) return;

      // For incident and asset upload tickets, use special handling
      if (_currentActivityType == ActivityTypeEnum.incident ||
          _currentActivityType == ActivityTypeEnum.assetUpload) {
        // Skip the general data fetching - will handle in specific branch
      } else {
        // If not found in local DB, fetch from API and save
        if (data == null || !data.isDownloaded) {
          Logger.infoLog('📥 Data not found in local DB, fetching from API...');
          final isAvailable = await service.getDataFromApiAndSaveToSqlite(
            siteType: siteType,
            auditSchId: ticket.auditSchId?.toString() ?? "",
            siteAuditSchId: ticket.ticketSchId.toString(),
            latitude: ticket.latitude ?? 0,
            longitude: ticket.longitude ?? 0,
            activityType: _currentActivityType,
            pvTicketId: ticket.pvTicketId,
            siteCode: ticket.siteCode ?? "",
            cluster: ticket.cluster ?? "",
            operator: ticket.operator ?? "",
            raisedDt: ticket.raisedDt,
            dueDt: ticket.dueDt,
            status: ticket.status ?? "",
          );
          if (!mounted) return;
          if (!isAvailable) {
            Toastbar.showErrorToastbar("Failed to load data", context);
            return;
          }

          // Get the data from local DB after saving
          data = await service.getDataFromSqlite(
            siteAuditSchId: ticket.ticketSchId.toString(),
          );
          if (!mounted) return;
        } else {
          Logger.infoLog('✅ Using data from local database');
        }

        if (data == null) {
          Toastbar.showErrorToastbar("Failed to load data", context);
          return;
        }

        Logger.infoLog(
          '✅ Loaded data from ${data.isDownloaded ? 'local database' : 'API'}',
        );
        Logger.infoLog('📊 Data keys: ${data.apiData.keys.toList()}');
      }

      final apiData = data?.apiData ?? <String, dynamic>{};

      if (_currentActivityType == ActivityTypeEnum.preventiveMaintenance) {
        if (!mounted) return;
        final parentContext = context;
        // View mode when ticket status is Completed: all elements/images visible but non-editable.
        final statusText = ticket.status ?? '';
        final isViewMode =
            statusText.trim().toLowerCase() == 'completed';

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PMPageRender(
              pmData: apiData,
              parentContext: parentContext,
              isViewMode: isViewMode,
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          // PM completion should reflect on the ticket list card status.
          _refreshTickets();
        });
      } else if (_currentActivityType == ActivityTypeEnum.energyReading) {
        if (!mounted) return;
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EnergyReadingScreen(
              siteType: ticket.siteDomainName ?? "Telecom",
              auditSchId: ticket.auditSchId?.toString() ?? "",
              siteAuditSchId: ticket.ticketSchId.toString(),
              siteId: ticket.ticketSchId.toString(),
              parentContext: parentContext,
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          // Refresh ticket list when returning from Energy Reading screen
          _loadTickets();
          // Re-initialize downloaded tickets state
          final currentState = context.read<TicketCubit>().state;
          if (currentState is TicketSuccess) {
            _initializeDownloadedTickets(currentState.ticketResponse.tickets);
          }
        });
      } else if (_currentActivityType == ActivityTypeEnum.siteVisit) {
        // Create site data from API response with correct field mapping.
        // Support both camelCase and snake_case for image IDs (API/DB may use either).
        final visitingPersonImageId = apiData['visitingPersonImageId']?.toString() ??
            apiData['visiting_person_image_id']?.toString();
        final officialIdImageId = apiData['officialIdImageId']?.toString() ??
            apiData['official_id_image_id']?.toString();
        final aadharCardImageId = apiData['aadharCardImageId']?.toString() ??
            apiData['aadhar_card_image_id']?.toString();
        final leavingStatusImageId = apiData['leavingStatusImageId']?.toString() ??
            apiData['leaving_status_image_id']?.toString();

        final siteData = AllSiteModel(
          siteId: apiData['siteId'] ?? ticket.ticketSchId,
          entityId: 0, // Default value
          siteCode: apiData['siteCode'] ?? ticket.siteCode ?? '',
          siteName: apiData['siteName'] ?? ticket.cluster ?? '',
          clusterDistrictId: 0, // Default value
          clusterDistrictName: apiData['cluster'] ?? ticket.cluster ?? '',
          circleStateId: 0, // Default value
          circleStateName: apiData['circle'] ?? ticket.operator ?? '',
          clientId: null,
          clientName: apiData['client'] ?? ticket.operator,
          svlId: apiData['svlId']?.toString(),
          oem: null,
          oemId: null,
          self: '',
          selfId: 0,
          siteDomainName: ticket.siteDomainName,
          distanceKM: null,
          infraEngineerName: apiData['infraDistrictEngineerName'],
          infraEngineerPhone: apiData['infraDistrictEngineerContactNo'],
          ownerName: apiData['ownerName'],
          ownerPhone: apiData['ownerContactNo'],
          siteVisitLogId: apiData['svlId']?.toString(),
          siteVisitLogDate: apiData['visitDate']?.toString(),
          purposeOfVisit: apiData['purposeOfVisit']?.toString(),
          visitingPersonImageId: visitingPersonImageId,
          officialIdImageId: officialIdImageId,
          aadharCardImageId: aadharCardImageId,
          leavingStatusImageId: leavingStatusImageId,
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
        ); // site visit screen

        // Extract organisation list from API response if available
        final organisationList = apiData['organisationList'] != null
            ? (apiData['organisationList'] as List)
                  .map((org) => Map<String, dynamic>.from(org))
                  .toList()
            : null;

        if (!mounted) return;
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SiteVisitScreen(
              siteData: siteData,
              parentContext: parentContext,
              preloadedOrganisationList: organisationList,
              siteAuditSchIdForStorage: ticket.ticketSchId.toString(),
            ),
          ),
        );
      } else if (_currentActivityType == ActivityTypeEnum.incident) {
        // For incident tickets, always fetch fresh data from API to get latest status
        Map<String, dynamic>? incidentTicketData;

        try {
          // Always fetch fresh data from API to ensure we have the latest status
          Logger.debugLog(
            '🔄 Fetching fresh incident ticket data from API for ticket ID: ${ticket.ticketSchId}',
          );
          final response = await ServiceLocator().incidentRepository
              .getIncidentTicket(incidentTicketId: ticket.ticketSchId);
          if (!mounted) return;

          // Extract data from response (response has a 'data' wrapper)
          if (response.containsKey('data') && response['data'] is Map) {
            incidentTicketData = response['data'] as Map<String, dynamic>;
          } else {
            incidentTicketData = response;
          }

          Logger.debugLog(
            '✅ Successfully fetched fresh incident ticket data. Status: ${incidentTicketData['status']}',
          );
        } catch (e) {
          Logger.errorLog('❌ Error fetching fresh incident ticket data: $e');
          // Fallback to stored data if API call fails
          if (data != null && data.isDownloaded) {
            final storedData = data.apiData;
            if (storedData.containsKey('data') && storedData['data'] is Map) {
              incidentTicketData = storedData['data'] as Map<String, dynamic>;
            } else {
              incidentTicketData = storedData;
            }
            Logger.debugLog('⚠️ Using stored data as fallback');
          } else {
            if (!mounted) return;
            Toastbar.showErrorToastbar(
              "Failed to load incident ticket data",
              context,
            );
            return;
          }
        }

        if (incidentTicketData.isEmpty) {
          LoaderWidget.hideLoader();
          if (!mounted) return;
          Toastbar.showErrorToastbar(
            "Failed to load incident ticket data",
            context,
          );
          return;
        }

        final resolvedSiteId = int.tryParse(
              '${incidentTicketData['siteId'] ?? incidentTicketData['site_id'] ?? ticket.ticketSchId}',
            ) ??
            ticket.ticketSchId;

        final sqliteIncidentSite = await ServiceLocator()
            .centralAssetAuditDataService
            .getDownloadedIncidentSiteRow(resolvedSiteId);
        final sqliteCmSite = await ServiceLocator()
            .centralAssetAuditDataService
            .getCMSiteData(resolvedSiteId);
        if (!mounted) return;

        final siteFieldSource = mergeIncidentTicketWithSqliteSiteRows(
          incidentTicketData,
          [sqliteIncidentSite, sqliteCmSite],
        );

        // Get status from fresh API data to determine mode
        final apiStatus = incidentTicketData['status']?.toString();
        final currentStatus = (apiStatus != null && apiStatus.isNotEmpty)
            ? apiStatus
            : (ticket.status != null && ticket.status!.isNotEmpty
                  ? ticket.status!
                  : 'OPEN');

        // Build site data for Incident Ticket (camelCase + snake_case + SQLite site row)
        final siteData = AllSiteModel(
          siteId: resolvedSiteId,
          entityId: 0,
          siteCode: ticket.siteCode ?? '',
          siteName: ticket.cluster ?? '',
          clusterDistrictId: 0,
          clusterDistrictName: ticket.cluster ?? '',
          circleStateId: 0,
          circleStateName: ticket.operator ?? '',
          clientId: null,
          clientName: ticket.operator,
          svlId: null,
          oem: null,
          oemId: null,
          self: '',
          selfId: 0,
          siteDomainName: ticket.siteDomainName,
          distanceKM: null,
          infraEngineerName: readMapString(siteFieldSource, [
            'infraDistrictEngineerName',
            'infra_district_engineer_name',
          ]),
          infraEngineerPhone: readMapString(siteFieldSource, [
            'infraDistrictEngineerContactNo',
            'infra_district_engineer_contact_no',
          ]),
          ownerName: readMapString(siteFieldSource, [
            'ownerName',
            'owner_name',
          ]),
          ownerPhone: readMapString(siteFieldSource, [
            'ownerContactNo',
            'owner_contact_no',
          ]),
          clusterInchargeName: readMapString(siteFieldSource, [
            'clusterInchargeName',
            'cluster_incharge_name',
          ]),
          clusterInchargeContactNo: readMapString(siteFieldSource, [
            'clusterInchargeContactNo',
            'cluster_incharge_contact_no',
          ]),
          siteVisitLogId: null,
          siteVisitLogDate: null,
          purposeOfVisit: null,
          visitingPersonImageId: null,
          checklistItems: null,
        );

        if (!mounted) return;
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentDetilScreen(
              siteData: siteData,
              // Use status from fresh API data to determine mode
              mode: currentStatus == 'CLOSED' || currentStatus == 'CLOSE'
                  ? CMScreenModeEnum.view
                  : CMScreenModeEnum.edit,
              apiResponseData: incidentTicketData,
              parentContext: parentContext,
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          // Refresh ticket list when returning from Incident Detail screen
          _loadTickets();
          // Re-initialize downloaded tickets state
          final currentState = context.read<TicketCubit>().state;
          if (currentState is TicketSuccess) {
            _initializeDownloadedTickets(currentState.ticketResponse.tickets);
          }
        });
      } else if (_currentActivityType == ActivityTypeEnum.generalInspection) {
        // For General Inspection, get checklist data from API response
        final genInspectionData = apiData;

        // Extract the actual data from the nested structure
        final actualData = genInspectionData['data'] as Map<String, dynamic>?;

        if (!mounted) return;
        if (actualData == null) {
          Toastbar.showErrorToastbar(
            "General inspection data structure is invalid",
            context,
          );
          return;
        }

        // Get checklist data from local database
        final checklistData = await ServiceLocator()
            .centralAssetAuditDataService
            .getGIChecklistData(ticket.ticketSchId);
        if (!mounted) return;

        // Map full GI `data` payload (camelCase / Schd ids) into site model for UI + PDF ids.
        final siteData = AllSiteModel.fromGeneralInspectionApi(
          d: actualData,
          siteId: ticket.ticketSchId,
          siteCodeFallback: ticket.siteCode,
          siteNameFallback: ticket.cluster,
          clusterFallback: ticket.cluster,
          circleFallback: ticket.operator,
          clientFallback: ticket.operator,
          siteDomainName: ticket.siteDomainName,
          checklistItems: checklistData,
        );

        if (!mounted) return;
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GInspectionDetailScreen(
              siteData: siteData,
              mode: ticket.status == 'COMPLETED' || ticket.status == 'CLOSED'
                  ? CMScreenModeEnum.view
                  : CMScreenModeEnum.edit,
              apiResponseData: actualData,
              parentContext: parentContext,
            ),
          ),
        );
      } else if (_currentActivityType ==
          ActivityTypeEnum.correctiveMaintenance) {
        if (!mounted || !context.mounted) return;

        final physicalSiteId = resolveCmPhysicalSiteId(apiData);
        final sqliteCmSite = physicalSiteId > 0
            ? await ServiceLocator()
                .centralAssetAuditDataService
                .getCMSiteData(physicalSiteId)
            : null;
        if (!mounted || !context.mounted) return;

        var mergedInner = mergeIncidentTicketWithSqliteSiteRows(
          unwrapTicketDataMap(apiData),
          [sqliteCmSite],
        );

        if (cmTicketPayloadMissingSiteContacts(mergedInner) &&
            physicalSiteId > 0 &&
            await ConnectivityHelper.isConnected()) {
          try {
            final sites =
                await ServiceLocator().cmRepository.getCMSitesDropdown();
            for (final site in sites) {
              if (site.siteId == physicalSiteId) {
                mergedInner = overlayCmSiteContactFields(
                  base: mergedInner,
                  infraName: site.infraEngineerName,
                  infraPhone: site.infraEngineerContactNo,
                  clusterInchargeName: site.clusterInchargeName,
                  clusterInchargeContact: site.clusterInchargeContactNo,
                );
                break;
              }
            }
          } catch (e) {
            Logger.errorLog(
              '⚠️ Could not load CM site contacts from dropdown: $e',
            );
          }
        }

        final Map<String, dynamic> cmPreloaded;
        if (apiData.containsKey('data') && apiData['data'] is Map) {
          cmPreloaded = Map<String, dynamic>.from(apiData);
          cmPreloaded['data'] = mergedInner;
        } else {
          cmPreloaded = mergedInner;
        }

        final parentContext = context;
        pushPage(
          context,
          CorrectiveMaintenanceScreen(
            mode: ticket.status == 'COMPLETED' || ticket.status == 'Closed'
                ? CMScreenModeEnum.view
                : CMScreenModeEnum.edit,
            preloadedSiteData: cmPreloaded,
            parentContext: parentContext,
          ),
        );
      } else if (_currentActivityType == ActivityTypeEnum.assetUpload) {
        // For Asset Upload, call getUploadedAssets API
        // Note: For asset upload tickets, ticket.ticketSchId is the siteId
        Logger.debugLog('📦 ========== ASSET UPLOAD TICKET CLICKED ==========');
        Logger.debugLog('📦 Ticket ID: ${ticket.ticketSchId}');
        Logger.debugLog(
          '📦 Site ID (using ticket.ticketSchId): ${ticket.ticketSchId}',
        );
        Logger.debugLog('📦 Activity Type: $_currentActivityType');
        Logger.debugLog('📦 Calling getUploadedAssets API with siteId...');
        try {
          // Use siteId if available, otherwise fallback to ticketSchId
          final siteId = ticket.siteId ?? ticket.ticketSchId;
          Logger.debugLog(
            '🔄 Fetching asset upload data from API for siteId: $siteId',
          );
          final repository = AssetUploadRepository(ServiceLocator().apiService);
          final result = await repository.getUploadedAssets(siteId: siteId);
          if (!mounted) return;

          Logger.debugLog(
            '📦 API Response - Success: ${result.isSuccess}, Status: ${result.statusCode}',
          );
          Logger.debugLog('📦 API Response - Error: ${result.errorMessage}');
          Logger.debugLog(
            '📦 API Response - Data keys: ${result.data?.keys.toList()}',
          );
          Logger.debugLog('📦 API Response - Data: ${result.data}');

          if (!result.isSuccess || result.data == null) {
            LoaderWidget.hideLoader();
            final errorMsg =
                result.errorMessage ?? 'Failed to load asset upload data';
            Logger.errorLog('❌ Failed to fetch asset upload data: $errorMsg');
            Toastbar.showErrorToastbar(errorMsg, context);
            return;
          }

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

          if (responseData == null) {
            LoaderWidget.hideLoader();
            Logger.errorLog(
              '❌ Invalid asset upload data structure: responseData is null',
            );
            Toastbar.showErrorToastbar(
              'Invalid asset upload data structure',
              context,
            );
            return;
          }

          Logger.debugLog(
            '📦 Response data keys: ${responseData.keys.toList()}',
          );

          // Try both camelCase and snake_case field names
          final assetUploadData =
              responseData['assetUpload'] ??
              responseData['asset_upload'] as Map<String, dynamic>?;
          final siteDetailsData =
              responseData['siteDetails'] ??
              responseData['site_details'] as Map<String, dynamic>?;

          Logger.debugLog('📦 AssetUpload data: ${assetUploadData != null}');
          Logger.debugLog('📦 SiteDetails data: ${siteDetailsData != null}');

          if (assetUploadData == null || siteDetailsData == null) {
            LoaderWidget.hideLoader();
            final missingData = [];
            if (assetUploadData == null)
              missingData.add('assetUpload/asset_upload');
            if (siteDetailsData == null)
              missingData.add('siteDetails/site_details');
            Logger.errorLog('❌ Missing data fields: ${missingData.join(", ")}');
            Logger.errorLog(
              '❌ Available keys in response: ${responseData.keys.toList()}',
            );
            Toastbar.showErrorToastbar(
              'Missing ${missingData.join(" or ")} data. Check logs for details.',
              context,
            );
            return;
          }

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

          Logger.debugLog('📦 ========== EXTRACTED DATA ==========');
          Logger.debugLog(
            '📦 makerSelfieImageId: $makerSelfieImageId (type: ${makerSelfieImageId.runtimeType})',
          );
          Logger.debugLog('📦 auId: $auId (type: ${auId.runtimeType})');
          Logger.debugLog(
            '📦 assetUploadItems count: ${assetUploadItems.length}',
          );
          Logger.debugLog('📦 assetUploadItems: $assetUploadItems');
          Logger.debugLog('📦 ====================================');

          // Create AllSiteModel from siteDetailsData
          final siteData = AllSiteModel(
            siteId: siteDetailsData['site_id'] ?? ticket.ticketSchId,
            entityId: siteDetailsData['entity_id'] ?? 0,
            siteCode:
                siteDetailsData['site_code']?.toString() ??
                ticket.siteCode ??
                '',
            siteName:
                siteDetailsData['site_name']?.toString() ??
                ticket.cluster ??
                '',
            clusterDistrictId: 0,
            clusterDistrictName:
                siteDetailsData['cluster']?.toString() ?? ticket.cluster ?? '',
            circleStateId: 0,
            circleStateName:
                siteDetailsData['circle']?.toString() ?? ticket.operator ?? '',
            clientId: null,
            clientName:
                siteDetailsData['client']?.toString() ?? ticket.operator,
            svlId: null,
            oem: null,
            oemId: null,
            self: '',
            selfId: 0,
            siteDomainName: ticket.siteDomainName,
            distanceKM: null,
            infraEngineerName: siteDetailsData['infra_district_engineer_name']
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

          // Convert asset_upload_item to format expected by AssetUploadDetailPage
          final List<Map<String, dynamic>> parsedAssetItems = assetUploadItems
              .map((item) {
                if (item is Map<String, dynamic>) {
                  return Map<String, dynamic>.from(item);
                }
                return <String, dynamic>{};
              })
              .where((item) => item.isNotEmpty)
              .toList();

          Logger.debugLog(
            '✅ Successfully fetched asset upload data. Items: ${parsedAssetItems.length}',
          );

          // Prepare values for navigation
          final finalMakerSelfieImageId = makerSelfieImageId?.toString();
          final finalAuId = auId != null
              ? (auId is int ? auId : int.tryParse(auId.toString()))
              : null;
          final finalAssetItems = parsedAssetItems.isNotEmpty
              ? parsedAssetItems
              : null;

          Logger.debugLog('📤 ========== NAVIGATING WITH DATA ==========');
          Logger.debugLog(
            '📤 preloadedSelfieImageId: $finalMakerSelfieImageId',
          );
          Logger.debugLog('📤 preloadedAuId: $finalAuId');
          Logger.debugLog(
            '📤 preloadedAssetItems: ${finalAssetItems != null ? finalAssetItems.length : "null"}',
          );
          Logger.debugLog('📤 =========================================');

          if (!mounted) return;
          final parentContext = context;
          LoaderWidget.hideLoader();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AssetUploadDetailPage(
                siteData: siteData,
                parentContext: parentContext,
                preloadedSelfieImageId: finalMakerSelfieImageId,
                preloadedAssetItems: finalAssetItems,
                preloadedAuId: finalAuId,
                mode: CMScreenModeEnum
                    .edit, // Edit mode when coming from ticket screen
                siteAuditSchIdForStorage: ticket.ticketSchId.toString(),
              ),
            ),
          );
        } catch (e, stackTrace) {
          LoaderWidget.hideLoader();
          Logger.errorLog('❌ Error fetching asset upload data: $e');
          Logger.errorLog('❌ Stack trace: $stackTrace');
          final errorMessage = e.toString();
          if (!mounted) return;
          Toastbar.showErrorToastbar(
            errorMessage.length > 100
                ? 'Error loading asset upload data. Check logs for details.'
                : 'Error loading asset upload data: $errorMessage',
            context,
          );
        }
      } else {
        if (!mounted) return;
        AssetAuditNavigationHelper.navigateToFirstAssetAuditScreen(
          siteType: siteType,
          auditSchId: ticket.auditSchId?.toString() ?? "",
          siteAuditSchId: ticket.ticketSchId.toString(),
          context: context,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Toastbar.showErrorToastbar("Failed to load data", context);
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  void _navigateToAuditScreen(Ticket? ticket) {
    if (ticket == null) return;

    Logger.debugLog(
      '🎫 _navigateToAuditScreen called for ticket: ${ticket.ticketSchId}',
    );
    Logger.debugLog('🎫 Current activity type: $_currentActivityType');
    Logger.debugLog('🎫 Widget audit name: ${widget.auditName}');

    // Check if ticket status is completed, closed, or missed deadline
    final status = ticket.status?.toLowerCase() ?? '';
    if (status == 'missed deadline' ||  (status == 'completed' && (_currentActivityType == ActivityTypeEnum.assetAudit || _currentActivityType == ActivityTypeEnum.preventiveMaintenance || _currentActivityType == ActivityTypeEnum.energyReading ))) {
      Toastbar.showInfoToastbar(
        "Ticket can't be opened. Please download PDF.",
        context,
      );
      return;
    }

    switch (_currentActivityType) {
      case ActivityTypeEnum.correctiveMaintenance:
        _navigateToWorkflow(ticket);
        break;
      default:
        _navigateToWorkflow(ticket);
        break;
    }
  }

  Future<bool> _isTicketDownloaded(Ticket ticket) {
    // 1. Synchronous fast path: in-memory cache or known-downloaded set.
    //    SynchronousFuture lets FutureBuilder skip the loading state entirely,
    //    which is the difference between a smooth scroll and a hitchy one when
    //    100+ cards rebuild after appending a page.
    final cached = _downloadedCache[ticket.ticketSchId];
    if (cached != null) return SynchronousFuture<bool>(cached);
    if (_downloadedTicketIds.contains(ticket.ticketSchId)) {
      _downloadedCache[ticket.ticketSchId] = true;
      return SynchronousFuture<bool>(true);
    }
    // 2. Slow path: actually hit SQLite, then memoise.
    return _computeDownloadedFromSqlite(ticket).then((isDownloaded) {
      _downloadedCache[ticket.ticketSchId] = isDownloaded;
      if (isDownloaded) _downloadedTicketIds.add(ticket.ticketSchId);
      return isDownloaded;
    });
  }

  Future<bool> _computeDownloadedFromSqlite(Ticket ticket) async {
    // Handle General Inspection tickets differently
    if (_currentActivityType == ActivityTypeEnum.generalInspection) {
      return await ServiceLocator().centralAssetAuditDataService
          .isGIChecklistDownloaded(ticket.ticketSchId);
    }
    if (_currentActivityType == ActivityTypeEnum.assetUpload) {
      // AU: row may be keyed by ticketSchId (downloaded from ticket screen)
      // or siteId (downloaded from All Sites).
      RawApiDataModel? data = await ServiceLocator().centralAssetAuditService
          .getDataFromSqlite(siteAuditSchId: ticket.ticketSchId.toString());
      if (data != null && data.isDownloaded) return true;
      if (ticket.siteId != null) {
        data = await ServiceLocator().centralAssetAuditService
            .getDataFromSqlite(siteAuditSchId: ticket.siteId.toString());
        if (data != null && data.isDownloaded) return true;
      }
      return false;
    }
    // For other ticket types, check database for existing downloads
    final data = await ServiceLocator().centralAssetAuditService
        .getDataFromSqlite(siteAuditSchId: ticket.ticketSchId.toString());
    return data != null && data.isDownloaded;
  }

  @override
  Widget build(BuildContext context) {
    // Check if route is active and refresh if we just returned to this screen
    if (_hasLoadedOnce && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final route = ModalRoute.of(context);
          final isRouteActive = route != null && route.isCurrent;
          
          // If route just became active again (was inactive, now active), refresh
          if (isRouteActive && !_wasRouteActive) {
            _wasRouteActive = true;
            _refreshTickets();
          } else if (isRouteActive) {
            _wasRouteActive = true;
          } else {
            _wasRouteActive = false;
          }
        }
      });
    }
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildCustomAppBar(),

      floatingActionButton: _buildFloatingActionButtons(),
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
              child: BlocBuilder<TicketCubit, TicketState>(
                bloc: context.read<TicketCubit>(),
                builder: (context, state) {
                  if (state is TicketLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    );
                  } else if (state is TicketSuccess) {
                    if (state.ticketResponse.tickets.isEmpty) {
                      // Show "no tickets" message in center of screen
                      return const Center(
                        child: Text(
                          'No tickets found for this selection',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    } else {
                      // Show ticket list with lazy-load pagination.
                      // CustomScrollView + SliverList builds cards on demand
                      // as they scroll into view, so growing the list past
                      // 50/100/200 items doesn't increase per-rebuild cost.
                      return CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 15)),
                          _buildTicketListSliver(state.ticketResponse),
                          if (state.isLoadingMore)
                            SliverToBoxAdapter(
                                child: _buildLoadMoreIndicator()),
                          if (state.hasReachedMax &&
                              state.ticketResponse.tickets.length >= _pageSize)
                            SliverToBoxAdapter(
                                child: _buildEndOfListIndicator()),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 20)),
                        ],
                      );
                    }
                  } else if (state is TicketFailure) {
                    return _buildErrorWidget(state.errorMessage);
                  } else {
                    return const SizedBox.shrink();
                  }
                },
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
                  widget.auditName == "SV"
                      ? "Site Access Logs"
                      : widget.auditName == "GI"
                      ? "General Inspection"
                      : widget.auditName == "Incident"
                      ? "Incident Tickets"
                      : widget.auditName == "Asset Upload"
                      ? "Asset Upload"
                      : "${widget.auditName} - ${widget.status}",
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

  Widget _buildTicketListSliver(TicketResponse ticketResponse) {
    return SliverList.builder(
      itemCount: ticketResponse.tickets.length,
      itemBuilder: (itemContext, index) {
        final ticket = ticketResponse.tickets[index];
        // Use API status when present. For types where list payload often omits status (SV, AU, GI),
        // do not show filter-based labels like "Allocated" — matches cards when status is null/empty.
        final resolvedStatus = ticket.status?.trim();
        final statusText = (resolvedStatus != null && resolvedStatus.isNotEmpty)
            ? resolvedStatus
            : (_currentActivityType == ActivityTypeEnum.assetUpload ||
                  _currentActivityType == ActivityTypeEnum.siteVisit ||
                  _currentActivityType == ActivityTypeEnum.generalInspection ||
                  _currentActivityType ==
                      ActivityTypeEnum.generalInspectionSelf)
            ? ''
            : _getStatusFromTicketType(_currentTicketType);

        return Padding(
          padding: EdgeInsets.only(
            bottom: index == ticketResponse.tickets.length - 1 ? 0 : 10,
          ),
          child: TicketCard(
            ticket: ticket,
            ticketId: ticket.pvTicketId,
            siteCode: ticket.siteCode ?? 'N/A',
            siteId: ticket.cluster ?? 'N/A',
            location: ticket.cluster ?? 'N/A',
            company: ticket.operator ?? 'N/A',
            raisedOn: (_currentActivityType == ActivityTypeEnum.assetUpload &&
                    ticket.lastModifiedDt != null &&
                    ticket.lastModifiedDt!.trim().isNotEmpty)
                ? ticket.lastModifiedDt!.trim()
                : ticket.raisedDt,
            dueDate: _currentActivityType ==
                    ActivityTypeEnum.correctiveMaintenance
                ? ''
                : ticket.dueDt,
            totalAssets: ticket.totalAssets,
            statusText: statusText,
            statusColor: _getCmStatusColor(statusText),
            activityType: _currentActivityType,
            isDownloadedFunc: _isTicketDownloaded,
            onPdfDownloadTap: () => _downloadReport(ticket),
            onTap: () => _navigateToAuditScreen(ticket),
            onDirectionTap: () {
              if (ticket.longitude != null && ticket.latitude != null) {
                // Open Google Maps with directions to the site
                LocationService.openDirectionsToSite(
                  siteLat: ticket.latitude!,
                  siteLng: ticket.longitude!,
                  siteName: ticket.pvTicketId,
                  context: itemContext,
                );
              } else {
                // Show a message to the user
                ScaffoldMessenger.of(itemContext).showSnackBar(
                  SnackBar(
                    content: Text('Directions are not available for this site'),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            },
            onDownloadTap: () async {
              try {
                LoaderWidget.showLoader(itemContext);
                bool isDownloaded = false;

                // Handle Asset Upload tickets differently
                if (_currentActivityType == ActivityTypeEnum.assetUpload) {
                  // Use siteId if available, otherwise fallback to ticketSchId
                  final siteId = ticket.siteId ?? ticket.ticketSchId;
                  Logger.debugLog(
                    '📥 Downloading asset upload data for siteId: $siteId',
                  );

                  final repository = AssetUploadRepository(
                    ServiceLocator().apiService,
                  );
                  final result = await repository.getUploadedAssets(
                    siteId: siteId,
                  );
                  if (!mounted || !itemContext.mounted) return;

                  if (result.isSuccess && result.data != null) {
                    // Parse response structure - check if data is wrapped or direct
                    Map<String, dynamic>? responseData;
                    if (result.data!.containsKey('data')) {
                      responseData =
                          result.data!['data'] as Map<String, dynamic>?;
                    } else {
                      responseData = result.data;
                    }

                    if (responseData != null) {
                      // Include total_asset_cnt and site_id so My Tickets and All Sites can match this ticket/site
                      final apiDataToSave = Map<String, dynamic>.from(responseData);
                      if (ticket.totalAssets != null) {
                        apiDataToSave['total_asset_cnt'] = ticket.totalAssets;
                      }
                      apiDataToSave['site_id'] = ticket.siteId ?? ticket.ticketSchId;
                      // Download all images and replace server IDs with local unique_ids so offline mode can show selfie and asset images
                      final processedApiData = await ServiceLocator()
                          .centralAssetAuditService
                          .processImagesInApiData(
                            apiDataToSave,
                            ActivityTypeEnum.assetUpload,
                            ticket.ticketSchId.toString(),
                          );
                      // Save processed data (with unique_ids) to SQLite
                      isDownloaded = await ServiceLocator()
                          .centralAssetAuditDataService
                          .saveRawApiData(
                            siteAuditSchId: ticket.ticketSchId.toString(),
                            siteType: ticket.siteDomainName ?? 'Solar',
                            auditSchId: ticket.auditSchId?.toString() ?? "",
                            pvTicketId: ticket.pvTicketId,
                            siteCode: ticket.siteCode ?? "",
                            cluster: ticket.cluster ?? "",
                            operator: ticket.operator ?? "",
                            raisedDt: ticket.raisedDt,
                            dueDt: ticket.dueDt,
                            status: ticket.status ?? "",
                            isDownloaded: true,
                            activityType: _currentActivityType,
                            latitude: ticket.latitude ?? 0,
                            longitude: ticket.longitude ?? 0,
                            apiData: processedApiData,
                          );
                      if (!mounted) return;
                    } else {
                      Logger.errorLog(
                        '❌ Invalid asset upload data structure: responseData is null',
                      );
                      Toastbar.showErrorToastbar(
                        'Invalid asset upload data structure',
                        itemContext,
                      );
                    }
                  } else {
                    final errorMsg =
                        result.errorMessage ??
                        'Failed to download asset upload data';
                    Logger.errorLog(
                      '❌ Failed to download asset upload data: $errorMsg',
                    );
                    Toastbar.showErrorToastbar(errorMsg, itemContext);
                  }
                } else {
                  // Handle General Inspection tickets differently

                  // For other ticket types, use the existing downloadData method
                  final service = ServiceLocator().centralAssetAuditService;
                  isDownloaded = await service.downloadData(
                    siteType: ticket.siteDomainName ?? 'Solar',
                    auditSchId: ticket.auditSchId?.toString() ?? "",
                    siteAuditSchId: ticket.ticketSchId.toString(),
                    pvTicketId: ticket.pvTicketId,
                    siteCode: ticket.siteCode ?? "",
                    cluster: ticket.cluster ?? "",
                    operator: ticket.operator ?? "",
                    raisedDt: ticket.raisedDt,
                    dueDt: ticket.dueDt,
                    status: ticket.status ?? "",
                    latitude: ticket.latitude ?? 0,
                    longitude: ticket.longitude ?? 0,

                    activityType: _currentActivityType,
                  );
                  if (!mounted || !itemContext.mounted) return;
                }

                if (isDownloaded) {
                  if (!mounted || !itemContext.mounted) return;
                  // Add to local state and trigger UI update
                  setState(() {
                    _downloadedTicketIds.add(ticket.ticketSchId);
                    _downloadedCache[ticket.ticketSchId] = true;
                  });

                  // Re-initialize downloaded tickets state to ensure consistency
                  final currentState = itemContext.read<TicketCubit>().state;
                  if (currentState is TicketSuccess) {
                    _initializeDownloadedTickets(
                      currentState.ticketResponse.tickets,
                    );
                  }

                  Toastbar.showSuccessToastbar(
                    "Data downloaded successfully",
                    itemContext,
                  );
                } else {
                  if (!mounted || !itemContext.mounted) return;
                  Toastbar.showErrorToastbar(
                    "Failed to download data, please try again",
                    itemContext,
                  );
                }
              } finally {
                LoaderWidget.hideLoader();
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                color: AppColors.primaryGreen,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading more tickets…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: fontFamilyMontserrat,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndOfListIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Center(
        child: Text(
          'No more tickets',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
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
              'Error loading tickets',
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
              onPressed: _loadTickets,
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

  // download pdf report
  Future<void> _downloadReport(Ticket ticket) async {
    if (_currentActivityType == ActivityTypeEnum.energyReading) {
      Toastbar.showErrorToastbar(
        'PDF report not available for this activity type',
        context,
      );
      return;
    }

    try {
      LoaderWidget.showLoader(context);

      // Use CentralApiService to download PDF
      final service = ServiceLocator().centralApiService;
      final filePath = await service.downloadPdfReport(
        ticketId: ticket.pvTicketId,
        ticketSchId: ticket.ticketSchId.toString(),
        activityType: _currentActivityType,
      );
      if (!mounted) return;

      if (filePath != null) {
        // Check if it's in public Downloads or app storage
        String locationMessage;
        if (filePath.contains('/Download/')) {
          locationMessage =
              'PDF saved to Downloads folder! Open file manager → Downloads to view';
        } else {
          locationMessage =
              'PDF saved to app storage. Check Android → data → com.rapadit.flutter_template_rad → files → Downloads';
        }

        Toastbar.showSuccessToastbar(locationMessage, context);

        // Show additional info about file location
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File saved to: $filePath'),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(label: 'OK', onPressed: () {}),
            ),
          );
        });
      } else {
        if (!mounted) return;
        Toastbar.showErrorToastbar('Failed to download PDF', context);
      }
    } catch (e) {
      String errorMessage = 'Error downloading PDF';

      if (e.toString().contains('Storage permission denied')) {
        errorMessage =
            'Storage permission denied. Please grant storage permission in app settings.';
      } else if (e.toString().contains('Network')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('404')) {
        errorMessage = 'PDF report not found. Please try again later.';
      }

      if (!mounted) return;
      Toastbar.showErrorToastbar(errorMessage, context);
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Widget _buildFloatingActionButtons() {
    final showAddSyncButtons =
        _currentActivityType == ActivityTypeEnum.siteVisit ||
            _currentActivityType == ActivityTypeEnum.generalInspection ||
            _currentActivityType == ActivityTypeEnum.incident ||
            _currentActivityType == ActivityTypeEnum.assetUpload;

    // Nothing to show: hide the FAB area entirely.
    if (!showAddSyncButtons && !_showScrollToTop) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];

    if (showAddSyncButtons) {
      if (_canShowAddButton()) {
        children.add(FloatingActionButton(
          onPressed: _onFloatingButtonPressed,
          backgroundColor: AppColors.primaryGreen,
          heroTag: "add_fab",
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ));
        children.add(const SizedBox(height: 16));
      }
      children.add(FloatingActionButton(
        onPressed: _syncOfflineData,
        backgroundColor: Colors.blue,
        heroTag: "sync_fab",
        tooltip: 'Sync Offline Data',
        child: const Icon(Icons.sync, color: Colors.white),
      ));
    }

    // Back-to-top FAB: appears once user has scrolled past
    // [_showScrollToTopAfter]; tapping animates the list to offset 0.
    if (_showScrollToTop) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 12));
      }
      children.add(FloatingActionButton(
        onPressed: _scrollToTop,
        backgroundColor: AppColors.primaryGreen,
        heroTag: "scroll_to_top_fab",
        mini: true,
        tooltip: 'Back to top',
        child: const Icon(Icons.arrow_upward, color: Colors.white),
      ));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  bool _canShowAddButton() {
    return widget.permission?.canAdd ?? true;
  }

  void _onFloatingButtonPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AllSitesScreen(ActivityType: _currentActivityType.value),
      ),
    );
  }

  /// Syncs offline data by checking pending requests and posting them to the server
  Future<void> _syncOfflineData() async {
    // Refuse to start a second sweep while one is already running so the same
    // pending_requests row isn't POSTed twice (which the server records as
    // duplicate `pclsri_id` / `pclsrd_id` entries).
    if (!AssetAuditPostService.beginSyncSweep()) {
      Logger.infoLog('TicketScreen: Sync already in progress, ignoring tap');
      if (mounted) {
        Toastbar.showInfoToastbar('Sync already in progress', context);
      }
      return;
    }
    try {
      Logger.infoLog('🔄 TicketScreen: Starting offline data sync');

      // Get pending requests
      final pendingRequestsService = ServiceLocator().pendingRequestService;
      final pendingRequests = await pendingRequestsService.getPendingRequests();
      if (!mounted) return;

      Logger.infoLog(
        'TicketScreen: Found ${pendingRequests.length} pending requests',
      );

      if (pendingRequests.isEmpty) {
        Logger.infoLog('TicketScreen: No pending requests found');
        Toastbar.showInfoToastbar('No pending requests to sync', context);
        return;
      }
      int successCount = 0;
      int totalCount = pendingRequests.length;
      // Process each pending request
      for (final request in pendingRequests) {
        try {
          await ServiceLocator().assetAuditPostService
              .syncRequestsWhenUserComesOnline(
                request['url'],
                jsonDecode(request['request_data']),
                request['request_id'],
              );
          successCount++;
        } catch (e) {
          Logger.errorLog(
            'TicketScreen: Failed to sync request ${request['request_id']}: $e',
          );
        }
      }

      // Show sync result
      final message =
          'Sync completed: $successCount successful, out of $totalCount';
      Logger.infoLog('TicketScreen: $message');
      if (!mounted) return;
      Toastbar.showSuccessToastbar(message, context);
    } catch (e) {
      Logger.errorLog('TicketScreen: Error during sync: $e');
      if (!mounted) return;
      Toastbar.showErrorToastbar('Sync failed: $e', context);
    } finally {
      AssetAuditPostService.endSyncSweep();
    }
  }
}
