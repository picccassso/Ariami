import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/download/download_manager.dart';

/// Global download progress bar that shows active download status
class DownloadProgressBar extends StatefulWidget {
  const DownloadProgressBar({super.key});

  @override
  State<DownloadProgressBar> createState() => _DownloadProgressBarState();
}

class _DownloadProgressBarState extends State<DownloadProgressBar>
    with SingleTickerProviderStateMixin {
  final DownloadManager _downloadManager = DownloadManager();

  StreamSubscription<DownloadProgress>? _progressSubscription;
  StreamSubscription<List<dynamic>>? _queueSubscription;

  double _progress = 0.0;
  bool _isVisible = false;
  bool _showError = false;
  String? _currentTaskId;

  late AnimationController _errorFlashController;
  late Animation<Color?> _errorColorAnimation;

  @override
  void initState() {
    super.initState();

    // Setup error flash animation
    _errorFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _errorColorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.red,
    ).animate(CurvedAnimation(
      parent: _errorFlashController,
      curve: Curves.easeInOut,
    ));

    _initializeDownloadManager();
  }

  Future<void> _initializeDownloadManager() async {
    await _downloadManager.initialize();

    // Listen to progress updates
    _progressSubscription = _downloadManager.progressStream.listen((progress) {
      setState(() {
        _currentTaskId = progress.taskId;
        _progress = progress.progress;

        // Show bar when download is active
        if (!_isVisible && progress.progress < 1.0) {
          _isVisible = true;
        }

        // Hide bar when download completes (progress reaches 1.0)
        if (progress.progress >= 1.0) {
          // Delay hiding to show completion briefly
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {
                _isVisible = false;
                _progress = 0.0;
                _currentTaskId = null;
              });
            }
          });
        }
      });
    });

    // Listen to queue updates to detect errors and hide when empty
    _queueSubscription = _downloadManager.queueStream.listen((queue) {
      // Hide bar if queue is empty or has no active/pending downloads
      if (queue.isEmpty ||
          !queue.any((task) =>
              task.status.toString() == 'DownloadStatus.downloading' ||
              task.status.toString() == 'DownloadStatus.pending')) {
        if (mounted && _isVisible) {
          setState(() {
            _isVisible = false;
            _progress = 0.0;
            _currentTaskId = null;
          });
        }
        return;
      }

      // Check if current task failed
      if (_currentTaskId != null) {
        final currentTask = queue.firstWhere(
          (task) => task.id == _currentTaskId,
          orElse: () => queue.first,
        );

        if (currentTask.status.toString() == 'DownloadStatus.failed' && !_showError) {
          _triggerErrorFlash();
        }
      }
    });

    // Check for any active downloads on init
    final stats = _downloadManager.getQueueStats();
    if (stats.downloading > 0) {
      setState(() {
        _isVisible = true;
      });
    }
  }

  void _triggerErrorFlash() {
    setState(() {
      _showError = true;
    });

    // Flash red once
    _errorFlashController.forward().then((_) {
      _errorFlashController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _showError = false;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _queueSubscription?.cancel();
    _errorFlashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: _isVisible ? 4 : 0,
      child: AnimatedOpacity(
        opacity: _isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: AnimatedBuilder(
          animation: _errorColorAnimation,
          builder: (context, child) {
            return LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                _showError ? _errorColorAnimation.value! : Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }
}
