part of '../api_models.dart';

// ============================================================================
// ERROR MODELS
// ============================================================================

/// Error response format
class ApiError {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  ApiError({
    required this.code,
    required this.message,
    this.details,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'details': details,
    };
  }
}

/// Error response wrapper
class ErrorResponse {
  final ApiError error;

  ErrorResponse({required this.error});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    return ErrorResponse(
      error: ApiError.fromJson(json['error'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'error': error.toJson(),
    };
  }
}

// ============================================================================
// ERROR CODES
// ============================================================================

class ApiErrorCodes {
  static const String invalidSession = 'INVALID_SESSION';
  static const String songNotFound = 'SONG_NOT_FOUND';
  static const String albumNotFound = 'ALBUM_NOT_FOUND';
  static const String libraryUpdating = 'LIBRARY_UPDATING';
  static const String serverError = 'SERVER_ERROR';
  static const String invalidRequest = 'INVALID_REQUEST';
  static const String unauthorized = 'UNAUTHORIZED';

  // Auth error codes
  static const String invalidCredentials = 'INVALID_CREDENTIALS';
  static const String userExists = 'USER_EXISTS';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String streamTokenExpired = 'STREAM_TOKEN_EXPIRED';
  static const String authRequired = 'AUTH_REQUIRED';
  static const String rateLimited = 'RATE_LIMITED';
  static const String alreadyLoggedInOtherDevice =
      'ALREADY_LOGGED_IN_OTHER_DEVICE';
}
