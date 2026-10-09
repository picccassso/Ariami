/// Authentication and stream ticket models for multi-user support
library;

class RegisterRequest {
  final String username;
  final String password;
  final String? registrationToken;

  RegisterRequest({
    required this.username,
    required this.password,
    this.registrationToken,
  });

  factory RegisterRequest.fromJson(Map<String, dynamic> json) {
    return RegisterRequest(
      username: json['username'] as String,
      password: json['password'] as String,
      registrationToken: json['registrationToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      if (registrationToken != null) 'registrationToken': registrationToken,
    };
  }
}

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

/// Request for a download ticket (long-lived token for offline downloads).
/// Session token is passed via Authorization header, not in the body.
class DownloadTicketRequest {
  final String songId;
  final String? quality; // Optional: high, medium, low
  final String? format; // Optional: aac, m4a, opus

  DownloadTicketRequest({
    required this.songId,
    this.quality,
    this.format,
  });

  factory DownloadTicketRequest.fromJson(Map<String, dynamic> json) {
    return DownloadTicketRequest(
      songId: json['songId'] as String,
      quality: json['quality'] as String?,
      format: json['format'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      if (quality != null) 'quality': quality,
      if (format != null) 'format': format,
    };
  }
}

class DownloadTicketResponse {
  final String downloadToken;
  final String expiresAt;

  DownloadTicketResponse({
    required this.downloadToken,
    required this.expiresAt,
  });

  factory DownloadTicketResponse.fromJson(Map<String, dynamic> json) {
    return DownloadTicketResponse(
      downloadToken: json['downloadToken'] as String,
      expiresAt: json['expiresAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'downloadToken': downloadToken,
      'expiresAt': expiresAt,
    };
  }
}

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
  static const String lastAdminProtected = 'LAST_ADMIN_PROTECTED';
  static const String registrationClosed = 'REGISTRATION_CLOSED';
  static const String userPickerDisabled = 'USER_PICKER_DISABLED';
  static const String ownerBootstrapRequired = 'OWNER_BOOTSTRAP_REQUIRED';
}
