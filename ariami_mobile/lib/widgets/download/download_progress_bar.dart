import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/download_task.dart';
import '../../services/download/download_manager.dart';
import 'global_download_chrome_visibility.dart';

/// Global download progress bar that shows active download status
class DownloadProgressBar extends StatefulWidget {
  const DownloadProgressBar({super.key});

  @override
  State<DownloadProgressBar> createState() => _DownloadProgressBarState();
}

class _DownloadProgressBarState extends State<DownloadProgressBar>
    with SingleTickerProviderStateMixin {
  final DownloadManager _downloadManager = DownloadManager();

  StreamSubscription<List<DownloadTask>>? _queueSubscription;

  bool _showError = false;
  String? _lastFailedTaskId;

  late AnimationController _errorFlashController;
  late Animation<Color?> _errorColorAnimation;

  @override
  void initState() {
    super.initState();

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

    _queueSubscription = _downloadManager.queueStream.listen((queue) {
      for (final task in queue) {
        if (task.status != DownloadStatus.failed) {
          continue;
        }
        if (task.id == _lastFailedTaskId || _showError) {
          continue;
        }
        _lastFailedTaskId = task.id;
        _triggerErrorFlash();
      }
    });
  }

  void _triggerErrorFlash() {
    setState(() {
      _showError = true;
    });

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
    _queueSubscription?.cancel();
    _errorFlashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalDownloadChromeVisibility.instance,
      builder: (context, _) {
        final chrome = GlobalDownloadChromeVisibility.instance;
        final isVisible = chrome.isBarVisible;
        final sessionProgress = chrome.sessionProgress;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: isVisible ? 4 : 0,
          child: AnimatedOpacity(
            opacity: isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: AnimatedBuilder(
              animation: _errorColorAnimation,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: sessionProgress,
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
      },
    );
  }
}
