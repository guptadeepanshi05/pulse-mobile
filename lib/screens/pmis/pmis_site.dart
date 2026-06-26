import 'package:app/app_config.dart';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/commonWidgets/pmis_header.dart';
import 'package:app/commonWidgets/pmis_site_card.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/models/pmis_project_model.dart';
import 'package:app/models/pmis_project_site_model.dart';
import 'package:app/screens/pmis/pmis_module.dart';
import 'package:app/services/location_service.dart';
import 'package:app/utils/site_radius_guard.dart';
import 'package:flutter/material.dart';

class PmisSiteScreen extends StatefulWidget {
  final PmisProject project;
  final int projectId;
  final int stateId;
  final String stateName;

  const PmisSiteScreen({
    super.key,
    required this.project,
    required this.projectId,
    required this.stateId,
    required this.stateName,
  });

  @override
  State<PmisSiteScreen> createState() => _PmisSiteScreenState();
}

class _PmisSiteScreenState extends State<PmisSiteScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<PmisProjectSite> _sites = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSites());
  }

  Future<void> _loadSites() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final config = AppConfig.of(context);
      final location = await LocationService.getCurrentLocation();
      final result = await config.pmisSiteRepository.getProjectSiteList(
        projectId: widget.projectId,
        stateId: widget.stateId,
        latitude: location.latitude,
        longitude: location.longitude,
      );

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        setState(() {
          _loading = false;
          _sites = result.data!;
        });
      } else {
        setState(() {
          _loading = false;
          _errorMessage = result.errorMessage ?? 'Failed to load sites';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
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
                    widget.stateName,
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
            child: Column(
              children: [
                PmisHeader(
                  breadcrumbText: 'Project > State > Site',
                  detailLines: [
                    PmisHeaderDetailLine(
                      label: 'Project',
                      value: widget.project.projectName,
                    ),
                    PmisHeaderDetailLine(
                      label: 'State',
                      value: widget.stateName,
                    ),
                  ],
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryGreen,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadSites,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: AppColors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_sites.isEmpty) {
      return const Center(
        child: Text(
          'No sites found',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _sites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final site = _sites[index];
        return PmisSiteCard(
          site: site,
          onTap: () async {
            LoaderWidget.showLoader(context);
            try {
              final allowed = await ensureUserWithinSiteRadius(
                context,
                siteLat: site.latitude,
                siteLng: site.longitude,
              );
              LoaderWidget.hideLoader();
              if (!mounted || !allowed) return;

              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => PmisModuleScreen(
                    project: widget.project,
                    projectId: widget.projectId,
                    stateName: widget.stateName,
                    site: site,
                  ),
                ),
              );
              if (!mounted) return;
              await _loadSites();
            } catch (e) {
              if (LoaderWidget.isShowing) {
                LoaderWidget.hideLoader();
              }
            }
          },
          onDirectionTap: () {
            if (site.latitude != null && site.longitude != null) {
              LocationService.openDirectionsToSite(
                siteLat: site.latitude!,
                siteLng: site.longitude!,
                siteName: site.siteCode,
                context: context,
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Directions are not available for this site',
                  ),
                  backgroundColor: AppColors.errorColor,
                ),
              );
            }
          },
        );
      },
    );
  }
}
