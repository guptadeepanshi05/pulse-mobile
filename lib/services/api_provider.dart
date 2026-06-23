import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../app_root.dart';
import '../constants/constants_methods.dart';
import 'local_storage_constants.dart';
import 'local_storage_db.dart';
import '../routes/routes.dart';
import '../bloc/global_loading_cubit.dart';
import '../utils/api_logger.dart';
import '../utils/app_version_helper.dart';

/// ApiProvider handles HTTP requests with Dio
///
/// Features:
/// - Automatic token injection for authenticated requests
/// - Global loading indicator management
/// - Logging with base64 image data filtering to prevent log spam
/// - Automatic logout on 401 responses

class ApiProvider {
  final String baseUrl;
  // Removed Hive box reference - using LocalStorageDB instead
  GlobalLoadingCubit? _loadingCubit;
  bool _isLoadingShown = false;

  final Dio _dio = Dio();

  ApiProvider({required this.baseUrl, GlobalLoadingCubit? loadingCubit}) {
    _loadingCubit = loadingCubit;
    BaseOptions options = BaseOptions(
      headers: {
        'content-Type': 'application/json',
        'accept': 'application/json',
      },
      baseUrl: baseUrl,
      receiveDataWhenStatusError: true,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      // Large JSON bodies (e.g. PMIS activity ticket) can exceed default send limits on slow links.
      sendTimeout: const Duration(seconds: 120),
    );

    _dio.options = options;

    // // Add PrettyDioLogger for development (can be disabled in production)
    // _dio.interceptors.add(PrettyDioLogger(
    //   requestHeader: true,
    //   requestBody: true,
    //   responseHeader: true,
    //   responseBody: true,
    //   error: true,
    //   compact: false,
    //   logPrint: (object) {
    //     // Filter out base64 image data from logs to prevent log spam
    //     String logMessage = object.toString();
    //
    //     // Check if this log contains image data and filter it out
    //     if (logMessage.contains('imageData') && logMessage.contains('base64')) {
    //       // Replace base64 image data with a placeholder
    //       logMessage = logMessage.replaceAllMapped(
    //         RegExp(r'"imageData":\s*"[^"]*"'),
    //         (match) => '"imageData": "[BASE64_IMAGE_DATA_REMOVED_FROM_LOGS]"',
    //       );
    //     }
    //
    //     // Also filter out any other large base64 strings that might be images
    //     if (logMessage.contains('data:image/')) {
    //       logMessage = logMessage.replaceAllMapped(
    //         RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]+'),
    //         (match) => 'data:image/jpeg;base64,[BASE64_IMAGE_DATA_REMOVED_FROM_LOGS]',
    //       );
    //     }
    //
    //     // Filter out any other potential large base64 data
    //     if (logMessage.length > 1000 && logMessage.contains('base64')) {
    //       logMessage = logMessage.replaceAllMapped(
    //         RegExp(r'[A-Za-z0-9+/]{100,}={0,2}'),
    //         (match) => '[LARGE_BASE64_DATA_REMOVED_FROM_LOGS]',
    //       );
    //     }
    //
    //   },
    // ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Log the request
          ApiLogger.logRequest(options);

          if (AppVersionHelper.requiresAppVersionHeader(options.path)) {
            await AppVersionHelper.attachAppVersionHeader(options.headers);
          }

          final isAuthEndpoint = options.path.contains('authenticate/login');

          if (!isAuthEndpoint) {
            if (LocalStorageDB.getToken != null) {
              options.headers['Authorization'] =
                  'Bearer ${LocalStorageDB.getToken}';
            }
          }

          // Show loading indicator for non-auth endpoints
          // if (!isAuthEndpoint && _loadingCubit != null && !_isLoadingShown) {
          //   _isLoadingShown = true;
          //   _loadingCubit!.showLoading(message: 'Loading...');
          // }

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // Log the response
          ApiLogger.logResponse(response);

          // Hide loading indicator
          if (_loadingCubit != null && _isLoadingShown) {
            _isLoadingShown = false;
            _loadingCubit!.hideLoading();
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) async {
         
          ApiLogger.logError(e);

          // Hide loading indicator on error
          if (_loadingCubit != null && _isLoadingShown) {
            _isLoadingShown = false;
            _loadingCubit!.hideLoading();
          }

          if (e.response?.statusCode == 401) {
            // Token is invalid or expired
            await _logoutUser();
            return handler.next(e);
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> _logoutUser() async {
    try {
      await LocalStorageDB.logout();
      // Navigate to login screen
      if (navigatorKey.currentContext != null) {
        pushNamedAndRemoveUntil(navigatorKey.currentContext!, loginScreen);
      }
    } catch (e) {

    }
  }

  Dio getClient() => _dio;
}
