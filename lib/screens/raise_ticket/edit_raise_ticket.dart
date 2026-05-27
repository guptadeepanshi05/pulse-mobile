import 'dart:io';

import 'package:app/commonWidgets/custom_file_upload_new.dart';
import 'package:app/commonWidgets/raise_it_ticket_comments_widget.dart';
import 'package:app/commonWidgets/custom_form_dropdown.dart';
import 'package:app/commonWidgets/custom_form_field.dart';
import 'package:app/commonWidgets/custom_remark.dart';
import 'package:app/commonWidgets/custom_radio_options.dart';
import 'package:app/commonWidgets/custom_submit_button_v2.dart';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/models/it_asset_code_model.dart';
import 'package:app/models/it_asset_type_model.dart';
import 'package:app/models/raise_it_ticket_detail_model.dart';
import 'package:app/models/raise_it_ticket_request_model.dart';
import 'package:app/models/raise_it_ticket_status_model.dart';
import 'package:app/models/raise_ticket_assigned_to_model.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/services/upload_dcouments.dart';
import 'package:app/utils/connectivity_helper.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

class EditRaiseItTicketScreen extends StatefulWidget {
  final int iaitId;

  const EditRaiseItTicketScreen({super.key, required this.iaitId});

  @override
  State<EditRaiseItTicketScreen> createState() =>
      _EditRaiseItTicketScreenState();
}

class _EditRaiseItTicketScreenState extends State<EditRaiseItTicketScreen> {
  final _ticketNoController = TextEditingController();
  final _issueTitleController = TextEditingController();
  final _issueDescriptionController = TextEditingController();
  final _commentsController = TextEditingController();
  final _uploadDocumentsService = UploadDcoumentsService(
    apiService: ServiceLocator().apiService,
  );

  RaiseItTicketDetail? _detail;
  List<ItAssetType> _assetTypes = [];
  List<ItAssetCode> _assetCodes = [];
  List<RaiseTicketAssignedTo> _assignees = [];
  List<RaiseItTicketStatus> _statuses = [];

  ItAssetType? _selectedAssetType;
  ItAssetCode? _selectedAssetCode;
  RaiseTicketAssignedTo? _selectedAssignee;
  RaiseItTicketStatus? _selectedStatus;
  String? _selectedPriority;

  String? _assetTypeInitial;
  String? _assetCodeInitial;
  String? _assigneeInitial;
  String? _statusInitial;

  final List<File> _attachments = [];
  dynamic _attachmentId;
  String? _attachmentName;
  List<RaiseItTicketCommentRequest> _existingComments = [];

  bool _isLoading = true;
  bool _isLoadingAssetCodes = false;
  bool _isSubmitting = false;
  bool _isUploadingAttachment = false;
  bool _isViewMode = false;
  String? _loadError;

  static const _priorities = ['Low', 'Medium', 'High', 'Critical'];

  String _statusCodeUpper(String? raw) {
    return (raw ?? '').trim().toUpperCase();
  }

  bool _isClosedStatusCode(String? raw) {
    final status = _statusCodeUpper(raw);
    return status == 'CLOSE' || status == 'CLOSED';
  }

  /// View-only when the ticket was already closed on load — not when the user
  /// picks CLOSED while editing (they must still be able to submit).
  bool _resolveInitialViewMode(RaiseItTicketDetail detail) {
    final closedBy = detail.closedById;
    if (closedBy != null && closedBy > 0) return true;

    if (detail.iaismId != null && detail.iaismId! > 0) {
      for (final s in _statuses) {
        if (s.iaismId == detail.iaismId) {
          return _isClosedStatusCode(s.statusCode);
        }
      }
    }

    return _isClosedStatusCode(detail.ticketStatus);
  }

