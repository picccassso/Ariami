part of '../api_models.dart';

// ============================================================================
// CONNECTION MODELS
// ============================================================================

/// Request for connecting a mobile device
class ConnectRequest {
  final String deviceId;
  final String deviceName;
  final String appVersion;
  final String platform;

  ConnectRequest({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.platform,
  });

  factory ConnectRequest.fromJson(Map<String, dynamic> json) {
    return ConnectRequest(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      appVersion: json['appVersion'] as String,
      platform: json['platform'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'appVersion': appVersion,
      'platform': platform,
    };
  }
}

/// Response when device successfully connects
class ConnectResponse {
  final String status;
  final String sessionId;
  final String serverVersion;
  final List<String> features;
  final String? deviceId;

  ConnectResponse({
    required this.status,
    required this.sessionId,
    required this.serverVersion,
    required this.features,
    this.deviceId,
  });

  factory ConnectResponse.fromJson(Map<String, dynamic> json) {
    return ConnectResponse(
      status: json['status'] as String,
      sessionId: json['sessionId'] as String,
      serverVersion: json['serverVersion'] as String,
      features: (json['features'] as List<dynamic>? ?? []).cast<String>(),
      deviceId: json['deviceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'sessionId': sessionId,
      'serverVersion': serverVersion,
      'features': features,
      if (deviceId != null) 'deviceId': deviceId,
    };
  }
}

/// Request for disconnecting a device
class DisconnectRequest {
  final String? deviceId;

  DisconnectRequest({this.deviceId});

  factory DisconnectRequest.fromJson(Map<String, dynamic> json) {
    return DisconnectRequest(
      deviceId: json['deviceId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (deviceId != null) 'deviceId': deviceId,
    };
  }
}

/// Response for disconnect request
class DisconnectResponse {
  final String status;

  DisconnectResponse({required this.status});

  factory DisconnectResponse.fromJson(Map<String, dynamic> json) {
    return DisconnectResponse(
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
    };
  }
}
