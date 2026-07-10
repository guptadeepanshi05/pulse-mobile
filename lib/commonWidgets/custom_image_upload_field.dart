import 'dart:convert';
import 'dart:io';

import 'package:app/commonWidgets/CustomCameraScreen.dart';
import 'package:app/commonWidgets/selfie_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';

import 'package:app/constants/constants_strings.dart';
import 'package:app/constants/app_colors.dart';

import 'package:app/utils/image_compression_helper.dart';
import 'package:app/utils/CrashLogger.dart';
import 'package:app/utils/toastbar.dart';
import 'package:app/commonWidgets/safe_file_image.dart';
import 'package:app/services/local_storage_service.dart';

class ImageUploadField extends StatefulWidget {
  final String? label;
  final String? placeholder;
  final bool isRequired;
  final bool isDisabled;
  final Function(File?) onImageSelected;
  final String? externalImageUrl;

  /// When true, shows a progress indicator instead of the "Take Photo" placeholder
  /// while the parent loads [externalImageUrl] (e.g. from `allImageList`).
  final bool externalImageLoading;

  /// Height of the tap target / preview area (default `150`).
  final double uploadBoxHeight;

  /// Corner radius of the upload box.
  final double uploadBorderRadius;

  /// When true, open system gallery instead of camera.
  final bool pickFromGallery;

  const ImageUploadField({
    super.key,
    this.label,
    this.placeholder,
    this.isRequired = false,
    this.isDisabled = false,
    required this.onImageSelected,
    this.externalImageUrl,
    this.externalImageLoading = false,
    this.uploadBoxHeight = 150,
    this.uploadBorderRadius = 6,
    this.pickFromGallery = false,
  });

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  final ImagePicker _picker = ImagePicker();

  static const String _cameraInProgressKey =
      'image_upload_field_camera_in_progress';

  File? _selectedImage;
  Widget? _externalImageWidget;
  String? _lastExternalUrl;

  bool _isLoading = false;
  bool _isPickingImage = false;

  static const int maxBase64Length = 5000000;

  /// 🔥 BACKGROUND COMPRESSION (ISOLATE)
  static Future<String?> _compressInBackground(String path) async {
    try {
      final file = File(path);
      final result =
          await ImageCompressionHelper.compressImageTo2MB(file);
      return result?.path;
    } catch (_) {
      return null;
    }
  }

  static String _formatNowForWatermark(DateTime now) {
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yyyy = now.year.toString();
    final hh = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min:$ss';
  }

