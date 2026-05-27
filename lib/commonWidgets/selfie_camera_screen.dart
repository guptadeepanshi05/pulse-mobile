import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:app/utils/CrashLogger.dart';

class SelfieCameraScreen extends StatefulWidget {
  const SelfieCameraScreen({super.key});

  @override
  State<SelfieCameraScreen> createState() => _SelfieCameraScreenState();
}

class _SelfieCameraScreenState extends State<SelfieCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      
      // Find front camera
      CameraDescription? frontCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      
      if (frontCamera == null) {
        // Fallback to first available camera if no front camera found
        frontCamera = _cameras!.first;
      }
      
      _controller = CameraController(
        frontCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );
      
      await _controller!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      await CrashLogger().logCrash(
        e,
        StackTrace.current,
        reason: 'SelfieCameraScreen._initializeCamera',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _takePicture() async {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    try {
      setState(() {
        _isCapturing = true;
      });

      final XFile image = await _controller!.takePicture();
      
      if (mounted) {
        Navigator.pop(context, File(image.path));
      }
    } catch (e, s) {
      await CrashLogger().logCrash(
        e,
        s,
        reason: 'SelfieCameraScreen._takePicture',
        context: {
          'feature': 'camera',
          'camera_flow': 'selfie',
          'action': 'take_picture',
          'isInitialized': _isInitialized,
          'isCapturing': _isCapturing,
          'controllerInitialized': _controller?.value.isInitialized ?? false,
        },
      );
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Capture and null out first so any rebuild during teardown can't
    // accidentally trigger a second dispose on the same controller.
    final controller = _controller;
    _controller = null;
    // CameraController.dispose() is async and, under camera_android_camerax,
    // can throw a PlatformException (NullPointerException on Surface.release())
    // when the Flutter engine has already released the surface texture.
    // Swallow it — there's nothing actionable here and the resources are gone.
    controller?.dispose().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Take Selfie',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),
          // Capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _takePicture,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCapturing ? Colors.grey : Colors.white,
                    border: Border.all(
                      color: _isCapturing ? Colors.grey.shade400 : AppColors.primaryGreen,
                      width: 4,
                    ),
                  ),
                  child: _isCapturing
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: AppColors.primaryGreen,
                          size: 35,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

