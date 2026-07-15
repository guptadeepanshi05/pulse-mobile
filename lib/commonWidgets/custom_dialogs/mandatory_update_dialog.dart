import 'package:app/constants/app_colors.dart';
import 'package:app/services/app_update_service.dart';
import 'package:flutter/material.dart';

/// Non-dismissible dialog that forces the user to update before using the app.
///
/// - Cannot be closed via barrier tap
/// - Android back / system pop is blocked via [PopScope]
/// - Single action: **Update** → opens the store listing
class MandatoryUpdateDialog extends StatelessWidget {
  /// Store listing URL from [AppUpdateCheckResult.storeUrl].
  final String storeUrl;

  /// Optional override for tests or custom open-store behavior.
  final Future<void> Function(String storeUrl)? onUpdatePressed;

  const MandatoryUpdateDialog({
    super.key,
    required this.storeUrl,
    this.onUpdatePressed,
  });

  /// Shows the dialog and never completes under normal use (non-dismissible).
  ///
  /// Call this from Splash (or another root gate) when an update is required.
  static Future<void> show(
    BuildContext context, {
    required String storeUrl,
    Future<void> Function(String storeUrl)? onUpdatePressed,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      // Keep the splash visible underneath; do not allow route pops.
      useRootNavigator: true,
      builder: (dialogContext) {
        return PopScope(
          // Blocks Android back button / predictive back / iOS swipe-to-dismiss.
          canPop: false,
          child: MandatoryUpdateDialog(
            storeUrl: storeUrl,
            onUpdatePressed: onUpdatePressed,
          ),
        );
      },
    );
  }

  Future<void> _handleUpdate() async {
    if (onUpdatePressed != null) {
      await onUpdatePressed!(storeUrl);
      return;
    }
    await AppUpdateService().openStore(storeUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      backgroundColor: Colors.white,
      elevation: 0,
      // Absorb taps so nothing behind the dialog is interactive.
      child: PopScope(
        canPop: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                size: 48,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(height: 16),
              const Text(
                'Update Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.blackColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'A newer version of the app is available. Please update to continue using the application.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.greyBlackColor,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonPrimary,
                    foregroundColor: AppColors.whiteColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _handleUpdate,
                  child: const Text(
                    'Update',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
