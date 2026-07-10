import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/logger.dart';

/// Ticket session sync mode stored on each pending row.
class TicketSyncMode {
  static const String online = 'ONLINE';
  static const String offline = 'OFFLINE';
}

class PendingRequestsService {
  static final PendingRequestsService _instance =
      PendingRequestsService._internal();
  factory PendingRequestsService() => _instance;
  PendingRequestsService._internal();
  static const int _databaseVersion = 3;
  static Database? _database;

  static final String _databaseName = 'pending_requests.db';

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pending_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id TEXT UNIQUE NOT NULL,
        url TEXT NOT NULL,
        headers TEXT,
        request_data TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        last_retry_at INTEGER,
        error_message TEXT,
        ticket_id TEXT,
        sequence_no INTEGER DEFAULT 0,
        ticket_sync_mode TEXT
      )
    ''');
    Logger.debugLog('✅ PendingRequestsService: Database created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS pending_requests');
      await _onCreate(db, newVersion);
      Logger.debugLog(
        '✅ Database upgraded from version $oldVersion to $newVersion (recreated)',
      );
      return;
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE pending_requests ADD COLUMN ticket_id TEXT',
      );
      await db.execute(
        'ALTER TABLE pending_requests ADD COLUMN sequence_no INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE pending_requests ADD COLUMN ticket_sync_mode TEXT',
      );
      Logger.debugLog(
        '✅ Database upgraded from version $oldVersion to $newVersion (added ticket columns)',
      );
    }
  }

  /// Save a pending request to the database.
  Future<bool> savePendingRequest({
    required String requestId,
    required String url,
    required Map<String, dynamic> headers,
    required String jsonEncodedRequestData,
    String? ticketId,
    int? sequenceNo,
    String? ticketSyncMode,
  }) async {
    try {
      final db = await database;

      final pendingRequest = <String, Object?>{
        'request_id': requestId,
        'url': url,
        'headers': jsonEncode(headers),
        'request_data': jsonEncodedRequestData,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'retry_count': 0,
        'status': 'pending',
        'last_retry_at': null,
        'error_message': null,
        'ticket_id': ticketId,
        'sequence_no': sequenceNo ?? 0,
        'ticket_sync_mode': ticketSyncMode,
      };

      int result = await db.insert(
        'pending_requests',
        pendingRequest,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (result > 0) {
        Logger.debugLog(
          'Pending post data saved for requestId $requestId '
          '(ticketId=$ticketId, seq=$sequenceNo, mode=$ticketSyncMode)',
        );
        return true;
      } else {
        Logger.debugLog(
          '⚠️ Pending post data could not be saved for requestId $requestId',
        );
        return false;
      }
    } catch (e) {
      Logger.errorLog(
        'PendingRequestsService: Error saving pending request: $e',
      );
      rethrow;
    }
  }

  /// Next sequence number for a ticket (1-based).
  Future<int> getNextSequenceNoForTicket(String ticketId) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT MAX(sequence_no) as max_seq FROM pending_requests '
        'WHERE ticket_id = ? AND status = ?',
        [ticketId, 'pending'],
      );
      final maxSeq = result.first['max_seq'] as int?;
      return (maxSeq ?? 0) + 1;
    } catch (e) {
      Logger.errorLog(
        'PendingRequestsService: Error getting next sequence for $ticketId: $e',
      );
      return 1;
    }
  }

  /// Whether any pending row marks this ticket as offline session mode.
  Future<bool> isTicketInOfflineMode(String ticketId) async {
    if (ticketId.trim().isEmpty) return false;
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM pending_requests '
        'WHERE ticket_id = ? AND status = ? AND ticket_sync_mode = ?',
        [ticketId, 'pending', TicketSyncMode.offline],
      );
      return (result.first['cnt'] as int? ?? 0) > 0;
    } catch (e) {
      Logger.errorLog(
        'PendingRequestsService: Error checking offline mode for $ticketId: $e',
      );
      return false;
    }
  }

  /// Mark all pending rows for a ticket as offline session mode.
  Future<void> markTicketOfflineMode(String ticketId) async {
    if (ticketId.trim().isEmpty) return;
    try {
      final db = await database;
      await db.update(
        'pending_requests',
        {'ticket_sync_mode': TicketSyncMode.offline},
        where: 'ticket_id = ? AND status = ?',
        whereArgs: [ticketId, 'pending'],
      );
    } catch (e) {
      Logger.errorLog(
        'PendingRequestsService: Error marking ticket offline $ticketId: $e',
      );
    }
  }

  /// Total pending requests awaiting sync.
  Future<int> countPendingRequests() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM pending_requests WHERE status = ?',
        ['pending'],
      );
      return result.first['cnt'] as int? ?? 0;
    } catch (e) {
      Logger.errorLog(
        'PendingRequestsService: Error counting pending requests: $e',
      );
      return 0;
    }
  }

  /// Pending row count for a ticket.
  Future<int> countPendingForTicket(String ticketId) async {
    if (ticketId.trim().isEmpty) return 0;
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM pending_requests '
        'WHERE ticket_id = ? AND status = ?',
        [ticketId, 'pending'],
      );
      return result.first['cnt'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get a pending request by requestId
  Future<Map<String, dynamic>?> getPendingRequest(String requestId) async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_requests',
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'pending'],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return result.first;
      }
      return null;
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error retrieving pending request: $e',
      );
      return null;
    }
  }

  /// Get all pending requests (legacy order: created_at ASC).
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    return getPendingRequestsFifoOrdered();
  }

  /// Strict FIFO: ticket_id ASC, sequence_no ASC, created_at ASC.
  /// Rows without ticket_id are processed last (legacy requests).
  Future<List<Map<String, dynamic>>> getPendingRequestsFifoOrdered() async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_requests',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy:
            'CASE WHEN ticket_id IS NULL OR ticket_id = \'\' THEN 1 ELSE 0 END, '
            'ticket_id ASC, sequence_no ASC, created_at ASC',
      );

      Logger.debugLog(
        '📋 PendingRequestsService: Retrieved ${result.length} pending requests (FIFO)',
      );
      return result;
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error retrieving pending requests: $e',
      );
      return [];
    }
  }

  /// Update request status
  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    String? errorMessage,
  }) async {
    try {
      final db = await database;

      final updateData = <String, Object?>{
        'status': status,
        'last_retry_at': DateTime.now().millisecondsSinceEpoch,
      };

      if (errorMessage != null) {
        updateData['error_message'] = errorMessage;
      }

      if (status == 'failed') {
        updateData['retry_count'] = await _incrementRetryCount(requestId);
      }

      await db.update(
        'pending_requests',
        updateData,
        where: 'request_id = ?',
        whereArgs: [requestId],
      );

      Logger.debugLog(
        '🔄 PendingRequestsService: Updated request $requestId status to $status',
      );
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error updating request status: $e',
      );
    }
  }

  /// Delete completed request
  Future<void> deleteRequest(String requestId) async {
    try {
      final db = await database;
      await db.delete(
        'pending_requests',
        where: 'request_id = ?',
        whereArgs: [requestId],
      );

      Logger.debugLog('🗑️ PendingRequestsService: Deleted request $requestId');
    } catch (e) {
      Logger.errorLog('❌ PendingRequestsService: Error deleting request: $e');
    }
  }

  /// Increment retry count for a request
  Future<int> _incrementRetryCount(String requestId) async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_requests',
        columns: ['retry_count'],
        where: 'request_id = ?',
        whereArgs: [requestId],
      );

      if (result.isNotEmpty) {
        final currentCount = result.first['retry_count'] as int;
        final newCount = currentCount + 1;

        await db.update(
          'pending_requests',
          {'retry_count': newCount},
          where: 'request_id = ?',
          whereArgs: [requestId],
        );

        return newCount;
      }

      return 0;
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error incrementing retry count: $e',
      );
      return 0;
    }
  }

  /// Clear all data
  Future<void> clearAllData() async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('pending_requests');
    });

    Logger.debugLog('✅ All data cleared');
  }

  /// Drop and recreate database with all tables
  Future<void> dropAndRecreateDatabase() async {
    try {
      Logger.debugLog(
        '🗑️ Dropping and recreating ImageUploadService database',
      );

      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, _databaseName);

      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        Logger.debugLog('🗑️ ImageUploadService database file deleted');
      }

      _database = await _initDatabase();
      Logger.debugLog(
        '✅ ImageUploadService database recreated with all tables',
      );
    } catch (e) {
      Logger.errorLog(
        '❌ Error dropping and recreating ImageUploadService database: $e',
      );
      _database = null;
      rethrow;
    }
  }

  /// Increment retry count for a request (public method)
  Future<int> incrementRetryCount(String requestId) async {
    return await _incrementRetryCount(requestId);
  }

  /// Get request details for retry
  Future<Map<String, dynamic>?> getRequestForRetry(String requestId) async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_requests',
        where: 'request_id = ? AND status = ?',
        whereArgs: [requestId, 'pending'],
      );

      if (result.isNotEmpty) {
        final request = result.first;
        return {
          'request_id': request['request_id'],
          'url': request['url'],
          'headers': jsonDecode(request['headers'] as String),
          'request_data': jsonDecode(request['request_data'] as String),
          'ticket_id': request['ticket_id'],
          'sequence_no': request['sequence_no'],
          'ticket_sync_mode': request['ticket_sync_mode'],
        };
      }

      return null;
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error getting request for retry: $e',
      );
      return null;
    }
  }

  /// Log all pending requests in the table
  Future<void> logPendingRequestsTable() async {
    try {
      final db = await database;
      final result = await db.query(
        'pending_requests',
        orderBy: 'created_at DESC',
      );

      Logger.infoLog(
        '📋 PendingRequestsService: Logged ${result.length} pending requests',
      );
    } catch (e) {
      Logger.errorLog(
        '❌ PendingRequestsService: Error logging pending requests table: $e',
      );
    }
  }

  /// Log table structure and stats
  Future<void> logTableInfo() async {
    try {
      final db = await database;
      await db.rawQuery("PRAGMA table_info(pending_requests)");
      await db.rawQuery("SELECT COUNT(*) as count FROM pending_requests");
      await db.rawQuery(
        "SELECT status, COUNT(*) as count FROM pending_requests GROUP BY status",
      );
    } catch (e) {
      Logger.errorLog('❌ PendingRequestsService: Error logging table info: $e');
    }
  }

  /// Test method to verify service is working
  Future<void> testService() async {
    try {
      final db = await database;

      final testRequest = {
        'request_id': 'test_${DateTime.now().millisecondsSinceEpoch}',
        'url': '/test/endpoint',
        'headers': '{"Content-Type":"application/json"}',
        'request_data': '[{"test":"data"}]',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'retry_count': 0,
        'status': 'pending',
        'last_retry_at': null,
        'error_message': null,
        'ticket_id': null,
        'sequence_no': 0,
        'ticket_sync_mode': null,
      };

      await db.insert('pending_requests', testRequest);
      await db.query('pending_requests');
      await db.delete(
        'pending_requests',
        where: 'request_id LIKE ?',
        whereArgs: ['test_%'],
      );
    } catch (e) {
      // test helper
    }
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      Logger.debugLog('✅ PendingRequestsService database closed');
    }
  }
}
