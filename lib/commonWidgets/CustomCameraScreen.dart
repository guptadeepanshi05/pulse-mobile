import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:app/utils/safe_camera_disposal.dart';

class CustomCameraScreen extends StatefulWidget {
  final bool useFrontCamera;

  const CustomCameraScreen({super.key, this.useFrontCamera = false});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
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
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _tearDownCamera();
    } else if (state == AppLifecycleState.resumed && mounted && !_isClosing) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_isClosing) return;

    try {
      _cameras = await availableCameras();

      final camera = widget.useFrontCamera
          ? _cameras!.firstWhere(
              (cam) => cam.lensDirection == CameraLensDirection.front,
            )
          : _cameras!.firstWhere(
              (cam) => cam.lensDirection == CameraLensDirection.back,
            );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted || _isClosing) {
        await safeDisposeCameraController(controller);
        return;
      }

      _controller = controller;
      setState(() => _isInitialized = true);
    } catch (_) {
      if (mounted) {
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

  Future<void> _captureImage() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _isClosing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final XFile file = await controller.takePicture();

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(file.path).copy(path);

      await _close(savedFile);
    } catch (_) {
      if (mounted) {
        setState(() => _isCapturing = false);
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
        body: _isInitialized && _controller != null
            ? Stack(
                children: [
                  Positioned.fill(
                    child: CameraPreview(_controller!),
                  ),
                  Positioned(
                    top: 40,
                    left: 20,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _isClosing ? null : () => _close(),
                    ),
                  ),
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _isCapturing ? null : _captureImage,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(width: 4, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
      ),
    );
  }
}
