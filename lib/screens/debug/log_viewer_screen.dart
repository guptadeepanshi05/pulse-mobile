import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/file_logger.dart';
import '../../services/log_push_service.dart';
import '../../app_config.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  List<File> _logFiles = [];
  String _selectedLogContent = '';
  bool _isLoading = false;
  File? _selectedFile;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await FileLogger.initialize();
      final files = await FileLogger.getLogFiles();
      
      // Sort files by modification time (newest first)
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      
      setState(() {
        _logFiles = files;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load log files: $e');
    }
  }

  Future<void> _loadLogContent(File file) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final content = await FileLogger.getLogFileContent(file);
      setState(() {
        _selectedLogContent = content;
        _selectedFile = file;
        _isLoading = false;
      });
      
      // Scroll to the end of the content after loading
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_scrollController.hasClients) {
            // First try to jump to the end immediately
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            
            // Then animate for smooth effect
            Future.delayed(const Duration(milliseconds: 50), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        });
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load log content: $e');
    }
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await _showConfirmDialog(
      'Clear All Logs',
      'Are you sure you want to delete all log files? This action cannot be undone.',
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await FileLogger.clearLogs();
        await _loadLogFiles();
        setState(() {
          _selectedLogContent = '';
          _selectedFile = null;
        });
        _showSuccessSnackBar('All logs cleared successfully');
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Failed to clear logs: $e');
      }
    }
  }

  Future<void> _copyLogContent() async {
    if (_selectedLogContent.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _selectedLogContent));
      _showSuccessSnackBar('Log content copied to clipboard');
    }
  }

  Future<void> _shareLogFile() async {
    if (_selectedFile != null) {
      // You can implement sharing functionality here
      // For now, just copy the file path
      await Clipboard.setData(ClipboardData(text: _selectedFile!.path));
      _showSuccessSnackBar('Log file path copied to clipboard');
    }
  }

  Future<void> _pushLogsNow() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final apiService = AppConfig.of(context).apiService;
      await LogPushService.pushLogsNow(apiService);
      if (!mounted) return;
      _showSuccessSnackBar('Logs pushed to backend successfully');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to push logs: $e');
    } finally {
      // Guard against the user popping the screen during the push — setState
      // on a disposed widget throws "Null check operator used on a null value".
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showServiceStatus() {
    final status = LogPushService.getServiceStatus();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Push Service Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${status['isRunning'] ? 'Running' : 'Stopped'}'),
            Text('Push Interval: ${status['pushInterval']} seconds'),
            Text('Max Log Size: ${(status['maxLogSize'] / 1024).toStringAsFixed(1)} KB'),
            Text('Endpoint: ${status['endpoint']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        actions: [
          IconButton(
            onPressed: _pushLogsNow,
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Push logs to backend',
          ),
          IconButton(
            onPressed: _showServiceStatus,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Service status',
          ),
          IconButton(
            onPressed: _loadLogFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh logs',
          ),
          IconButton(
            onPressed: _clearAllLogs,
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Clear all logs',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Log files list
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Log Files (${_logFiles.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: _logFiles.isEmpty
                              ? const Center(
                                  child: Text('No log files found'),
                                )
                              : ListView.builder(
                                  itemCount: _logFiles.length,
                                  itemBuilder: (context, index) {
                                    final file = _logFiles[index];
                                    final isSelected = _selectedFile == file;
                                    
                                    return ListTile(
                                      selected: isSelected,
                                      title: Text(
                                        file.path.split('/').last,
                                        style: TextStyle(
                                          fontWeight: isSelected 
                                              ? FontWeight.bold 
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Size: ${_formatFileSize(file.lengthSync())}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          Text(
                                            'Modified: ${_formatDateTime(file.lastModifiedSync())}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      onTap: () => _loadLogContent(file),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Log content
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      if (_selectedFile != null)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Content: ${_selectedFile!.path.split('/').last}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                onPressed: _copyLogContent,
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy to clipboard',
                              ),
                              IconButton(
                                onPressed: _shareLogFile,
                                icon: const Icon(Icons.share),
                                tooltip: 'Share log file',
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _selectedLogContent.isEmpty
                            ? const Center(
                                child: Text('Select a log file to view its content'),
                              )
                            : SingleChildScrollView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16.0),
                                child: SelectableText(
                                  _selectedLogContent,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
