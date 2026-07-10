import 'package:app/services/asset_audit_post_service.dart';
import 'package:app/services/service_locator.dart';
import 'package:flutter/material.dart';

/// Sync FAB: blue when offline data exists, grey when empty, spinning while syncing.
class OfflineSyncFloatingActionButton extends StatefulWidget {
  final Future<void> Function() onSync;
  final String heroTag;

  const OfflineSyncFloatingActionButton({
    super.key,
    required this.onSync,
    this.heroTag = 'sync_fab',
  });

  @override
  State<OfflineSyncFloatingActionButton> createState() =>
      _OfflineSyncFloatingActionButtonState();
}

class _OfflineSyncFloatingActionButtonState
    extends State<OfflineSyncFloatingActionButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _activeColor = Colors.blue;
  static const Color _inactiveColor = Color(0xFFB0B0B0);

  late final AnimationController _spinController;
  int _pendingCount = 0;
  bool _localSyncing = false;

  bool get _isSyncing =>
      _localSyncing || AssetAuditPostService.syncInProgressNotifier.value;

  bool get _hasPendingData => _pendingCount > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    AssetAuditPostService.syncInProgressNotifier.addListener(_onSyncProgressChanged);
    _refreshPendingCount();
    _updateSpinAnimation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AssetAuditPostService.syncInProgressNotifier.removeListener(
      _onSyncProgressChanged,
    );
    _spinController.dispose();
    super.dispose();
  }

  @override
  void activate() {
    super.activate();
    _refreshPendingCount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPendingCount();
    }
  }

  void _onSyncProgressChanged() {
    if (!mounted) return;
    _updateSpinAnimation();
    setState(() {});
    if (!AssetAuditPostService.syncInProgressNotifier.value) {
      _refreshPendingCount();
    }
  }

  void _updateSpinAnimation() {
    if (_isSyncing) {
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else {
      _spinController
        ..stop()
        ..reset();
    }
  }

  Future<void> _refreshPendingCount() async {
    final count =
        await ServiceLocator().pendingRequestService.countPendingRequests();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  Future<void> _handlePressed() async {
    if (_isSyncing || !_hasPendingData) return;

    setState(() => _localSyncing = true);
    _updateSpinAnimation();

    try {
      await widget.onSync();
    } finally {
      if (mounted) {
        setState(() => _localSyncing = false);
        _updateSpinAnimation();
        await _refreshPendingCount();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = _hasPendingData && !_isSyncing;

    return FloatingActionButton(
      onPressed: isEnabled ? _handlePressed : null,
      backgroundColor: _hasPendingData ? _activeColor : _inactiveColor,
      disabledElevation: 0,
      heroTag: widget.heroTag,
      tooltip: _isSyncing
          ? 'Syncing offline data…'
          : _hasPendingData
              ? 'Sync offline data ($_pendingCount)'
              : 'No offline data to sync',
      child: RotationTransition(
        turns: _spinController,
        child: Icon(
          Icons.sync,
          color: _hasPendingData ? Colors.white : Colors.white70,
        ),
      ),
    );
  }
}
