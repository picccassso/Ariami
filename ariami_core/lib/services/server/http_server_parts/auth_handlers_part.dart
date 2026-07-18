part of '../http_server.dart';

const int _maxAvatarBytes = 5 * 1024 * 1024;
const String _avatarContentTypeJpeg = 'image/jpeg';
const String _avatarContentTypePng = 'image/png';

class _AvatarRecord {
  const _AvatarRecord({
    required this.file,
    required this.contentType,
    required this.updatedAt,
  });

  final File file;
  final String contentType;
  final int updatedAt;
}

extension AriamiHttpServerAuthHandlersMethods on AriamiHttpServer {
  /// Handle user registration
  Future<Response> _handleAuthRegister(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final password = data['password'] as String?;
      final registrationToken = data['registrationToken'] as String?;

      if (username == null || password == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message': 'username and password are required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      final hasUsers = _authService.hasUsers();
      if (!hasUsers) {
        // The first account becomes the owner/admin, so claiming it must
        // prove local access to the server machine: a loopback/in-process
        // request, a registration token from a locally displayed QR, or the
        // bootstrap code printed on the server's own console.
        final bootstrapCode = data['bootstrapCode'] as String?;
        final authorized = _isLocalRequest(request) ||
            _hasValidRegistrationToken(registrationToken) ||
            _isValidOwnerBootstrapCode(bootstrapCode);
        if (!authorized) {
          return _jsonForbidden({
            'error': {
              'code': AuthErrorCodes.ownerBootstrapRequired,
              'message':
                  'Creating the first (owner) account from another device '
                      'requires the setup code shown on the server console',
            },
          });
        }
      } else if (!_hasValidRegistrationToken(registrationToken)) {
        return _jsonForbidden({
          'error': {
            'code': AuthErrorCodes.registrationClosed,
            'message': 'Registration requires a valid QR registration token',
          },
        });
      }

      final response = await _authService.register(username, password);
      if (registrationToken != null && registrationToken.isNotEmpty) {
        _consumeRegistrationToken(registrationToken);
      }

      // Update auth mode after first user registration; the owner bootstrap
      // code has served its purpose once an owner exists.
      if (_authService.userCount == 1) {
        _ownerBootstrapCode = null;
        updateAuthMode();
      }

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on UserExistsException {
      return Response(
        409,
        body: jsonEncode({
          'error': {
            'code': AuthErrorCodes.userExists,
            'message': 'Username already taken',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response.badRequest(
        body: jsonEncode({
          'error': {
            'code': e.code,
            'message': e.message,
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// List registered usernames for login user-pickers.
  ///
  /// Reachable without auth, but answers only when the owner has enabled the
  /// account picker ([AriamiHttpServer.setPublicUserPickerEnabled]); otherwise
  /// any LAN/tailnet device could enumerate household accounts. Clients treat
  /// the 403 as "use manual sign-in".
  Response _handleAuthUsers(Request request) {
    if (!_publicUserPickerEnabled) {
      return _jsonForbidden({
        'error': {
          'code': AuthErrorCodes.userPickerDisabled,
          'message': 'The account picker is disabled on this server',
        },
      });
    }

    final users = _authService.getUsers().toList()
      ..sort((a, b) =>
          a.username.toLowerCase().compareTo(b.username.toLowerCase()));

    final rows = users
        .map((user) => <String, dynamic>{
              'username': user.username,
              ..._avatarSummaryForUser(user.userId),
            })
        .toList(growable: false);

    return _jsonOk({'users': rows});
  }

  /// Serve a login-picker avatar for a registered username.
  ///
  /// Gated with the account picker; 404 when disabled so the endpoint can't
  /// be used to probe which usernames exist.
  Response _handlePublicUserAvatar(Request request, String username) {
    if (!_publicUserPickerEnabled) {
      return Response.notFound('');
    }

    final decodedUsername = Uri.decodeComponent(username);
    User? user;
    for (final candidate in _authService.getUsers()) {
      if (candidate.username == decodedUsername) {
        user = candidate;
        break;
      }
    }

    if (user == null) {
      return Response.notFound('');
    }

    return _avatarImageResponseForUser(user.userId) ?? Response.notFound('');
  }

  /// Handle user login
  Future<Response> _handleAuthLogin(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final username = data['username'] as String?;
      final password = data['password'] as String?;
      final deviceId = data['deviceId'] as String?;
      final deviceName = data['deviceName'] as String?;
      final allowOtherDeviceTakeover = data['allowOtherDeviceTakeover'] == true;

      if (username == null ||
          password == null ||
          deviceId == null ||
          deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': {
              'code': 'INVALID_REQUEST',
              'message':
                  'username, password, deviceId, and deviceName are required',
            },
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // A user-renamed device keeps its custom display name across logins;
      // classification below still uses the reported name.
      final effectiveDeviceName = _effectiveDeviceName(deviceId, deviceName);
      final response = await _authService.login(
        username,
        password,
        deviceId,
        effectiveDeviceName,
        rateLimitKey: AuthService.buildLoginRateLimitKey(
          clientIp: _clientIp(request),
          username: username,
        ),
        allowOtherDeviceTakeover: allowOtherDeviceTakeover,
      );

      // Register client connection
      final presenceClientType = AuthService.isDashboardControlDevice(
              deviceId: deviceId, deviceName: deviceName)
          ? 'dashboard'
          : null;
      _connectionManager.registerClient(
        deviceId,
        effectiveDeviceName,
        userId: response.userId,
        clientType: presenceClientType,
      );

      // Broadcast client connection
      broadcastWebSocketMessage(ClientConnectedMessage(
        clientCount: _connectionManager.clientCount,
        deviceName: effectiveDeviceName,
      ));

      return Response.ok(
        jsonEncode(response.toJson()),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response(
        _statusForAuthException(e.code),
        body: jsonEncode({
          'error': {
            'code': e.code,
            'message': e.message,
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  }

  /// Map a login [AuthException] code to its HTTP status.
  int _statusForAuthException(String code) {
    switch (code) {
      case AuthErrorCodes.rateLimited:
        return HttpStatus.tooManyRequests;
      // A login blocked because the account is signed in elsewhere is a
      // conflict the client can resolve by retrying with a confirmed takeover,
      // not an authentication failure — keep it distinct from 401.
      case AuthErrorCodes.alreadyLoggedInOtherDevice:
        return HttpStatus.conflict;
      default:
        return HttpStatus.unauthorized;
    }
  }

  /// Handle user logout
  Future<Response> _handleAuthLogout(Request request) async {
    // Session is attached by auth middleware
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    // Revoke session
    final response = await _authService.logout(session.sessionToken);

    // Revoke any stream tickets for this session
    _streamTracker.revokeSessionTickets(session.sessionToken);

    // Unregister client connection
    final client = _connectionManager.getClient(session.deviceId);
    _connectionManager.unregisterClient(session.deviceId);

    // Broadcast client disconnection
    broadcastWebSocketMessage(ClientDisconnectedMessage(
      clientCount: _connectionManager.clientCount,
      deviceName: client?.deviceName,
    ));

    return Response.ok(
      jsonEncode(response.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Handle get current user info
  Response _handleGetMe(Request request) {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return Response.unauthorized(
        jsonEncode({
          'error': {
            'code': AuthErrorCodes.authRequired,
            'message': 'Not authenticated',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    final user = _authService.getUserById(session.userId);
    if (user == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'USER_NOT_FOUND',
            'message': 'User not found',
          },
        }),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }

    return Response.ok(
      jsonEncode({
        'userId': user.userId,
        'username': user.username,
        'deviceId': session.deviceId,
        'deviceName': session.deviceName,
        'isAdmin': _authService.isAdminUser(session.userId),
        ..._avatarSummaryForUser(user.userId),
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handlePutMeAvatar(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _authRequiredResponse();
    }

    final contentType = request.mimeType;
    if (contentType != _avatarContentTypeJpeg &&
        contentType != _avatarContentTypePng) {
      return _badAvatarResponse();
    }

    final declaredLength = request.contentLength;
    if (declaredLength != null && declaredLength > _maxAvatarBytes) {
      await request.read().drain<void>();
      return _avatarTooLargeResponse();
    }

    // On overflow the rest of the body is drained without buffering;
    // responding mid-upload severs the connection before the client can
    // read the 413.
    final bytesBuilder = BytesBuilder(copy: false);
    var totalBytes = 0;
    var tooLarge = false;
    await for (final chunk in request.read()) {
      if (tooLarge) continue;
      totalBytes += chunk.length;
      if (totalBytes > _maxAvatarBytes) {
        tooLarge = true;
        bytesBuilder.clear();
        continue;
      }
      bytesBuilder.add(chunk);
    }
    if (tooLarge) {
      return _avatarTooLargeResponse();
    }

    final bytes = bytesBuilder.takeBytes();
    if (!_avatarMagicMatches(bytes, contentType)) {
      return _badAvatarResponse();
    }

    final avatarUpdatedAt = await _writeAvatarBytes(
      userId: session.userId,
      bytes: bytes,
      contentType: contentType!,
    );
    return _jsonOk({'avatarUpdatedAt': avatarUpdatedAt});
  }

  Response _handleGetMeAvatar(Request request) {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _authRequiredResponse();
    }

    return _avatarImageResponseForUser(session.userId) ?? Response.notFound('');
  }

  Future<Response> _handleDeleteMeAvatar(Request request) async {
    final session = request.context['session'] as Session?;
    if (session == null) {
      return _authRequiredResponse();
    }

    await _deleteAvatarFiles(session.userId);
    return _jsonOk({});
  }

  Response? _avatarImageResponseForUser(String userId) {
    final avatar = _avatarRecordForUser(userId);
    if (avatar == null) {
      return null;
    }

    return Response.ok(
      avatar.file.openRead(),
      headers: {
        'Content-Type': avatar.contentType,
        'Content-Length': avatar.file.lengthSync().toString(),
      },
    );
  }

  Map<String, dynamic> _avatarSummaryForUser(String userId) {
    final avatar = _avatarRecordForUser(userId);
    return {
      'hasAvatar': avatar != null,
      'avatarUpdatedAt': avatar?.updatedAt,
    };
  }

  _AvatarRecord? _avatarRecordForUser(String userId) {
    final directoryPath = _userAvatarsDirectoryPath;
    if (directoryPath == null) {
      return null;
    }

    final jpgFile = File(p.join(directoryPath, '$userId.jpg'));
    if (jpgFile.existsSync()) {
      return _recordFromAvatarFile(jpgFile, _avatarContentTypeJpeg);
    }

    final pngFile = File(p.join(directoryPath, '$userId.png'));
    if (pngFile.existsSync()) {
      return _recordFromAvatarFile(pngFile, _avatarContentTypePng);
    }

    return null;
  }

  _AvatarRecord _recordFromAvatarFile(File file, String contentType) {
    return _AvatarRecord(
      file: file,
      contentType: contentType,
      updatedAt: file.lastModifiedSync().millisecondsSinceEpoch,
    );
  }

  Future<int> _writeAvatarBytes({
    required String userId,
    required List<int> bytes,
    required String contentType,
  }) async {
    final directoryPath = _userAvatarsDirectoryPath;
    if (directoryPath == null) {
      throw StateError('Avatar storage is not initialized.');
    }

    final existingUpdatedAt = _avatarRecordForUser(userId)?.updatedAt;
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final extension = contentType == _avatarContentTypeJpeg ? 'jpg' : 'png';
    final target = File(p.join(directory.path, '$userId.$extension'));
    final temp = File(p.join(
      directory.path,
      '$userId.$extension.${DateTime.now().microsecondsSinceEpoch}.tmp',
    ));

    await temp.writeAsBytes(bytes, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);

    // File mtimes only reliably round-trip whole seconds, and this value is
    // re-read from the mtime later (_recordFromAvatarFile), so it must be
    // second-aligned or the PUT response and subsequent reads disagree.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000;
    final avatarUpdatedAt =
        existingUpdatedAt == null ? now : max(now, existingUpdatedAt + 1000);
    await target.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(avatarUpdatedAt),
    );

    for (final staleExtension in const ['jpg', 'png']) {
      if (staleExtension == extension) continue;
      final staleFile = File(p.join(directory.path, '$userId.$staleExtension'));
      if (await staleFile.exists()) {
        await staleFile.delete();
      }
    }

    return avatarUpdatedAt;
  }

  Future<void> _deleteAvatarFiles(String userId) async {
    final directoryPath = _userAvatarsDirectoryPath;
    if (directoryPath == null) {
      return;
    }

    for (final extension in const ['jpg', 'png']) {
      final file = File(p.join(directoryPath, '$userId.$extension'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  bool _avatarMagicMatches(List<int> bytes, String? contentType) {
    if (contentType == _avatarContentTypeJpeg) {
      return bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
    }

    if (contentType == _avatarContentTypePng) {
      return bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
    }

    return false;
  }

  Response _badAvatarResponse() {
    return _jsonBadRequest({
      'error': {
        'code': 'INVALID_AVATAR',
        'message': 'Avatar must be JPEG or PNG image bytes',
      },
    });
  }

  Response _avatarTooLargeResponse() {
    return _jsonResponse(HttpStatus.requestEntityTooLarge, {
      'error': {
        'code': 'AVATAR_TOO_LARGE',
        'message': 'Avatar image exceeds the 5 MB limit',
      },
    });
  }
}
