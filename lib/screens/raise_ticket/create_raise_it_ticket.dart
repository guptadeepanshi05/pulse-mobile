import 'package:app/commonWidgets/custom_form_dropdown.dart';
import 'package:app/commonWidgets/custom_form_field.dart';
import 'package:app/commonWidgets/custom_radio_options.dart';
import 'package:app/commonWidgets/custom_submit_button_v2.dart';
import 'package:app/commonWidgets/loader_widget.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/app_images.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/models/it_asset_code_model.dart';
import 'package:app/models/it_asset_type_model.dart';
import 'package:app/models/raise_it_ticket_request_model.dart';
import 'package:app/models/raise_it_ticket_status_model.dart';
import 'package:app/commonWidgets/safe_svg_picture.dart';
import 'package:app/services/service_locator.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:flutter/material.dart';

class CreateRaiseItTicketScreen extends StatefulWidget {
  const CreateRaiseItTicketScreen({super.key});

  @override
  State<CreateRaiseItTicketScreen> createState() =>
      _CreateRaiseItTicketScreenState();
}

class _CreateRaiseItTicketScreenState extends State<CreateRaiseItTicketScreen> {
  final _issueTitleController = TextEditingController();
  final _issueDescriptionController = TextEditingController();

  List<ItAssetType> _assetTypes = [];
  List<ItAssetCode> _assetCodes = [];
  ItAssetType? _selectedAssetType;
  RaiseItTicketStatus? _openStatus;
  ItAssetCode? _selectedAssetCode;
  String? _selectedPriority;

  bool _isLoadingDropdowns = true;
  bool _isLoadingAssetCodes = false;
  bool _isSubmitting = false;

