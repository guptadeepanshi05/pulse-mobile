import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:app/utils.dart';
import 'package:app/utils/uppercase_text_formatter.dart';
import 'package:flutter/material.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/constants_strings.dart';
import 'package:app/commonWidgets/custom_image_upload_field.dart';
import 'package:app/screens/qrScannerScreen.dart';
import 'package:app/services/image_upload_service.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/app_config.dart';
import 'package:app/commonWidgets/safe_file_image.dart';

class CctvFormComponent extends StatefulWidget {
  /// Unique identifier for this component instance
  final String componentId;

  /// Label for the serial number field
  final String serialLabel;

  /// Hint text for the serial number field
  final String serialHintText;

  /// Label for the photo upload field
  final String photoLabel;

  /// Label for the disabled text field
  final String? disabledFieldLabel;

  /// Value for the disabled text field
  final String? disabledFieldValue;

  /// Controller for the serial number field
  final TextEditingController serialController;

  /// Initial list of saved items (for display only)
  final List<dynamic> initialSavedItems;

  /// Callback when items are updated (passes complete list)
  final Function(List<Map<String, dynamic>>)? onItemSaved;

  /// Callback when status changes
  final Function(bool?) onStatusChanged;

  /// Custom validation function for serial number
  /// Returns true if valid, false if invalid
  final bool Function(String serialNumber, bool isScanned)? customValidator;

  /// Error message for custom validation failure
  final String? customValidationErrorMessage;

  /// Background color for the component (static)
  static const Color backgroundColor = AppColors.green7;

  /// Site audit schedule ID for API calls (optional)
  final String siteAuditSchId;

  /// Whether to show the table of saved items
  final bool showTable;

  /// Title for the table
  final String? tableTitle;

  /// Height for the image display
  final double imageHeight;

  /// Whether to enable image compression
  final bool enableImageCompression;

  /// Label for the custom text field (optional)
  final String? customFieldLabel;

  /// Initial value for the custom text field (optional)
  final String? customFieldValue;

  /// Whether the custom field is editable (default: true)
  final bool isCustomFieldEditable;

  const CctvFormComponent({
    super.key,
    required this.componentId,
    required this.serialLabel,
    required this.serialHintText,
    required this.photoLabel,
    this.disabledFieldLabel,
    this.disabledFieldValue,
    required this.serialController,
    required this.initialSavedItems,
    this.onItemSaved,
    required this.onStatusChanged,
    this.customValidator,
    this.customValidationErrorMessage,
    required this.siteAuditSchId,
    this.showTable = true,
    this.tableTitle,
    this.imageHeight = 150,
    this.enableImageCompression = true,
    this.customFieldLabel,
    this.customFieldValue,
    this.isCustomFieldEditable = true,
  });

  @override
  State<CctvFormComponent> createState() =>
      _CCTVFormComponentState();
}

class _CCTVFormComponentState extends State<CctvFormComponent> {
  // Form state
  String? _selectedPhotoPath;
  bool? _selectedStatus;
  bool _isQRCodeScanned = false;

  bool _isUploading = false;
  int _photoFieldNonce = 0;
  String? qrCodeScannedTs;
  String? _uploadedImageId; // Photo ID from server
  String? _photoData; // Photo byte data or base64
  bool _hasNewPhotoSelected = false; // Track if user selected a new photo

  // Validation state
  bool _showValidationErrors = false;
  String? _validationErrorMessage;

  // Edit state
  bool _isEditing = false;
  Map<String, dynamic>? _editingItem;

  // Internal saved items state
  late List<Map<String, dynamic>> _savedItems;

  // Image upload service
  late ImageUploadService _imageUploadService;

  // Height field controller
  final TextEditingController _heightController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize internal saved items list
    _savedItems = List<Map<String, dynamic>>.from(widget.initialSavedItems);

