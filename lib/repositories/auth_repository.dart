import 'dart:convert';
import 'package:app/services/local_storage_db.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/auth_model.dart';
import '../models/forgot_password_model.dart';
import '../models/otp_verification_model.dart';
import '../models/reset_password_model.dart';
import '../services/api_service.dart';

class AuthRepository {
  final ApiService _apiService;

  AuthRepository(this._apiService);

  Future<ResponseResult<AuthModel>> login({
    required String username,
    required String password,
  }) async {
    try {
      // Use stored token, or fetch from FCM if not yet available (e.g. slow init on some devices)
      String? firebaseToken = LocalStorageDB.getFireBaseToken;
      if (firebaseToken == null || firebaseToken.isEmpty) {
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null && fcmToken.isNotEmpty) {
            await LocalStorageDB.saveFireBaseToken(fcmToken);
            firebaseToken = fcmToken;
          }
        } catch (_) {
          // FCM not available (emulator, no Play Services, etc.) - continue with null/empty
        }
      }
      // Send empty string instead of null to avoid backend 500 when token is unavailable
      final tokenForApi = firebaseToken ?? '';

      // Fetch the current app version to send as a header so the backend can
      // identify which client version initiated the login request.
      String appVersion = '';
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        appVersion = packageInfo.version;
      } catch (_) {
        // package_info_plus can fail on some platforms/contexts; fall back to
        // an empty string rather than blocking login.
      }

      final response = await _apiService.post<Map<String, dynamic>>(
        path: 'authenticate/login',
        data: {
          'username': username,
          'password': password,
          'firebaseAccessToken': tokenForApi,
        },
        headers: {
          'App-Version': appVersion,
        },
      );

      if (response.isSuccess && response.data != null) {
        final authModel = AuthModel.fromJson(response.data!);
        return ResponseResult.success(authModel, response.statusCode);
      } else {

        String errorMessage = 'Login failed';
        if (response.errorMessage != null) {
          if (response.errorMessage!.contains('timeout')) {
            errorMessage = 'Login request timed out. Please check your connection and try again.';
          } else if (response.errorMessage!.contains('connection')) {
            errorMessage = 'Unable to connect to server. Please check your internet connection.';
          } else if (response.errorMessage!.contains('401')) {
            errorMessage = 'Invalid username or password. Please try again.';
          } else if (response.statusCode == 500 || 
                     response.errorMessage!.toLowerCase().contains('internal server error')) {
            errorMessage = 'Internal Server Error. Please try again later.';
          } else {
            errorMessage = response.errorMessage!;
          }
        } else if (response.statusCode == 500) {
          errorMessage = 'Internal Server Error. Please try again later.';
        }
        
        // Send detailed failure logs to server for API failures too

        _sendLoginFailureLogs(username, 'API_RESPONSE_FAILURE: ${response.errorMessage}');
        
        return ResponseResult.error(
          errorMessage: errorMessage,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {

      String errorMessage = 'Login failed';
      
      if (e.toString().contains('timeout')) {
        errorMessage = 'Login request timed out. Please check your connection and try again.';
      } else if (e.toString().contains('connection')) {
        errorMessage = 'Unable to connect to server. Please check your internet connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'No internet connection. Please check your network and try again.';
      } else if (e.toString().toLowerCase().contains('internal server error') || 
                 e.toString().contains('500')) {
        errorMessage = 'Internal Server Error. Please try again later.';
      } else {
        errorMessage = 'Login failed. Please try again.';
      }
      
      // Send detailed exception logs to server

      _sendLoginFailureLogs(username, e);
      
      return ResponseResult.error(
        errorMessage: errorMessage,
      );
    }
  }

  // Forgot Password API
  Future<ResponseResult<ForgotPasswordModel?>> forgotPassword({
    required String email,
  }) async {
    try {
      final result = await _apiService.post<dynamic>(
        path: "authenticate/generateOtp",
        queryParameters: {
          'emailId': email,
        },
      );

      // Check if status code is 200 for success
      if (result.isSuccess && result.data != null) {

        ForgotPasswordModel forgotPasswordModel;
        
        if (result.data is Map<String, dynamic>) {

          forgotPasswordModel = ForgotPasswordModel.fromJson(result.data);
        } else if (result.data is String) {

          forgotPasswordModel = ForgotPasswordModel.fromString(result.data);
        } else {

          forgotPasswordModel = ForgotPasswordModel.fromString("OTP sent successfully");
        }

        return ResponseResult.success(forgotPasswordModel, result.statusCode);
      } else {
        String errorMessage = 'Failed to send OTP';
        if (result.errorMessage != null) {
          if (result.errorMessage!.contains('503')) {
            errorMessage = 'Service temporarily unavailable. Please try again later.';
          } else if (result.errorMessage!.contains('500')) {
            errorMessage = 'Server error. Please try again later.';
          } else {
            errorMessage = result.errorMessage!;
          }
        }
        return ResponseResult.error(errorMessage: errorMessage);
      }
    } catch (e) {

      String errorMessage = 'We could not process your forgot password request';
      
      if (e.toString().contains('503')) {
        errorMessage = 'Service temporarily unavailable. Please try again later.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      }
      
      return ResponseResult.error(errorMessage: errorMessage);
    }
  }

  // Verify OTP API
  Future<ResponseResult<OtpVerificationModel?>> verifyOtp({
    required String emailId,
    required String otp,
  }) async {
    try {
      final result = await _apiService.post<dynamic>(
        path: "authenticate/verifyOtp",
        queryParameters: {
          'emailId': emailId,
          'otp': otp,
        },
      );

      // Check if status code is 200 for success
      if (result.isSuccess && result.data != null) {

        OtpVerificationModel otpVerificationModel;
        
        if (result.data is Map<String, dynamic>) {

          otpVerificationModel = OtpVerificationModel.fromJson(result.data);
        } else if (result.data is String) {

          otpVerificationModel = OtpVerificationModel.fromString(result.data);
        } else {

          otpVerificationModel = OtpVerificationModel.fromString("OTP verified successfully");
        }

        return ResponseResult.success(otpVerificationModel, result.statusCode);
      } else {
        String errorMessage = 'Failed to verify OTP';
        if (result.errorMessage != null) {
          if (result.errorMessage!.contains('503')) {
            errorMessage = 'Service temporarily unavailable. Please try again later.';
          } else if (result.errorMessage!.contains('500')) {
            errorMessage = 'Server error. Please try again later.';
          } else if (result.errorMessage!.contains('timeout')) {
            errorMessage = 'Request timed out. Please check your connection and try again.';
          } else {
            errorMessage = result.errorMessage!;
          }
        }
        return ResponseResult.error(errorMessage: errorMessage);
      }
    } catch (e) {

      String errorMessage = 'We could not process your OTP verification request';
      
      if (e.toString().contains('503')) {
        errorMessage = 'Service temporarily unavailable. Please try again later.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      }
      
      return ResponseResult.error(errorMessage: errorMessage);
    }
  }

  // Resend OTP API
  Future<ResponseResult<ForgotPasswordModel?>> resendOtp({
    required String emailId,
  }) async {
    try {
      final result = await _apiService.post<dynamic>(
        path: "authenticate/generateOtp",
        queryParameters: {
          'emailId': emailId,
        },
      );

      // Check if status code is 200 for success
      if (result.isSuccess && result.data != null) {

        ForgotPasswordModel forgotPasswordModel;
        
        if (result.data is Map<String, dynamic>) {

          forgotPasswordModel = ForgotPasswordModel.fromJson(result.data);
        } else if (result.data is String) {

          forgotPasswordModel = ForgotPasswordModel.fromString(result.data);
        } else {

          forgotPasswordModel = ForgotPasswordModel.fromString("OTP resent successfully");
        }

        return ResponseResult.success(forgotPasswordModel, result.statusCode);
      } else {
        String errorMessage = 'Failed to resend OTP';
        if (result.errorMessage != null) {
          if (result.errorMessage!.contains('503')) {
            errorMessage = 'Service temporarily unavailable. Please try again later.';
          } else if (result.errorMessage!.contains('500')) {
            errorMessage = 'Server error. Please try again later.';
          } else if (result.errorMessage!.contains('timeout')) {
            errorMessage = 'Request timed out. Please check your connection and try again.';
          } else {
            errorMessage = result.errorMessage!;
          }
        }
        return ResponseResult.error(errorMessage: errorMessage);
      }
    } catch (e) {

      String errorMessage = 'We could not process your resend OTP request';
      
      if (e.toString().contains('503')) {
        errorMessage = 'Service temporarily unavailable. Please try again later.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      }
      
      return ResponseResult.error(errorMessage: errorMessage);
    }
  }

  // Reset Password API
  Future<ResponseResult<ResetPasswordModel?>> resetPassword({
    required String emailId,
    required String newPassword,
  }) async {
    try {
      final result = await _apiService.post<dynamic>(
        path: "authenticate/changePassword",
        queryParameters: {
          'emailId': emailId,
          'newPassword': newPassword,
        },
      );

      // Check if status code is 200 for success
      if (result.isSuccess && result.data != null) {

        ResetPasswordModel resetPasswordModel;
        
        if (result.data is Map<String, dynamic>) {

          resetPasswordModel = ResetPasswordModel.fromJson(result.data);
        } else if (result.data is String) {

          resetPasswordModel = ResetPasswordModel.fromString(result.data);
        } else {

          resetPasswordModel = ResetPasswordModel.fromString("Password changed successfully");
        }

        return ResponseResult.success(resetPasswordModel, result.statusCode);
      } else {
        String errorMessage = 'Failed to reset password';
        if (result.errorMessage != null) {
          if (result.errorMessage!.contains('503')) {
            errorMessage = 'Service temporarily unavailable. Please try again later.';
          } else if (result.errorMessage!.contains('500')) {
            errorMessage = 'Server error. Please try again later.';
          } else if (result.errorMessage!.contains('timeout')) {
            errorMessage = 'Request timed out. Please check your connection and try again.';
          } else {
            errorMessage = result.errorMessage!;
          }
        }
        return ResponseResult.error(errorMessage: errorMessage);
      }
    } catch (e) {

      String errorMessage = 'We could not process your reset password request';
      
      if (e.toString().contains('503')) {
        errorMessage = 'Service temporarily unavailable. Please try again later.';
      } else if (e.toString().contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      }
      
      return ResponseResult.error(errorMessage: errorMessage);
    }
  }

  /// Helper method to send login failure logs
  void _sendLoginFailureLogs(String username, dynamic exception) {

    try {
      // Create detailed log information
      final logData = {
        'timestamp': DateTime.now().toIso8601String(),
        'event': 'LOGIN_FAILURE',
        'username': username,
        'exception': exception.toString(),
        'exceptionType': exception.runtimeType.toString(),
        'stackTrace': exception is Error ? exception.stackTrace?.toString() : null,
        'deviceInfo': {
          'platform': 'mobile',
          'appVersion': '1.0.0', // You can get this from package_info_plus
        }
      };
      
      // Convert to JSON string
      final logsJson = jsonEncode(logData);

      // Send logs asynchronously (don't wait for response)

      sendMobileLogs(logs: logsJson).then((result) {

        if (result.isSuccess) {

        } else {

        }
      }).catchError((error) {

      });
    } catch (e) {

    }
  }

  /// Test method to manually send mobile logs (for debugging)
  Future<ResponseResult<bool>> testSendMobileLogs() async {

    final testLogs = {
      'timestamp': DateTime.now().toIso8601String(),
      'event': 'TEST_LOG',
      'message': 'This is a test log from mobile app',
      'deviceInfo': {
        'platform': 'mobile',
        'appVersion': '1.0.0',
      }
    };
    
    return sendMobileLogs(logs: jsonEncode(testLogs));
  }

  /// Send mobile logs to server when login fails
  Future<ResponseResult<bool>> sendMobileLogs({
    required String logs,
  }) async {

    try {

      final response = await _apiService.post<Map<String, dynamic>>(
        path: 'api/v1/mobile/upload/MobileLogs',
        data: {
          'logs': logs,
        },
      );

      if (response.isSuccess) {

        return ResponseResult.success(true, response.statusCode);
      } else {

        return ResponseResult.error(
          errorMessage: response.errorMessage ?? 'Failed to send mobile logs',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {

      return ResponseResult.error(
        errorMessage: 'Failed to send mobile logs: $e',
      );
    }
  }
}

class ResponseResult<T> extends Equatable {
  final bool isSuccess;
  final T? data;
  final String? errorMessage;
  final int? statusCode;
  final DioExceptionType? dioErrorType;

  const ResponseResult._({
    required this.isSuccess,
    this.data,
    this.errorMessage,
    this.statusCode,
    this.dioErrorType,
  });

  factory ResponseResult.success(T data, [int? statusCode]) {
    return ResponseResult._(
      isSuccess: true,
      data: data,
      statusCode: statusCode,
    );
  }

  factory ResponseResult.error({
    String? errorMessage,
    int? statusCode,
    DioExceptionType? dioErrorType,
  }) {
    return ResponseResult._(
      isSuccess: false,
      errorMessage: errorMessage,
      statusCode: statusCode,
      dioErrorType: dioErrorType,
    );
  }

  @override
  List<Object?> get props => [isSuccess, data, errorMessage, statusCode, dioErrorType];
}