  static const _priorities = ['Low', 'Medium', 'High', 'Critical'];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _issueTitleController.dispose();
    _issueDescriptionController.dispose();
    super.dispose();
  }

  RaiseItTicketStatus? _findOpenStatus(List<RaiseItTicketStatus> statuses) {
    for (final status in statuses) {
      final code = status.statusCode.trim().toUpperCase();
      if (code == 'OPEN') return status;
    }
    return null;
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingDropdowns = true);
    try {
      final repo = ServiceLocator().raiseItTicketRepository;
      final results = await Future.wait([
        repo.getAssetType(),
        repo.getRaiseTicketStatus(),
      ]);

      final assetTypes = results[0] as List<ItAssetType>;
      final statuses = results[1] as List<RaiseItTicketStatus>;

      if (!mounted) return;
      setState(() {
        _assetTypes = assetTypes;
        _openStatus = _findOpenStatus(statuses);
        _isLoadingDropdowns = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingDropdowns = false);
      Toastbar.showErrorToastbar(
        'Failed to load form data: $e',
        context,
      );
    }
  }

  Future<void> _loadAssetCodes(int iatmId) async {
    setState(() {
      _isLoadingAssetCodes = true;
      _selectedAssetCode = null;
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
    if (label == null) {
      setState(() {
        _selectedAssetType = null;
        _selectedAssetCode = null;
        _assetCodes = [];
      });
      return;
    }

    final type = _assetTypes.firstWhere(
      (t) => _assetTypeLabel(t) == label,
      orElse: () => _assetTypes.first,
    );

    setState(() => _selectedAssetType = type);
    _loadAssetCodes(type.iatmId);
  }

  void _onAssetCodeChanged(String? label) {
    if (label == null) {
      setState(() => _selectedAssetCode = null);
      return;
    }
    final code = _assetCodes.firstWhere(
      (c) => c.asset == label,
      orElse: () => _assetCodes.first,
    );
    setState(() => _selectedAssetCode = code);
  }

  String _assetTypeLabel(ItAssetType type) => type.assetType;

  List<String> _collectRequiredFieldErrors() {
    final errors = <String>[];
    if (_selectedAssetType == null) {
      errors.add('Please select asset type');
    }
    if (_selectedAssetCode == null) {
      errors.add('Please select asset code');
    }
    if (_issueDescriptionController.text.trim().isEmpty) {
      errors.add('Issue Description is required');
    }
    if (_openStatus == null) {
      errors.add('Unable to load OPEN status');
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
    if (_isSubmitting) return;

    FocusScope.of(context).unfocus();

    final errors = _collectRequiredFieldErrors();
    if (errors.isNotEmpty) {
      _showValidationErrors(errors);
      return;
    }

    setState(() => _isSubmitting = true);
    LoaderWidget.showLoader(context);

    try {
      final openStatus = _openStatus!;
      final request = RaiseItTicketRequest(
        iatmId: _selectedAssetType!.iatmId,
        iamId: _selectedAssetCode!.iamId,
        issueTitle: _issueTitleController.text.trim(),
        issueDescription: _issueDescriptionController.text.trim(),
        priority: _selectedPriority?.trim().toUpperCase() ?? '',
        iaismId: openStatus.iaismId,
        assignedToId: '',
        assignedToName: '',
        ticketStatus: openStatus.statusCode,
        isActive: true,
      );

      Logger.debugLog(
        '[CreateRaiseItTicket] Submitting ticket: ${request.toJson()}',
      );

      await ServiceLocator().raiseItTicketRepository.postRaiseITTicket(request);

      if (!mounted) return;

      LoaderWidget.hideLoader();
      Toastbar.showSuccessToastbar('Ticket raised successfully', context);

      // Return to RaiseTicketsScreen and trigger list refresh.
      Navigator.of(context).pop(true);
    } catch (e) {
      Logger.errorLog('[CreateRaiseItTicket] Submit failed: $e');
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
          SafeArea(
            child: _isLoadingDropdowns
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryGreen,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                CustomDropdown(
                                  label: 'Asset Type',
                                  isRequired: true,
                                  items: _assetTypes
                                      .map(_assetTypeLabel)
                                      .toList(),
                                  onChanged: _onAssetTypeChanged,
                                ),
                                getHeight(16),
                                CustomDropdown(
                                  label: 'Asset Code',
                                  isRequired: true,
                                  items: _assetCodes.map((c) => c.asset).toList(),
                                  isDisabled: _selectedAssetType == null ||
                                      _isLoadingAssetCodes,
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
                                // CustomFormField(
                                //   label: 'Issue Title',
                                //   hintText: 'Issue Title',
                                //   isRequired: false,
                                //   controller: _issueTitleController,
                                //   inputType: InputType.multiline,
                                //   minLines: 2,
                                //   inputBorderRadius: 8,
                                //   validator: (_) => null,
                                // ),
                                // getHeight(16),
                                CustomFormField(
                                  label: 'Issue Description',
                                  hintText: 'Description',
                                  isRequired: true,
                                  controller: _issueDescriptionController,
                                  inputType: InputType.multiline,
                                  minLines: 4,
                                  inputBorderRadius: 8,
                                  maxLength: 500,
                                ),
                                getHeight(16),
                                // CustomRadioButton(
                                //   label: 'Priority',
                                //   isRequired: false,
                                //   horizontalSpacing: 8,
                                //   iconTextSpacing: 4,
                                //   iconSize: 20,
                                //   fontSize: 13,
                                //   initialValue: _selectedPriority,
                                //   options: _priorities
                                //       .map(
                                //         (p) => OptionItem(
                                //           value: p,
                                //           label: p,
                                //         ),
                                //       )
                                //       .toList(),
                                //   onChanged: (value) {
                                //     setState(() => _selectedPriority = value);
                                //   },
                                // ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: CustomSubmitButtonV2(
                          text: 'Submit',
                          isLoading: _isSubmitting,
                          onPressed: _onSubmit,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
              const Expanded(
                child: Text(
                  'Raise Ticket',
                  style: TextStyle(
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
