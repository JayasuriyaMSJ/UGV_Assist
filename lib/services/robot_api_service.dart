import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amr_assist/models/robot_config.dart';

class SystemStats {
  final double cpuPercent;
  final double ramPercent;
  final double diskFreeGb;

  const SystemStats({
    required this.cpuPercent,
    required this.ramPercent,
    required this.diskFreeGb,
  });

  factory SystemStats.fromJson(Map<String, dynamic> json) => SystemStats(
        cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
        ramPercent: (json['ram_percent'] as num?)?.toDouble() ?? 0.0,
        diskFreeGb: (json['disk_free_gb'] as num?)?.toDouble() ?? 0.0,
      );
}

class DockerContainerInfo {
  final String id;
  final String name;
  final String status;
  final String image;

  const DockerContainerInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.image,
  });

  bool get isRunning => status.toLowerCase() == 'running';

  factory DockerContainerInfo.fromJson(Map<String, dynamic> json) =>
      DockerContainerInfo(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        status: '${json['status'] ?? 'unknown'}',
        image: '${json['image'] ?? ''}',
      );
}

class StartupContainerConfig {
  final String name;
  bool present;
  int? order;
  int? waitTime;
  String? waitTopic;

  StartupContainerConfig({
    required this.name,
    required this.present,
    this.order,
    this.waitTime,
    this.waitTopic,
  });

  factory StartupContainerConfig.fromJson(Map<String, dynamic> json) =>
      StartupContainerConfig(
        name: '${json['name'] ?? ''}',
        present: json['present'] == true,
        order: json['order'] is int
            ? json['order'] as int
            : int.tryParse('${json['order']}'),
        waitTime: json['wait_time'] is int
            ? json['wait_time'] as int
            : int.tryParse('${json['wait_time']}'),
        waitTopic: json['wait_topic']?.toString(),
      );

  Map<String, dynamic> toUpdatePayload() => {
        'present': present,
        'order': order?.toString() ?? '',
        'wait_time': waitTime?.toString() ?? '',
        'wait_topic': waitTopic ?? '',
      };
}

class SensorCalibration {
  final String name;
  final String link;
  String x;
  String y;
  String z;
  String roll;
  String pitch;
  String yaw;

  SensorCalibration({
    required this.name,
    required this.link,
    required this.x,
    required this.y,
    required this.z,
    required this.roll,
    required this.pitch,
    required this.yaw,
  });

  factory SensorCalibration.fromJson(Map<String, dynamic> json) =>
      SensorCalibration(
        name: '${json['name'] ?? ''}',
        link: '${json['link'] ?? ''}',
        x: '${json['x'] ?? '0'}',
        y: '${json['y'] ?? '0'}',
        z: '${json['z'] ?? '0'}',
        roll: '${json['roll'] ?? '0'}',
        pitch: '${json['pitch'] ?? '0'}',
        yaw: '${json['yaw'] ?? '0'}',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'x': x,
        'y': y,
        'z': z,
        'roll': roll,
        'pitch': pitch,
        'yaw': yaw,
      };
}

class RobotPeerPose {
  final String robotId;
  double x;
  double y;
  double yawDeg;

  RobotPeerPose({
    required this.robotId,
    required this.x,
    required this.y,
    required this.yawDeg,
  });
}

class LocalizationProgressEvent {
  final String status;
  final String message;

  const LocalizationProgressEvent({
    required this.status,
    required this.message,
  });
}

/// HTTP + SSE client for the UGV Flask UI backend (`/home/suriya/ugv/ui/app.py`).
class RobotApiService {
  final RobotConfig robot;
  final Duration timeout;
  final HttpClient _client;
  bool _disposed = false;

  RobotApiService(
    this.robot, {
    this.timeout = const Duration(seconds: 5),
  }) : _client = HttpClient()
         ..connectionTimeout = timeout
         ..idleTimeout = const Duration(seconds: 15);

