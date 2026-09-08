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
