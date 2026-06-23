import 'package:package_info_plus/package_info_plus.dart';

/// Caches app version from [PackageInfo] at startup so login can always send it.
class AppVersionHelper {
  AppVersionHelper._();

  static String _versionName = '';
  static String _buildNumber = '';
  static bool _initialized = false;

  static String get versionName => _versionName;
  static String get buildNumber => _buildNumber;

  static Future<void> init() async {
    if (_initialized) return;
    await _load();
    _initialized = true;
  }

  /// Returns cached version name, reloading once if still empty.
  static Future<String> resolveVersionName() async {
    if (_versionName.isNotEmpty) return _versionName;
    await _load();
    return _versionName;
  }

  static bool requiresAppVersionHeader(String path) {
    return path.contains('authenticate/login') ||
        path.contains('api/v1/mobile/upload/MobileLogs');
  }

  static Future<void> attachAppVersionHeader(
    Map<String, dynamic> headers,
  ) async {
    final appVersion = await resolveVersionName();
    if (appVersion.isNotEmpty) {
      headers['App-Version'] = appVersion;
    }
  }

  static Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _versionName = info.version.trim();
      _buildNumber = info.buildNumber.trim();
    } catch (_) {
      // Leave empty; caller/interceptor may skip the header.
    }
  }
}
