class ServerInfo {
  final String ip;
  final int port;
  final String? sessionId;

  ServerInfo({
    required this.ip,
    required this.port,
    this.sessionId,
  });

  String get baseUrl => 'http://$ip:$port';
  String get wsUrl => 'ws://$ip:$port/ws';

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'sessionId': sessionId,
    };
  }

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      ip: json['ip'],
      port: json['port'],
      sessionId: json['sessionId'],
    );
  }

  ServerInfo copyWith({
    String? ip,
    int? port,
    String? sessionId,
  }) {
    return ServerInfo(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
