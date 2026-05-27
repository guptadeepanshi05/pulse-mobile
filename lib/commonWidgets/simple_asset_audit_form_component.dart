import 'dart:io';
import 'package:app/app_config.dart';
import 'package:app/commonWidgets/custom_image_upload_field.dart';
import 'package:app/commonWidgets/qr_screen_form_field.dart';
import 'package:app/constants/app_colors.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/services/image_upload_service.dart';
import 'package:app/enum/activity_type_enum.dart';
import 'package:app/utils/logger.dart';
import 'package:app/utils.dart';
import 'package:flutter/material.dart';

class SimpleAssetAuditFormComponent extends StatefulWidget {
  final String componentId;
  final String serialLabel;
  final String serialHintText;
  final String photoLabel;
  final TextEditingController serialController;
  final String? initialSerialValue;
  final String? initialPhotoId;
  final String? initialImageData;
  final Function(String? photoId, String? imageData, bool? isQRCodeScanned, String? qrCodeScannedTs)? onDataChanged;
  final bool Function(String)? customValidator;
  final String? customValidationErrorMessage;
  final String siteAuditSchId;

  const SimpleAssetAuditFormComponent({
    super.key,
    required this.componentId,
    required this.serialLabel,
    required this.serialHintText,
    required this.photoLabel,
    required this.serialController,
    this.initialSerialValue,
    this.initialPhotoId,
    this.initialImageData,
    this.onDataChanged,
    this.customValidator,
    this.customValidationErrorMessage,
    required this.siteAuditSchId,
  });

  @override
  State<SimpleAssetAuditFormComponent> createState() => _SimpleAssetAuditFormComponentState();
}

class _SimpleAssetAuditFormComponentState extends State<SimpleAssetAuditFormComponent> {
  String? _currentPhotoId;
  String? _currentImageData;
  File? _selectedImage;
  bool _isUploading = false;
  bool _isQRCodeScanned = false;
  String? _qrCodeScannedTs;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    if (widget.initialSerialValue != null) {
      widget.serialController.text = widget.initialSerialValue!;
    }
    _currentPhotoId = widget.initialPhotoId;
    _currentImageData = widget.initialImageData;
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isUploading = true;
    });

    try {
      final apiService = AppConfig.of(context).apiService;
      final imageUploadService = ImageUploadService(apiService: apiService);

      final photoId = await imageUploadService.uploadImageFromFilePath(
        _selectedImage!.path,
        ActivityTypeEnum.assetAudit,
        false,
        widget.siteAuditSchId,
      );
      // If the user navigated away during the upload, bail out entirely so we
      // don't call setState / use BuildContext on a disposed widget. The
      // `finally` block below is also guarded for the same reason.
      if (!mounted) return;

      if (photoId.isNotEmpty) {
        final imagePath = _selectedImage!.path;
        setState(() {
          _currentPhotoId = photoId;
          _currentImageData = imagePath;
        });

        widget.onDataChanged?.call(photoId, imagePath, _isQRCodeScanned, _qrCodeScannedTs);
        showCustomToast(context, 'Image uploaded successfully');
        Logger.debugLog('✅ Image uploaded with ID: $photoId');
      } else {
        showCustomToast(context, 'Failed to upload image');
        Logger.errorLog('❌ Failed to upload image');
      }
    } catch (e) {
      Logger.errorLog('❌ Error uploading image: $e');
      // Guard context use — the upload future may have completed while the
      // widget was unmounted, in which case showCustomToast must be skipped.
      if (!mounted) return;
      showCustomToast(context, 'Failed to upload image: $e');
    } finally {
      // `finally` runs even when we returned early via `if (!mounted) return;`
      // above. Without this guard we'd hit `Null check operator used on a null
      // value` inside State.setState on a disposed widget.
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Serial Number field with QR scanner
        SerialNumberField(
          label: widget.serialLabel,
          controller: widget.serialController,
          onQRScanned: (scannedValue) {
            setState(() {
              _isQRCodeScanned = true;
              _qrCodeScannedTs = Utils.getCurrentDateTimeForAPICall();
            });
            // Notify parent about the QR scan
            widget.onDataChanged?.call(_currentPhotoId, _currentImageData, _isQRCodeScanned, _qrCodeScannedTs);

          },
        ),
        getHeight(15),

        // Photo upload field
        ImageUploadField(
          label: widget.photoLabel,
          placeholder: "Add Photo",
          isRequired: true,
          externalImageUrl: _currentImageData,
          onImageSelected: (file) {
            if (file != null) {
              setState(() {
                _selectedImage = file;
              });
              _uploadImage();
            } else {
              setState(() {
                _selectedImage = null;
                _currentPhotoId = null;
                _currentImageData = null;
              });
              widget.onDataChanged?.call(null, null, _isQRCodeScanned, _qrCodeScannedTs);
            }
          },
        ),

        // Show validation error if custom validator fails
        if (widget.customValidator != null && 
            widget.serialController.text.isNotEmpty &&
            !widget.customValidator!(widget.serialController.text))
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.errorColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppColors.errorColor,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: AppColors.errorColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.customValidationErrorMessage ?? 'Invalid input',
                    style: TextStyle(
                      color: AppColors.errorColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Show uploading indicator
        if (_isUploading)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Uploading image...',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
