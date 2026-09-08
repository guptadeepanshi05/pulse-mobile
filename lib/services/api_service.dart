import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import 'api_provider.dart';
import 'dio_exception.dart';

class ApiService {
  final ApiProvider apiProvider;

  String get baseUrl => apiProvider.baseUrl;

  ApiService(this.apiProvider);

  /// Internal helper to send mobile logs whenever an API call fails.
  /// This mirrors the `sendMobileLogs` behaviour in `AuthRepository`, but is
  /// centralized here so it can be used for **all** API failures.
  Future<void> _sendMobileLogs({
    required String path,
    required String method,
    int? statusCode,
    String? errorMessage,
    DioExceptionType? dioErrorType,
    dynamic responseData,
  }) async {
    try {
      String? backendError;
      if (responseData is Map && responseData['error'] != null) {
        backendError = responseData['error'].toString();
      }

      final logData = {
        'timestamp': DateTime.now().toIso8601String(),
        'event': 'API_FAILURE',
        'method': method,
        'path': path,
        'baseUrl': baseUrl,
        'statusCode': statusCode,
        'errorMessage': errorMessage,
        'dioErrorType': dioErrorType?.toString(),
        'backendError': backendError,
        'rawResponse': responseData,
      };

      // Use the raw Dio client directly so that logging itself does not
      // go through ApiService (avoids recursive logging on failure).
      await apiProvider.getClient().post(
        'api/v1/mobile/upload/MobileLogs',
        data: {
          'logs': jsonEncode(logData),
        },
      );
    } catch (_) {
      // Swallow any errors from log sending – logging must never break the app.
    }
  }

  /// Public helper to send **camera crash logs** (plain text only) to backend.
  /// This is used by camera/selfie flows to push a simple text log without
  /// any structured payload.
  Future<void> sendCameraCrashLogs(String message) async {
    try {
      await apiProvider.getClient().post(
        'api/v1/mobile/upload/MobileLogs',
        data: {
          'logs': message,
        },
      );
    } catch (_) {
      // Never throw from logging – failures here must not crash the app.
    }
  }

  Future<ResponseResult<T>> get<T>({
    required String path,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    bool refreshCache = false,
    ResponseType responseType = ResponseType.json,
  }) async {
    try {
      final result = await apiProvider.getClient().get(
            path,
            queryParameters: queryParameters,
            options: Options(headers: headers, responseType: responseType),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        // If Dio didn't automatically decode the JSON, manually decode it.
        if (result.data is String) {
          return ResponseResult.success(jsonDecode(result.data), result.statusCode);
        }
        return ResponseResult.success(result.data, result.statusCode);
      } else {
        await _sendMobileLogs(
          path: path,
          method: 'GET',
          statusCode: result.statusCode,
          errorMessage:
              'Request failed with status code: ${result.statusCode}',
          responseData: result.data,
        );
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      // log("path: $path");
      _recordError(e);
      await _sendMobileLogs(
        path: path,
        method: 'GET',
        statusCode: e.response?.statusCode,
        errorMessage:
            DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        responseData: e.response?.data,
      );
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }


  static dynamic _decodePostResponseBody(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String) return raw;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return trimmed;
    }
  }

