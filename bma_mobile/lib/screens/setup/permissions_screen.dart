import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../services/permissions_service.dart';
import '../../services/app_state_service.dart';
import 'dart:io';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final _permissionsService = PermissionsService();
  int _currentStep = 0;
  bool _isProcessing = false;

  // Track permission states
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  PermissionStatus _storageStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissions();
  }

  Future<void> _checkCurrentPermissions() async {
    final notificationStatus =
        await _permissionsService.getNotificationPermissionStatus();
    final storageStatus =
        await _permissionsService.getStoragePermissionStatus();

    setState(() {
      _notificationStatus = notificationStatus;
      _storageStatus = storageStatus;
    });
  }

  Future<void> _requestNotificationPermission() async {
    setState(() {
      _isProcessing = true;
    });

    final status = await _permissionsService.requestNotificationPermission();

    setState(() {
      _notificationStatus = status;
      _isProcessing = false;
    });

    if (status.isGranted) {
      _moveToNextStep();
    } else if (_permissionsService.isPermanentlyDenied(status)) {
      _showPermanentlyDeniedDialog('Notifications');
    }
  }

  Future<void> _requestStoragePermission() async {
    setState(() {
      _isProcessing = true;
    });

    final status = await _permissionsService.requestStoragePermission();

    setState(() {
      _storageStatus = status;
      _isProcessing = false;
    });

    if (status.isGranted) {
      _moveToNextStep();
    } else if (_permissionsService.isPermanentlyDenied(status)) {
      _showPermanentlyDeniedDialog('Storage');
    }
  }

  void _showPermanentlyDeniedDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionName Permission Required'),
        content: Text(
          'Please enable $permissionName permission in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _moveToNextStep() {
    if (_currentStep == 0) {
      // From notification to storage (or finish if iOS)
      if (_permissionsService.isStoragePermissionNeeded()) {
        setState(() {
          _currentStep = 1;
        });
      } else {
        _finishSetup();
      }
    } else {
      // From storage to finish
      _finishSetup();
    }
  }

  void _skipCurrentStep() {
    if (_currentStep == 0) {
      // Skipping notifications
      _showSkipWarning(
        'Limited Functionality',
        'Without notifications, you won\'t see playback controls in your notification panel.',
        () => _moveToNextStep(),
      );
    } else {
      // Skipping storage
      _showSkipWarning(
        'No Offline Playback',
        'Without storage access, you won\'t be able to download music for offline playback.',
        () => _finishSetup(),
      );
    }
  }

  void _showSkipWarning(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Skip Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishSetup() async {
    // Mark setup as complete
    final appStateService = Provider.of<AppStateService>(
      context,
      listen: false,
    );
    await appStateService.markSetupComplete();

    // Navigate to main app
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Permissions'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Progress indicator
              _buildProgressIndicator(),
              const SizedBox(height: 32),

              // Content
              Expanded(
                child: _currentStep == 0
                    ? _buildNotificationPermissionScreen()
                    : _buildStoragePermissionScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final totalSteps =
        _permissionsService.isStoragePermissionNeeded() ? 2 : 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Step ${_currentStep + 1} of $totalSteps',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationPermissionScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon
        Icon(
          Icons.notifications_active,
          size: 120,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(height: 32),

        // Title
        const Text(
          'Notification Permission',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Description
        Text(
          'Show playback controls in notification panel',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Why we need this
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why we need this:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Control playback without opening the app\n'
                '• See what\'s currently playing\n'
                '• Quick access to pause/play, skip tracks',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const Spacer(),

        // Buttons
        _buildActionButtons(
          onAllow: _requestNotificationPermission,
          onSkip: _skipCurrentStep,
          allowText: 'Allow Notifications',
        ),
      ],
    );
  }

  Widget _buildStoragePermissionScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon
        Icon(
          Icons.download_for_offline,
          size: 120,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(height: 32),

        // Title
        const Text(
          'Storage Permission',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Description
        Text(
          'Download music for offline playback',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Why we need this
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why we need this:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Download songs for offline listening\n'
                '• Save mobile data\n'
                '• Listen without internet connection',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const Spacer(),

        // Buttons
        _buildActionButtons(
          onAllow: _requestStoragePermission,
          onSkip: _skipCurrentStep,
          allowText: 'Allow Storage Access',
        ),
      ],
    );
  }

  Widget _buildActionButtons({
    required VoidCallback onAllow,
    required VoidCallback onSkip,
    required String allowText,
  }) {
    return Column(
      children: [
        // Allow button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : onAllow,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    allowText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Skip button
        TextButton(
          onPressed: _isProcessing ? null : onSkip,
          child: const Text(
            'Skip',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}
