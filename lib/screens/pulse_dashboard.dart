import 'dart:convert';
import 'package:app/models/screen_permission.dart';
import 'package:app/models/user_role_screen.dart';
import 'package:app/screens/pmis/project_list.dart';
import 'package:app/screens/raise_ticket/raise_tickets.dart';
import 'package:app/screens/ticket_screen.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/asset_audit_post_service.dart';
import 'package:app/services/local_storage_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/utils/toastbar.dart';
import 'package:app/utils/user_name_utils.dart';
import 'package:app/bloc/login_bloc/auth_cubit.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/home_screen.dart';
import 'package:app/screens/my_tickets.dart';
import 'package:app/screens/notifications.dart';
import 'package:app/services/notification_service.dart';
import 'package:app/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';

class PulseDashboard extends StatefulWidget {
  const PulseDashboard({Key? key}) : super(key: key);

  @override
  State<PulseDashboard> createState() => _PulseDashboardState();
}

class _PulseDashboardState extends State<PulseDashboard> {
  final GlobalKey<PopupMenuButtonState> _profileMenuKey =
      GlobalKey<PopupMenuButtonState>();

  String _notificationCount = "0";
  String version = "";
  bool _isRolesLoading = true;
  String? _rolesErrorMessage;
  List<UserRoleScreen> _roleScreens = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    loadVersion();
    _loadUserRoles();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh notifications when the screen becomes visible
    _loadNotifications();
  }

  Future<void> loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      version = info.version;
    });
  }

  Future<void> _loadNotifications() async {
    try {
      final notificationService = NotificationService(
        ServiceLocator().apiService,
      );

      final count = await notificationService.getNotificationsCount();

      if (!mounted) return;
      setState(() {
        _notificationCount = count;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notificationCount = "0";
      });
    }
  }

  Future<void> _loadUserRoles() async {
    try {
      setState(() {
        _isRolesLoading = true;
        _rolesErrorMessage = null;
      });

      final response = await ServiceLocator().rolesService.getUserRoles();
      if (!mounted) return;

      if (response.errorMessage != null) {
        setState(() {
          _isRolesLoading = false;
          _rolesErrorMessage = response.errorMessage;
        });
        return;
      }

      final orderedScreens = response.data ?? [];
      setState(() {
        _roleScreens = orderedScreens;
        _isRolesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRolesLoading = false;
        _rolesErrorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
         
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: () {
              _syncOfflineData();
            },
            backgroundColor: Colors.blue,
            heroTag: "sync_fab",
            child: const Icon(Icons.sync, color: Colors.white),
            tooltip: 'Sync Offline Data',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background - same as HomeScreen
          Positioned.fill(
            child: SafeSvgPicture.asset(AppImages.home, fit: BoxFit.cover),
          ),

          // Header Section
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _buildHeader()),
          ),

          // Greeting Section
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: _buildGreetingSection(),
          ),

          // Main Content - Cards Grid
          Positioned(
            top: 200,
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  /// Avoids [MemoryImage] / [instantiateImageCodec] crashes on corrupt profile data.
  Widget _buildProfileAvatar() {
    const double size = 40;
    final String? raw = LocalStorageDB.getUserProfile;
    if (raw == null || raw.isEmpty) {
      return const CircleAvatar(
        radius: 20,
        backgroundImage: AssetImage(AppImages.userPlaceholder),
      );
    }
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) {
        return const CircleAvatar(
          radius: 20,
          backgroundImage: AssetImage(AppImages.userPlaceholder),
        );
      }
      return CircleAvatar(
        radius: 20,
        child: ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset(
                AppImages.userPlaceholder,
                width: size,
                height: size,
                fit: BoxFit.cover,
              );
            },
          ),
        ),
      );
    } catch (_) {
      return const CircleAvatar(
        radius: 20,
        backgroundImage: AssetImage(AppImages.userPlaceholder),
      );
    }
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () async {
              try {
                // Clear all asset audit data
                await ServiceLocator().centralAssetAuditService.clearAllData();
                if (!mounted) return;

                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All asset audit data cleared successfully!'),
                    backgroundColor: AppColors.primaryGreen,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                // Show error message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error clearing data: $e'),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            },
            // Logo - using the same image as HomeScreen
            child: Image.asset(
              AppImages.pulseImg,
              fit: BoxFit.cover,
              width: 113,
              height: 40,
            ),
          ),
          const Spacer(),
          // Notification bell - same as HomeScreen
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                  // Refresh notifications when returning from notifications screen
                  _loadNotifications();
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.notifications,
                    color: AppColors.bellColor,
                    size: 35,
                  ),
                ),
              ),
              Positioned(
                right: 1,
                top: 4,
                child: _notificationCount != "0" && _notificationCount.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.errorColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _notificationCount,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Profile dropdown - same as HomeScreen
          PopupMenuButton<String>(
            key: _profileMenuKey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            offset: const Offset(0, 50),
            color: Colors.white,
            onSelected: (String value) {
              if (value == 'my_tickets') {
                _navigateToMyTickets();
              } else if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'my_tickets',
                child: Row(
                  children: [
                    Icon(Icons.assignment, color: Colors.grey),
                    SizedBox(width: 12),
                    Text('My Tickets'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            child: _buildProfileAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
      decoration: BoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello ${UserNameUtils.getUserDisplayName()}, ',

            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Here's a quick look at your tasks.",

            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),

          const SizedBox(height: 5),
          Text(
            "Version $version",
            style: const TextStyle(
              fontSize: 8,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildDynamicGrid(),
      ),
    );
  }

  Widget _buildDynamicGrid() {
    if (_isRolesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_rolesErrorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Failed to load user screens',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _rolesErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadUserRoles,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_roleScreens.isEmpty) {
      return const Center(
        child: Text(
          'No screens available',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUserRoles,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _roleScreens.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _isIPad(context) ? 4 : 3,
          crossAxisSpacing: _isIPad(context) ? 8 : 10,
          mainAxisSpacing: _isIPad(context) ? 8 : 10,
          childAspectRatio: _isIPad(context) ? 1.0 : 0.85,
        ),
        itemBuilder: (context, index) {
          final screen = _roleScreens[index];
          final isComingSoon = _isComingSoonScreen(screen.screenId);
          return _buildTaskCard(
            iconPath: _iconPathForScreen(screen),
            label: screen.displayName,
            onTap: () => _navigateToScreen(screen),
            isComingSoon: isComingSoon,
          );
        },
      ),
    );
  }

  Widget _buildTaskCard({
    required String iconPath,
    required String label,
    required VoidCallback onTap,
    bool isComingSoon = false,
  }) {
    return GestureDetector(
      onTap: isComingSoon ? null : onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.dashboardIconBoxColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: SafeSvgPicture.asset(
                    iconPath,
                    fit: BoxFit.contain,
                    width: 40,
                    height: 40,
                    allowDrawingOutsideViewBox: true,
                  ),
                ),
              ),
              if (isComingSoon)
                Positioned(
                  top: -7,
                  right: -20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.isComingSoonColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'Coming soon',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Label below
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.dashboardTextColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _iconPathForScreen(UserRoleScreen screen) {
    final name = screen.displayName.trim().toLowerCase();
    if (name.contains('raise it ticket')) {
      return AppImages.raiseItTicket;
    }
    return _iconPathFromScreenId(screen.screenId);
  }

  String _iconPathFromScreenId(int screenId) {
    switch (screenId) {
      case 76:
        return AppImages.assetAudit;
      case 77:
        return AppImages.correctiveMaintenance;
      case 78:
        return AppImages.energyReading;
      case 79:
        return AppImages.inspection;
      case 80:
        return AppImages.incident;
      case 81:
        return AppImages.preventiveMaintenance;
      case 82:
        return AppImages.project;
      case 83:
        return AppImages.theft;
      case 84:
        return AppImages.warehouse;
      case 85:
        return AppImages.assetUpload;
      case 86:
        return AppImages.project;
      case 87:
        return AppImages.siteaccess;
      case 88:
        return AppImages.raiseItTicket;
      default:
        return AppImages.project;
    }
  }

  bool _isComingSoonScreen(int screenId) {
    return screenId == 83 || screenId == 84;
  }

  bool _isIPad(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return isIOS && shortestSide >= 600;
  }


  void _navigateToScreen(UserRoleScreen screen) {
    final permission = screen.permission;
    if (screen.displayName.trim().toLowerCase().contains('raise it ticket') ||
        screen.screenId == 88) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RaiseTicketsScreen(permission: permission),
        ),
      );
      return;
    }
    final taskName = _taskNameFromScreenId(screen.screenId);
    if (taskName == null) {
      Toastbar.showInfoToastbar(
        'No route configured for ${screen.displayName}',
        context,
      );
      return;
    }
    _navigateToTask(taskName, permission);
  }

  String? _taskNameFromScreenId(int screenId) {
    switch (screenId) {
      case 76:
        return 'Asset Audit';
      case 77:
        return 'Corrective Maintenance';
      case 78:
        return 'Energy Reading';
      case 79:
        return 'GI';
      case 80:
        return 'Incident';
      case 81:
        return 'Preventive Maintenance';
      case 82:
        return 'Project';
      case 83:
        return 'Theft';
      case 84:
        return 'Warehouse';
      case 85:
        return 'Asset Upload';
      case 86:
        return 'Activity';
      case 87:
        return 'SV';
      case 88:
        return 'Raise It Ticket';
      default:
        return null;
    }
  }

  void _navigateToTask(String taskName, ScreenPermission permission) {
    if (taskName == 'Raise It Ticket') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RaiseTicketsScreen(permission: permission),
        ),
      );
      return;
    }
    if (taskName == 'Project' || taskName == 'Activity') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProjectListScreen(
            title: taskName == 'Project' ? 'Projects' : 'Activity',
            activityType: taskName,
          ),
        ),
      );
    } else {
    if (taskName == 'SV' ||
        taskName == 'GI' ||
        taskName == 'Incident' ||
        taskName == 'AU' ||
        taskName == 'Asset Upload') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TicketScreen(
                auditName: taskName,
                status: taskName,
                permission: permission,
              ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            selectedActivity: taskName,
            permission: permission,
          ),
        ),
      );
    }
  }
  }



  void _navigateToMyTickets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MyTicketsScreen()),
    );
  }

  /// Syncs offline data by checking pending requests and posting them to the server
  Future<void> _syncOfflineData() async {
    // Refuse to start a second sweep while one is already running.
    // Without this, rapid taps each fetch the same `pending_requests` rows and
    // re-POST them before `deleteRequest` runs — that's what produces the
    // multiplied `pclsri_id` / `pclsrd_id` records seen on the server.
    if (!AssetAuditPostService.beginSyncSweep()) {
      Logger.infoLog('PulseDashboard: Sync already in progress, ignoring tap');
      if (mounted) {
        Toastbar.showInfoToastbar('Sync already in progress', context);
      }
      return;
    }
    try {
      Logger.infoLog('🔄 PulseDashboard: Starting offline data sync');

      // Get pending requests
      final pendingRequestsService = ServiceLocator().pendingRequestService;
      final pendingRequests = await pendingRequestsService.getPendingRequests();
      if (!mounted) return;

      Logger.infoLog(
        'PulseDashboard: Found ${pendingRequests.length} pending requests',
      );

      // Log each pending request so we can verify offline storage is saving
      // every PM page (Tower/Battery/.../CT), not just the last one.
      // NOTE: must use Logger.infoLog, not print() — bare print() is rate-limited
      // by Flutter (debugPrintThrottled) and silently dropped under load.
      for (int i = 0; i < pendingRequests.length; i++) {
        final r = pendingRequests[i];
        final dataStr = r['request_data']?.toString() ?? '';
        Logger.infoLog(
          '📋 Pending request in database[$i] id=${r['request_id']} url=${r['url']} '
          'dataLen=${dataStr.length} created=${r['created_at']}',
        );
      }

      if (pendingRequests.isEmpty) {
        Logger.infoLog('PulseDashboard: No pending requests found');
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
            'PulseDashboard: Failed to sync request ${request['request_id']} '
            '(url=${request['url']}): $e',
          );
        }
      }

      // Show sync result
      final message =
          'Sync completed: $successCount successful, out of $totalCount';
      Logger.infoLog('PulseDashboard: $message');
      if (!mounted) return;
      Toastbar.showSuccessToastbar(message, context);
    } catch (e) {
      Logger.errorLog('PulseDashboard: Error during sync: $e');
      if (!mounted) return;
      Toastbar.showErrorToastbar('Sync failed: $e', context);
    } finally {
      AssetAuditPostService.endSyncSweep();
    }
  }

  bool _isLogoutDialogShowing = false;

  void _handleLogout() {
    // Prevent multiple dialogs from being shown
    if (_isLogoutDialogShowing) {
      return;
    }

    _isLogoutDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isLogoutDialogShowing = false;
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                _isLogoutDialogShowing = false;

                try {
                  // Store context reference before async operations
                  final currentContext = context;

                  // Clear all authentication data before navigating to login
                  await currentContext.read<AuthCubit>().forceClearAllData();

                  // Use stored context and check if still mounted
                  if (mounted && currentContext.mounted) {
                    // Use pushAndRemoveUntil to clear entire navigation stack
                    pushAndRemoveUntilPage(currentContext, const LoginScreen());
                    Toastbar.showSuccessToastbar(
                      'Logged out successfully',
                      currentContext,
                    );
                  }
                } catch (e) {
                  // If logout fails, reset the flag
                  _isLogoutDialogShowing = false;
                }
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    ).then((_) {
      // Reset flag when dialog is dismissed
      _isLogoutDialogShowing = false;
    });
  }
}
