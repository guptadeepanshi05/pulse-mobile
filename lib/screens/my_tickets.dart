import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/constants/api_codes.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/models/all_site_model.dart';
import 'package:app/models/pmis_project_activity_model.dart';
import 'package:app/models/sqlite/raw_api_data_model.dart';
import 'package:app/services/asset_audit/central_asset_audit_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/asset_audit_navigation_helper.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:app/utils/map_api_field_reader.dart';
import 'package:app/utils/calculate_distance.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:app/models/pmis_activity_ticket_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../commonWidgets/activity_card.dart';
import '../commonWidgets/ticket_card.dart';
import '../constants/app_colors.dart';
import '../constants/app_images.dart';
import '../models/ticket_model.dart';
import '../services/location_service.dart';
import 'corrective_maintainece/corrective_maintenance_screen.dart';
import 'energy_reading/energy_reading_screen.dart';
import 'general_inspection/ginspection_detail.dart';
import 'incident_ticket/incident_detail_screen.dart';
import 'pmis/activity_ticket/activity_ticket_checker_list.dart';
import 'preventive_maintainance/pm_page_render.dart';
import 'site_visit/site_visit.dart';
import 'asset_upload/asset_upload_detail_page.dart';
import '../enum/corrective_maintenance_screen_mode_enum.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen>
    with WidgetsBindingObserver {
  List<RawApiDataModel> _downloadedTickets = [];
  List<RawApiDataModel> _filteredTickets = [];
  List<Map<String, dynamic>> _downloadedSites = [];
  List<Map<String, dynamic>> _filteredSites = [];
  /// For Asset Upload sites: siteId -> total asset count (from raw_api_data)
  Map<int, int> _siteIdToTotalAssets = {};
  bool _isLoading = true;
  String? _errorMessage;
  ActivityTypeEnum? _selectedActivityType;
  bool _hasLoadedOnce = false;
  bool _wasRouteActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDownloadedTickets();
    _hasLoadedOnce = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
            _loadDownloadedTickets();
          } else if (isRouteActive) {
            _wasRouteActive = true;
          } else {
            _wasRouteActive = false;
          }
        }
      });
    }
  }

  ActivityTypeEnum _parseActivityTypeFromString(String activityTypeStr) {
    // Normalize the string
    final normalized = activityTypeStr.toLowerCase().trim();

    // Map various possible formats to enum
    if (normalized == 'correctivemaintenance' || normalized == 'cm') {
      return ActivityTypeEnum.correctiveMaintenance;
    } else if (normalized == 'sitevisit' ||
        normalized == 'sv' ||
        normalized == 'site access') {
      return ActivityTypeEnum.siteVisit;
    } else if (normalized == 'generalinspection' || normalized == 'gi') {
      return ActivityTypeEnum.generalInspection;
    } else if (normalized == 'incident' || normalized == 'it') {
      return ActivityTypeEnum.incident;
    } else if (normalized == 'assetupload' || normalized == 'au') {
      return ActivityTypeEnum.assetUpload;
    } else {
      // Fallback to try the standard enum conversion
      try {
        return ActivityTypeEnum.fromString(activityTypeStr);
      } catch (e) {
        return ActivityTypeEnum.correctiveMaintenance; // Default fallback
      }
    }
  }

  Future<void> _loadDownloadedTickets() async {
    if (!mounted) return;
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final tickets = await ServiceLocator().centralAssetAuditDataService
          .getAllDownloadedTickets();
      final sites = await ServiceLocator().centralAssetAuditDataService
          .getAllDownloadedCMSites();

      // For Asset Upload sites, get total_asset_cnt from raw_api_data so My Tickets can show it
      final Map<int, int> siteIdToTotalAssets = {};
      for (final siteMap in sites) {
        final activityTypeStr = siteMap['activity_type']?.toString() ?? '';
        if (_parseActivityTypeFromString(activityTypeStr) !=
            ActivityTypeEnum.assetUpload) continue;
        final siteId = siteMap['site_id'];
        if (siteId == null) continue;
        final sid = siteId is int ? siteId : int.tryParse(siteId.toString());
        if (sid == null) continue;
        try {
          final raw = await ServiceLocator().centralAssetAuditDataService
              .getRawApiData(sid.toString());
          if (raw != null &&
              raw.apiData['total_asset_cnt'] != null) {
            final cnt = int.tryParse(raw.apiData['total_asset_cnt'].toString());
            if (cnt != null) siteIdToTotalAssets[sid] = cnt;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _downloadedTickets = tickets;
        _downloadedSites = sites;
        _siteIdToTotalAssets = siteIdToTotalAssets;
        _selectedActivityType = ActivityTypeEnum.assetAudit;
        _filteredTickets = tickets
            .where(
              (ticket) => ticket.activityType == ActivityTypeEnum.assetAudit,
            )
            .toList();
        _filteredSites = sites
            .where(
              (site) =>
                  _parseActivityTypeFromString(
                    site['activity_type']?.toString() ?? '',
                  ) ==
                  ActivityTypeEnum.assetAudit,
            )
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _filterTicketsByActivityType(ActivityTypeEnum? activityType) {
    setState(() {
      _selectedActivityType = activityType;
      if (activityType == null) {
        _filteredTickets = _downloadedTickets;
        _filteredSites = _downloadedSites;
      } else {
        _filteredTickets = _downloadedTickets
            .where((ticket) => ticket.activityType == activityType)
            .toList();
        _filteredSites = _downloadedSites
            .where(
              (site) =>
                  _parseActivityTypeFromString(
                    site['activity_type']?.toString() ?? '',
                  ) ==
                  activityType,
            )
            .toList();

        // For Site Visit and Asset Upload, filter out duplicates - if a site appears in both tickets and sites,
        // prefer the site entry (from cm_sites_data) and remove the ticket entry (from raw_api_data)
        if (activityType == ActivityTypeEnum.siteVisit ||
            activityType == ActivityTypeEnum.assetUpload) {
          final siteIdsInSites = _filteredSites
              .map((site) => site['site_id']?.toString())
              .where((id) => id != null)
              .toSet();

          _filteredTickets = _filteredTickets.where((ticket) {
            // Keep tickets that don't have a corresponding site entry
            // Tickets from raw_api_data with empty pvTicketId are sites downloaded from "All Sites"
            final ticketSiteId = ticket.siteAuditSchId;
            return !siteIdsInSites.contains(ticketSiteId);
          }).toList();
        }
      }
    });
  }

  int _getTicketCountForActivityType(ActivityTypeEnum activityType) {
    final filteredTickets = _downloadedTickets
        .where((ticket) => ticket.activityType == activityType)
        .toList();
    final filteredSites = _downloadedSites
        .where(
          (site) =>
              _parseActivityTypeFromString(
                site['activity_type']?.toString() ?? '',
              ) ==
              activityType,
        )
        .toList();

    // For Site Visit and Asset Upload, avoid double-counting duplicates
    if (activityType == ActivityTypeEnum.siteVisit ||
        activityType == ActivityTypeEnum.assetUpload) {
      final siteIdsInSites = filteredSites
          .map((site) => site['site_id']?.toString())
          .where((id) => id != null)
          .toSet();

      final uniqueTickets = filteredTickets.where((ticket) {
        return !siteIdsInSites.contains(ticket.siteAuditSchId);
      }).length;

      return uniqueTickets + filteredSites.length;
    }

    return filteredTickets.length + filteredSites.length;
  }

  String _getActivityTypeDisplayName(ActivityTypeEnum activityType) {
    switch (activityType) {
      case ActivityTypeEnum.assetAudit:
        return "Asset Audit";
      case ActivityTypeEnum.preventiveMaintenance:
        return "Preventive Maintenance";
      case ActivityTypeEnum.correctiveMaintenance:
        return "Corrective Maintenance";
      case ActivityTypeEnum.energyReading:
        return "Energy Reading";
      case ActivityTypeEnum.siteVisit:
      case ActivityTypeEnum.siteVisitLog:
      case ActivityTypeEnum.siteVisitDocs:
        return "Site Visit";
      case ActivityTypeEnum.generalInspection:
      case ActivityTypeEnum.generalInspectionSelf:
      case ActivityTypeEnum.generalInspChecklist:
        return "General Inspection";       
      case ActivityTypeEnum.incident:
      case ActivityTypeEnum.incidentSelf:
        return "Incident";
      case ActivityTypeEnum.assetUpload:
        return "Asset Upload";
      case ActivityTypeEnum.projectTicket:
        return "Project";
      case ActivityTypeEnum.activityTicket:
        return "Activities";
      case ActivityTypeEnum.itAssetIssueTicket:
        return "IT Raise Ticket";
    }
  }

  /// CM ticket status badge: OPEN = orange, CLOSED = grey (matches ticket_screen).
  Color? _getCmStatusColor(ActivityTypeEnum activityType, String status) {
    if (activityType != ActivityTypeEnum.correctiveMaintenance) {
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

  Future<void> _navigateToWorkflow(RawApiDataModel ticket) async {
    try {
      LoaderWidget.showLoader(context);

      // Use ServiceLocator to get the service
      final service = ServiceLocator().centralAssetAuditService;
      final data = await service.getDataFromSqlite(
        siteAuditSchId: ticket.siteAuditSchId,
      );
      if (!mounted) return;

      if (data == null) {
        Toastbar.showErrorToastbar("Failed to load data", context);
        return;
      }

      if (ticket.activityType == ActivityTypeEnum.preventiveMaintenance) {
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PMPageRender(
              pmData: data.apiData,
              parentContext: parentContext,
            ),
          ),
        ).then((_) {
          if (!mounted) return;
          // PM completion should reflect on the ticket list card status.
          _loadDownloadedTickets();
        });
      } else if (ticket.activityType == ActivityTypeEnum.energyReading) {
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EnergyReadingScreen(
              siteType: ticket.siteType,
              auditSchId: ticket.auditSchId,
              siteAuditSchId: ticket.siteAuditSchId,
              siteId: ticket.siteAuditSchId,
              parentContext: parentContext,
            ),
          ),
        );
      } else if (ticket.activityType == ActivityTypeEnum.siteVisit) {
        // Create site data from API response with correct field mapping
        final siteData = AllSiteModel(
          siteId:
              data.apiData['siteId'] ??
              int.tryParse(ticket.siteAuditSchId) ??
              0,
          entityId: 0, // Default value
          siteCode: data.apiData['siteCode'] ?? ticket.siteCode,
          siteName: data.apiData['siteName'] ?? ticket.cluster,
          clusterDistrictId: 0, // Default value
          clusterDistrictName: data.apiData['cluster'] ?? ticket.cluster,
          circleStateId: 0, // Default value
          circleStateName: data.apiData['circle'] ?? ticket.operator,
          clientId: null,
          clientName: data.apiData['client'] ?? ticket.operator,
          oem: null,
          oemId: null,
          self: '',
          selfId: 0,
          siteDomainName: ticket.siteType,
          distanceKM: null,
          infraEngineerName: data.apiData['infraDistrictEngineerName'],
          infraEngineerPhone: data.apiData['infraDistrictEngineerContactNo'],
          ownerName: data.apiData['ownerName'],
          ownerPhone: data.apiData['ownerContactNo'],
          siteVisitLogId: data.apiData['svlId']?.toString(),
          siteVisitLogDate: data.apiData['visitDate']?.toString(),
          purposeOfVisit: data.apiData['purposeOfVisit']?.toString(),
          visitingPersonImageId: data.apiData['visitingPersonImageId']
              ?.toString(),
          officialIdImageId: data.apiData['officialIdImageId']?.toString(),
          aadharCardImageId: data.apiData['aadharCardImageId']?.toString(),
          leavingStatusImageId: data.apiData['leavingStatusImageId']
              ?.toString(),
          visitorName:
              data.apiData['visitorName']?.toString() ??
              data.apiData['visitor_name']?.toString(),
          visitorContactNo:
              data.apiData['visitorContactNo']?.toString() ??
              data.apiData['visitor_contact_no']?.toString(),
          organisationName:
              data.apiData['organisationName']?.toString() ??
              data.apiData['organisation_name']?.toString() ??
              data.apiData['organizationName']?.toString() ??
              data.apiData['organization_name']?.toString(),
          orgId: data.apiData['orgId'] != null
              ? (data.apiData['orgId'] is int
                    ? data.apiData['orgId'] as int
                    : int.tryParse(data.apiData['orgId'].toString()))
              : null,
          roleDesignation:
              data.apiData['roleDesignation']?.toString() ??
              data.apiData['role_designation']?.toString(),
          reportingManager:
              data.apiData['reportingManager']?.toString() ??
              data.apiData['reporting_manager']?.toString(),
        );

        // Extract organisation list from API response if available
        final organisationList = data.apiData['organisationList'] != null
            ? (data.apiData['organisationList'] as List)
                  .map((org) => Map<String, dynamic>.from(org))
                  .toList()
            : null;

        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SiteVisitScreen(
              siteData: siteData,
              parentContext: parentContext,
              preloadedOrganisationList: organisationList,
              siteAuditSchIdForStorage: ticket.siteAuditSchId,
            ),
          ),
        );
      } else if (ticket.activityType == ActivityTypeEnum.generalInspection ||
          ticket.activityType == ActivityTypeEnum.generalInspectionSelf ||
          ticket.activityType == ActivityTypeEnum.generalInspChecklist) {
        // For General Inspection, get checklist data from API response
        final genInspectionData = data.apiData;

        // Extract the actual data from the nested structure
        final actualData = genInspectionData['data'] as Map<String, dynamic>?;

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
            .getGIChecklistData(int.tryParse(ticket.siteAuditSchId) ?? 0);
        if (!mounted) return;

        final siteData = AllSiteModel.fromGeneralInspectionApi(
          d: actualData,
          siteId: int.tryParse(ticket.siteAuditSchId) ?? 0,
          siteCodeFallback: ticket.siteCode,
          siteNameFallback: ticket.cluster,
          clusterFallback: ticket.cluster,
          circleFallback: ticket.operator,
          clientFallback: ticket.operator,
          siteDomainName: ticket.siteType,
          checklistItems: checklistData,
        );

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
      } else if (ticket.activityType ==
          ActivityTypeEnum.correctiveMaintenance) {
        final apiData = data.apiData;
        final physicalSiteId = resolveCmPhysicalSiteId(apiData);
        final sqliteCmSite = physicalSiteId > 0
            ? await ServiceLocator()
                .centralAssetAuditDataService
                .getCMSiteData(physicalSiteId)
            : null;
        if (!mounted) return;

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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CorrectiveMaintenanceScreen(
              mode: _resolveCmScreenMode(ticket, data.apiData),
              preloadedSiteData: cmPreloaded,
              parentContext: parentContext,
            ),
          ),
        );
      } else if (ticket.activityType == ActivityTypeEnum.incident ||
          ticket.activityType == ActivityTypeEnum.incidentSelf) {
        // For incident tickets, always fetch fresh data from API to get latest status
        Map<String, dynamic>? incidentTicketData;

        try {
          // Always fetch fresh data from API to ensure we have the latest status
          Logger.debugLog(
            '🔄 Fetching fresh incident ticket data from API for ticket ID: ${ticket.siteAuditSchId}',
          );
          final response = await ServiceLocator().incidentRepository
              .getIncidentTicket(
                incidentTicketId: int.tryParse(ticket.siteAuditSchId) ?? 0,
              );
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
          final storedData = data.apiData;
          if (storedData.containsKey('data') && storedData['data'] is Map) {
            incidentTicketData = storedData['data'] as Map<String, dynamic>;
          } else {
            incidentTicketData = storedData;
          }
          Logger.debugLog('⚠️ Using stored data as fallback');
        }

        if (incidentTicketData.isEmpty) {
          LoaderWidget.hideLoader();
          Toastbar.showErrorToastbar(
            "Failed to load incident ticket data",
            context,
          );
          return;
        }

        final resolvedSiteId = int.tryParse(
              '${incidentTicketData['siteId'] ?? incidentTicketData['site_id'] ?? ticket.siteAuditSchId}',
            ) ??
            (int.tryParse(ticket.siteAuditSchId) ?? 0);

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
            : (ticket.status.isNotEmpty ? ticket.status : 'OPEN');

        // Build site data for Incident Ticket (camelCase + snake_case + SQLite site row)
        final siteData = AllSiteModel(
          siteId: resolvedSiteId,
          entityId: 0,
          siteCode: ticket.siteCode,
          siteName: ticket.cluster,
          clusterDistrictId: 0,
          clusterDistrictName: ticket.cluster,
          circleStateId: 0,
          circleStateName: ticket.operator,
          clientId: null,
          clientName: ticket.operator,
          svlId: null,
          oem: null,
          oemId: null,
          self: '',
          selfId: 0,
          siteDomainName: ticket.siteType,
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
        );
      } else if (ticket.activityType == ActivityTypeEnum.assetUpload) {
        // For Asset Upload, parse the stored data and navigate to AssetUploadDetailPage
        Logger.debugLog('📦 Loading Asset Upload ticket from downloaded data');

        // Parse response structure - check if data is wrapped or direct
        Map<String, dynamic>? responseData;
        if (data.apiData.containsKey('data')) {
          responseData = data.apiData['data'] as Map<String, dynamic>?;
          Logger.debugLog('📦 Found data wrapper, extracting inner data');
        } else {
          responseData = data.apiData;
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

        Logger.debugLog('📦 Response data keys: ${responseData.keys.toList()}');

        // Try both camelCase and snake_case field names
        final assetUploadData =
            responseData['assetUpload'] ??
            responseData['asset_upload'] as Map<String, dynamic>?;
        final siteDetailsData =
            responseData['siteDetails'] ??
            responseData['site_details'] as Map<String, dynamic>?;

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
            'Missing ${missingData.join(" or ")} data.',
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

        Logger.debugLog('📦 Found ${assetUploadItems.length} asset items');
        Logger.debugLog('📦 AuId: $auId');

        // Create AllSiteModel from siteDetailsData
        final siteData = AllSiteModel(
          siteId:
              siteDetailsData['site_id'] ??
              int.tryParse(ticket.siteAuditSchId ?? '') ??
              0,
          entityId: siteDetailsData['entity_id'] ?? 0,
          siteCode:
              siteDetailsData['site_code']?.toString() ??
              (ticket.siteCode ?? ''),
          siteName:
              siteDetailsData['site_name']?.toString() ??
              (ticket.cluster ?? ''),
          clusterDistrictId: 0,
          clusterDistrictName:
              siteDetailsData['cluster']?.toString() ?? ticket.cluster ?? '',
          circleStateId: 0,
          circleStateName:
              siteDetailsData['circle']?.toString() ?? ticket.operator ?? '',
          clientId: null,
          clientName: siteDetailsData['client']?.toString() ?? ticket.operator,
          svlId: null,
          oem: null,
          oemId: null,
          self: '',
          selfId: 0,
          siteDomainName: ticket.siteType,
          distanceKM: null,
          infraEngineerName: siteDetailsData['infra_district_engineer_name']
              ?.toString(),
          infraEngineerPhone:
              siteDetailsData['infra_district_engineer_contact_no']?.toString(),
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
          '✅ Successfully loaded asset upload data. Items: ${parsedAssetItems.length}',
        );

        final parentContext = context;
        LoaderWidget.hideLoader();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AssetUploadDetailPage(
              siteData: siteData,
              parentContext: parentContext,
              preloadedSelfieImageId: makerSelfieImageId?.toString(),
              preloadedAssetItems: parsedAssetItems.isNotEmpty
                  ? parsedAssetItems
                  : null,
              preloadedAuId: auId != null
                  ? (auId is int ? auId : int.tryParse(auId.toString()))
                  : null,
              mode: CMScreenModeEnum
                  .edit, // Edit mode when coming from my tickets
              siteAuditSchIdForStorage: ticket.siteAuditSchId,
            ),
          ),
        );
      } else if (ticket.activityType == ActivityTypeEnum.activityTicket) {
        final detail = PmisActivityTicketDetail.fromJson(
          Map<String, dynamic>.from(data.apiData),
        );
        final title = ticket.siteCode.trim().isNotEmpty
            ? ticket.siteCode.trim()
            : 'Activity';
        final summary = ticket.cluster.trim().isNotEmpty
            ? ticket.cluster.trim()
            : null;
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActivityTicketCheckerListScreen(
              activityTicketId: int.tryParse(ticket.siteAuditSchId) ?? 0,
              breadcrumbText: 'My Tickets > Activities',
              activityName: title,
              summaryCardTitle: summary,
              preloadedDetail: detail,
            ),
          ),
        );
      } else {
        AssetAuditNavigationHelper.navigateToFirstAssetAuditScreen(
          siteType: ticket.siteType,
          auditSchId: ticket.auditSchId,
          siteAuditSchId: ticket.siteAuditSchId,
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

  Future<void> _navigateToAuditScreen(RawApiDataModel ticket) async {
    // Keep restricted statuses non-openable (CM closed tickets open in view mode).
    final status = ticket.status.toLowerCase();
    if (ticket.activityType != ActivityTypeEnum.correctiveMaintenance &&
        (status == 'closed' ||
            status == 'close' ||
            status == 'missed deadline')) {
      Toastbar.showInfoToastbar(
        "Ticket can't be opened. Please download PDF.",
        context,
      );
      return;
    }

    // Check distance from current location to ticket location (works in offline/online mode)
    LoaderWidget.showLoader(context);

    if (!hasValidSiteCoordinates(ticket.latitude, ticket.longitude)) {
      LoaderWidget.hideLoader();
      if (mounted) {
        Toastbar.showErrorToastbar(siteNotInRadiusMessage, context);
      }
      return;
    }

    try {
      // Check location permission first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          LoaderWidget.hideLoader();
          if (mounted) {
            Toastbar.showErrorToastbar(
              "Location permission is required to access this ticket.",
              context,
            );
          }
          return;
        }
      }

      if (!mounted) return;

      if (permission == LocationPermission.deniedForever) {
        LoaderWidget.hideLoader();
        if (!mounted) return;
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

      if (!mounted) return;

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
        ticket.latitude,
        ticket.longitude,
      );

      // Check if distance is more than the allowed distance
      // distanceFromLocation is in meters; convert to km for comparison
      final maxDistanceKm =
          double.parse(ApiCodes.distanceFromLocation) ;
      if (distanceInKm > maxDistanceKm) {
        // Hide loader before showing toast
        LoaderWidget.hideLoader();
        if (mounted) {
          Toastbar.showErrorToastbar(
            siteNotInRadiusMessage,
            context,
          );
        }
        // Prevent ticket from opening if distance exceeds the allowed radius
        return;
      }

      // Hide loader after distance check passes (will be shown again in _navigateToWorkflow if needed)
      LoaderWidget.hideLoader();
    } catch (e) {
      // If location fetch fails, hide loader and show error
      LoaderWidget.hideLoader();
      Logger.errorLog('Error calculating distance: $e');
      if (mounted) {
        Toastbar.showErrorToastbar(
          "Unable to get your location. Please ensure location services are enabled.",
          context,
        );
      }
      return;
    }

    if (!mounted) return;

    switch (ticket.activityType) {
      case ActivityTypeEnum.assetAudit:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.preventiveMaintenance:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.correctiveMaintenance:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.energyReading:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.siteVisit:
      case ActivityTypeEnum.siteVisitLog:
      case ActivityTypeEnum.siteVisitDocs:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.generalInspection:
      case ActivityTypeEnum.generalInspectionSelf:
      case ActivityTypeEnum.generalInspChecklist:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.incident:
      case ActivityTypeEnum.incidentSelf:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.assetUpload:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.projectTicket:
      case ActivityTypeEnum.activityTicket:
        await _navigateToWorkflow(ticket);
        break;
      case ActivityTypeEnum.itAssetIssueTicket:
        break;
    }
  }

  /// My Tickets reads `raw_api_data.status`; asset audit only updated `api_data` until we
  /// synced `pageHeader.status` on save. Prefer column, then payload (older rows).
  ///
  /// For incidents, prefer the DB column so the card stays OPEN until sync even when
  /// offline edits merged `data.status` into `api_data` for the detail screen.
  String _displayStatusForTicket(RawApiDataModel rawData) {
    final col = rawData.status.trim();
    final fromIncident = CentralAssetAuditService.statusFromIncidentApiData(
      Map<String, dynamic>.from(rawData.apiData),
    );

    if (rawData.activityType == ActivityTypeEnum.incident ||
        rawData.activityType == ActivityTypeEnum.incidentSelf) {
      if (col.isNotEmpty && col.toUpperCase() != 'N/A') {
        return col;
      }
      if (fromIncident != null && fromIncident.isNotEmpty) {
        return fromIncident;
      }
      return 'N/A';
    }

    if (col.isNotEmpty && col.toUpperCase() != 'N/A') {
      return col;
    }
    final fromPayload =
        CentralAssetAuditService.statusFromAssetAuditApiData(rawData.apiData);
    if (fromPayload != null && fromPayload.isNotEmpty) {
      return fromPayload;
    }
    return col.isEmpty ? 'N/A' : rawData.status;
  }

  String? _cmStatusFromApiData(Map<String, dynamic> apiData) {
    var map = mergeNestedSiteMapsIntoIncidentTicket(
      Map<String, dynamic>.from(apiData),
    );
    if (map['data'] is Map<String, dynamic>) {
      map = mergeNestedSiteMapsIntoIncidentTicket(
        Map<String, dynamic>.from(map['data'] as Map),
      );
    }
    final status = map['status'] ?? map['Status'];
    if (status == null) return null;
    final text = status.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _isCmClosedOrCompletedStatus(String? status) {
    if (status == null) return false;
    final normalized = status.trim().toUpperCase();
    return normalized == 'CLOSED' ||
        normalized == 'CLOSE' ||
        normalized == 'COMPLETED';
  }

  CMScreenModeEnum _resolveCmScreenMode(
    RawApiDataModel ticket,
    Map<String, dynamic> apiData,
  ) {
    final apiStatus = _cmStatusFromApiData(apiData);
    if (_isCmClosedOrCompletedStatus(apiStatus) ||
        _isCmClosedOrCompletedStatus(_displayStatusForTicket(ticket)) ||
        _isCmClosedOrCompletedStatus(ticket.status)) {
      return CMScreenModeEnum.view;
    }
    return CMScreenModeEnum.edit;
  }

  // Convert RawApiDataModel to Ticket for display
  Ticket _convertToTicket(RawApiDataModel rawData) {
    final totalAssets = rawData.apiData['total_asset_cnt'] != null
        ? int.tryParse(rawData.apiData['total_asset_cnt'].toString())
        : null;
    return Ticket(
      ticketSchId: int.tryParse(rawData.siteAuditSchId) ?? 0,
      pvTicketId: rawData.pvTicketId,
      siteCode: rawData.siteCode,
      cluster: rawData.cluster,
      operator: rawData.operator,
      raisedDt: rawData.raisedDt,
      dueDt: rawData.dueDt,
      status: _displayStatusForTicket(rawData),
      latitude: rawData.latitude,
      longitude: rawData.longitude,
      auditSchId: int.tryParse(rawData.auditSchId),
      siteDomainName: rawData.siteType,
      totalAssets: totalAssets,
    );
  }

  PmisProjectActivity _convertToPmisProjectActivity(RawApiDataModel rawData) {
    final apiMap = Map<String, dynamic>.from(rawData.apiData);
    final nestedData = apiMap['data'] is Map
        ? Map<String, dynamic>.from(apiMap['data'] as Map)
        : <String, dynamic>{};

    dynamic readFirst(List<String> keys) {
      for (final key in keys) {
        if (apiMap.containsKey(key) && apiMap[key] != null) {
          return apiMap[key];
        }
        if (nestedData.containsKey(key) && nestedData[key] != null) {
          return nestedData[key];
        }
      }
      return null;
    }

    dynamic deepFindByKeys(dynamic node, List<String> keys) {
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        for (final key in keys) {
          if (map.containsKey(key) && map[key] != null) {
            return map[key];
          }
        }
        for (final entry in map.entries) {
          final found = deepFindByKeys(entry.value, keys);
          if (found != null) return found;
        }
      } else if (node is List) {
        for (final item in node) {
          final found = deepFindByKeys(item, keys);
          if (found != null) return found;
        }
      }
      return null;
    }

    String deriveApprovalStatus() {
      final direct = readFirst([
        'approval_status',
        'approvalStatus',
        'approvalstatus',
      ]);
      final deepDirect = deepFindByKeys(apiMap, [
        'approval_status',
        'approvalStatus',
        'approvalstatus',
      ]);
      final resolved = direct ?? deepDirect;
      if (resolved != null && resolved.toString().trim().isNotEmpty) {
        return resolved.toString().trim();
      }

      if (rawData.status.trim().isNotEmpty &&
          rawData.status.trim().toUpperCase() != 'N/A') {
        return rawData.status.trim();
      }

      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }

      final ticketCheckers = readFirst(['ticketCheckers']);
      if (ticketCheckers is List) {
        var pending = 0;
        for (final checker in ticketCheckers) {
          if (checker is! Map) continue;
          final m = Map<String, dynamic>.from(checker);
          final decision = (m['decisionStatus'] ?? m['decision_status'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          if (decision.isEmpty || decision == 'PENDING') {
            pending++;
          }
        }
        if (pending > 0) return '$pending Approvals Pending';
      }
      return '';
    }

    final derivedApprovalStatus = deriveApprovalStatus();
    final explicitActivityStatus = (readFirst([
          'activity_status',
          'activityStatus',
          'activitystatus',
        ]) ??
        deepFindByKeys(apiMap, [
          'activity_status',
          'activityStatus',
          'activitystatus',
        ]));

    String? statusFromHistory() {
      final history = readFirst(['ticketStatusHistory']) ??
          deepFindByKeys(apiMap, ['ticketStatusHistory']);
      if (history is! List || history.isEmpty) return null;
      for (final item in history) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final candidate = (m['status'] ??
                m['activity_status'] ??
                m['activityStatus'] ??
                m['currentStatus'])
            ?.toString()
            .trim();
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
      return null;
    }

    final derivedActivityStatus = (explicitActivityStatus != null &&
            explicitActivityStatus.toString().trim().isNotEmpty)
        ? explicitActivityStatus.toString()
        : (statusFromHistory() ??
            (rawData.status.trim().isNotEmpty ? rawData.status.trim() : ''));
    final derivedState = (readFirst([
              'state',
              'state_name',
              'stateName',
              'circle_state_name',
              'circleStateName',
              'circle',
            ]) ??
            deepFindByKeys(apiMap, [
              'state',
              'state_name',
              'stateName',
              'circle_state_name',
              'circleStateName',
              'circle',
            ]))
        ?.toString();

    return PmisProjectActivity.fromJson({
      ...apiMap,
      ...nestedData,
      'at_id': readFirst(['at_id', 'atId', 'activityTicketId']) ??
          int.tryParse(rawData.siteAuditSchId),
      'site_name': readFirst(['site_name', 'siteName']) ?? rawData.siteCode,
      'module_name':
          readFirst(['module_name', 'moduleName']) ?? rawData.operator,
      'sub_module_name': readFirst(['sub_module_name', 'subModuleName']) ??
          rawData.cluster,
      'activity_name':
          readFirst(['activity_name', 'activityName']) ?? rawData.siteCode,
      'approval_status': readFirst([
            'approval_status',
            'approvalStatus',
            'approvalstatus',
          ]) ??
          derivedApprovalStatus,
      'activity_status': derivedActivityStatus,
      'planned_start_dt':
          readFirst(['planned_start_dt', 'plannedStartDt']) ?? rawData.raisedDt,
      'planned_end_dt':
          readFirst(['planned_end_dt', 'plannedEndDt']) ?? rawData.dueDt,
      'actual_start_dt': readFirst(['actual_start_dt', 'actualStartDt']),
      'actual_end_dt': readFirst(['actual_end_dt', 'actualEndDt']),
      'is_geo_fenced': readFirst(['is_geo_fenced', 'isGeoFenced']) ?? false,
      'state': derivedState ?? '',
      'distance_km': readFirst(['distance_km', 'distanceKm']) ?? '',
      'distance_m': readFirst(['distance_m', 'distanceM']),
      'latitude': readFirst(['latitude', 'lat']) ?? rawData.latitude,
      'longitude': readFirst(['longitude', 'lng', 'long']) ?? rawData.longitude,
    });
  }

  // download pdf report
  Future<void> _downloadReport(RawApiDataModel ticket) async {
    if (ticket.activityType != ActivityTypeEnum.preventiveMaintenance &&
        ticket.activityType != ActivityTypeEnum.assetAudit) {
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
        ticketSchId: ticket.siteAuditSchId,
        activityType: ticket.activityType,
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

      Toastbar.showErrorToastbar(errorMessage, context);
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
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(
            left: 10,
            top: 12,
            right: 0,
            bottom: 10,
          ),
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
                  "My Tickets",
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

  Widget _buildFilterBar() {
    final activityTypes = [
      ActivityTypeEnum.assetAudit,
      ActivityTypeEnum.preventiveMaintenance,
      ActivityTypeEnum.correctiveMaintenance,
      ActivityTypeEnum.energyReading,
      ActivityTypeEnum.siteVisit,
      ActivityTypeEnum.generalInspection,
      ActivityTypeEnum.incident,
      ActivityTypeEnum.assetUpload,
      ActivityTypeEnum.activityTicket,
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: activityTypes.length,
        itemBuilder: (context, index) {
          final activityType = activityTypes[index];
          final count = _getTicketCountForActivityType(activityType);
          final isSelected = _selectedActivityType == activityType;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildFilterButton(
              activityType: activityType,
              count: count,
              isSelected: isSelected,
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterButton({
    required ActivityTypeEnum activityType,
    required int count,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => _filterTicketsByActivityType(activityType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.myTicketsSelected : AppColors.myTickets,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          '${_getActivityTypeDisplayName(activityType)} ($count)',
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.dashboardTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
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
    } else if (_filteredTickets.isEmpty && _filteredSites.isEmpty) {
      return Center(
        child: Text(
          _downloadedTickets.isEmpty && _downloadedSites.isEmpty
              ? 'No downloaded tickets found'
              : 'No tickets found for ${_selectedActivityType != null ? _getActivityTypeDisplayName(_selectedActivityType!) : 'selected filter'}',
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
          children: [
            getHeight(15),
            _buildTicketList(),
            _buildSiteList(),
            getHeight(20),
          ],
        ),
      );
    }
  }

  Widget _buildTicketList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredTickets.length,
      itemBuilder: (context, index) {
        final rawTicket = _filteredTickets[index];

        if (rawTicket.activityType == ActivityTypeEnum.activityTicket) {
          final activity = _convertToPmisProjectActivity(rawTicket);
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == _filteredTickets.length - 1 ? 0 : 10,
            ),
            child: ActivityCard(
              activity: activity,
              showProjectHierarchy: false,
              isOfflineDownloaded: true,
              onTap: () async {
                await _navigateToAuditScreen(rawTicket);
              },
              onDirectionTap: () {
                if (activity.longitude != null && activity.latitude != null) {
                  LocationService.openDirectionsToSite(
                    siteLat: activity.latitude!,
                    siteLng: activity.longitude!,
                    siteName: activity.siteName,
                    context: context,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Directions are not available for this activity',
                      ),
                      backgroundColor: AppColors.errorColor,
                    ),
                  );
                }
              },
              onDownloadTap: () async {
                Toastbar.showInfoToastbar("Activity already downloaded", context);
              },
            ),
          );
        }

        final ticket = _convertToTicket(rawTicket);

        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _filteredTickets.length - 1 ? 0 : 10,
          ),
          child: TicketCard(
            ticket: ticket,
            ticketId: ticket.pvTicketId,
            siteCode: ticket.siteCode ?? 'N/A',
            siteId: ticket.cluster ?? 'N/A',
            location: ticket.cluster ?? 'N/A',
            company: ticket.operator ?? 'N/A',
            raisedOn: ticket.raisedDt,
            dueDate: rawTicket.activityType ==
                    ActivityTypeEnum.correctiveMaintenance
                ? ''
                : ticket.dueDt,
            statusText: ticket.status ?? 'N/A',
            statusColor: _getCmStatusColor(
              rawTicket.activityType,
              ticket.status ?? 'N/A',
            ),
            totalAssets: ticket.totalAssets,
            activityType: rawTicket.activityType,
            isDownloadedFunc: (ticket) async =>
                true, // All tickets here are downloaded
            onPdfDownloadTap: () => _downloadReport(rawTicket),
            onTap: () async {
              await _navigateToAuditScreen(rawTicket);
            },
            onDirectionTap: () {
              if (ticket.longitude != null && ticket.latitude != null) {
                // Open Google Maps with directions to the site
                LocationService.openDirectionsToSite(
                  siteLat: ticket.latitude!,
                  siteLng: ticket.longitude!,
                  siteName: ticket.pvTicketId,
                  context: context,
                );
              } else {
                // Show a message to the user
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Directions are not available for this site'),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            },
            onDownloadTap: () async {
              // This is not needed for downloaded tickets, but keeping for consistency
              Toastbar.showInfoToastbar("Ticket already downloaded", context);
            },
          ),
        );
      },
    );
  }

  Widget _buildSiteList() {
    if (_filteredSites.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredSites.length,
      itemBuilder: (context, index) {
        final siteMap = _filteredSites[index];
        try {
          final site = AllSiteModel.fromDownloadedSiteSqliteRow(
            Map<String, dynamic>.from(siteMap),
          );
          final activityType = _parseActivityTypeFromString(
            siteMap['activity_type']?.toString() ?? '',
          );

          // Convert site to ticket-like display format
          final ticket = Ticket(
            ticketSchId: site.siteId,
            pvTicketId: site.siteCode,
            siteCode: site.siteCode,
            cluster: site.clusterDistrictName,
            operator: site.clientName ?? 'N/A',
            raisedDt: siteMap['created_at']?.toString() ?? '',
            dueDt: '',
            status: 'Site',
            latitude: 0.0,
            longitude: 0.0,
            auditSchId: null,
            siteDomainName: site.siteDomainName,
          );

          // For sites, display site name with site code in parentheses if available
          final siteDisplayName = site.siteName.isNotEmpty
              ? "${site.siteName}"
              : site.siteCode;

          return Padding(
            padding: EdgeInsets.only(
              bottom: index == _filteredSites.length - 1 ? 0 : 10,
            ),
            child: TicketCard(
              ticket: ticket,
              ticketId: ticket.pvTicketId,
              siteCode: siteDisplayName,
              siteId: site.clusterDistrictName,
              location: site.clusterDistrictName,
              company: site.clientName ?? 'N/A',
              raisedOn: siteMap['created_at']?.toString() ?? '',
              dueDate: '',
              statusText: 'Site',
              activityType: activityType,
              totalAssets: activityType == ActivityTypeEnum.assetUpload
                  ? _siteIdToTotalAssets[site.siteId]
                  : null,
              isDownloadedFunc: (ticket) async => true,
              onPdfDownloadTap: () {},
              onTap: () async => await _navigateToDownloadedSite(site, activityType),
              onDirectionTap: () {},
              onDownloadTap: () async {
                Toastbar.showInfoToastbar("Site already downloaded", context);
              },
            ),
          );
        } catch (e) {
          return const SizedBox.shrink();
        }
      },
    );
  }

  Future<void> _navigateToDownloadedSite(
    AllSiteModel site,
    ActivityTypeEnum activityType,
  ) async {
    try {
      // Show loader immediately when site is clicked
      LoaderWidget.showLoader(context);

      // Get site coordinates - try from site model first, then from raw_api_data if needed
      double? siteLat;
      double? siteLng;

      // First, try to get coordinates from the site model
      if (site.latitude != null && site.longitude != null) {
        siteLat = double.tryParse(site.latitude!);
        siteLng = double.tryParse(site.longitude!);
      }

      // If coordinates are still null/zero, try to get from raw_api_data
      if ((siteLat == null || siteLat == 0.0) || (siteLng == null || siteLng == 0.0)) {
        try {
          final service = ServiceLocator().centralAssetAuditService;
          final rawData = await service.getDataFromSqlite(
            siteAuditSchId: site.siteId.toString(),
          );

          if (rawData != null) {
            siteLat = rawData.latitude;
            siteLng = rawData.longitude;
            Logger.debugLog(
              '📍 Got coordinates from raw_api_data: lat=$siteLat, lng=$siteLng',
            );
          }
        } catch (e) {
          Logger.errorLog('❌ Error fetching coordinates from raw_api_data: $e');
        }
      }

      // Check distance if we have valid coordinates
      if (hasValidSiteCoordinates(siteLat, siteLng)) {
        try {
          // Check location permission first
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
            if (permission == LocationPermission.denied) {
              LoaderWidget.hideLoader();
              if (mounted) {
                Toastbar.showErrorToastbar(
                  "Location permission is required to access this site.",
                  context,
                );
              }
              return;
            }
          }

          if (permission == LocationPermission.deniedForever) {
            LoaderWidget.hideLoader();
            if (mounted) {
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
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Open Settings'),
                      ),
                    ],
                  );
                },
              );

              if (shouldOpenSettings == true) {
                await openAppSettings();
              }
            }
            return;
          }

          if (!mounted) return;

          // Get current location
          final currentLocation = await LocationService.getCurrentLocation();
          if (!mounted) return;

          // Calculate distance in kilometers
          // At this point, siteLat and siteLng are guaranteed to be non-null
          final distanceInKm = calculateDistance(
            currentLocation.latitude,
            currentLocation.longitude,
            siteLat ?? 0.0,
            siteLng ?? 0.0,
          );

          // Check if distance is more than the allowed distance
          // distanceFromLocation is in meters; convert to km for comparison
          final maxDistanceKm =
              double.parse(ApiCodes.distanceFromLocation) ;
          if (distanceInKm > maxDistanceKm) {
            // Hide loader before showing toast
            LoaderWidget.hideLoader();
            if (mounted) {
              Toastbar.showErrorToastbar(
                siteNotInRadiusMessage,
                context,
              );
            }
            // Prevent site from opening if distance exceeds the allowed radius
            return;
          }

          // Hide loader after distance check passes
          LoaderWidget.hideLoader();
        } catch (e) {
          // If location fetch fails, hide loader and show error
          LoaderWidget.hideLoader();
          Logger.errorLog('Error calculating distance: $e');
          if (mounted) {
            Toastbar.showErrorToastbar(
              "Unable to get your location. Please ensure location services are enabled.",
              context,
            );
          }
          return;
        }
      } else {
        // No valid coordinates available
        LoaderWidget.hideLoader();
        if (mounted) {
          Toastbar.showErrorToastbar(
            siteNotInRadiusMessage,
            context,
          );
        }
        return;
      }

      if (!mounted) return;

      // Proceed with navigation after distance check passes
      switch (activityType) {
      case ActivityTypeEnum.correctiveMaintenance:
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CorrectiveMaintenanceScreen(
              mode: CMScreenModeEnum.create,
              preloadedSiteData: site.toJson(),
              parentContext: parentContext,
            ),
          ),
        );
        break;
      case ActivityTypeEnum.siteVisit:
      case ActivityTypeEnum.siteVisitLog:
      case ActivityTypeEnum.siteVisitDocs:
        final parentContext = context;
        // Load raw_api_data so we can pass organisationList for dropdown (offline/online)
        List<Map<String, dynamic>>? organisationList;
        AllSiteModel siteDataToUse = site;
        try {
          final rawData = await ServiceLocator().centralAssetAuditService
              .getDataFromSqlite(siteAuditSchId: site.siteId.toString());
          if (rawData != null && rawData.apiData.isNotEmpty) {
            final apiData = rawData.apiData;
            if (apiData['organisationList'] != null) {
              organisationList = (apiData['organisationList'] as List)
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
            siteDataToUse = AllSiteModel(
              siteId: apiData['siteId'] ?? site.siteId,
              entityId: site.entityId,
              siteCode: apiData['siteCode'] ?? site.siteCode,
              siteName: apiData['siteName'] ?? site.siteName,
              clusterDistrictId: site.clusterDistrictId,
              clusterDistrictName: apiData['cluster'] ?? site.clusterDistrictName,
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
                  apiData['infraDistrictEngineerName'] ?? site.infraEngineerName,
              infraEngineerPhone:
                  apiData['infraDistrictEngineerContactNo'] ?? site.infraEngineerPhone,
              ownerName: apiData['ownerName'] ?? site.ownerName,
              ownerPhone: apiData['ownerContactNo'] ?? site.ownerPhone,
              siteVisitLogId: apiData['svlId']?.toString(),
              siteVisitLogDate: apiData['visitDate']?.toString(),
              purposeOfVisit: apiData['purposeOfVisit']?.toString(),
              visitingPersonImageId: apiData['visitingPersonImageId']?.toString(),
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
              latitude: site.latitude,
              longitude: site.longitude,
            );
          }
        } catch (_) {}
        // If no organisationList from raw_api_data, try cached list (e.g. offline)
        if ((organisationList == null || organisationList.isEmpty)) {
          try {
            organisationList = await ServiceLocator()
                .sitesRepository
                .getOrganisationList();
            if (!mounted) return;
          } catch (_) {}
        }
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SiteVisitScreen(
              siteData: siteDataToUse,
              parentContext: parentContext,
              preloadedOrganisationList: organisationList,
              siteAuditSchIdForStorage: site.siteId.toString(),
              clearStoredDataAfterSubmit: true,
            ),
          ),
        );
        break;
      case ActivityTypeEnum.generalInspection:
      case ActivityTypeEnum.generalInspectionSelf:
      case ActivityTypeEnum.generalInspChecklist:
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GInspectionDetailScreen(
              siteData: site,
              mode: CMScreenModeEnum.edit,
              parentContext: parentContext,
            ),
          ),
        );
        break;
      case ActivityTypeEnum.incident:
      case ActivityTypeEnum.incidentSelf:
        final parentContext = context;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentDetilScreen(
              siteData: site,
              mode: CMScreenModeEnum.create,
              parentContext: parentContext,
            ),
          ),
        );
        break;
      case ActivityTypeEnum.assetUpload:
        // For Asset Upload sites, load data from SQLite and navigate
        await _navigateToAssetUploadSite(site);
        break;
      default:
        break;
      }
    } catch (e) {
      LoaderWidget.hideLoader();
      Logger.errorLog('❌ Error navigating to downloaded site: $e');
      if (mounted) {
        Toastbar.showErrorToastbar(
          "Error opening site. Please try again.",
          context,
        );
      }
    }
  }

  Future<void> _navigateToAssetUploadSite(AllSiteModel site) async {
    try {
      LoaderWidget.showLoader(context);

      // Get stored data from SQLite
      final service = ServiceLocator().centralAssetAuditService;
      final data = await service.getDataFromSqlite(
        siteAuditSchId: site.siteId.toString(),
      );
      if (!mounted) return;

      if (data == null) {
        LoaderWidget.hideLoader();
        if (!mounted) return;
        Toastbar.showErrorToastbar("Failed to load asset upload data", context);
        return;
      }

      // Parse response structure - check if data is wrapped or direct
      Map<String, dynamic>? responseData;
      if (data.apiData.containsKey('data')) {
        responseData = data.apiData['data'] as Map<String, dynamic>?;
        Logger.debugLog('📦 Found data wrapper, extracting inner data');
      } else {
        responseData = data.apiData;
        Logger.debugLog('📦 Using data directly (no wrapper)');
      }

      if (responseData == null) {
        LoaderWidget.hideLoader();
        if (!mounted) return;
        Logger.errorLog(
          '❌ Invalid asset upload data structure: responseData is null',
        );
        Toastbar.showErrorToastbar(
          'Invalid asset upload data structure',
          context,
        );
        return;
      }

      Logger.debugLog('📦 Response data keys: ${responseData.keys.toList()}');

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
        if (!mounted) return;
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

      Logger.debugLog('📦 Found ${assetUploadItems.length} asset items');
      Logger.debugLog('📦 AuId: $auId');

      // Use the site data passed in, or create from siteDetailsData if needed
      final siteData = AllSiteModel(
        siteId: siteDetailsData['site_id'] != null
            ? (siteDetailsData['site_id'] is int
                ? siteDetailsData['site_id'] as int
                : int.tryParse(siteDetailsData['site_id'].toString()) ?? site.siteId)
            : site.siteId,
        entityId: siteDetailsData['entity_id'] != null
            ? (siteDetailsData['entity_id'] is int
                ? siteDetailsData['entity_id'] as int
                : int.tryParse(siteDetailsData['entity_id'].toString()) ?? site.entityId)
            : site.entityId,
        siteCode: siteDetailsData['site_code']?.toString() ?? site.siteCode,
        siteName: siteDetailsData['site_name']?.toString() ?? site.siteName,
        clusterDistrictId: site.clusterDistrictId,
        clusterDistrictName:
            siteDetailsData['cluster']?.toString() ?? site.clusterDistrictName,
        circleStateId: site.circleStateId,
        circleStateName:
            siteDetailsData['circle']?.toString() ?? site.circleStateName,
        clientId: site.clientId,
        clientName: siteDetailsData['client']?.toString() ?? site.clientName,
        svlId: site.svlId,
        oem: site.oem,
        oemId: site.oemId,
        self: site.self,
        selfId: site.selfId,
        siteDomainName: site.siteDomainName,
        distanceKM: site.distanceKM,
        infraEngineerName:
            siteDetailsData['infra_district_engineer_name']?.toString() ??
            site.infraEngineerName,
        infraEngineerPhone:
            siteDetailsData['infra_district_engineer_contact_no']?.toString() ??
            site.infraEngineerPhone,
        ownerName: siteDetailsData['owner_name']?.toString() ?? site.ownerName,
        ownerPhone:
            siteDetailsData['owner_contact_no']?.toString() ?? site.ownerPhone,
        latitude: site.latitude,
        longitude: site.longitude,
        siteVisitLogId: site.siteVisitLogId,
        siteVisitLogDate: site.siteVisitLogDate,
        purposeOfVisit: site.purposeOfVisit,
        visitingPersonImageId: site.visitingPersonImageId,
        checklistItems: site.checklistItems,
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
        '✅ Successfully loaded asset upload data. Items: ${parsedAssetItems.length}',
      );

      final parentContext = context;
      LoaderWidget.hideLoader();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssetUploadDetailPage(
            siteData: siteData,
            parentContext: parentContext,
            preloadedSelfieImageId: makerSelfieImageId?.toString(),
            preloadedAssetItems: parsedAssetItems.isNotEmpty
                ? parsedAssetItems
                : null,
            preloadedAuId: auId != null
                ? (auId is int ? auId : int.tryParse(auId.toString()))
                : null,
            mode:
                CMScreenModeEnum.edit, // Edit mode when coming from my tickets
            siteAuditSchIdForStorage: site.siteId.toString(),
          ),
        ),
      );
    } catch (e) {
      LoaderWidget.hideLoader();
      Logger.errorLog('❌ Error loading asset upload site: $e');
      if (!mounted) return;
      Toastbar.showErrorToastbar("Failed to load asset upload data", context);
    }
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
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontFamily: fontFamilyMontserrat,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDownloadedTickets,
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