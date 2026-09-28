import 'package:app/app_config.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/screens/pmis/activity_ticket/activity_ticket.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/models/pmis_activity_ticket_model.dart';
import 'package:app/services/api_service.dart';
import 'package:app/services/pmis_activity_ticket_offline_service.dart';
import 'package:flutter/material.dart';

/// Approver list for `pmis/api/v1/project-plan/activity-ticket/{atId}`.
class ActivityTicketCheckerListScreen extends StatefulWidget {
  final int activityTicketId;
  final String breadcrumbText;
  final String activityName;
  final String? initialActivityStatus;

  /// Bold title inside the top summary card; falls back to API / [activityName].
  final String? summaryCardTitle;

  /// When set (e.g. after activities-list prefetch), skips a second ticket GET.
  final PmisActivityTicketDetail? preloadedDetail;

  const ActivityTicketCheckerListScreen({
    super.key,
    required this.activityTicketId,
    required this.breadcrumbText,
    required this.activityName,
    this.initialActivityStatus,
    this.summaryCardTitle,
    this.preloadedDetail,
  });

  @override
  State<ActivityTicketCheckerListScreen> createState() =>
      _ActivityTicketCheckerListScreenState();
}

class _ActivityTicketCheckerListScreenState
    extends State<ActivityTicketCheckerListScreen> {
  late Future<ResponseResult<PmisActivityTicketDetail>> _future;

  void _goBackWithRefresh() {
    Navigator.of(context).pop(true);
  }

  static String _nowForBackend() {
    final now = DateTime.now();
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString();
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  PmisActivityTicketDetail _detailForStartActivity(
    PmisActivityTicketDetail detail,
  ) {
    if (!detail.startActivity) return detail;
    final actualStart =
        (detail.actualStartDt?.trim().isNotEmpty ?? false)
        ? detail.actualStartDt
        : _nowForBackend();
    return PmisActivityTicketDetail(
      atId: detail.atId,
      ppaId: detail.ppaId,
      currentStatus: 'WIP',
      currentStatusCode: 2,
      currentStatusDt: _nowForBackend(),
      makerDesignationMstId: detail.makerDesignationMstId,
      makerUserMstId: detail.makerUserMstId,
      makerAssignedDt: detail.makerAssignedDt,
      plannedStartDt: detail.plannedStartDt,
      plannedEndDt: detail.plannedEndDt,
      actualStartDt: actualStart,
      actualEndDt: detail.actualEndDt,
      isActive: detail.isActive,
      remarks: detail.remarks,
      ticketCheckers: detail.ticketCheckers,
      ticketFieldValues: detail.ticketFieldValues,
      ticketAttachments: detail.ticketAttachments,
      makerUserName: detail.makerUserName,
      makerDesignationName: detail.makerDesignationName,
      oldData: detail.oldData,
      showReviewBtns: detail.showReviewBtns,
      checkerLvl: detail.checkerLvl,
      role: detail.role,
      viewOnly: detail.viewOnly,
      ticketStatusHistory: detail.ticketStatusHistory,
      isRepeating: detail.isRepeating,
      repeatDt: detail.repeatDt,
      allowedStatuses: detail.allowedStatuses,
      startActivity: false,
    );
  }

  Map<String, dynamic> _buildStartActivityPayload(
    PmisActivityTicketDetail detail,
    PmisActivityTicketDetail startedDetail,
  ) {
    final fieldValues = detail.ticketFieldValues
        .map(
          (f) => <String, dynamic>{
            'tfvId': f.tfvId,
            'valText': f.valText?.toString() ?? '',
            'valNumeric': f.valNumeric,
            'valInt': f.valInt,
            'valDate': f.valDate,
            'valJson': f.valJson,
            'latitude': f.latitude ?? '0',
            'longitude': f.longitude ?? '0',
            'geoAccuracyM': f.geoAccuracyM ?? '0',
            'geoSource': f.geoSource ?? '',
            'isActive': f.isActive,
            'remarks': f.remarks ?? '',
            'attachments': f.attachments,
            'subActivityName': f.subActivityName ?? '',
            'subActivityDataType': f.subActivityDataType ?? '',
            'subActivityControlType': f.subActivityControlType ?? '',
            'isRequired': f.isRequired ?? false,
            'seqNo': f.seqNo ?? 0,
            'minVal': f.minVal,
            'maxVal': f.maxVal,
            'configJson': f.configJson is Map
                ? Map<String, dynamic>.from(f.configJson as Map)
                : <String, dynamic>{},
            'linkMmId': f.linkMmId ?? 0,
            'isModified': false,
          },
        )
        .toList();
    final checkers = detail.ticketCheckers
        .map(
          (c) => <String, dynamic>{
            'tcId': c.tcId,
            'levelNo': c.levelNo,
            'designationMstId': c.designationMstId ?? 0,
            'checkerUserMstId': c.checkerUserMstId ?? 0,
            'decisionStatus': c.decisionStatus ?? '',
            'decisionBy': c.decisionBy ?? '',
            'decisionDt': c.decisionDt,
            'decisionRemarks': c.decisionRemarks ?? '',
            'latitude': c.latitude ?? '0',
            'longitude': c.longitude ?? '0',
            'geoAccuracyM': c.geoAccuracyM ?? '0',
            'geoSource': c.geoSource ?? '',
            'isActive': c.isActive,
            'remarks': c.remarks ?? '',
            'decisionByName': c.decisionByName ?? '',
            'checkerUserName': c.checkerUserName ?? '',
            'designationName': c.designationName ?? '',
          },
        )
        .toList();

    return <String, dynamic>{
      'atId': detail.atId,
      'ppaId': detail.ppaId,
      'currentStatus': 'WIP',
      'currentStatusCode': 2,
      'currentStatusId': 2,
      'currentStatusDt': _nowForBackend(),
      'makerDesignationMstId': detail.makerDesignationMstId ?? 0,
      'makerUserMstId': detail.makerUserMstId ?? 0,
      'makerAssignedDt': detail.makerAssignedDt,
      'plannedStartDt': detail.plannedStartDt,
      'plannedEndDt': detail.plannedEndDt,
      'actualStartDt': startedDetail.actualStartDt,
      'actualEndDt': detail.actualEndDt,
      'isActive': detail.isActive,
      'remarks': detail.remarks ?? '',
      'ticketCheckers': checkers,
      'ticketFieldValues': fieldValues,
      'ticketAttachments': detail.ticketAttachments.map((e) => e.raw).toList(),
      'makerUserName': detail.makerUserName ?? '',
      'makerDesignationName': detail.makerDesignationName ?? '',
      'oldData': detail.oldData
          .map(
            (item) => <String, dynamic>{
              'actualStartDt': item.actualStartDt,
              'actualEndDt': item.actualEndDt,
              'ticketFieldValues': item.ticketFieldValues
                  .map(
                    (f) => <String, dynamic>{
                      'tfvId': f.tfvId,
                      'valText': f.valText?.toString() ?? '',
                      'valNumeric': f.valNumeric,
                      'valInt': f.valInt,
                      'valDate': f.valDate,
                      'valJson': f.valJson,
                      'latitude': f.latitude ?? '0',
                      'longitude': f.longitude ?? '0',
                      'geoAccuracyM': f.geoAccuracyM ?? '0',
                      'geoSource': f.geoSource ?? '',
                      'isActive': f.isActive,
                      'remarks': f.remarks ?? '',
                      'attachments': f.attachments,
                      'subActivityName': f.subActivityName ?? '',
                      'subActivityDataType': f.subActivityDataType ?? '',
                      'subActivityControlType': f.subActivityControlType ?? '',
                      'isRequired': f.isRequired ?? false,
                      'seqNo': f.seqNo ?? 0,
                      'minVal': f.minVal,
                      'maxVal': f.maxVal,
                      'configJson': f.configJson is Map
                          ? Map<String, dynamic>.from(f.configJson as Map)
                          : <String, dynamic>{},
                      'linkMmId': f.linkMmId ?? 0,
                      'isModified': item.isModified ?? false,
                    },
                  )
                  .toList(),
              'makerUserName': item.makerUserName ?? '',
              'isModified': item.isModified ?? false,
            },
          )
          .toList(),
      'showReviewBtns': detail.showReviewBtns,
      'checkerLvl': detail.checkerLvl ?? '',
      'role': detail.role ?? '',
      'viewOnly': detail.viewOnly,
      'ticketStatusHistory': detail.ticketStatusHistory,
      'allowedStatuses': detail.allowedStatuses.map((e) => e.toJson()).toList(),
      'isRepeatNature': detail.isRepeating,
      'isRepeating': detail.isRepeating,
      'repeatDt': detail.repeatDt,
    };
  }

  Future<PmisActivityTicketDetail> _transitionAllocatedMakerToWipIfNeeded(
    PmisActivityTicketDetail detail,
  ) async {
    if (!detail.startActivity) return detail;
    final startedDetail = _detailForStartActivity(detail);
    final payload = _buildStartActivityPayload(detail, startedDetail);
    final repository = AppConfig.of(context).pmisActivityTicketRepository;
    try {
      await repository.postActivityTicket(payload: payload);
    } catch (_) {
      // Ignore transition API errors here; proceed with local WIP flow.
    }
    return startedDetail;
  }

  @override
  void initState() {
    super.initState();
    final pre = widget.preloadedDetail;
    _future = pre != null
        ? Future.value(
            ResponseResult<PmisActivityTicketDetail>.success(pre, 200),
          )
        : _loadTicket();
  }

  Future<ResponseResult<PmisActivityTicketDetail>> _loadTicket() async {
    try {
      final config = AppConfig.of(context);
      final res = await config.pmisActivityTicketRepository.getActivityTicket(
        activityTicketId: widget.activityTicketId,
      );
      if (res.isSuccess && res.data != null) return res;
      return res;
    } catch (e) {
      final offline =
          await PmisActivityTicketOfflineService.loadOfflineDetail(
        widget.activityTicketId,
      );
      if (offline != null) {
        return ResponseResult<PmisActivityTicketDetail>.success(offline, 200);
      }
      return ResponseResult.error(errorMessage: e.toString());
    }
  }

  Future<void> _openLatestActivityTicketScreen(
    PmisActivityTicketDetail detail,
  ) async {
    final transitionedDetail = await _transitionAllocatedMakerToWipIfNeeded(
      detail,
    );
    if (!mounted) return;
    if (transitionedDetail.currentStatus.trim().toUpperCase() !=
        detail.currentStatus.trim().toUpperCase()) {
      setState(() {
        _future = Future.value(
          ResponseResult<PmisActivityTicketDetail>.success(
            transitionedDetail,
            200,
          ),
        );
      });
    }
    final latestOffline = await PmisActivityTicketOfflineService.loadOfflineDetail(
      widget.activityTicketId,
    );
    if (!mounted) return;
    // Prefer fresh detail from API path. Use offline only when it is the same
    // ticket and has matching role/status; this avoids stale role overrides.
    final canUseOffline = latestOffline != null &&
        latestOffline.atId == widget.activityTicketId &&
        (latestOffline.role ?? '').trim().toUpperCase() ==
            (transitionedDetail.role ?? '').trim().toUpperCase() &&
        latestOffline.currentStatus.trim().toUpperCase() ==
            transitionedDetail.currentStatus.trim().toUpperCase();
    final openDetail = canUseOffline ? latestOffline : transitionedDetail;
    final shouldRefreshActivities = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ActivityTicketScreen(
          activityTicketId: widget.activityTicketId,
          breadcrumbText: widget.breadcrumbText,
          activityName: widget.activityName,
          summaryCardTitle: widget.summaryCardTitle,
          detail: openDetail,
        ),
      ),
    );
    if (!mounted) return;
    if (shouldRefreshActivities == true) {
      Navigator.of(context).pop(true);
    }
  }

  static String _formatPlanDate(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    final trimmed = value.trim();

    // Handle values like:
    // - 31/Mar/2026 00:00:00
    // - 31/03/2026 12:10:45
    final slashDateWithOptionalTime = RegExp(
      r'^(\d{1,2})/([A-Za-z]{3}|\d{1,2})/(\d{4})(?:\s+.*)?$',
    ).firstMatch(trimmed);
    if (slashDateWithOptionalTime != null) {
      final day = int.tryParse(slashDateWithOptionalTime.group(1)!);
      final monthToken = slashDateWithOptionalTime.group(2)!;
      final year = int.tryParse(slashDateWithOptionalTime.group(3)!);
      if (day != null && year != null) {
        int? month;
        final monthFromNumber = int.tryParse(monthToken);
        if (monthFromNumber != null) {
          month = monthFromNumber;
        } else {
          const monthNames = <String>[
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec',
          ];
          final normalizedMonth =
              '${monthToken[0].toUpperCase()}${monthToken.substring(1).toLowerCase()}';
          final monthIndex = monthNames.indexOf(normalizedMonth);
          if (monthIndex >= 0) month = monthIndex + 1;
        }
        if (month != null && month >= 1 && month <= 12) {
          final d = day.toString().padLeft(2, '0');
          final m = month.toString().padLeft(2, '0');
          return '$d-$m-$year';
        }
      }
    }

    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      return '$d-$m-$y';
    }
    final match = RegExp(
      r'^(\d{2})/([A-Za-z]{3})/(\d{4})$',
    ).firstMatch(trimmed);
    if (match == null) return trimmed;

    final day = match.group(1)!;
    final rawMonth = match.group(2)!;
    final year = match.group(3)!;
    final month =
        '${rawMonth[0].toUpperCase()}${rawMonth.substring(1).toLowerCase()}';
    return '$day-$month-$year';
  }

  String _summaryTitle(PmisActivityTicketDetail? detail) {
    final fromWidget = widget.summaryCardTitle?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    final fromApi = detail?.makerDesignationName?.trim();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    return widget.activityName;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _goBackWithRefresh();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Stack(
        children: [
          Positioned.fill(
            child: SafeSvgPicture.asset(AppImages.home, fit: BoxFit.cover),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScreenAppHeader(
                  title: widget.activityName,
                  breadcrumb: widget.breadcrumbText,
                  onBack: _goBackWithRefresh,
                ),
                Expanded(
                  child:
                      FutureBuilder<ResponseResult<PmisActivityTicketDetail>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryGreen,
                              ),
                            );
                          }

                          final result = snapshot.data;
                          if (result == null ||
                              !result.isSuccess ||
                              result.data == null) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 24,
                              ),
                              child: Text(
                                result?.errorMessage ??
                                    'Could not load ticket checkers',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }

                          final detail = result.data!;
                          final checkers = detail.ticketCheckers;
                          final bottomButtonLabel = detail.startActivity
                              ? 'Start Activity'
                              : 'Next';

                          if (checkers.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              child: Column(
                                children: [
                                  _ActivitySummaryCard(
                                    title: _summaryTitle(detail),
                                    planStart: _formatPlanDate(
                                      detail.plannedStartDt,
                                    ),
                                    planEnd: _formatPlanDate(
                                      detail.plannedEndDt,
                                    ),
                                    actualStart: _formatPlanDate(
                                      detail.actualStartDt,
                                    ),
                                    actualEnd: _formatPlanDate(
                                      detail.actualEndDt,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'No approvers assigned for this ticket',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  _NextButton(
                                    label: bottomButtonLabel,
                                    onPressed: () =>
                                        _openLatestActivityTicketScreen(detail),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _ActivitySummaryCard(
                                        title: _summaryTitle(detail),
                                        planStart: _formatPlanDate(
                                          detail.plannedStartDt,
                                        ),
                                        planEnd: _formatPlanDate(
                                          detail.plannedEndDt,
                                        ),
                                        actualStart: _formatPlanDate(
                                          detail.actualStartDt,
                                        ),
                                        actualEnd: _formatPlanDate(
                                          detail.actualEndDt,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _CheckerPanel(
                                        checkers: checkers,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _NextButton(
                                label: bottomButtonLabel,
                                onPressed: () =>
                                    _openLatestActivityTicketScreen(detail),
                              ),
                            ],
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _ScreenAppHeader extends StatelessWidget {
  final String title;
  final String breadcrumb;
  final VoidCallback onBack;

  const _ScreenAppHeader({
    required this.title,
    required this.breadcrumb,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_sharp,
                  color: AppColors.white,
                  size: 24,
                ),
                onPressed: onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                alignment: Alignment.centerLeft,
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: poppins,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, right: 8),
            child: Text(
              breadcrumb,
              style: TextStyle(
                color: AppColors.white.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                fontFamily: poppins,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  final String title;
  final String planStart;
  final String planEnd;
  final String actualStart;
  final String actualEnd;

  const _ActivitySummaryCard({
    required this.title,
    required this.planStart,
    required this.planEnd,
    required this.actualStart,
    required this.actualEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: fontFamilyMontserrat,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.locationColor,
            ),
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.black.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _planLine('Plan Start', planStart),
              const SizedBox(height: 8),
              _planLine('Plan End', planEnd),
              const SizedBox(height: 8),
              _planLine('Actual Start', actualStart),
              const SizedBox(height: 8),
              _planLine('Actual End', actualEnd),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: poppins,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.3,
        ),
        children: [
          TextSpan(
            text: '$label : ',
            style: TextStyle(
              color: AppColors.color555555.withValues(alpha: 0.85),
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppColors.color555555,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckerPanel extends StatelessWidget {
  final List<PmisTicketChecker> checkers;

  const _CheckerPanel({
    required this.checkers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < checkers.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CheckerTile(
              checker: checkers[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckerTile extends StatelessWidget {
  final PmisTicketChecker checker;

  const _CheckerTile({
    required this.checker,
  });

  static (Color bg, String label) _badgeStyle(String? raw) {
    final s = (raw ?? '').trim().toUpperCase();
    if (s == 'APPROVED' || s == 'ACCEPT' || s == 'ACCEPTED') {
      return (const Color(0xFF43A047), 'Approved');
    }
    if (s == 'REJECTED' || s == 'REJECT') {
      return (const Color(0xFFE53935), 'Rejected');
    }
    return (const Color(0xFFFF9F43), 'Pending');
  }

  String? _remarksText(PmisTicketChecker c) {
    final r = c.remarks?.trim();
    if (r != null && r.isNotEmpty) return r;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badgeStyle(checker.decisionStatus);
    final name = checker.checkerUserName?.trim().isNotEmpty == true
        ? checker.checkerUserName!.trim()
        : '—';
    final remarks = _remarksText(checker);

    return Material(
      color: const Color(0xFFF4F6F8),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checker (Level ${checker.levelNo})',
                        style: TextStyle(
                          fontFamily: poppins,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.color555555.withValues(
                            alpha: 0.85,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: fontFamilyMontserrat,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.locationColor,
                        ),
                      ),
                      if (remarks != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Remarks',
                          style: TextStyle(
                            fontFamily: poppins,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.color555555.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          remarks,
                          style: const TextStyle(
                            fontFamily: poppins,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppColors.color555555,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badge.$1,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge.$2,
                    style: const TextStyle(
                      fontFamily: poppins,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _NextButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDAF0E7),
            foregroundColor: const Color(0xFF0A5D4A),
            disabledBackgroundColor: const Color(0xFFDAF0E7)
                .withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          onPressed: onPressed,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: poppins,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
