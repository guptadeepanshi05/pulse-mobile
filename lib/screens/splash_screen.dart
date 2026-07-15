import 'package:app/bloc/login_bloc/auth_cubit.dart';
import 'package:app/commonWidgets/custom_dialogs/mandatory_update_dialog.dart';
import 'package:app/constants/constants_methods.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/pulse_dashboard.dart';
import 'package:app/screens/welcome_screen.dart';
import 'package:app/services/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hasNavigated = false;

  /// Becomes true only after the store check finishes and no mandatory update is required.
  /// Until then, [BlocListener] must not navigate away from splash.
  bool _mayContinueStartup = false;

  /// Shared service instance for the splash gate.
  final AppUpdateService _appUpdateService = AppUpdateService();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    // Version check runs before auth navigation so outdated builds never enter the app.
    _bootstrap();
  }

  /// Runs the store version check (in parallel with the splash delay), then
  /// either blocks on the mandatory update dialog or continues normal startup.
  Future<void> _bootstrap() async {
    // Parallelize so a slow store lookup does not extend splash unnecessarily.
    final List<Object?> results = await Future.wait<Object?>([
      _appUpdateService.checkForUpdate(),
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);

    if (!mounted || _hasNavigated) return;

    final AppUpdateCheckResult updateResult =
        results.first as AppUpdateCheckResult;

    // Confirmed newer store version → non-dismissible dialog; do not navigate.
    if (updateResult.isUpdateRequired &&
        updateResult.storeUrl != null &&
        updateResult.storeUrl!.isNotEmpty) {
      await MandatoryUpdateDialog.show(
        context,
        storeUrl: updateResult.storeUrl!,
      );
      // Dialog is non-dismissible; code below only runs if it somehow closes.
      return;
    }

    // Up to date, or check failed (offline / temporary error) → allow startup.
    _mayContinueStartup = true;
    _navigateBasedOnAuth();
  }

  /// Existing auth routing: dashboard, login (remember me), or welcome.
  void _navigateBasedOnAuth() {
    if (!mounted || _hasNavigated || !_mayContinueStartup) return;

    final authCubit = context.read<AuthCubit>();

    if (authCubit.isLoggedIn) {
      _hasNavigated = true;
      pushAndRemoveUntilPage(context, const PulseDashboard());
    } else if (authCubit.getRememberMe) {
      pushAndRemoveUntilPage(context, const LoginScreen());
      _hasNavigated = true;
    } else {
      _hasNavigated = true;
      pushAndRemoveUntilPage(context, const WelcomeScreen());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          // Block auth-driven navigation until the mandatory update gate passes.
          if (_hasNavigated || !_mayContinueStartup) return;

          if (state is AuthSuccess) {
            _hasNavigated = true;
            pushAndRemoveUntilPage(context, const PulseDashboard());
          } else if (state is AuthFailure) {
            _hasNavigated = true;
            pushAndRemoveUntilPage(context, const WelcomeScreen());
          } else if (state is AuthInitial) {
            // Initial state after logout — _bootstrap / auth check handles navigation.
          }
        },
        child: Center(
          child: Lottie.asset(
            'assets/lottie/both.json',
            controller: _controller,
            onLoaded: (composition) {
              _controller
                ..duration = composition.duration
                ..forward();
            },
            width: 300,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
