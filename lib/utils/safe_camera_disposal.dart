import 'package:camera/camera.dart';

/// Disposes a [CameraController] and swallows Android Camera2 races where
/// native callbacks arrive after the session has already been closed.
Future<void> safeDisposeCameraController(CameraController? controller) async {
  if (controller == null) return;

  try {
    if (controller.value.isInitialized) {
      await controller.dispose();
    }
  } catch (_) {
    // No-op: Camera2 can throw NPEs if onResultReceived races with dispose.
  }
}
