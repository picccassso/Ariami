/// Authentication and stream ticket models for multi-user support
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

  factory RegisterRequest.fromJson(Map<String, dynamic> json) {
    return RegisterRequest(
      username: json['username'] as String,
      password: json['password'] as String,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'sessionToken': sessionToken,
    };
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

  factory LoginRequest.fromJson(Map<String, dynamic> json) {
    return LoginRequest(
      username: json['username'] as String,
      password: json['password'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'sessionToken': sessionToken,
      'expiresAt': expiresAt,
    };
  }
}

/// Request for user logout
class LogoutRequest {
  final String sessionToken;

  LogoutRequest({required this.sessionToken});

  factory LogoutRequest.fromJson(Map<String, dynamic> json) {
    return LogoutRequest(
      sessionToken: json['sessionToken'] as String,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'success': success,
    };
  }
}

// ============================================================================
// STREAM TICKET MODELS
// ============================================================================

/// Request for a stream ticket (short-lived token for audio streaming)
/// Session token is passed via Authorization header, not in the body
class StreamTicketRequest {
  final String songId;
  final String? quality; // Optional: high, medium, low

  StreamTicketRequest({
    required this.songId,
    this.quality,
  });

  factory StreamTicketRequest.fromJson(Map<String, dynamic> json) {
    return StreamTicketRequest(
      songId: json['songId'] as String,
      quality: json['quality'] as String?,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
      'streamToken': streamToken,
      'expiresAt': expiresAt,
    };
  }
}

// ============================================================================
// USER AND SESSION STORAGE MODELS
// ============================================================================

/// User account stored on server
class User {
  final String userId;
  final String username;
  final String passwordHash;
  final String createdAt;

  User({
    required this.userId,
    required this.username,
    required this.passwordHash,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['userId'] as String,
      username: json['username'] as String,
      passwordHash: json['passwordHash'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'passwordHash': passwordHash,
      'createdAt': createdAt,
    };
  }
}

/// Active session stored on server
class Session {
  final String sessionToken;
  final String userId;
  final String deviceId;
  final String deviceName;
  final String createdAt;
  final String expiresAt;

  Session({
    required this.sessionToken,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      sessionToken: json['sessionToken'] as String,
      userId: json['userId'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      createdAt: json['createdAt'] as String,
      expiresAt: json['expiresAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionToken': sessionToken,
      'userId': userId,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
    };
  }
}

// ============================================================================
// AUTH ERROR CODES
// ============================================================================

class AuthErrorCodes {
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String userExists = 'USER_EXISTS';
  static const String alreadyLoggedInOtherDevice =
      'ALREADY_LOGGED_IN_OTHER_DEVICE';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String streamTokenExpired = 'STREAM_TOKEN_EXPIRED';
  static const String authRequired = 'AUTH_REQUIRED';
  static const String forbiddenAdmin = 'FORBIDDEN_ADMIN';
  static const String rateLimited = 'RATE_LIMITED';
}
