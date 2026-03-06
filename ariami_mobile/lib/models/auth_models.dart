/// Authentication models for multi-user support (mobile client)
library;

// ============================================================================
// AUTHENTICATION REQUEST/RESPONSE MODELS
// ============================================================================

/// Request for user registration
class RegisterRequest {
  final String username;
  final String password;

  RegisterRequest({
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
    };
  }
}

/// Response for successful registration
class RegisterResponse {
  final String userId;
  final String username;
  final String sessionToken;

  RegisterResponse({
    required this.userId,
    required this.username,
    required this.sessionToken,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    return RegisterResponse(
      userId: json['userId'] as String,
      username: json['username'] as String,
      sessionToken: json['sessionToken'] as String,
    );
  }
}

/// Request for user login
class LoginRequest {
  final String username;
  final String password;
  final String deviceId;
  final String deviceName;

  LoginRequest({
    required this.username,
    required this.password,
    required this.deviceId,
    required this.deviceName,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'deviceId': deviceId,
      'deviceName': deviceName,
    };
  }
}

/// Response for successful login
class LoginResponse {
  final String userId;
  final String username;
  final String sessionToken;
  final String expiresAt;

  LoginResponse({
    required this.userId,
    required this.username,
    required this.sessionToken,
    required this.expiresAt,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      userId: json['userId'] as String,
      username: json['username'] as String,
      sessionToken: json['sessionToken'] as String,
      expiresAt: json['expiresAt'] as String,
    );
  }
}

/// Request for user logout
class LogoutRequest {
  final String sessionToken;

  LogoutRequest({required this.sessionToken});

  Map<String, dynamic> toJson() {
    return {
      'sessionToken': sessionToken,
    };
  }
}

/// Response for logout
class LogoutResponse {
  final bool success;

  LogoutResponse({required this.success});

  factory LogoutResponse.fromJson(Map<String, dynamic> json) {
    return LogoutResponse(
      success: json['success'] as bool,
    );
  }
}

// ============================================================================
// STREAM TICKET MODELS
// ============================================================================

/// Request for a stream ticket (short-lived token for audio streaming)
class StreamTicketRequest {
  final String songId;
  final String? quality;

  StreamTicketRequest({
    required this.songId,
    this.quality,
  });

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      if (quality != null) 'quality': quality,
    };
  }
}

/// Response with stream ticket
class StreamTicketResponse {
  final String streamToken;
  final String expiresAt;

  StreamTicketResponse({
    required this.streamToken,
    required this.expiresAt,
  });

  factory StreamTicketResponse.fromJson(Map<String, dynamic> json) {
    return StreamTicketResponse(
      streamToken: json['streamToken'] as String,
      expiresAt: json['expiresAt'] as String,
    );
  }
}
