import 'package:app/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

import '../constants/constants_strings.dart';

class CustomDropdown extends StatefulWidget {
  final String? label;
  final List<String> items;
  final String? initialValue;
  final ValueChanged<String?> onChanged;
  final bool isDisabled;
  final bool isRequired;

  const CustomDropdown({
    super.key,
    this.label,
    required this.items,
    this.initialValue,
    required this.onChanged,
    this.isDisabled = false,
    this.isRequired = false,
  });

  @override
  State<CustomDropdown> createState() => _CustomDropdownState();
}

class _CustomDropdownState extends State<CustomDropdown> {
  String? selectedValue;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Only assign initialValue if it’s in the items list
    if (widget.initialValue != null &&
        widget.items.contains(widget.initialValue)) {
      selectedValue = widget.initialValue;
    }
  }

  @override
  void didUpdateWidget(CustomDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != null &&
        widget.items.contains(widget.initialValue)) {
      setState(() => selectedValue = widget.initialValue);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: widget.label ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    fontFamily: fontFamilyMontserrat,
                  ),
                ),
                if (widget.isRequired)
                  const TextSpan(
                    text: " *",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                      fontFamily: fontFamilyMontserrat,
                    ),
                  ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
        const SizedBox(height: 5),
        const SizedBox(height: 5),
        DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            isExpanded: true,
            hint: Text(
              widget.isDisabled ? 'Field disabled' : 'Select',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: widget.isDisabled
                    ? AppColors.borderColorE0E0E0
                    : AppColors.color555555,
                fontFamily: fontFamilyMontserrat,
              ),
            ),
            items: widget.items.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    fontFamily: fontFamilyMontserrat,
                    color: AppColors.color555555,
                  ),
                ),
              );
            }).toList(),
            value:
                (selectedValue != null && widget.items.contains(selectedValue))
                ? selectedValue
                : null,
            onChanged: widget.isDisabled
                ? null
                : (value) {
                    setState(() {
                      selectedValue = value;
                    });
                    widget.onChanged(value);
                  },

       
            onMenuStateChange: (isOpen) {
              if (!isOpen) {
                _searchController.clear(); // clear search when closed
                FocusScope.of(context).unfocus();
              }
            },

            dropdownStyleData: DropdownStyleData(
              maxHeight: 200,
              direction: DropdownDirection.textDirection,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
            ),
            buttonStyleData: ButtonStyleData(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: widget.isDisabled
                    ? null
                    : Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(5),
                color: widget.isDisabled
                    ? AppColors.borderColorE0E0E0
                    : Colors.white,
              ),
            ),
            iconStyleData: IconStyleData(
              icon: Icon(
                widget.isDisabled ? null : Icons.keyboard_arrow_down,
                color: widget.isDisabled
                    ? Colors.grey.shade600
                    : AppColors.color555555,
              ),
              openMenuIcon: Icon(
                Icons.keyboard_arrow_up,
                color: widget.isDisabled
                    ? Colors.grey.shade600
                    : AppColors.color555555,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// CustomDropdown(
// label: "Type",
// items: ["Battery", "DC"],
// initialValue: selectedType,
// onChanged: (value) {
// setState(() {
// selectedType = value;
// hasUnsavedChanges = true;
// });
// },
// ),
// ),