  /// Closes the underlying pooled [HttpClient] and idle keep-alive sockets.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: true);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri(
      scheme: 'http',
      host: robot.ip,
      port: robot.apiPort,
      path: path,
      queryParameters: query,
    );
  }

  Future<dynamic> _getJson(String path, [Map<String, String>? query]) async {
    final req = await _client.getUrl(_uri(path, query)).timeout(timeout);
    final res = await req.close().timeout(timeout);
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(body);
    if (res.statusCode >= 400) {
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? 'HTTP ${res.statusCode}')
          : 'HTTP ${res.statusCode}';
      throw HttpException('$msg');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _postJson(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final req = await _client.postUrl(_uri(path)).timeout(timeout);
    req.headers.contentType = ContentType.json;
    if (body != null) {
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(timeout);
    final raw = await res.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw HttpException('Unexpected response (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      final msg = decoded['message'] ?? decoded['error'] ?? 'HTTP ${res.statusCode}';
      throw HttpException('$msg');
    }
    return decoded;
  }

  Future<SystemStats> getSystemStats() async {
    final json = await _getJson('/api/system/stats');
    return SystemStats.fromJson(Map<String, dynamic>.from(json as Map));
  }

  Future<List<DockerContainerInfo>> getDockerContainers() async {
    final json = await _getJson('/api/docker/containers');
    if (json is! List) return [];
    return json
        .map((e) => DockerContainerInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> dockerContainerAction(String name, String action) async {
    await _postJson('/api/docker/$action/$name');
  }

  Future<String> getDockerLogs(String name, {int tail = 100}) async {
    final json = await _getJson('/api/docker/logs/$name', {'tail': '$tail'});
    if (json is Map<String, dynamic>) {
      return '${json['logs'] ?? ''}';
    }
    return '';
  }

  Future<List<String>> listMapFiles() async {
    final json = await _getJson('/api/files');
    if (json is Map && json['files'] is List) {
      return (json['files'] as List).map((e) => '$e').toList();
    }
    return [];
  }

  Stream<LocalizationProgressEvent> startLocalizationMode(String dbName) async* {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final encoded = Uri.encodeComponent(dbName);
      final req = await client
          .getUrl(_uri('/api/docker/localization_mode/$encoded'))
          .timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final res = await req.close().timeout(const Duration(seconds: 60));

      final lines = res.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            yield LocalizationProgressEvent(
              status: '${decoded['status'] ?? 'progress'}',
              message: '${decoded['message'] ?? ''}',
            );
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  Future<List<StartupContainerConfig>> getStartupContainers() async {
    final json = await _getJson('/api/containers');
    if (json is Map && json['data'] is List) {
      return (json['data'] as List)
          .map((e) =>
              StartupContainerConfig.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  Future<void> updateStartupContainers(
    Map<String, Map<String, dynamic>> updates,
  ) async {
    await _postJson('/api/containers', updates);
  }

  Future<String> runStackAction(String action) async {
    final res = await _postJson('/api/containers/action', {'action': action});
    return '${res['message'] ?? 'Executed $action'}';
  }

  Future<List<SensorCalibration>> getSensors() async {
    final json = await _getJson('/api/sensors');
    if (json is Map && json['data'] is List) {
      return (json['data'] as List)
          .map((e) =>
              SensorCalibration.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return [];
  }

  Future<void> updateSensor(SensorCalibration sensor) async {
    await _postJson('/api/sensors', sensor.toJson());
  }

  Future<List<RobotPeerPose>> getRobotPlacement() async {
    final json = await _getJson('/api/robot-placement');
    if (json is Map && json['data'] is Map && json['data']['peers'] is Map) {
      final peers = Map<String, dynamic>.from(json['data']['peers'] as Map);
      return peers.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        return RobotPeerPose(
          robotId: e.key,
          x: (v['x'] as num?)?.toDouble() ?? 0.0,
          y: (v['y'] as num?)?.toDouble() ?? 0.0,
          yawDeg: (v['yaw_deg'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    }
    return [];
  }

  Future<void> updateRobotPeerPose(RobotPeerPose pose) async {
    await _postJson('/api/robot-placement', {
      'robot_id': pose.robotId,
      'x': pose.x,
      'y': pose.y,
      'yaw_deg': pose.yawDeg,
    });
  }
}