  Future<ResponseResult<T>> post<T>({
    required String path,
    dynamic data, // Changed from Map<String, dynamic>? to dynamic
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    List<MultipartFile>? files,
    bool useFormDataFormat = false,
  }) async {
    try {

      dynamic dataPayload;
      
      if (useFormDataFormat) {
        // Handle FormData creation
        if (data is Map<String, dynamic>) {
          dataPayload = FormData.fromMap(data);
        } else {
          dataPayload = null;
        }
        
        if (dataPayload is FormData && files != null) {
          for (int i = 0; i < files.length; i++) {
            final file = files[i];
            dataPayload.files.add(MapEntry('Documents', file));
          }
        }
      } else {
        // Send data directly (could be Map, List, or any JSON-serializable type)
        dataPayload = data;
      }

      final result = await apiProvider.getClient().post(
            path,
            data: dataPayload,
            queryParameters: queryParameters,
            options: Options(
              headers: headers,
              responseType: ResponseType.plain,
            ),
          );

      // Check if status code indicates success (200, 201, 202, etc.)
      if (result.statusCode! >= 200 && result.statusCode! < 300) {
        final decoded = _decodePostResponseBody(result.data);
        return ResponseResult.success(decoded as T?, result.statusCode);
      } else {
        await _sendMobileLogs(
          path: path,
          method: 'POST',
          statusCode: result.statusCode,
          errorMessage:
              'Request failed with status code: ${result.statusCode}',
          responseData: result.data,
        );
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
       // log("path: $path");
      _recordError(e);
      await _sendMobileLogs(
        path: path,
        method: 'POST',
        statusCode: e.response?.statusCode,
        errorMessage:
            DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        responseData: e.response?.data,
      );
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    } catch (e) {

      await _sendMobileLogs(
        path: path,
        method: 'POST',
        errorMessage: 'Request failed: $e',
        responseData: null,
      );
      return ResponseResult.error(
        errorMessage: 'Request failed: $e',
      );
    }
  }

  Future<ResponseResult<T>> put<T>({
    required String path,
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    List<MultipartFile>? files,
    bool useFormDataFormat = true,
  }) async {
    try {
      final dataPayload = useFormDataFormat ? (data != null ? FormData.fromMap(data) : null) : data;

      if (dataPayload is FormData && files != null) {
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          dataPayload.files.add(MapEntry('image_$i', file));
        }
      }

      final result = await apiProvider.getClient().put(
            path,
            data: dataPayload,
            queryParameters: queryParameters,
            options: Options(headers: headers),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        return ResponseResult.success(result.data, result.statusCode);
      } else {
        await _sendMobileLogs(
          path: path,
          method: 'PUT',
          statusCode: result.statusCode,
          errorMessage:
              'Request failed with status code: ${result.statusCode}',
          responseData: result.data,
        );
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      // log("path: $path");
      _recordError(e);
      await _sendMobileLogs(
        path: path,
        method: 'PUT',
        statusCode: e.response?.statusCode,
        errorMessage:
            DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        responseData: e.response?.data,
      );
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<ResponseResult<T>> patch<T>({
    required String path,
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiProvider.getClient().patch(
            path,
            data: data,
            options: Options(headers: headers),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        return ResponseResult.success(result.data, result.statusCode);
      } else {
        await _sendMobileLogs(
          path: path,
          method: 'PATCH',
          statusCode: result.statusCode,
          errorMessage:
              'Request failed with status code: ${result.statusCode}',
          responseData: result.data,
        );
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      // log("path: $path");
      _recordError(e);
      await _sendMobileLogs(
        path: path,
        method: 'PATCH',
        statusCode: e.response?.statusCode,
        errorMessage:
            DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        responseData: e.response?.data,
      );
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<ResponseResult<T>> delete<T>({
    required String path,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiProvider.getClient().delete(
            path,
            options: Options(headers: headers),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        return ResponseResult.success(result.data, result.statusCode);
      } else {
        await _sendMobileLogs(
          path: path,
          method: 'DELETE',
          statusCode: result.statusCode,
          errorMessage:
              'Request failed with status code: ${result.statusCode}',
          responseData: result.data,
        );
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      // log("path: $path");
      _recordError(e);
      await _sendMobileLogs(
        path: path,
        method: 'DELETE',
        statusCode: e.response?.statusCode,
        errorMessage:
            DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        responseData: e.response?.data,
      );
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }

  void _recordError(DioException error) {

  }

  /// Get notifications for a user
  Future<ResponseResult<List<dynamic>>> getNotifications({
    required String userId,
    int pageSize = 50,
    int pageNo = 1,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiProvider.getClient().post(
            '/notifications/allNotificationAndMarkRead',
            queryParameters: {
              'userId': userId,
              'pageSize': pageSize.toString(),
              'pageNo': pageNo.toString(),
            },
            options: Options(headers: headers),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        return ResponseResult.success(result.data, result.statusCode);
      } else {
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      _recordError(e);
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Get unseen notifications count for a user
  Future<ResponseResult<String>> getNotificationsCount({
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiProvider.getClient().get(
            '/notifications/get-unseen-count',
            options: Options(headers: headers),
          );

      // Check if status code is 200 for success
      if (result.statusCode == 200) {
        // Extract count from response as string
        String count = "0";
        if (result.data is Map) {
          final data = result.data['count'] ?? result.data['unseenCount'] ?? "0";
          count = data.toString();
        } else if (result.data is String) {
          count = result.data as String;
        } else if (result.data is int) {
          count = result.data.toString();
        }
        return ResponseResult.success(count, result.statusCode);
      } else {
        return ResponseResult.error(
          errorMessage: 'Request failed with status code: ${result.statusCode}',
          statusCode: result.statusCode,
        );
      }
    } on DioException catch (e) {
      _recordError(e);
      return ResponseResult.error(
        errorMessage: DioExceptions.fromDioError(dioError: e).errorMessage(),
        dioErrorType: e.type,
        statusCode: e.response?.statusCode,
      );
    }
  }

}

class ResponseResult<T> extends Equatable {
  final T? data;
  final String? errorMessage;
  final DioExceptionType? dioErrorType;
  final int? statusCode;

  const ResponseResult.success(this.data, this.statusCode)
      : errorMessage = null,
        dioErrorType = null;

  const ResponseResult.error({
    required this.errorMessage,
    this.dioErrorType,
    this.statusCode,
  }) : data = null;

  bool get isSuccess => errorMessage == null && statusCode == 200;

  @override
  List<Object?> get props => [data, errorMessage, statusCode];
}