  Future<Position?> _getCurrentPositionForWatermark() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return null;
      }
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 5),
          );
    } catch (_) {
      return null;
    }
  }

  bool _isSelfieField() {
    final label = widget.label?.toLowerCase() ?? '';
    final placeholder = widget.placeholder?.toLowerCase() ?? '';
    return label.contains('selfie') || placeholder.contains('selfie');
  }

  static const double _defaultUploadBoxHeight = 150;
  static const double _selfieUploadBoxHeight = 220;

  double get _effectiveUploadBoxHeight {
    if (_isSelfieField() && widget.uploadBoxHeight == _defaultUploadBoxHeight) {
      return _selfieUploadBoxHeight;
    }
    return widget.uploadBoxHeight;
  }

  Future<File?> _applyWatermark(File file, Position? position) async {
    try {
      final bytes = await file.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      final font = img.arial14;
      final timestamp = _formatNowForWatermark(DateTime.now());
      final latText = position != null
          ? position.latitude.toStringAsFixed(6)
          : 'N/A';
      final lngText = position != null
          ? position.longitude.toStringAsFixed(6)
          : 'N/A';

      const padX = 12;
      const lineGap = 18;
      const textTopPadding = 8;
      const boxBottomPadding = 6;
      final desiredBoxHeight =
          textTopPadding + (lineGap * 3) + boxBottomPadding;
      final maxAllowedBoxHeight = (image.height * 0.24).round();
      final boxHeight = desiredBoxHeight < maxAllowedBoxHeight
          ? desiredBoxHeight
          : maxAllowedBoxHeight;
      final safeBoxHeight = boxHeight < 44 ? 44 : boxHeight;
      final yStart =
          (image.height - safeBoxHeight).clamp(0, image.height - 1);

      final textColor = img.ColorRgb8(255, 255, 255);

      img.fillRect(
        image,
        x1: 0,
        y1: yStart,
        x2: image.width - 1,
        y2: image.height - 1,
        color: img.ColorRgba8(0, 0, 0, 150),
      );

      img.drawString(
        image,
        'Date: $timestamp',
        font: font,
        x: padX,
        y: yStart + textTopPadding,
        color: textColor,
      );
      img.drawString(
        image,
        'Lat: $latText',
        font: font,
        x: padX,
        y: yStart + textTopPadding + lineGap,
        color: textColor,
      );
      img.drawString(
        image,
        'Lng: $lngText',
        font: font,
        x: padX,
        y: yStart + textTopPadding + (lineGap * 2),
        color: textColor,
      );

      final outputPath = file.path.replaceFirst(
        RegExp(r'(\.[A-Za-z0-9]+)$'),
        '_wm.jpg',
      );
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(image, quality: 92), flush: true);
      return outputFile;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _prepareExternalImageWidget(widget.externalImageUrl);
    _handleCameraRecovery();
  }

  @override
  void didUpdateWidget(ImageUploadField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.externalImageUrl != oldWidget.externalImageUrl) {
      _prepareExternalImageWidget(widget.externalImageUrl);
    }
  }

  /// 🔥 SAFE RECOVERY (NO COMPRESSION)
  Future<File?> _recoverLostImage() async {
    if (_selectedImage != null) return null;

    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty) return null;

      final xFile = lost.file;
      if (xFile == null) return null;

      final file = File(xFile.path);
      if (!file.existsSync()) return null;

      if (!mounted) return null;

      final position = await _getCurrentPositionForWatermark();
      final watermarked = await _applyWatermark(file, position);
      final uploadFile = watermarked ?? file;
      setState(() {
        _selectedImage = uploadFile;
        _isLoading = false;
      });

      widget.onImageSelected(uploadFile);
      return file;
    } catch (e, s) {
      await CrashLogger().logCrash(e, s);
    }

    return null;
  }

  Future<void> _handleCameraRecovery() async {
    final wasCameraInProgress =
        LocalStorageService.getBool(_cameraInProgressKey) == true;

    final recovered = await _recoverLostImage();

    if (wasCameraInProgress) {
      await LocalStorageService.setBool(_cameraInProgressKey, false);

      if (recovered == null && mounted) {
        Toastbar.showErrorWithoutContext(
          'Low Resources. Please try again.',
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (_isPickingImage || widget.isDisabled) return;
    _isPickingImage = true;
    try {
      setState(() => _isLoading = true);
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;
      final file = File(picked.path);
      if (!file.existsSync()) {
        Toastbar.showErrorWithoutContext('Unable to pick image from gallery.');
        return;
      }
      setState(() {
        _selectedImage = file;
        _isLoading = false;
      });
      widget.onImageSelected(file);
    } catch (e, s) {
      await CrashLogger().logCrash(e, s);
      Toastbar.showErrorWithoutContext('Unable to open gallery');
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _isPickingImage = false;
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 🔥 CAMERA PICK (ULTIMATE SAFE FLOW)
  Future<void> _pickImage() async {
  if (_isPickingImage || widget.isDisabled) return;

  _isPickingImage = true;

  final isSelfie = _isSelfieField();

  File? pickedFile;

  try {
    setState(() => _isLoading = true);
    await LocalStorageService.setBool(_cameraInProgressKey, true);

    /// ✅ OPEN CUSTOM CAMERA
    if (isSelfie) {
      /// FRONT CAMERA
      final result = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => const SelfieCameraScreen(),
        ),
      );

      if (result != null) pickedFile = result;
    } else {
      /// REAR CAMERA
      final result = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => const CustomCameraScreen(),
        ),
      );

      if (result != null) pickedFile = result;
    }

    /// ❌ User cancelled
    if (pickedFile == null || !pickedFile.existsSync()) {
      Toastbar.showErrorWithoutContext(
          'Camera closed without saving image.');
      return;
    }

    final capturedFile = pickedFile;
    final position = await _getCurrentPositionForWatermark();
    final watermarked = await _applyWatermark(capturedFile, position);
    final fileForUpload = watermarked ?? capturedFile;

    /// ✅ STEP 1: SHOW WATERMARKED PREVIEW
    setState(() {
      _selectedImage = fileForUpload;
      _isLoading = false;
    });

    /// ✅ STEP 2: CALLBACK WITH WATERMARKED IMAGE
    widget.onImageSelected(fileForUpload);

    /// ✅ STEP 3: OPTIONAL COMPRESSION (STILL WATERMARKED)
    final size = await fileForUpload.length();
    const twoMb = 2 * 1024 * 1024;

    if (size > twoMb) {
      final originalPath = fileForUpload.path;

      Future.delayed(const Duration(milliseconds: 300), () {
        compute(_compressInBackground, originalPath)
            .then((compressedPath) {
          if (!mounted) return;

          if (compressedPath != null) {
            final compressedFile = File(compressedPath);

            /// 🔥 Update with compressed+watermarked file
            setState(() {
              _selectedImage = compressedFile;
            });
            widget.onImageSelected(compressedFile);
          }
        });
      });
    }

    await LocalStorageService.setBool(_cameraInProgressKey, false);
  } catch (e, s) {
    await CrashLogger().logCrash(e, s);

    Toastbar.showErrorWithoutContext(
      "Unable to open camera",
    );

    if (mounted) setState(() => _isLoading = false);
  } finally {
    _isPickingImage = false;

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }

    await LocalStorageService.setBool(_cameraInProgressKey, false);
  }
}

  /// UI Helpers

  Future<void> _prepareExternalImageWidget(String? url) async {
    if (url == null || url.isEmpty) {
      _lastExternalUrl = null;
      if (!mounted) return;
      setState(() => _externalImageWidget = null);
      return;
    }
    if (url == _lastExternalUrl) return;

    _lastExternalUrl = url;

    await Future<void>.delayed(Duration.zero);

    if (!mounted) return;

    setState(() {
      _externalImageWidget = _buildImageFromUrl(url);
    });
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_outlined,
              size: 20, color: AppColors.color555555),
          SizedBox(width: 6),
          Text(
            "Take Photo",
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.color555555,
              fontFamily: fontFamilyMontserrat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageFromUrl(String url) {
    try {
      if (url.length > maxBase64Length) {
        return _buildPlaceholder();
      }

      if (url.startsWith('data:image')) {
        final comma = url.indexOf(',');
        if (comma == -1 || comma >= url.length - 1) {
          return _buildPlaceholder();
        }
        final bytes = base64Decode(url.substring(comma + 1));

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          cacheWidth: 600,
          filterQuality: FilterQuality.low,
        );
      }

      // Local filesystem path (e.g. Asset Upload / PM saved file paths)
      final file = File(url);
      if (file.existsSync()) {
        return SafeImageFile(
          file: file,
          fit: BoxFit.cover,
          alignment: Alignment.bottomCenter,
          width: double.infinity,
          cacheWidth: 600,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      }

      final bytes = base64Decode(url);

      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        cacheWidth: 600,
      );
    } catch (_) {
      return _buildPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (_isLoading) {
      child = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text(
              'Adding watermark...',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF555555),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else if (_selectedImage != null) {
      child = SafeImageFile(
        file: _selectedImage!,
        fit: BoxFit.cover,
        alignment: Alignment.bottomCenter,
        width: double.infinity,
        cacheWidth: 600,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(),
      );
    } else if (widget.externalImageLoading) {
      child = const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else if (_externalImageWidget != null) {
      child = _externalImageWidget!;
    } else {
      child = _buildPlaceholder();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontFamily: fontFamilyMontserrat,
                fontSize: 16,
                color: AppColors.white,
              ),
              children: [
                TextSpan(text: widget.label!),
                if (widget.isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: (widget.isDisabled ||
                  _isLoading ||
                  _isPickingImage ||
                  widget.externalImageLoading)
              ? null
              : (widget.pickFromGallery ? _pickImageFromGallery : _pickImage),
          child: Container(
            width: double.infinity,
            height: _effectiveUploadBoxHeight,
            decoration: BoxDecoration(
              color: widget.isDisabled
                  ? Colors.grey.shade200
                  : Colors.white,
              borderRadius: BorderRadius.circular(widget.uploadBorderRadius),
              border: Border.all(color: Colors.grey),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}