import 'package:app/app_config.dart';
import 'package:app/commonWidgets/activity_card.dart';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/commonWidgets/pmis_header.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/models/pmis_project_activity_model.dart';
import 'package:app/screens/pmis/activity_ticket/activity_ticket_checker_list.dart';
import 'package:app/services/location_service.dart';
import 'package:app/services/pmis_activity_ticket_offline_service.dart';
import 'package:app/utils/site_radius_guard.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';

class ProjectActivitiesScreen extends StatefulWidget {
  /// Passed to PMIS `project-activity-list` as `projectId`.
  final int projectId;

  final String appBarTitle;

  /// Breadcrumb under the header (e.g. `Project > Activities`).
  final String breadcrumbText;

  /// Context rows in the dark band; if null, shows `Project ID : [projectId]`.
  final List<PmisHeaderDetailLine>? headerDetailLines;

  /// When true (Activity dashboard from [ProjectListScreen]), shows the same
  /// search UI as [AllSitesScreen] and uses `/api/v1/common/allSiteData` with
  /// `searchText` to narrow activities by matched site names.
  final bool enableDashboardActivitySearch;

  /// `activity` => `project-activity-list`, `project` => `project-submodule-activiy-list`.
  final String activityType;

  /// Required for `activityType == project`.
  final int? siteId;

  /// Required for `activityType == project`.
  final int? subModuleId;

  const ProjectActivitiesScreen({
    super.key,
    required this.projectId,
    this.appBarTitle = 'Project Activities',
    this.breadcrumbText = 'Project > Activities',
    this.headerDetailLines,
    this.enableDashboardActivitySearch = false,
    this.activityType = 'activity',
    this.siteId,
    this.subModuleId,
  });

  @override
  State<ProjectActivitiesScreen> createState() =>
      _ProjectActivitiesScreenState();
}

