import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:app/constants/constants_methods.dart';
import 'package:app/services/push_notification_api.dart';
import 'package:app/services/location_permission_service.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app_config.dart';
import 'app_root.dart';
import 'bloc/global_bloc_observer.dart';
import 'bloc/global_loading_cubit.dart';
import 'firebase_options.dart';
import 'services/local_storage_db.dart';
import 'database/asset_audit_database.dart';
import 'services/app_initialization_service.dart';
import 'utils.dart';
import 'utils/CrashLogger.dart';
import 'utils/app_version_helper.dart';
import 'utils/file_logger.dart';
import 'services/log_push_service.dart';
import 'services/log_push_config.dart';

// Global config variable
AppConfig? globalConfig;

void main() {
  // ✅ Same zone for binding init + runApp (must not call ensureInitialized outside this zone)
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Force portrait orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // System UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    // Load environment, local storage, DB, location permissions
    await init();

    // Initialize Firebase
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      if (Firebase.apps.isNotEmpty) {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      }
    } catch (e) {
      // continue without firebase
    }

   

  

    // ✅ SINGLE unified Flutter error handler
    FlutterError.onError = (FlutterErrorDetails details) async {
      // 👉 always save locally
      await CrashLogger().logCrash(
        details.exception,
        details.stack,
        reason: 'FlutterError.onError',
        fatal: true,
      );

      // 👉 send to Crashlytics if available
      try {
        if (Firebase.apps.isNotEmpty) {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        }
      } catch (_) {}
    };

    // Capture uncaught async/platform errors.
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashLogger().logCrash(
        error,
        stack,
        reason: 'PlatformDispatcher.onError',
        fatal: true,
      );
      return true;
    };

    // Initialize push notifications
    try {
      if (Firebase.apps.isNotEmpty) {
        await PushNotificationApi().initNotifications();
      }
    } catch (_) {}

    // Initialize app configuration
    final _baseUrl = dotenv.env['BASE_URL_DEV'];
    final globalLoadingCubit = GlobalLoadingCubit();
    globalConfig = AppConfig(
      baseUrl: _baseUrl!,
      loadingCubit: globalLoadingCubit,
    );

    // Initialize file logger
    await FileLogger.initialize();
    await FileLogger.info('App starting up');

    // Initialize all app services
    await FileLogger.info('Initializing all services');
    final success =
        await AppInitializationService.initializeApp(
            globalConfig!.apiService);

    if (!success) {
      await FileLogger.error('Failed to initialize app services');
      throw Exception('Failed to initialize app services');
    }

    await FileLogger.info('All services initialized successfully');

    // Start log push service
    if (LogPushConfig.autoStartOnAppLaunch) {
      await LogPushService.startLogPushing(globalConfig!.apiService);
      await FileLogger.info('Log push service started');
    }

    // HTTP overrides
    HttpOverrides.global = MyHttpOverrides();

    // Bloc observer
    Bloc.observer = GlobalBlocObserver();

    // Check token status
    _checkTokenStatus();

    // ✅ finally run app
    runApp(
      AppRoot(
        config: globalConfig!,
      ),
    );

  }, (error, stack) async {
    // ✅ catches async/native errors
    await CrashLogger().logCrash(
      error,
      stack,
      reason: 'runZonedGuarded',
      fatal: true,
    );

    try {
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          fatal: true,
        );
      }
    } catch (_) {}
  });
}

Future<void> init() async {
  // Load .env file
  await dotenv.load(fileName: ".env");

  // Initialize local storage
  await LocalStorageDB.init();

  // Initialize SQLite database
  await AssetAuditDatabase().database;

  // Initialize location permissions
  await _initializeLocationPermissions();

  // Cache app version before any API calls (e.g. login App-Version header).
  await AppVersionHelper.init();
}

late AppLinks _appLinks;

// Deep links handling
Future<void> initDeepLinks() async {
  _appLinks = AppLinks();

  final appLink = await _appLinks.getInitialLink();
  if (appLink != null) {
    kDebugPrint('getInitialAppLink: $appLink');
    openAppLink(appLink);
  }

  _appLinks.uriLinkStream.listen((uri) {
    kDebugPrint('onAppLink: $uri');
    openAppLink(uri);
  });
}

void openAppLink(Uri uri) {
  navigatorKey.currentState?.pushNamed(uri.fragment);
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

// Location permissions
Future<void> _initializeLocationPermissions() async {
  try {

    final permissionResult = await LocationPermissionService.requestLocationPermissions();
    if (permissionResult['success']) {
    } 
  } catch (e) {
    throw Exception(e);

  }
}

// Check token status on startup
void _checkTokenStatus() async {
  final token = LocalStorageDB.getToken;
  if (token != null) {
    if (Utils.isTokenExpired(token)) {
      await LocalStorageDB.logout();
    }
  } 
}