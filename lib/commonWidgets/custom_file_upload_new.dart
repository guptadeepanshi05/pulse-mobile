import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app/commonWidgets/custom_video_recorder_screen.dart';
import '../constants/app_colors.dart';
import '../constants/constants_strings.dart';
import '../utils/toastbar.dart';

class CustomFileUploadNew extends StatelessWidget {
  static const List<String> _defaultAllowedExtensions = ['pdf', 'doc', 'docx'];
  final String? label;
  final String? placeholder;
  final File? selectedFile;
  final Function(File?) onFileSelected;
  final bool isRequired;
  final String? acceptedFileTypes;
  final String? maxSizeText;
  final List<File> uploadedFiles;
  final Function(File) onFileDeleted;
  final bool isDisabled; // Add isDisabled parameter
  final String? serverAttachmentName; // Server attachment file name
  final dynamic serverAttachmentId; // Server attachment ID
  final Function(dynamic)? onServerAttachmentClicked; // Callback when server attachment is clicked
  final Function()? onServerAttachmentDeleted; // Callback when server attachment is deleted

  /// When set, tapping a selected / uploaded file name invokes this (e.g. play video).
  final Function(File file)? onFileNameTapped;

  /// When set (e.g. `['pdf']`), opens the document picker with [FileType.custom]
  /// instead of [FileType.any] (which can default to gallery/images on some devices).
  final List<String>? pickAllowedExtensions;

  /// When true, opens the system video picker ([FileType.video]). Takes precedence
  /// over [pickAllowedExtensions].
  final bool useVideoPicker;

  /// When true, records video from device camera.
  final bool useVideoRecorder;

  /// When true, opens the system image gallery picker.
  final bool useImagePicker;

  /// When true, opens the device camera for a still photo.
  final bool useImageCamera;

  /// When true, each pick is appended (caller manages [uploadedFiles] list).
  /// When false, a new pick replaces the previous selection.
  final bool allowMultipleFiles;

  const CustomFileUploadNew({
    super.key,
    this.label,
    this.placeholder,
    this.selectedFile,
    required this.onFileSelected,
    this.isRequired = false,
    this.acceptedFileTypes,
    this.maxSizeText,
    this.uploadedFiles = const [],
    required this.onFileDeleted,
    this.isDisabled = false, // Default value is false
    this.serverAttachmentName,
    this.serverAttachmentId,
    this.onServerAttachmentClicked,
    this.onServerAttachmentDeleted,
    this.onFileNameTapped,
    this.pickAllowedExtensions,
    this.useVideoPicker = false,
    this.useVideoRecorder = false,
    this.useImagePicker = false,
    this.useImageCamera = false,
    this.allowMultipleFiles = false,
  });