class _ProjectActivitiesScreenState extends State<ProjectActivitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _loading = true;
  String? _errorMessage;
  List<PmisProjectActivity> _allActivities = [];
  List<PmisProjectActivity> _displayedActivities = [];

  /// PMIS `atId` values present in SQLite `raw_api_data` (activity_type AI).
  Set<int> _offlineDownloadedAtIds = {};

  bool get _useProjectActivityListApi =>
      widget.activityType.trim().toLowerCase() == 'activity';

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PmisHeaderDetailLine> get _headerDetailLines {
    return widget.headerDetailLines ??
        [
          PmisHeaderDetailLine(
            label: 'Project ID',
            value: widget.projectId.toString(),
          ),
        ];
  }

  Future<void> _loadActivities() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final config = AppConfig.of(context);
      final location = await LocationService.getCurrentLocation();
      final result = _useProjectActivityListApi
          ? await config.pmisActivitiesRepository.getProjectActivityList(
              id: widget.projectId,
              latitude: location.latitude,
              longitude: location.longitude,
              searchText: '',
            )
          : await config.pmisActivitiesRepository.getSubModuleActivties(
              siteId: widget.siteId ?? 0,
              subModuleId: widget.subModuleId ?? 0,
              latitude: location.latitude,
              longitude: location.longitude,
            );

      if (!mounted) return;

      if (!result.isSuccess || result.data == null) {
        setState(() {
          _loading = false;
          _errorMessage =
              result.errorMessage ?? 'Failed to load activities';
          _allActivities = [];
          _displayedActivities = [];
          _offlineDownloadedAtIds = {};
        });
        return;
      }

      final list = result.data!;
      final offlineIds = <int>{};
      for (final a in list) {
        final id = a.atId;
        if (id == null) continue;
        if (await PmisActivityTicketOfflineService.isTicketDownloadedForOffline(
              id,
            )) {
          offlineIds.add(id);
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allActivities = list;
        _displayedActivities = _filterActivities(list, _searchQuery);
        _offlineDownloadedAtIds = offlineIds;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
        _allActivities = [];
        _displayedActivities = [];
        _offlineDownloadedAtIds = {};
      });
    }
  }

  List<PmisProjectActivity> _filterActivities(
    List<PmisProjectActivity> source,
    String query,
  ) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<PmisProjectActivity>.from(source);
    return source.where((a) {
      return a.siteName.toLowerCase().contains(q) ||
          a.moduleName.toLowerCase().contains(q) ||
          a.subModuleName.toLowerCase().contains(q) ||
          a.activityName.toLowerCase().contains(q) ||
          (a.activityStatus ?? '').toLowerCase().contains(q) ||
          a.currentStatus.toLowerCase().contains(q) ||
          a.status.toLowerCase().contains(q);
    }).toList();
  }

  void _performSearch(String query) {
    setState(() {
      _searchQuery = query;
      _displayedActivities = _filterActivities(_allActivities, query);
    });
  }

  void _performSearchAndLoad(String raw) {
    _performSearch(raw);
  }

  Widget _buildSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchController,
            onChanged: _performSearch,
            onSubmitted: _performSearchAndLoad,
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
                          onPressed: () =>
                              _performSearchAndLoad(_searchController.text),
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
                              _displayedActivities =
                                  List<PmisProjectActivity>.from(
                                _allActivities,
                              );
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
                      onPressed: () =>
                          _performSearchAndLoad(_searchController.text),
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
                'Searching locally',
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

  /// Loads `activity-ticket` then warms `DocumentById` for attachments, then opens the checker flow.
  Future<void> _openActivityTicket(PmisProjectActivity a) async {
    final ticketId = a.atId;
    if (ticketId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity ticket is not available for this activity'),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    LoaderWidget.showLoader(context);
    try {
      final allowed = await ensureUserWithinSiteRadius(
        context,
        siteLat: a.latitude,
        siteLng: a.longitude,
      );
      if (!mounted || !allowed) return;

      final config = AppConfig.of(context);
      final res = await config.pmisActivityTicketRepository
          .getActivityTicketWithDocumentWarmup(
        activityTicketId: ticketId,
      );
      if (!mounted) return;

      if (!res.isSuccess || res.data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.errorMessage ?? 'Failed to load activity ticket',
            ),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }

      LoaderWidget.hideLoader();

      if (!mounted) return;
      final shouldRefreshActivities = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ActivityTicketCheckerListScreen(
            activityTicketId: ticketId,
            activityName: a.activityName,
            initialActivityStatus: a.activityStatus,
            summaryCardTitle: a.subModuleName.trim().isNotEmpty
                ? a.subModuleName
                : null,
            breadcrumbText: widget.breadcrumbText,
            preloadedDetail: res.data,
          ),
        ),
      );
      if (!mounted) return;
      if (shouldRefreshActivities == true) {
        await _loadActivities();
      }
    } finally {
      LoaderWidget.hideLoader();
    }
  }

  /// Same offline model as SV ticket download: `raw_api_data` + LOCAL_IMAGE_ID media.
  Future<void> _downloadActivityTicketForOffline(PmisProjectActivity a) async {
    final ticketId = a.atId;
    if (ticketId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity ticket is not available for this activity'),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    LoaderWidget.showLoader(context);
    try {
      final config = AppConfig.of(context);
      final result = await PmisActivityTicketOfflineService.downloadCompleteTicket(
        repository: config.pmisActivityTicketRepository,
        activity: a,
      );
      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Failed to download ticket'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }

      setState(() {
        _offlineDownloadedAtIds.add(ticketId);
      });

      Toastbar.showSuccessToastbar(
        'Ticket saved for offline (same storage as My Tickets)',
        context,
      );

    } finally {
      LoaderWidget.hideLoader();
    }
  }

  Widget _buildHeaderBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmisHeader(
          breadcrumbText: widget.breadcrumbText,
          detailLines: _headerDetailLines,
        ),
        if (widget.enableDashboardActivitySearch) _buildSearchBar(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
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
                    widget.appBarTitle,
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
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeSvgPicture.asset(AppImages.home, fit: BoxFit.cover),
          ),
          SafeArea(
            child: _loading
                ? CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeaderBlock()),
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 64),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _errorMessage != null
                    ? CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeaderBlock()),
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 24,
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : _displayedActivities.isEmpty
                            ? CustomScrollView(
                                slivers: [
                                  SliverToBoxAdapter(child: _buildHeaderBlock()),
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 24,
                                      ),
                                      child: Text(
                                        widget.enableDashboardActivitySearch &&
                                                _searchQuery.isNotEmpty
                                            ? 'No matching activities'
                                            : 'No activities found',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : CustomScrollView(
                                slivers: [
                                  SliverToBoxAdapter(child: _buildHeaderBlock()),
                                  SliverPadding(
                                    padding:
                                        const EdgeInsets.fromLTRB(8, 8, 8, 24),
                                    sliver: SliverList.separated(
                                      itemCount: _displayedActivities.length,
                                      itemBuilder: (context, index) {
                                        final activity =
                                            _displayedActivities[index];
                                        return ActivityCard(
                                          activity: activity,
                                          showProjectHierarchy: widget
                                              .breadcrumbText
                                              .toLowerCase()
                                              .contains('project'),
                                          isOfflineDownloaded:
                                              activity.atId != null &&
                                              _offlineDownloadedAtIds.contains(
                                                activity.atId!,
                                              ),
                                          onDownloadTap: () =>
                                              _downloadActivityTicketForOffline(
                                                activity,
                                              ),
                                          onDirectionTap: () {
                                            if (activity.latitude != null &&
                                                activity.longitude != null) {
                                              LocationService.openDirectionsToSite(
                                                siteLat: activity.latitude!,
                                                siteLng: activity.longitude!,
                                                siteName: activity.siteName,
                                                context: context,
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Directions are not available for this activity',
                                                  ),
                                                  backgroundColor:
                                                      AppColors.errorColor,
                                                ),
                                              );
                                            }
                                          },
                                          onTap: () =>
                                              _openActivityTicket(activity),
                                        );
                                      },
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                    ),
                                  ),
                                ],
                              ),
          ),
        ],
      ),
    );
  }
}
