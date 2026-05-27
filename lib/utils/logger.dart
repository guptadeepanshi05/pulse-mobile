import 'dart:developer' as developer;

class Logger {
  static const bool _enableImageLogs = false; // Set to true to enable image-related logs
  static const bool _enableDebugLogs = false; // Set to true to enable debug logs
  static const bool _enableErrorLogs = true; // Always enable error logs

  /// Log image-related operations (compression, upload, download)
  static void imageLog(String message) {
    if (_enableImageLogs) {
      developer.log(message, name: 'IMAGE');
    }
  }

  /// Log debug information
  static void debugLog(String message) {
    if (_enableDebugLogs) {
      developer.log(message, name: 'DEBUG');
    }
  }

  /// Log errors (always enabled)
  static void errorLog(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_enableErrorLogs) {
      developer.log(message, name: 'ERROR', error: error, stackTrace: stackTrace);
    }
  }

  /// Log general information
  static void infoLog(String message) {
    developer.log(message, name: 'INFO');
    print(message);

  }

  /// Log API calls
  static void apiLog(String message) {
    developer.log(message, name: 'API');
  }

  /// Log form changes
  static void formLog(String message) {
    developer.log(message, name: 'FORM');
  }
}