  Future<void> _pickFile(BuildContext context) async {
    if (useVideoRecorder) {
      // Native camera video recorder (not still photo). Prefer system UI so
      // users clearly get video capture rather than a photo shutter screen.
      try {
        final picker = ImagePicker();
        final picked = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 60),
        );
        if (picked == null) return;
        final file = File(picked.path);
        await _validateAndSelectFile(context, file);
      } catch (_) {
        // Fallback to in-app recorder if the platform picker fails.
        if (!context.mounted) return;
        final recordedFile = await Navigator.push<File>(
          context,
          MaterialPageRoute(
            builder: (_) => const CustomVideoRecorderScreen(),
          ),
        );
        if (recordedFile == null) return;
        await _validateAndSelectFile(context, File(recordedFile.path));
      }
      return;
    }

    if (useVideoPicker) {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      final file = File(picked.path);
      await _validateAndSelectFile(context, file);
      return;
    }

    if (useImageCamera || useImagePicker) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: useImageCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      final file = File(picked.path);
      await _validateAndSelectFile(context, file);
      return;
    }

    final FilePickerResult? result;
    final exts =
        (pickAllowedExtensions != null && pickAllowedExtensions!.isNotEmpty)
            ? pickAllowedExtensions!.map((e) => e.toLowerCase()).toList()
            : _defaultAllowedExtensions;
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: exts,
      allowMultiple: allowMultipleFiles,
    );

    if (result == null || result.files.isEmpty) return;
    if (allowMultipleFiles) {
      for (final platformFile in result.files) {
        final path = platformFile.path;
        if (path == null) continue;
        await _validateAndSelectFile(context, File(path));
      }
      return;
    }
    final path = result.files.single.path;
    if (path != null) {
      await _validateAndSelectFile(context, File(path));
    }
  }

  Future<void> _validateAndSelectFile(BuildContext context, File file) async {
    final isMediaFlow =
        useVideoPicker || useVideoRecorder || useImagePicker || useImageCamera;
    // Video / image pickers already constrain selection — don't apply PDF allowlist.
    if (!isMediaFlow) {
      // Honor [pickAllowedExtensions] when provided so callers can opt-in to
      // additional file types (e.g. images) without being blocked by the
      // default PDF/DOC/DOCX allowlist.
      final allowedExts =
          (pickAllowedExtensions != null && pickAllowedExtensions!.isNotEmpty)
              ? pickAllowedExtensions!.map((e) => e.toLowerCase()).toList()
              : _defaultAllowedExtensions;

      final extension = file.path.split('.').last.toLowerCase();
      if (!allowedExts.contains(extension)) {
        if (!context.mounted) return;
        final readable = allowedExts.map((e) => e.toUpperCase()).join(', ');
        Toastbar.showErrorToastbar(
          'Only $readable files are allowed.',
          context,
        );
        return;
      }
    } else if (useVideoPicker || useVideoRecorder) {
      // Soft-check common video extensions from gallery / recorder.
      const videoExts = <String>[
        'mp4',
        'mov',
        'm4v',
        'avi',
        'mkv',
        '3gp',
        'webm',
      ];
      final extension = file.path.split('.').last.toLowerCase();
      if (extension.isNotEmpty && !videoExts.contains(extension)) {
        if (!context.mounted) return;
        Toastbar.showErrorToastbar(
          'Only video files are allowed.',
          context,
        );
        return;
      }
    } else if (useImagePicker || useImageCamera) {
      const imageExts = <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'heic',
      ];
      final extension = file.path.split('.').last.toLowerCase();
      if (extension.isNotEmpty && !imageExts.contains(extension)) {
        if (!context.mounted) return;
        Toastbar.showErrorToastbar(
          'Only image files are allowed.',
          context,
        );
        return;
      }
    }

    // Check file size (2 MB = 2 * 1024 * 1024 bytes)
    const int maxSizeInBytes = 2 * 1024 * 1024; // 2 MB
    final int fileSizeInBytes = await file.length();
    if (!context.mounted) return;

    if (fileSizeInBytes > maxSizeInBytes) {
      Toastbar.showErrorToastbar(
        'File size exceeds 2 MB limit. Please select a smaller file.',
        context,
      );
      return;
    } else {
      onFileSelected(file);
    }
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with required asterisk
        if (label != null) ...[
          Row(
            children: [
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.whiteColor,
                  fontFamily: fontFamilyMontserrat,
                ),
              ),
              if (isRequired)
                const Text(
                  " *",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                    fontFamily: fontFamilyMontserrat,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        
        // Upload box
        GestureDetector(
          onTap: isDisabled ? null : () => _pickFile(context),
          child: Container(
            width: double.infinity,
            height: 100,
            decoration: BoxDecoration(
              color: isDisabled ? Colors.grey.shade200 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
                style: BorderStyle.solid,
              ),
            ),
            child: selectedFile != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isVideoFile(selectedFile!.path)
                              ? Icons.play_circle_outline
                              : Icons.attach_file,
                          size: 18,
                          color: AppColors.color555555,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onFileNameTapped == null
                                ? null
                                : () => onFileNameTapped!(selectedFile!),
                            child: Text(
                              _getFileName(selectedFile!.path),
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: onFileNameTapped != null
                                    ? AppColors.textBlueAccent
                                    : AppColors.color555555,
                                fontFamily: fontFamilyMontserrat,
                                fontSize: 12,
                                decoration: onFileNameTapped != null
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (!isDisabled)
                          GestureDetector(
                            onTap: () => onFileSelected(null),
                            child: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red.shade400,
                            ),
                          ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.upload_file,
                          size: 20,
                          color: AppColors.color555555,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          placeholder ?? "Upload File",
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.color555555,
                            fontFamily: fontFamilyMontserrat,
                            fontSize: 14,
                          ),
                        ),
                        if (maxSizeText != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            maxSizeText!,
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: AppColors.color555555.withValues(alpha: 0.7),
                              fontFamily: fontFamilyMontserrat,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (acceptedFileTypes != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            acceptedFileTypes!,
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: AppColors.color555555.withValues(alpha: 0.7),
                              fontFamily: fontFamilyMontserrat,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
        
        if (serverAttachmentId != null && 
            serverAttachmentId != 0 && 
            serverAttachmentId.toString().trim().isNotEmpty &&
            serverAttachmentName != null &&
            serverAttachmentName!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildServerAttachmentItem(),
        ],
        
        // Uploaded Files List
        if (uploadedFiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...uploadedFiles.map((file) => _buildUploadedFileItem(context, file)),
        ],
        
      ],
    );
  }

  Widget _buildServerAttachmentItem() {
    // Get the display name - use serverAttachmentName if available, otherwise fallback
    final displayName = (serverAttachmentName != null && serverAttachmentName!.isNotEmpty)
        ? serverAttachmentName!
        : 'attachment';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(displayName),
            size: 20,
            color: AppColors.color555555,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              // Viewing server files is allowed in read-only mode (e.g. maker role);
              // [isDisabled] only blocks picking / deleting, not opening an attachment.
              onTap: onServerAttachmentClicked == null
                  ? null
                  : () => onServerAttachmentClicked!(serverAttachmentId),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: onServerAttachmentClicked == null
                      ? AppColors.color555555
                      : AppColors.textBlueAccent,
                  fontFamily: fontFamilyMontserrat,
                  decoration: onServerAttachmentClicked == null
                      ? TextDecoration.none
                      : TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isDisabled && onServerAttachmentDeleted != null)
            GestureDetector(
              onTap: onServerAttachmentDeleted,
              child: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.shade400,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadedFileItem(BuildContext context, File file) {
    final isImage = _isImageFile(file.path);
    final isVideo = _isVideoFile(file.path);
    final canPreview = isImage || (isVideo && onFileNameTapped != null);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isVideo ? Icons.play_circle_outline : _getFileIcon(file.path),
            size: 20,
            color: AppColors.color555555,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: !canPreview
                  ? null
                  : () {
                      if (isImage) {
                        _showImagePreview(context, file);
                      } else if (isVideo) {
                        onFileNameTapped!(file);
                      }
                    },
              child: Text(
                _getFileName(file.path),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: canPreview
                      ? AppColors.textBlueAccent
                      : AppColors.color555555,
                  fontFamily: fontFamilyMontserrat,
                  decoration: canPreview
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isDisabled)
            GestureDetector(
              onTap: () => onFileDeleted(file),
              child: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.shade400,
              ),
            ),
        ],
      ),
    );
  }

  bool _isImageFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
        .contains(extension);
  }

  bool _isVideoFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return const ['mp4', 'mov', 'm4v', 'avi', 'mkv', '3gp', 'webm']
        .contains(extension);
  }

  void _showImagePreview(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            'Unable to load image',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 32,
                right: 16,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getFileIcon(String path) {
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
}
