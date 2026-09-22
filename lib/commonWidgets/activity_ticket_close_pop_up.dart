import 'package:app/constants/app_colors.dart';
import 'package:app/commonWidgets/custom_form_dropdown.dart';
import 'package:flutter/material.dart';

class ActivityTicketCloseStatusOption {
  final String statusName;
  final String statusCode;
  final int? psmId;

  const ActivityTicketCloseStatusOption({
    required this.statusName,
    required this.statusCode,
    required this.psmId,
  });
}

/// Lowercases and maps Unicode dash/minus to ASCII `-` for status comparisons.
String normalizeActivityTicketCloseStatusForCompare(String? raw) {
  if (raw == null) return '';
  var s = raw.trim().toLowerCase();
  for (final ch in <String>[
    '\u2013',
    '\u2014',
    '\u2015',
    '\u2212',
    '\uFE63',
    '\uFF0D',
  ]) {
    s = s.replaceAll(ch, '-');
  }
  // Normalize machine codes and labels to one comparable form.
  s = s.replaceAll('_', ' ');
  s = s.replaceAll('-', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// PMIS `repeatDt` as date only: `dd/MM/yyyy` (no time component).
String _formatActivityRepetitionDateForRepeatDt(DateTime value) {
  final dd = value.day.toString().padLeft(2, '0');
  final mm = value.month.toString().padLeft(2, '0');
  final yyyy = value.year.toString();
  return '$dd/$mm/$yyyy';
}

class ActivityTicketClosePopupResult {
  final String statusName;
  final String statusCode;
  final int? statusPsmId;
  final DateTime? repetitionDate;
  final String remarks;

  const ActivityTicketClosePopupResult({
    required this.statusName,
    required this.statusCode,
    required this.statusPsmId,
    required this.repetitionDate,
    required this.remarks,
  });

  /// POST `currentStatus` uses selected option `statusName`.
  String get currentStatus => statusName;

  /// POST `currentStatusCode` uses selected option `statusCode`.
  String get currentStatusCode => statusCode;

  /// POST `currentStatusId` uses selected option `psmId`.
  int? get currentStatusId => statusPsmId;

  /// POST `repeatDt` from Activity Repetition Date; null if not set.
  String? get repeatDt => repetitionDate == null
      ? null
      : _formatActivityRepetitionDateForRepeatDt(repetitionDate!);

  /// POST `isRepeatNature`: true for Completed or Completed – To Be Repeated only.
  bool get isRepeatNature {
    final n = normalizeActivityTicketCloseStatusForCompare(statusCode);
    return n == 'completed' || n == 'completed to be repeated';
  }
}

Future<ActivityTicketClosePopupResult?> showActivityTicketClosePopup(
  BuildContext context, {
  String? initialStatus,
  DateTime? initialRepetitionDate,
  String? initialRemarks,
  List<ActivityTicketCloseStatusOption>? statusOptions,
  String? role,
  int? currentStatusId,
  int? currentStatusCode,
}) {
  return showDialog<ActivityTicketClosePopupResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => ActivityTicketClosePopup(
      initialStatus: initialStatus,
      initialRepetitionDate: initialRepetitionDate,
      initialRemarks: initialRemarks,
      statusOptions: statusOptions,
      role: role,
      currentStatusId: currentStatusId,
      currentStatusCode: currentStatusCode,
    ),
  );
}

class ActivityTicketClosePopup extends StatefulWidget {
  final String? initialStatus;
  final DateTime? initialRepetitionDate;
  final String? initialRemarks;
  final List<ActivityTicketCloseStatusOption>? statusOptions;
  final String? role;
  final int? currentStatusId;
  final int? currentStatusCode;

  const ActivityTicketClosePopup({
    super.key,
    this.initialStatus,
    this.initialRepetitionDate,
    this.initialRemarks,
    this.statusOptions,
    this.role,
    this.currentStatusId,
    this.currentStatusCode,
  });

  @override
  State<ActivityTicketClosePopup> createState() =>
      _ActivityTicketClosePopupState();
}

class _ActivityTicketClosePopupState extends State<ActivityTicketClosePopup> {
  static const List<ActivityTicketCloseStatusOption> _defaultStatusOptions =
      <ActivityTicketCloseStatusOption>[
    ActivityTicketCloseStatusOption(
      statusName: 'Completed',
      statusCode: 'COMPLETED',
      psmId: null,
    ),
    ActivityTicketCloseStatusOption(
      statusName: 'Completed – To Be Repeated',
      statusCode: 'COMPLETED_TO_BE_REPEATED',
      psmId: null,
    ),
  ];

  final TextEditingController _remarksController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  ActivityTicketCloseStatusOption? _selectedStatus;
  DateTime? _repetitionDate;
  bool _showStatusError = false;

  bool get _isMakerWithExistingStatus {
    final role = (widget.role ?? '').trim().toUpperCase();
    return role == 'MAKER' &&
        widget.currentStatusId != null &&
        widget.currentStatusCode != null;
  }

  bool get _statusRequired => !_isMakerWithExistingStatus;
  bool get _remarksRequired => true;

  /// Repetition date should appear only for Completed - To Be Repeated.
  bool _repetitionDateEnabled(String? status) {
    final n = normalizeActivityTicketCloseStatusForCompare(status);
    return n == 'completed to be repeated';
  }

  /// Completed - To Be Repeated requires a repetition date before save.
  bool _repetitionDateRequired(String? status) {
    final n = normalizeActivityTicketCloseStatusForCompare(status);
    return n == 'completed to be repeated';
  }
  List<ActivityTicketCloseStatusOption> get _statusOptions {
    final options = widget.statusOptions
        ?.where(
          (e) =>
              e.statusName.trim().isNotEmpty && e.statusCode.trim().isNotEmpty,
        )
        .toList();
    if (options == null || options.isEmpty) return _defaultStatusOptions;
    return options;
  }

  @override
  void initState() {
    super.initState();
    final initial = normalizeActivityTicketCloseStatusForCompare(
      widget.initialStatus,
    );
    for (final s in _statusOptions) {
      final byName = normalizeActivityTicketCloseStatusForCompare(s.statusName);
      final byCode = normalizeActivityTicketCloseStatusForCompare(s.statusCode);
      if (initial.isNotEmpty && (byName == initial || byCode == initial)) {
        _selectedStatus = s;
        break;
      }
    }
    _repetitionDate = widget.initialRepetitionDate;
    // Drop stale repetition dates that are today or earlier.
    if (_repetitionDate != null &&
        !_isRepetitionDateAfterToday(_repetitionDate)) {
      _repetitionDate = null;
    }
    _remarksController.text = widget.initialRemarks ?? '';
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  /// Calendar day only (ignore time) for comparison.
  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Earliest allowed repetition date: tomorrow (today is disabled).
  DateTime get _minRepetitionDate {
    final today = _dateOnly(DateTime.now());
    return today.add(const Duration(days: 1));
  }

  bool _isRepetitionDateAfterToday(DateTime? value) {
    if (value == null) return false;
    return _dateOnly(value).isAfter(_dateOnly(DateTime.now()));
  }

  Future<void> _pickDate() async {
    if (!_repetitionDateEnabled(_selectedStatus?.statusCode)) return;
    final firstAllowed = _minRepetitionDate;
    var initial = _repetitionDate ?? firstAllowed;
    if (initial.isBefore(firstAllowed)) initial = firstAllowed;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstAllowed,
      lastDate: firstAllowed.add(const Duration(days: 3650)),
      selectableDayPredicate: (day) =>
          !_dateOnly(day).isBefore(firstAllowed),
    );
    if (picked == null) return;
    setState(() {
      _repetitionDate = picked;
    });
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d-$m-$y';
  }

  void _onSave() {
    final hasStatus =
        _selectedStatus != null &&
        _selectedStatus!.statusName.trim().isNotEmpty;
    if (_statusRequired && !hasStatus) {
      setState(() {
        _showStatusError = true;
      });
      return;
    }
    final statusForSave =
        _selectedStatus ??
        (_statusOptions.isNotEmpty ? _statusOptions.first : null);
    if (statusForSave == null) {
      setState(() {
        _showStatusError = true;
      });
      return;
    }
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;
    if (_repetitionDateRequired(statusForSave.statusCode) &&
        !_isRepetitionDateAfterToday(_repetitionDate)) {
      setState(() {});
      return;
    }
    // Match showDialog(useRootNavigator: true) so we only dismiss this dialog.
    Navigator.of(context, rootNavigator: true).pop(
      ActivityTicketClosePopupResult(
        statusName: statusForSave.statusName,
        statusCode: statusForSave.statusCode,
        statusPsmId: statusForSave.psmId,
        repetitionDate:
            _repetitionDateEnabled(statusForSave.statusCode)
            ? _repetitionDate
            : null,
        remarks: _remarksController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.8;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: const Color(0xFF5B5B5B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Activity Status', required: true),
                const SizedBox(height: 8),
                CustomDropdown(
                  items: _statusOptions.map((e) => e.statusName).toList(),
                  initialValue: _selectedStatus?.statusName,
                  onChanged: (v) {
                    ActivityTicketCloseStatusOption? selected;
                    for (final s in _statusOptions) {
                      if (s.statusName == v) {
                        selected = s;
                        break;
                      }
                    }
                    setState(() {
                      _selectedStatus = selected;
                      _showStatusError = false;
                      if (!_repetitionDateEnabled(selected?.statusCode)) {
                        _repetitionDate = null;
                      }
                    });
                  },
                ),
                if (_showStatusError)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Please select status',
                      style: TextStyle(
                        color: AppColors.errorColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_repetitionDateEnabled(_selectedStatus?.statusCode)) ...[
                  const SizedBox(height: 8),
                  _helper(
                    'Activity Repetition Date is required and must be '
                    'after today for Completed - To Be Repeated.',
                  ),
                  const SizedBox(height: 12),
                  _label(
                    'Activity Repetition Date',
                    required: _repetitionDateRequired(_selectedStatus?.statusCode),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: _fieldDecoration(
                        hint: 'DD-MM-YYYY',
                      ).copyWith(
                        suffixIcon: Icon(
                          Icons.calendar_month_outlined,
                          color: _repetitionDateEnabled(_selectedStatus?.statusCode)
                              ? AppColors.color555555
                              : AppColors.colorA0A0A0,
                        ),
                      ),
                      child: Text(
                        _repetitionDate == null ? '' : _fmtDate(_repetitionDate),
                        style: TextStyle(
                          color: _repetitionDateEnabled(_selectedStatus?.statusCode)
                              ? AppColors.color555555
                              : AppColors.colorA0A0A0,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  if (_repetitionDateRequired(_selectedStatus?.statusCode) &&
                      _repetitionDate == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Please select repetition date',
                        style: TextStyle(
                          color: AppColors.errorColor,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (_repetitionDateRequired(_selectedStatus?.statusCode) &&
                      _repetitionDate != null &&
                      !_isRepetitionDateAfterToday(_repetitionDate))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Repetition date must be after today',
                        style: TextStyle(
                          color: AppColors.errorColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                _label('Remarks', required: _remarksRequired),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 4,
                
                  decoration: _fieldDecoration(hint: 'Remarks'),
                  validator: (v) =>
                      (_remarksRequired && (v == null || v.trim().isEmpty))
                      ? 'Remarks are required'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF0EEEE),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.errorColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_repetitionDateRequired(_selectedStatus?.statusCode) &&
                              (_repetitionDate == null ||
                                  !_isRepetitionDateAfterToday(
                                    _repetitionDate,
                                  ))) {
                            setState(() {});
                            return;
                          }
                          _onSave();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCFE3DB),
                          foregroundColor: const Color(0xFF2D6C53),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size.fromHeight(52),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.errorColor),
            ),
        ],
      ),
    );
  }

  Widget _helper(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline,
            size: 16,
            color: Color(0xFFE0E0E0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFFB9B9B9),
        fontSize: 16,
      ),
      filled: true,
      fillColor: const Color(0xFFF2F2F2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDADADA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDADADA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.errorColor, width: 1.2),
      ),
    );
  }
}
