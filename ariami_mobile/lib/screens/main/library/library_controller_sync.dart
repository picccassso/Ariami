part of 'library_controller.dart';

extension _LibraryControllerSync on LibraryController {
  void _setupStreamListeners() {
    _offlineSubscription = _offlineService.offlineModeStream.listen((_) {
      unawaited(_loadLibrary(background: true));
    });

    _connectionSubscription =
        _connectionService.connectionStateStream.listen((isConnected) {
      if (isConnected) {
        unawaited(_loadLibrary(background: true));
        unawaited(_loadDownloadedSongs());
      }
    });

    _cacheSubscription = _cacheManager.cacheUpdateStream.listen((event) {
      if (!event.affectsSongCache) return;
      _scheduleCachedSongsRefresh();
    });

    _downloadSubscription = _downloadManager.queueStream.listen((tasks) {
      _scheduleDownloadedSongsRefresh(tasks);
    });

    _webSocketSubscription = _connectionService.webSocketMessages.listen(
      _handleWebSocketMessage,
    );
  }

  void _handleWebSocketMessage(WsMessage message) {
    if (message.type == WsMessageType.syncTokenAdvanced) {
      final latestToken = _parseLatestToken(message.data?['latestToken']);
      unawaited(_handleSyncTokenAdvanced(latestToken));
      return;
    }

    if (message.type == WsMessageType.libraryUpdated) {
      unawaited(_handleLibraryUpdatedMessage());
    }
  }

  Future<void> _handleSyncTokenAdvanced(int latestToken) async {
    if (!await _isUsingV2LibrarySource()) return;
    if (latestToken > 0 && latestToken <= _lastHandledSyncToken) {
      return;
    }
    final refreshed = await _refreshFromSyncToken(latestToken);
    if (refreshed && latestToken > 0) {
      _lastHandledSyncToken = latestToken;
    }
  }

  Future<void> _handleLibraryUpdatedMessage() async {
    if (await _isUsingV2LibrarySource()) {
      return;
    }

    if (!_durationsPending) return;
    if (_isLibraryLoadInFlight) return;
    if (_durationRetryCount >= LibraryController._maxDurationRetries) return;

    _durationRetryCount++;
    await _loadLibrary(background: true);
  }

  Future<bool> _isUsingV2LibrarySource() async {
    final decision = await _connectionService.libraryReadFacade.resolveSource();
    return decision.source == LibraryReadSource.v2LocalStore;
  }

  int _parseLatestToken(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<bool> _refreshFromSyncToken(int latestToken) async {
    if (_isLibraryLoadInFlight) {
      _pendingBackgroundReload = true;
      return false;
    }
    if (!await _isUsingV2LibrarySource()) return false;

    if (latestToken <= 0) {
      await _loadLibrary(background: true);
      return true;
    }

    for (var attempt = 0; attempt < 10; attempt++) {
      final appliedToken = await _connectionService.libraryReadFacade
          .getActiveLastAppliedToken();
      if (appliedToken != null && appliedToken >= latestToken) {
        await _loadLibrary(background: true);
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    await _loadLibrary(background: true);
    return true;
  }

  void _scheduleDurationRetry() {
    if (_durationRetryCount >= LibraryController._maxDurationRetries) return;

    _durationRetryTimer?.cancel();
    _durationRetryTimer = Timer(LibraryController._durationRetryDelay, () {
      if (!_durationsPending || _isLibraryLoadInFlight) return;
      if (_durationRetryCount >= LibraryController._maxDurationRetries) return;

      _durationRetryCount++;
      unawaited(_loadLibrary(background: true));
    });
  }

  void _clearDurationRetries() {
    _durationsPending = false;
    _durationRetryCount = 0;
    _durationRetryTimer?.cancel();
    _durationRetryTimer = null;
  }
}
