import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CustomCameraScreen extends StatefulWidget {
  final bool useFrontCamera;

  const CustomCameraScreen({super.key, this.useFrontCamera = false});

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();

      final camera = widget.useFrontCamera
          ? _cameras!.firstWhere(
              (cam) => cam.lensDirection == CameraLensDirection.front,
            )
          : _cameras!.firstWhere(
              (cam) => cam.lensDirection == CameraLensDirection.back,
            );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium, // 🔥 IMPORTANT (prevents crash)
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      Navigator.pop(context);
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) return;

    _isCapturing = true;

    try {
      final XFile file = await _controller!.takePicture();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final savedFile = await File(file.path).copy(path);

      if (!mounted) return;

      Navigator.pop(context, savedFile);
    } catch (e) {
      _isCapturing = false;
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
      body: _isInitialized
          ? Stack(
              children: [
                Positioned.fill(
                  child: CameraPreview(_controller!),
                ),

                /// 🔙 Back button
                Positioned(
                  top: 40,
                  left: 20,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                /// 📸 Capture button
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _captureImage,
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
    );
  }
}