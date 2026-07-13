import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:app/utils/safe_camera_disposal.dart';

class CustomVideoRecorderScreen extends StatefulWidget {
  final bool useFrontCamera;

  const CustomVideoRecorderScreen({super.key, this.useFrontCamera = false});

  @override
  State<CustomVideoRecorderScreen> createState() =>
      _CustomVideoRecorderScreenState();
}

class _CustomVideoRecorderScreenState extends State<CustomVideoRecorderScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isBusy = false;
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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        await _close();
        return;
      }

      CameraDescription selected = cameras.first;
      for (final c in cameras) {
        if (widget.useFrontCamera &&
            c.lensDirection == CameraLensDirection.front) {
          selected = c;
          break;
        }
        if (!widget.useFrontCamera &&
            c.lensDirection == CameraLensDirection.back) {
          selected = c;
          break;
        }
      }

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await controller.initialize();

      if (!mounted || _isClosing) {
        await safeDisposeCameraController(controller);
        return;
      }

      _controller = controller;
      setState(() => _isInitialized = true);
    } catch (_) {
      if (!mounted) return;
      await _close();
    }
  }

  Future<void> _tearDownCamera() async {
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isRecording = false;
      });
    }
    await safeDisposeCameraController(controller);
  }

  Future<void> _close([File? result]) async {
    if (_isClosing || !mounted) return;
    _isClosing = true;

    setState(() {
      _isInitialized = false;
      _isBusy = true;
    });

    await _tearDownCamera();

    if (mounted) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isBusy ||
        _isClosing) {
      return;
    }

    _isBusy = true;
    try {
      if (!_isRecording) {
        await controller.startVideoRecording();
        if (!mounted) return;
        setState(() => _isRecording = true);
        return;
      }

      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _isRecording = false);
      await _close(File(file.path));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRecording = false);
    } finally {
      _isBusy = false;
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
                  Positioned.fill(child: CameraPreview(_controller!)),
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
                        onTap: _isBusy ? null : _toggleRecording,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.red : Colors.white,
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