    // Initialize height controller with provided value (only if it's a valid value, not 'N/A' or empty)
    if (widget.customFieldValue != null && 
        widget.customFieldValue!.isNotEmpty && 
        widget.customFieldValue!.toUpperCase() != 'N/A') {
      _heightController.text = widget.customFieldValue!;
    }

    // Listen to serial controller changes to detect manual input vs scanning
    widget.serialController.addListener(_onSerialChanged);
    // Initialize image upload service
    _imageUploadService = ImageUploadService(
      apiService: AppConfig.of(context).apiService,
    );
  }

  @override
  void dispose() {
    widget.serialController.removeListener(_onSerialChanged);
    _heightController.dispose();
    super.dispose();
  }

  void _onSerialChanged() {
    // If text is manually typed, mark as not scanned
    if (!_isQRCodeScanned) {
      setState(() {
        _isQRCodeScanned = false;
        qrCodeScannedTs = null;
      });
    }
  }

  /// Validates all mandatory fields
  bool _validateAllFields() {
    setState(() {
      _showValidationErrors = true;
      _validationErrorMessage = null;
    });

    // Check serial number
    if (widget.serialController.text.isEmpty) {
      _validationErrorMessage = 'Please enter a serial number';
      return false;
    }

    // Check photo
    if (_selectedPhotoPath == null || _selectedPhotoPath!.isEmpty) {
      _validationErrorMessage = 'Please select a photo';
      return false;
    }

    // Check status
    if (_selectedStatus == null) {
      _validationErrorMessage = 'Please select a status';
      return false;
    }
    return true;
  }

  /// Runs custom validation on serial number
  bool _validateSerialNumber() {

    if (widget.customValidator != null) {

      final isValid = widget.customValidator!(
        widget.serialController.text,
        _isQRCodeScanned,
      );

      if (!isValid) {
        _validationErrorMessage =
            widget.customValidationErrorMessage ??
            'Invalid serial number. Please check and try again.';

        return false;
      }
    } else {

    }
    return true;
  }

  /// Handles photo selection (paths from [ImageUploadField] / existing item data).
  void _handlePhotoSelection(String? photoPath) {
    setState(() {
      _selectedPhotoPath =
          (photoPath == null || photoPath.isEmpty) ? null : photoPath;
      _photoData = _selectedPhotoPath;
      _uploadedImageId = null; // Reset photo ID since we have new photo data
      _hasNewPhotoSelected = photoPath != null && photoPath.isNotEmpty;
      _showValidationErrors = false;
    });
  }

  /// Preview URL/path for [ImageUploadField] (data URLs, filesystem paths; not raw numeric ids).
  String? _externalPhotoPreviewForUploadField() {
    final p = _selectedPhotoPath;
    if (p == null || p.isEmpty) return null;
    if (int.tryParse(p) != null) return null;
    return p;
  }

  Widget _buildSafeMemoryImage(String base64Payload) {
    try {
      final bytes = base64Decode(base64Payload);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.broken_image,
              color: Colors.white,
              size: 48,
            ),
          );
        },
      );
    } catch (_) {
      return const Center(
        child: Icon(
          Icons.broken_image,
          color: Colors.white,
          size: 48,
        ),
      );
    }
  }

  /// Handles status change
  void _handleStatusChange(bool? status) {
    setState(() {
      _selectedStatus = status;
      _showValidationErrors = false;
    });
    widget.onStatusChanged(status);
  }

  /// Handles save button click
  Future<void> _handleSave() async {

    try {
      // Reset validation state
      setState(() {
        _showValidationErrors = false;
        _validationErrorMessage = null;
      });

      // Step 1: Run mandatory checks

      if (!_validateAllFields()) {

        _showValidationError();
        return;
      }

      // Step 2: Run custom validation on serial number

      if (!_validateSerialNumber()) {

        _showValidationError();
        return;
      }

      // Step 3: Handle photo upload
      // Use _editingItem if we're editing, otherwise look for existing item
      final existingItem = _isEditing && _editingItem != null
          ? _editingItem!
          : _savedItems.firstWhere(
              (item) => item['mfg_serial_no'] == widget.serialController.text,
              orElse: () => {},
            );

      if (_hasNewPhotoSelected &&
          _selectedPhotoPath != null &&
          _selectedPhotoPath!.isNotEmpty) {
        // User actually selected a new photo - upload it

        await _uploadPhoto();
        if (!mounted) return;
      } else {
        // No new photo selected by user
        if (_isEditing && _uploadedImageId != null) {
          // If we're editing and have a preserved photo ID, use it

        } else if (existingItem.isNotEmpty &&
            existingItem['photo'] != null &&
            existingItem['photo'].toString().isNotEmpty) {
          // If editing existing item with photo, preserve it

          _uploadedImageId = existingItem['photo'];
        }
      }

      // Step 4: Create item data and add to saved items
      final itemData = {
        'mfg_serial_no': widget.serialController.text,
        'asset_status': _selectedStatus! ? 'OK' : 'Not OK',
        'photo_id': _uploadedImageId, // Photo ID from server
        'photoPath': _selectedPhotoPath, // Local photo path
        'qr_code_scanned': _isQRCodeScanned,
        'qr_code_scanned_ts': qrCodeScannedTs,
        'disabledFieldValue': widget.disabledFieldValue,
        'customFieldValue': _heightController.text.trim().isNotEmpty 
            ? _heightController.text.trim() 
            : null,
        'timestamp': Utils.getCurrentDateTimeForAPICall(),
      };

      // Handle photo data properly
      if (_uploadedImageId != null) {
        // We have a photo ID from server
        itemData['photo_id'] = _uploadedImageId;
        // Store photoPath - if we have base64 image data, keep it; otherwise use photo_id
        if (_selectedPhotoPath != null && _selectedPhotoPath!.startsWith('data:image/')) {
          // We have base64 image data - store it for instant display next time
          itemData['photoPath'] = _selectedPhotoPath;
        } else if (_photoData != null && _photoData.toString().startsWith('data:image/')) {
          // We have cached base64 data
          itemData['photoPath'] = _photoData;
        } else if (existingItem.isNotEmpty && existingItem['photoPath'] != null) {
          // Keep original photoPath (might be base64 or path)
          itemData['photoPath'] = existingItem['photoPath'];
        } else {
          // Fallback to photo_id as string
          itemData['photoPath'] = _uploadedImageId.toString();
        }
      } else if (_photoData != null) {
        // We have local photo data (base64 or local path)
        itemData['photo'] = null;
        itemData['photoPath'] = _photoData;
      }

      // Debug logging for photo data

      // Step 5: Handle save (add new or update existing)
      if (_isEditing && _editingItem != null) {
        // Update existing item in the internal list
        final existingIndex = _savedItems.indexWhere(
          (item) => item['mfg_serial_no'] == _editingItem!['mfg_serial_no'],
        );

        if (existingIndex != -1) {
          // Replace the existing item in the list
          _savedItems[existingIndex] = itemData;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Check if item with same serial number already exists
        final existingIndex = _savedItems.indexWhere(
          (item) => item['mfg_serial_no'] == widget.serialController.text,
        );

        if (existingIndex != -1) {
          // Update existing item instead of creating duplicate
          _savedItems[existingIndex] = itemData;

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Add new item to the internal list
          _savedItems.add(itemData);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Notify parent with the complete updated list
      widget.onItemSaved?.call(List.from(_savedItems));

      // Force a rebuild to ensure the table updates
      setState(() {});

      // Step 6: Clear form
      _clearForm();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving item: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Handles photo upload using ImageUploadService
  Future<void> _uploadPhoto() async {

    if (_selectedPhotoPath == null || _selectedPhotoPath!.isEmpty) {

      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {

      final imageFile = File(_selectedPhotoPath!);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }

      // Upload using file path to reduce runtime memory pressure.
      final uniqueId = await _imageUploadService.uploadImageFromFilePath(
        _selectedPhotoPath!,
        ActivityTypeEnum.assetAudit,
        false,
        widget.siteAuditSchId,
      );

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadedImageId = uniqueId;
      });

      if (uniqueId.isEmpty) {

        if (!mounted) return;
        setState(() {
          _isUploading = false;
        });
        throw Exception('Photo upload failed - no unique ID returned');
      }

    } catch (e) {

      if (!mounted) return;
      setState(() {
        _isUploading = false;
      });
      throw Exception('Photo upload failed: $e');
    }
  }

  /// Shows validation error
  void _showValidationError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _validationErrorMessage ?? 'Please fill all required fields',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Clears the form
  void _clearForm() {
    setState(() {
      _photoFieldNonce++;
      widget.serialController.clear();
      _heightController.clear();
      _selectedPhotoPath = null;
      _selectedStatus = null;
      _isQRCodeScanned = false;
      qrCodeScannedTs = null;
      _uploadedImageId = null;
      _photoData = null;
      _hasNewPhotoSelected = false;
      _showValidationErrors = false;
      _validationErrorMessage = null;
      _isEditing = false;
      _editingItem = null;
    });
  }

  /// Starts editing an item
  void _startEditing(Map<String, dynamic> item) async {

    setState(() {
      _photoFieldNonce++;
      _isEditing = true;
      _editingItem = item;
      widget.serialController.text = item['mfg_serial_no'] ?? '';
      // Check both customFieldValue and dimension_value for height
      _heightController.text = item['customFieldValue']?.toString() ?? 
                               item['dimension_value']?.toString() ?? '';
      _selectedStatus = item['asset_status'] == 'OK' ? true : false;
      _isQRCodeScanned = item['qr_code_scanned'] ?? false;
      qrCodeScannedTs = item['qr_code_scanned'] == true
          ? item['qr_code_scanned_ts']
          : null;
      _hasNewPhotoSelected = false; // Reset flag when starting to edit
    });

    // Handle photo loading for editing
    final photoId = item['photo_id']; // This could be numeric (server ID) or string (local ID)
    final photoPath = item['photoPath']; // This is the local path or base64 data

    // Check if photoPath is base64 data first (faster, no fetch needed)
    final photoPathString = photoPath?.toString();
    if (photoPathString != null && 
        photoPathString.isNotEmpty && 
        photoPathString.startsWith('data:image/')) {
      // We have base64 image data - use it immediately

      _uploadedImageId = photoId?.toString();
      _photoData = photoPathString;
      setState(() {
        _selectedPhotoPath = photoPathString;
        _isUploading = false;
      });

      return; // Exit early - no need to fetch
    }

    // Convert photo_id to string if it's numeric
    final uniqueIdString = photoId?.toString();

    if (uniqueIdString != null && 
        uniqueIdString.isNotEmpty && 
        uniqueIdString != "null" && 
        uniqueIdString != "0") {

      _uploadedImageId = uniqueIdString; // Store the unique ID as string
      _photoData = null; // No local photo data
      await _fetchAndDisplayServerImage(uniqueIdString);
    } else if (photoPathString != null && photoPathString.isNotEmpty) {
      // Local photo path (not base64)

      _uploadedImageId = null; // No server photo ID
      _photoData = photoPathString; // Store the photo data as string
      setState(() {
        _selectedPhotoPath = photoPathString; // Convert to string
        _isUploading = false;
      });

    } else {

      _uploadedImageId = null;
      _photoData = null;
      setState(() {
        _selectedPhotoPath = null;
        _isUploading = false;
      });
    }
  }

  /// Fetches and displays server image for editing using ImageUploadService
  Future<void> _fetchAndDisplayServerImage(String uniqueId) async {

    try {
      // Show loading indicator
      setState(() {
        _isUploading = true;
      });

      String? imageData;
      String? finalUniqueId = uniqueId;
      
      // Check if this is a server ID (numeric, not LOCAL_IMAGE_ID)
      // If so, try to get from local first, then download from server if not found
      if (!uniqueId.contains("LOCAL_IMAGE_ID") && int.tryParse(uniqueId) != null) {
        
        // Try to get from local SQLite (checks both unique_id and server_id)
        imageData = await _imageUploadService.getImageUsingUniqueId(uniqueId);
        
        if (imageData == null || imageData.isEmpty) {
          // Not found locally, download from server

          finalUniqueId = await _imageUploadService.downloadImageUsingServerId(
            uniqueId,
            ActivityTypeEnum.assetAudit,
            widget.siteAuditSchId,
          );

          // After download, get the image data
          if (finalUniqueId != null) {
            imageData = await _imageUploadService.getImageUsingUniqueId(finalUniqueId);
          }
        } else {

        }
      } else {
        // Not a server ID, get directly

        imageData = await _imageUploadService.getImageUsingUniqueId(uniqueId);
      }

      if (mounted && imageData != null && imageData.isNotEmpty) {
        // Ensure the image data has proper data URL format
        final finalImageData = imageData.startsWith('data:image/')
            ? imageData
            : 'data:image/jpeg;base64,$imageData';

        setState(() {
          _selectedPhotoPath = finalImageData; // Store as base64 data for display
          _isUploading = false; // Clear loading state
        });

      } else {

        setState(() {
          _selectedPhotoPath = null; // Clear photo path on failure
          _isUploading = false; // Clear loading state
        });
      }
    } catch (e) {

      if (mounted) {
        setState(() {
          _selectedPhotoPath = null; // Don't set to uniqueId - keep null to show error
          _isUploading = false; // Clear loading state
        });

      }
    }
  }

  /// Builds the serial number field with QR scanner (matching CustomInfoCard design)
  Widget _buildSerialNumberField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with asterisk (matching CustomInfoCard)
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: widget.serialLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontFamily: fontFamilyMontserrat,
                  fontSize: 16,
                  color: AppColors.white,
                ),
              ),
              const TextSpan(
                text: " *",
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontFamily: fontFamilyMontserrat,
                  fontSize: 16,
                  color: AppColors.errorColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // TextFormField (matching CustomInfoCard)
        TextFormField(
          controller: widget.serialController,
          inputFormatters: [UpperCaseTextFormatter()],
          onChanged: (value) {
            setState(() {
              _isQRCodeScanned = false;
              qrCodeScannedTs = null;
            });
          },
          decoration: InputDecoration(
            hintText: widget.serialHintText,
            hintStyle: TextStyle(
              fontWeight: FontWeight.w400,
              fontFamily: fontFamilyMontserrat,
              fontSize: 16,
              color: AppColors.color555555,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                try {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QRScannerScreen()),
                  );
                  if (result != null && result is String) {
                    setState(() {
                      widget.serialController.text = result.toUpperCase();
                      _isQRCodeScanned = true;
                      qrCodeScannedTs = Utils.getCurrentDateTimeForAPICall();
                      _showValidationErrors = false;
                    });
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error scanning QR code: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide.none,
            ),
          ),
        ),

        // Validation error
        if (_showValidationErrors && widget.serialController.text.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Serial number is required',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),

        // QR scan indicator
        if (_isQRCodeScanned)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner, color: Colors.green, size: 16),
                SizedBox(width: 4),
                Text(
                  'Scanned via QR Code',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Builds the height field (similar to serial number field but without QR scanner)
  Widget _buildHeightField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label (matching CustomInfoCard)
        Text(
          widget.customFieldLabel ?? "Height (in Meters)",
          style: const TextStyle(
            fontWeight: FontWeight.w400,
            fontFamily: fontFamilyMontserrat,
            fontSize: 16,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 6),

        // TextFormField (matching CustomInfoCard)
        TextFormField(
          controller: _heightController,
          readOnly: !widget.isCustomFieldEditable,
          decoration: InputDecoration(
            hintText: "Height (in Meters)",
            hintStyle: TextStyle(
              fontWeight: FontWeight.w400,
              fontFamily: fontFamilyMontserrat,
              fontSize: 16,
              color: AppColors.color555555,
            ),
            filled: true,
            fillColor: widget.isCustomFieldEditable 
                ? Colors.white 
                : AppColors.borderColorE0E0E0, // Grey when not editable
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide.none,
            ),
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontWeight: FontWeight.w400,
            fontFamily: fontFamilyMontserrat,
            fontSize: 16,
            color: widget.isCustomFieldEditable 
                ? AppColors.color555555 
                : AppColors.color555555.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  /// Photo capture via shared [ImageUploadField] (CustomCameraScreen + compression).
  Widget _buildPhotoUploadField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ImageUploadField(
          key: ValueKey('${widget.componentId}_$_photoFieldNonce'),
          label: widget.photoLabel,
          placeholder: widget.photoLabel,
          isRequired: true,
          isDisabled: _isUploading,
          externalImageUrl: _externalPhotoPreviewForUploadField(),
          onImageSelected: (File? file) {
            if (_isUploading) return;
            _handlePhotoSelection(file?.path);
          },
        ),

        // Validation error
        if (_showValidationErrors &&
            (_selectedPhotoPath == null || _selectedPhotoPath!.isEmpty))
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Photo is required',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds the disabled text field (matching CustomInfoCard design)
  Widget _buildDisabledField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label (matching CustomInfoCard)
        Text(
          widget.disabledFieldLabel ?? "",
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            fontFamily: fontFamilyMontserrat,
          ),
        ),
        const SizedBox(height: 5),

        // Input field (matching CustomInfoCard)
        TextFormField(
          initialValue: widget.disabledFieldValue,
          readOnly: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.borderColorE0E0E0, // Grey when not editable
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide.none,
            ),
            hintText: widget.disabledFieldValue,
            hintStyle: TextStyle(
              fontWeight: FontWeight.w400,
              fontFamily: fontFamilyMontserrat,
              fontSize: 16,
              color: AppColors.color555555.withValues(alpha: 0.6),
            ),
          ),
          style: TextStyle(
            fontWeight: FontWeight.w400,
            fontFamily: fontFamilyMontserrat,
            fontSize: 16,
            color: AppColors.color555555,
          ),
        ),
      ],
    );
  }

  /// Builds the status radio buttons (matching CustomInfoCard design)
  Widget _buildStatusField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with asterisk (matching CustomInfoCard)
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "Status",
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontFamily: fontFamilyMontserrat,
                  fontSize: 16,
                  color: AppColors.white,
                ),
              ),
              const TextSpan(
                text: " *",
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  fontFamily: fontFamilyMontserrat,
                  fontSize: 16,
                  color: AppColors.errorColor,
                ),
              ),
            ],
          ),
        ),

        // Radio buttons (matching CustomInfoCard) - more compact layout
        RadioGroup<bool>(
          groupValue: _selectedStatus,
          onChanged: (bool? value) {
            _handleStatusChange(value);
          },
          child: Wrap(
            spacing: 20,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<bool>(
                    value: true,
                    activeColor: const Color(0xFF5678BA),
                    fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFF5678BA);
                      }
                      return Colors.white;
                    }),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "Ok",
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontFamily: fontFamilyMontserrat,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<bool>(
                    value: false,
                    activeColor: const Color(0xFF5678BA),
                    fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFF5678BA);
                      }
                      return Colors.white;
                    }),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "Not Ok",
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontFamily: fontFamilyMontserrat,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Validation error
        if (_showValidationErrors && _selectedStatus == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Status is required',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Builds the save button (matching CustomInfoCard design exactly)
  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isUploading
          ? null
          : _handleSave, // Disable button when uploading
      style: ElevatedButton.styleFrom(
        backgroundColor: _isUploading
            ? Colors.grey.shade400
            : const Color(0xFFDBE2F0),
        foregroundColor: _isUploading
            ? Colors.grey.shade600
            : const Color(0xFF2D426E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      child: _isUploading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2D426E)),
              ),
            )
          : Text("Save"),
    );
  }

  /// Gets the dynamic label for the custom field column header
  String _getCustomFieldTableHeader() {
    if (widget.customFieldLabel == null) {
      return '';
    }
    final label = widget.customFieldLabel!.toLowerCase();
    if (label.contains('height')) {
      return 'Height';
    } else if (label.contains('year') && label.contains('manufactur')) {
      return 'MFGYear';
    } else if (label.contains('mfg') && label.contains('year')) {
      return 'MFGYear';
    }
    // Default: extract first word or use a shortened version
    final words = widget.customFieldLabel!.split(' ');
    return words.isNotEmpty ? words.first : widget.customFieldLabel!;
  }

  /// Builds the table of saved items
  Widget _buildSavedItemsTable() {
    if (!widget.showTable || _savedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final customFieldHeader = _getCustomFieldTableHeader();
    final showCustomFieldColumn = widget.customFieldLabel != null && customFieldHeader.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CctvFormComponent.backgroundColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.tableTitle != null) ...[
            Text(
              widget.tableTitle!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: fontFamilyMontserrat,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                // Table header
                Row(
                  children: [
                    _buildTableHeaderCell('Serial No.', 200),
                    if (showCustomFieldColumn)
                      _buildTableHeaderCell(customFieldHeader, 80),
                    _buildTableHeaderCell('Status', 80),
                    _buildTableHeaderCell('Scanned', 80),
                    _buildTableHeaderCell('Photo', 80),
                    _buildTableHeaderCell('Edit', 80),
                  ],
                ),
                const SizedBox(height: 8),
                // Table rows
                ..._savedItems.map((item) => _buildTableRow(item)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a table header cell
  Widget _buildTableHeaderCell(String text, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: fontFamilyMontserrat,
          fontWeight: FontWeight.w400,
        ),
        maxLines: 1,
      ),
    );
  }

  /// Builds a table row
  Widget _buildTableRow(Map<String, dynamic> item) {
    final showCustomFieldColumn = widget.customFieldLabel != null;
    
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          _buildTableDataCell(item['mfg_serial_no'] ?? '', 200),
          if (showCustomFieldColumn)
            _buildTableDataCell(item['customFieldValue'] ?? 'N/A', 80),
          _buildTableDataCell(item['asset_status'] ?? '', 80),
          _buildTableDataCell(
            item['qr_code_scanned'] == true ? 'Yes' : 'No',
            80,
            isScanned: item['qr_code_scanned'] == true,
          ),
          _buildTablePhotoCell(item, 80),
          _buildTableEditCell(item, 80),
        ],
      ),
    );
  }

  /// Builds a table data cell
  Widget _buildTableDataCell(String text, double width, {bool? isScanned}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isScanned != null) ...[
            Icon(
              isScanned ? Icons.qr_code_scanner : Icons.close,
              color: isScanned ? Colors.blue : Colors.red,
              size: 16,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.color555555,
                fontSize: 14,
                fontFamily: fontFamilyMontserrat,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a table photo cell
  Widget _buildTablePhotoCell(Map<String, dynamic> item, double width) {
    // Debug logging for table photo cell

    // Convert photo_id to string if it's numeric, and check if valid
    final photoId = item['photo_id'];
    final photoIdString = photoId?.toString();
    final hasValidPhotoId = photoIdString != null && 
                           photoIdString.isNotEmpty && 
                           photoIdString != "null" && 
                           photoIdString != "0";
    
    // Check photoPath
    final photoPath = item['photoPath'];
    final photoPathString = photoPath?.toString();
    final hasValidPhotoPath = photoPathString != null && photoPathString.isNotEmpty;
    
    // Determine which photo to show (prefer photo_id over photoPath)
    final photoToShow = hasValidPhotoId ? photoIdString : 
                       (hasValidPhotoPath ? photoPathString : null);

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: Icon(
          Icons.camera_alt,
          color: (hasValidPhotoId || hasValidPhotoPath)
              ? AppColors.color555555
              : Colors.grey,
        ),
        onPressed: photoToShow != null
            ? () => _showPhotoViewer(context, photoToShow)
            : null,
      ),
    );
  }

  /// Builds a table edit cell
  Widget _buildTableEditCell(Map<String, dynamic> item, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: const Icon(
          Icons.edit_calendar_outlined,
          color: AppColors.color555555,
        ),
        onPressed: () {
          _startEditing(item);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main form container matching CustomInfoCard design
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CctvFormComponent.backgroundColor,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Serial Number field
              _buildSerialNumberField(),
              const SizedBox(height: 16),

              // Custom field (if provided) - Height field similar to serial number
              if (widget.customFieldLabel != null) ...[
                _buildHeightField(),
                const SizedBox(height: 16),
              ],

              // Photo Picker
              _buildPhotoUploadField(),
              const SizedBox(height: 16),

              // Disabled field (if needed)
              if (widget.disabledFieldLabel != null) ...[
                _buildDisabledField(),
                const SizedBox(height: 16),
              ],

              // Status field with save button inline (matching CustomInfoCard layout)
              Row(
                children: [
                  Expanded(flex: 3, child: _buildStatusField()),
                  const SizedBox(width: 16),
                  Flexible(flex: 1, child: _buildSaveButton()),
                ],
              ),
            ],
          ),
        ),

        // Saved items table
        _buildSavedItemsTable(),
      ],
    );
  }

  /// Shows photo viewer dialog
  Future<void> _showPhotoViewer(BuildContext context, String? photo) async {
    // Debug logging for photo viewer

    if (photo == null || photo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photo available to view.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String? imageData;

    // Case 1: Photo is a base64 data URL
    if (photo.startsWith('data:image/')) {
      imageData = photo;
    }
    // Case 2: Photo is a local file path
    else if (await File(photo).exists()) {
      imageData = photo;
    }
    // Case 3: Photo is a unique ID from ImageUploadService (can be numeric server ID or string local ID)
    else {
      // Show loading dialog while fetching from ImageUploadService
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );

      try {

        String? finalUniqueId = photo;
        
        // Check if this is a server ID (numeric, not LOCAL_IMAGE_ID)
        // If so, try to get from local first, then download from server if not found
        if (!photo.contains("LOCAL_IMAGE_ID") && int.tryParse(photo) != null) {
          
          // Try to get from local SQLite (checks both unique_id and server_id)
          imageData = await _imageUploadService.getImageUsingUniqueId(photo);
          
          if (imageData == null || imageData.isEmpty) {
            // Not found locally, download from server

            finalUniqueId = await _imageUploadService.downloadImageUsingServerId(
              photo,
              ActivityTypeEnum.assetAudit,
              widget.siteAuditSchId,
            );

            // After download, get the image data
            if (finalUniqueId != null) {
              imageData = await _imageUploadService.getImageUsingUniqueId(finalUniqueId);
            }
          } else {

          }
        } else {
          // Use ImageUploadService to get image data (handles both numeric and string IDs)
          imageData = await _imageUploadService.getImageUsingUniqueId(photo);
        }

        if (imageData != null && imageData.isNotEmpty) {
          // Ensure proper data URL format
          imageData = imageData.startsWith('data:image/')
              ? imageData
              : 'data:image/jpeg;base64,$imageData';

        } else {

        }

        // Close loading dialog
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {

        // Close loading dialog on error
        if (context.mounted) {
          Navigator.of(context).pop();
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load image: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Show photo viewer for valid image data
    if (imageData != null && imageData.isNotEmpty) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                      maxWidth: MediaQuery.of(context).size.width * 0.9,
                    ),
                    child: imageData!.startsWith('data:image/')
                        ? _buildSafeMemoryImage(
                            imageData.split(',').last,
                          )
                        : SafeImageFile(
                            file: File(imageData),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load photo.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
