import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CustomVideoRecorderScreen extends StatefulWidget {
  final bool useFrontCamera;

  const CustomVideoRecorderScreen({super.key, this.useFrontCamera = false});

  @override
  State<CustomVideoRecorderScreen> createState() =>
      _CustomVideoRecorderScreenState();
}

class _CustomVideoRecorderScreenState extends State<CustomVideoRecorderScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context);
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

      _controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isBusy) {
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
      Navigator.pop(context, File(file.path));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRecording = false);
    } finally {
      _isBusy = false;
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
    return Scaffold(
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
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.red : Colors.white,
                          border: Border.all(color: Colors.grey, width: 4),
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.videocam,
                          color: _isRecording ? Colors.white : Colors.red,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