  void _applyStatusSelection(RaiseItTicketDetail detail) {
    if (detail.iaismId != null && detail.iaismId! > 0) {
      for (final s in _statuses) {
        if (s.iaismId == detail.iaismId) {
          _selectedStatus = s;
          _statusInitial = s.statusCode;
          return;
        }
      }
    }

    final ticketStatus = _statusCodeUpper(detail.ticketStatus);
    if (ticketStatus.isNotEmpty) {
      for (final s in _statuses) {
        if (_statusCodeUpper(s.statusCode) == ticketStatus) {
          _selectedStatus = s;
          _statusInitial = s.statusCode;
          return;
        }
      }
    }

    _selectedStatus = null;
    _statusInitial = null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ticketNoController.dispose();
    _issueTitleController.dispose();
    _issueDescriptionController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final repo = ServiceLocator().raiseItTicketRepository;
      final results = await Future.wait([
        repo.getRaiseTicketData(widget.iaitId),
        repo.getAssetType(),
        repo.getRaiseTicketAssignedTo(),
        repo.getRaiseTicketStatus(),
      ]);

      final detail = results[0] as RaiseItTicketDetail;
      final assetTypes = results[1] as List<ItAssetType>;
      final assignees = results[2] as List<RaiseTicketAssignedTo>;
      final statuses = results[3] as List<RaiseItTicketStatus>;

      final assetCodes =
          await repo.getAssetCode(detail.iatmId);

      if (!mounted) return;

      _applyDetail(
        detail,
        assetTypes,
        assetCodes.allAssets,
        assignees,
        statuses,
      );

      setState(() => _isLoading = false);
    } catch (e) {
      Logger.errorLog('[EditRaiseItTicket] Load failed: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = _formatError(e);
      });
    }
  }

  void _applyDetail(
    RaiseItTicketDetail detail,
    List<ItAssetType> assetTypes,
    List<ItAssetCode> assetCodes,
    List<RaiseTicketAssignedTo> assignees,
    List<RaiseItTicketStatus> statuses,
  ) {
    _detail = detail;
    _assetTypes = assetTypes;
    _assetCodes = assetCodes;
    _assignees = assignees;
    _statuses = statuses;
    _existingComments = List.from(detail.ticketComments);

    _ticketNoController.text = detail.ticketNumber;
    _issueTitleController.text = detail.issueTitle;
    _issueDescriptionController.text = detail.issueDescription;
    _commentsController.clear();
    _attachmentId = null;
    _attachmentName = null;
    _attachments.clear();

    for (final t in assetTypes) {
      if (t.iatmId == detail.iatmId) {
        _selectedAssetType = t;
        break;
      }
    }
    for (final c in assetCodes) {
      if (c.iamId == detail.iamId) {
        _selectedAssetCode = c;
        break;
      }
    }

    _assetTypeInitial = _selectedAssetType?.assetType;
    _assetCodeInitial = _selectedAssetCode?.asset;

    final priorityUi = _priorityLabel(detail.priority);
    _selectedPriority =
        _priorities.contains(priorityUi) ? priorityUi : priorityUi;

    final assignedId = detail.assignedToId;
    if (assignedId != null && assignedId > 0) {
      RaiseTicketAssignedTo? matched;
      for (final a in assignees) {
        if (a.userMstId == assignedId) {
          matched = a;
          break;
        }
      }

      if (matched == null) {
        // Assignee exists on the ticket but isn't in the fetched list
        // (filtered/inactive). Synthesize an entry so the dropdown can
        // display the current assignee and the user can still switch.
        matched = RaiseTicketAssignedTo(
          userMstId: assignedId,
          fullName: detail.assignedToName.isNotEmpty
              ? detail.assignedToName
              : 'User #$assignedId',
          entityId: 0,
          roleName: '',
        );
        _assignees = [matched, ..._assignees];
      }

      _selectedAssignee = matched;
      _assigneeInitial = matched.fullName;
    }

    _applyStatusSelection(detail);
    _isViewMode = _resolveInitialViewMode(detail);
  }

  List<RaiseItTicketCommentRequest> get _visibleExistingComments =>
      RaiseItTicketCommentsWidget.visibleComments(_existingComments);

  void _onStatusChanged(String? value) {
    if (_isViewMode) return;
    if (value == null) {
      setState(() {
        _selectedStatus = null;
        _statusInitial = null;
      });
      return;
    }
    RaiseItTicketStatus? status;
    for (final s in _statuses) {
      if (s.statusCode == value) {
        status = s;
        break;
      }
    }
    if (status == null) return;
    setState(() {
      _selectedStatus = status;
      _statusInitial = value;
    });
  }

  String _priorityLabel(String apiValue) {
    final v = apiValue.trim();
    if (v.isEmpty) return '';
    final lower = v.toLowerCase();
    for (final p in _priorities) {
      if (p.toLowerCase() == lower) return p;
    }
    return v[0].toUpperCase() + v.substring(1).toLowerCase();
  }

  String _priorityApiValue(String? ui) {
    if (ui == null || ui.trim().isEmpty) return '';
    return ui.trim().toUpperCase();
  }

  Future<void> _loadAssetCodes(int iatmId, {bool clearSelection = false}) async {
    setState(() {
      _isLoadingAssetCodes = true;
      if (clearSelection) {
        _selectedAssetCode = null;
        _assetCodeInitial = null;
      }
      _assetCodes = [];
    });

    try {
      final dropdown =
          await ServiceLocator().raiseItTicketRepository.getAssetCode(iatmId);
      if (!mounted) return;
      setState(() {
        _assetCodes = dropdown.allAssets;
        _isLoadingAssetCodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAssetCodes = false);
      Toastbar.showErrorToastbar(
        'Failed to load asset codes: $e',
        context,
      );
    }
  }

  void _onAssetTypeChanged(String? label) {
    if (_isViewMode) return;
    if (label == null) {
      setState(() {
        _selectedAssetType = null;
        _selectedAssetCode = null;
        _assetTypeInitial = null;
        _assetCodeInitial = null;
        _assetCodes = [];
      });
      return;
    }

    final type = _assetTypes.firstWhere(
      (t) => t.assetType == label,
      orElse: () => _assetTypes.first,
    );

    setState(() {
      _selectedAssetType = type;
      _assetTypeInitial = label;
    });
    _loadAssetCodes(type.iatmId, clearSelection: true);
  }

  void _onAssetCodeChanged(String? label) {
    if (_isViewMode) return;
    if (label == null) {
      setState(() {
        _selectedAssetCode = null;
        _assetCodeInitial = null;
      });
      return;
    }
    final code = _assetCodes.firstWhere(
      (c) => c.asset == label,
      orElse: () => _assetCodes.first,
    );
    setState(() {
      _selectedAssetCode = code;
      _assetCodeInitial = label;
    });
  }

  void _onAssigneeChanged(String? name) {
    if (_isViewMode) return;
    if (name == null) {
      setState(() {
        _selectedAssignee = null;
        _assigneeInitial = null;
      });
      return;
    }
    final assignee = _assignees.firstWhere(
      (a) => a.fullName == name,
      orElse: () => _assignees.first,
    );
    setState(() {
      _selectedAssignee = assignee;
      _assigneeInitial = name;
    });
  }

  int? get _attachmentIdAsInt {
    if (_attachmentId == null) return null;
    return int.tryParse(_attachmentId.toString().trim());
  }

  bool _needsAttachmentUpload(dynamic id) {
    if (_attachments.isEmpty) return false;
    if (id == null) return true;
    final s = id.toString().trim();
    if (s.isEmpty || s == '0') return true;
    if (s.startsWith('LOCAL_IMAGE_ID')) return true;
    return false;
  }

  Future<String?> _uploadDocumentWithFallback(File file) async {
    final isOnline = await ConnectivityHelper.isConnected();
    if (!isOnline) {
      return await ServiceLocator().imageUploadService
          .persistCmDocumentLocalWithoutMobileUploads(file.path);
    }

    final result = await _uploadDocumentsService.uploadFile(
      file: file,
      id: '0',
      activityType: ActivityTypeEnum.itAssetIssueTicket.value,
    );

    if (result.isSuccess && (result.data ?? '').trim().isNotEmpty) {
      return result.data!.trim();
    }

    return await ServiceLocator().imageUploadService
        .persistCmDocumentLocalWithoutMobileUploads(file.path);
  }

  Future<void> _uploadAttachmentImmediately(File file) async {
    if (_isViewMode) return;

    setState(() {
      _isUploadingAttachment = true;
      _attachmentId = null;
      _attachmentName = null;
      _attachments
        ..clear()
        ..add(file);
    });

    try {
      final docId = await _uploadDocumentWithFallback(file);
      if (!mounted) return;

      if (docId != null && docId.trim().isNotEmpty) {
        setState(() {
          _attachmentId = docId;
          _attachmentName = file.path.split('/').last;
        });
      } else {
        Toastbar.showErrorToastbar('Failed to upload attachment', context);
      }
    } catch (e) {
      Logger.errorLog('[EditRaiseItTicket] Attachment upload failed: $e');
      if (mounted) {
        Toastbar.showErrorToastbar('Failed to upload attachment: $e', context);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAttachment = false);
      }
    }
  }

  bool get _hasTicketAttachment {
    final id = _detail?.itAssetIssueAttachmentId;
    return id != null && id > 0;
  }

  String get _ticketAttachmentDisplayName {
    final name = _detail?.itAssetIssueAttachmentName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final id = _detail?.itAssetIssueAttachmentId;
    return id != null ? 'attachment_$id' : 'attachment';
  }

  IconData _attachmentIcon(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildTicketAttachmentSection() {
    final displayName = _ticketAttachmentDisplayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add Attachment',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.whiteColor,
            fontFamily: fontFamilyMontserrat,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                _attachmentIcon(displayName),
                size: 20,
                color: AppColors.color555555,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _openTicketAttachment,
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textBlueAccent,
                      fontFamily: fontFamilyMontserrat,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddCommentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DottedLine(
          dashLength: 4,
          dashGapLength: 3,
          lineThickness: 2,
          dashColor: AppColors.whiteColor,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F5EF).withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomRemarksField(
                label: 'Add Comments',
                hintText: 'Enter comments',
                controller: _commentsController,
                isDisabled: false,
                maxLines: 4,
              ),
              getHeight(16),
              CustomFileUploadNew(
                label: 'Add Attachment',
                placeholder: 'Upload File',
                isRequired: false,
                acceptedFileTypes: '(PDF, DOC, DOCX, JPG, JPEG, PNG)',
                maxSizeText: '(Max Size: 2MB)',
                pickAllowedExtensions: const [
                  'pdf',
                  'doc',
                  'docx',
                  'jpg',
                  'jpeg',
                  'png',
                ],
                uploadedFiles: _attachments,
                onFileSelected: (File? file) async {
                  if (file != null) {
                    await _uploadAttachmentImmediately(file);
                  }
                },
                onFileDeleted: (File file) {
                  setState(() {
                    _attachments.remove(file);
                    _attachmentId = null;
                    _attachmentName = null;
                  });
                },
                isDisabled: _isUploadingAttachment,
              ),
              if (_isUploadingAttachment) ...[
                getHeight(8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openTicketAttachment() async {
    final detail = _detail;
    if (detail == null) return;
    final attachmentId = detail.itAssetIssueAttachmentId;
    if (attachmentId == null || attachmentId <= 0) return;

    final fileName = detail.itAssetIssueAttachmentName?.trim().isNotEmpty == true
        ? detail.itAssetIssueAttachmentName!.trim()
        : 'attachment_$attachmentId';

    try {
      LoaderWidget.showLoader(context);
      final filePath = await ServiceLocator().cmRepository.downloadDocument(
            attachmentId,
            fileName,
          );
      final openResult = await OpenFile.open(filePath);
      if (openResult.type != ResultType.done && mounted) {
        Toastbar.showErrorToastbar(
          openResult.message.isNotEmpty
              ? openResult.message
              : 'Unable to open attachment',
          context,
        );
      }
    } catch (e) {
      Logger.errorLog('[EditRaiseItTicket] Open attachment failed: $e');
      if (mounted) {
        Toastbar.showErrorToastbar('Unable to open attachment: $e', context);
      }
    } finally {
      if (LoaderWidget.isShowing) {
        LoaderWidget.hideLoader();
      }
    }
  }

  Future<void> _ensureAttachmentUploadedBeforeSubmit() async {
    if (_attachments.isEmpty) return;
    if (!_needsAttachmentUpload(_attachmentId)) return;

    final docId = await _uploadDocumentWithFallback(_attachments.first);
    if (docId == null || docId.trim().isEmpty) {
      throw Exception('Failed to upload attachment');
    }

    _attachmentId = docId;
    _attachmentName = _attachments.first.path.split('/').last;
  }

  List<RaiseItTicketCommentRequest> _buildCommentsForSubmit() {
    final comments = List<RaiseItTicketCommentRequest>.from(_existingComments);
    final commentText = _commentsController.text.trim();
    final attachmentId = _attachmentIdAsInt;

    if (commentText.isEmpty && (attachmentId == null || attachmentId <= 0)) {
      return comments;
    }

    comments.add(
      RaiseItTicketCommentRequest(
        iaitcId: 0,
        comments: commentText.isNotEmpty ? commentText : null,
        itAssetAttachmentId: attachmentId,
        attachmentName: _attachmentName,
        isActive: true,
      ),
    );
    return comments;
  }

  List<String> _collectRequiredFieldErrors() {
    final errors = <String>[];
    if (_selectedAssetType == null) {
      errors.add('Please select asset type');
    }
    if (_selectedAssetCode == null) {
      errors.add('Please select asset code');
    }
    // if (_issueTitleController.text.trim().isEmpty) {
    //   errors.add('Issue Title is required');
    // }
    // if (_selectedPriority == null || _selectedPriority!.trim().isEmpty) {
    //   errors.add('Priority is required');
    // }
    if (_selectedStatus == null) {
      errors.add('Status is required');
    }
    if (_selectedAssignee == null) {
      errors.add('Assigned To is required');
    }
    return errors;
  }

  void _showValidationErrors(List<String> errors) {
    if (errors.isEmpty || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please fill all required fields:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...errors.map(
              (error) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $error'),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  Future<void> _onSubmit() async {
    if (_isViewMode || _isSubmitting || _detail == null) return;

    FocusScope.of(context).unfocus();

    final errors = _collectRequiredFieldErrors();
    if (errors.isNotEmpty) {
      _showValidationErrors(errors);
      return;
    }

    setState(() => _isSubmitting = true);
    LoaderWidget.showLoader(context);

    try {
      await _ensureAttachmentUploadedBeforeSubmit();

      final assignee = _selectedAssignee;
      final request = RaiseItTicketRequest(
        iaitId: widget.iaitId,
        iatmId: _selectedAssetType!.iatmId,
        iamId: _selectedAssetCode!.iamId,
        issueTitle: _issueTitleController.text.trim(),
        issueDescription: _issueDescriptionController.text.trim(),
        priority: _priorityApiValue(_selectedPriority),
        assignedToId: assignee != null ? assignee.userMstId.toString() : '',
        assignedToName: assignee?.fullName ?? _detail!.assignedToName,
        iaismId: _selectedStatus?.iaismId ?? _detail!.iaismId,
        ticketStatus:
            _selectedStatus?.statusCode ?? _detail!.ticketStatus,
        isActive: _detail!.isActive,
        remarks: _detail!.remarks,
        ticketComments: _buildCommentsForSubmit(),
        ticketNumber: _detail!.ticketNumber,
        itAssetIssueAttachmentId: _detail!.itAssetIssueAttachmentId,
      );

      await ServiceLocator().raiseItTicketRepository.postRaiseITTicket(request);

      if (!mounted) return;
      LoaderWidget.hideLoader();
      Toastbar.showSuccessToastbar('Ticket updated successfully', context);
      Navigator.of(context).pop(true);
    } catch (e) {
      Logger.errorLog('[EditRaiseItTicket] Submit failed: $e');
      if (!mounted) return;
      Toastbar.showErrorToastbar(_formatError(e), context);
    } finally {
      if (LoaderWidget.isShowing) {
        LoaderWidget.hideLoader();
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
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
          SafeArea(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.white, fontSize: 16),
              ),
              getHeight(16),
              TextButton(
                onPressed: _loadData,
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

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomFormField(
                  label: 'Ticket No',
                  hintText: 'Ticket No',
                  controller: _ticketNoController,
                  isEditable: false,
                  inputBorderRadius: 8,
                ),
                getHeight(16),
                CustomDropdown(
                  key: ValueKey('status_$_statusInitial'),
                  label: 'Status',
                  isRequired: !_isViewMode,
                  items: _statuses.map((s) => s.statusCode).toList(),
                  initialValue: _statusInitial,
                  isDisabled: _isViewMode,
                  onChanged: _onStatusChanged,
                ),
                getHeight(16),
                CustomDropdown(
                  key: ValueKey('assetType_$_assetTypeInitial'),
                  label: 'Asset Type',
                  isRequired: false,
                  items: _assetTypes.map((t) => t.assetType).toList(),
                  initialValue: _assetTypeInitial,
                  isDisabled: true,
                  onChanged: _onAssetTypeChanged,
                ),
                getHeight(16),
                CustomDropdown(
                  key: ValueKey('assetCode_$_assetCodeInitial'),
                  label: 'Asset Code',
                  isRequired: false,
                  items: _assetCodes.map((c) => c.asset).toList(),
                  initialValue: _assetCodeInitial,
                  isDisabled: true,
                  onChanged: _onAssetCodeChanged,
                ),
                if (_isLoadingAssetCodes) ...[
                  getHeight(8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ],
                getHeight(16),
                
                CustomFormField(
                  label: 'Issue Title',
                  hintText: 'Issue Title',
                  isRequired: false,
                  controller: _issueTitleController,
                  isEditable: !_isViewMode,
                  inputBorderRadius: 8,
                  validator: (_) => null,
                ),
                getHeight(16),
                CustomRemarksField(
                  label: 'Issue Description',
                  hintText: 'Enter issue description',
                  controller: _issueDescriptionController,
                  isDisabled: true,
                  maxLines: 4,
                ),
                getHeight(16),
                AbsorbPointer(
                  absorbing: _isViewMode,
                  child: CustomRadioButton(
                    label: 'Priority',
                    isRequired: false,
                    horizontalSpacing: 8,
                    iconTextSpacing: 4,
                    iconSize: 20,
                    fontSize: 13,
                    initialValue: _selectedPriority,
                    options: _priorities
                        .map((p) => OptionItem(value: p, label: p))
                        .toList(),
                    onChanged: _isViewMode
                        ? null
                        : (value) {
                            setState(() => _selectedPriority = value);
                          },
                  ),
                ),
                
                 getHeight(16),
                CustomDropdown(
                  key: ValueKey('assignee_$_assigneeInitial'),
                  label: 'Assigned To',
                  isRequired: !_isViewMode,
                  items: _assignees.map((a) => a.fullName).toList(),
                  initialValue: _assigneeInitial,
                  isDisabled: _isViewMode,
                  onChanged: _onAssigneeChanged,
                ),
                if (_hasTicketAttachment) ...[
                  getHeight(16),
                  _buildTicketAttachmentSection(),
                ],
                getHeight(16),
                if (!_isViewMode) ...[
                  _buildAddCommentSection(),
                  getHeight(16),
                ],
                if (_visibleExistingComments.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Comments History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.white,
                        fontFamily: fontFamilyMontserrat,
                      ),
                    ),
                  ),
                  getHeight(8),
                  RaiseItTicketCommentsWidget(comments: _existingComments),
                ],
              ],
            ),
          ),
        ),
        if (!_isViewMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: CustomSubmitButtonV2(
              text: 'Submit',
              isLoading: _isSubmitting,
              onPressed: _onSubmit,
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final title = _isViewMode ? 'View Ticket' : 'Edit Ticket';

    return AppBar(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 10, top: 12, right: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_sharp,
                  color: AppColors.white,
                  size: 25,
                ),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: poppins,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
