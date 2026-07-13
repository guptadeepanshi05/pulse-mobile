import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'package:app/utils/CrashLogger.dart';
import 'package:app/utils/safe_camera_disposal.dart';

class SelfieCameraScreen extends StatefulWidget {
  const SelfieCameraScreen({super.key});

  @override
  State<SelfieCameraScreen> createState() => _SelfieCameraScreenState();
}

class _SelfieCameraScreenState extends State<SelfieCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _tearDownCamera();
    } else if (state == AppLifecycleState.resumed && mounted && !_isClosing) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isClosing) return;

    try {
      _cameras = await availableCameras();

      CameraDescription? frontCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      frontCamera ??= _cameras!.first;

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted || _isClosing) {
        await safeDisposeCameraController(controller);
        return;
      }

      _controller = controller;
      setState(() {
        _isInitialized = true;
      });
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
        await _close();
      }
    }
  }

  Future<void> _tearDownCamera() async {
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() => _isInitialized = false);
    }
    await safeDisposeCameraController(controller);
  }

  Future<void> _close([File? result]) async {
    if (_isClosing || !mounted) return;
    _isClosing = true;

    setState(() {
      _isInitialized = false;
      _isCapturing = true;
    });

    await _tearDownCamera();

    if (mounted) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (!_isInitialized ||
        controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _isClosing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile image = await controller.takePicture();
      await _close(File(image.path));
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
          'controllerInitialized': controller.value.isInitialized,
        },
      );
      if (mounted) {
        setState(() => _isCapturing = false);
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
    WidgetsBinding.instance.removeObserver(this);
    _isClosing = true;
    final controller = _controller;
    _controller = null;
    safeDisposeCameraController(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _isClosing ? null : () => _close(),
          ),
          title: const Text(
            'Take Selfie',
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: !_isInitialized ||
                _controller == null ||
                !_controller!.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: CameraPreview(_controller!),
                  ),
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
                              color: _isCapturing
                                  ? Colors.grey.shade400
                                  : AppColors.primaryGreen,
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
      ),
    );
  }
}
