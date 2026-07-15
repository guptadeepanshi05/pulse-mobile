import 'package:app/utils/logger.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Outcome of a store version check.
///
/// [isUpdateRequired] is only `true` when a newer store version was confirmed.
/// Network / lookup failures set [checkFailed] so the app can continue startup.
class AppUpdateCheckResult {
  /// Whether the installed build is behind the store and must update.
  final bool isUpdateRequired;

  /// Installed app version (e.g. `1.0.61`), if known.
  final String? localVersion;

  /// Latest version published on the store, if known.
  final String? storeVersion;

  /// Deep link / store listing URL used by the Update button.
  final String? storeUrl;

  /// `true` when the store could not be reached (offline, timeout, etc.).
  final bool checkFailed;

  const AppUpdateCheckResult({
    required this.isUpdateRequired,
    this.localVersion,
    this.storeVersion,
    this.storeUrl,
    this.checkFailed = false,
  });

  /// App is current — proceed with normal startup.
  factory AppUpdateCheckResult.upToDate({
    String? localVersion,
    String? storeVersion,
  }) {
    return AppUpdateCheckResult(
      isUpdateRequired: false,
      localVersion: localVersion,
      storeVersion: storeVersion,
    );
  }

  /// Store version is newer — block the app behind the mandatory dialog.
  factory AppUpdateCheckResult.updateRequired({
    required String localVersion,
    required String storeVersion,
    required String storeUrl,
  }) {
    return AppUpdateCheckResult(
      isUpdateRequired: true,
      localVersion: localVersion,
      storeVersion: storeVersion,
      storeUrl: storeUrl,
    );
  }

  /// Version lookup failed — do not block the user.
  factory AppUpdateCheckResult.failed() {
    return const AppUpdateCheckResult(
      isUpdateRequired: false,
      checkFailed: true,
    );
  }
}

/// Checks Play Store / App Store for a newer version and opens the listing.
///
/// Uses [new_version_plus] only (no backend / Remote Config). UI stays out of
/// this class — callers decide how to present [AppUpdateCheckResult].
class AppUpdateService {
  AppUpdateService({NewVersionPlus? newVersionPlus})
      : _newVersionPlus = newVersionPlus ??
            NewVersionPlus(
              // Explicit IDs match android applicationId / iOS bundle id.
              androidId: 'com.pulse.nexgeninfra',
              iOSId: 'com.pulse.nexgeninfra',
              // App is published on the India App Store only. Without this,
              // itunes.apple.com/lookup defaults to US and returns 0 results,
              // so getVersionStatus() is null and the update dialog never shows.
              iOSAppStoreCountry: 'in',
            );

  final NewVersionPlus _newVersionPlus;

  /// Compares the installed version with the latest store version.
  ///
  /// Returns [AppUpdateCheckResult.failed] on network or parsing errors so
  /// startup is never blocked when the store is unreachable.
  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final VersionStatus? status = await _newVersionPlus.getVersionStatus();

      // null usually means the store page could not be fetched / parsed.
      if (status == null) {
        Logger.infoLog(
          'AppUpdateService: version status unavailable; allowing startup.',
        );
        return AppUpdateCheckResult.failed();
      }

      final String localVersion = status.localVersion;
      final String storeVersion = status.storeVersion;
      final String storeUrl = status.appStoreLink;

      Logger.infoLog(
        'AppUpdateService: local=$localVersion store=$storeVersion '
        'canUpdate=${status.canUpdate}',
      );

      // Prefer the package's comparison, with an empty-link guard.
      if (status.canUpdate && storeUrl.trim().isNotEmpty) {
        return AppUpdateCheckResult.updateRequired(
          localVersion: localVersion,
          storeVersion: storeVersion,
          storeUrl: storeUrl,
        );
      }

      return AppUpdateCheckResult.upToDate(
        localVersion: localVersion,
        storeVersion: storeVersion,
      );
    } catch (e, stackTrace) {
      // Graceful degradation: offline / temporary store errors must not lock users out.
      Logger.errorLog(
        'AppUpdateService: version check failed; allowing startup.',
        e,
        stackTrace,
      );
      return AppUpdateCheckResult.failed();
    }
  }

  /// Opens the Play Store (Android) or App Store (iOS) listing.
  ///
  /// [storeUrl] comes from [VersionStatus.appStoreLink] via [checkForUpdate].
  Future<bool> openStore(String storeUrl) async {
    try {
      // Prefer the package helper — it picks a sensible LaunchMode per platform.
      await _newVersionPlus.launchAppStore(storeUrl);
      return true;
    } catch (e, stackTrace) {
      Logger.errorLog(
        'AppUpdateService: launchAppStore failed; trying url_launcher.',
        e,
        stackTrace,
      );

      // Fallback if the package launcher fails on a given device / OS version.
      final Uri? uri = Uri.tryParse(storeUrl);
      if (uri == null) return false;

      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    }
  }
}
