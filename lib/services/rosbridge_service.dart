import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amr_assist/models/robot_config.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection lifecycle state for the active robot WebSocket.
enum RobotConnectionState { disconnected, connecting, connected, error }

/// Metadata for a discovered ROS 2 topic.
class RosTopicInfo {
  final String name;
  final String type;
  final String nameLower;
  final String typeLower;

  RosTopicInfo({required this.name, required this.type})
      : nameLower = name.toLowerCase(),
        typeLower = type.toLowerCase();

  bool get isHeavy => RosbridgeService.isHeavyMessageType(type);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RosTopicInfo && name == other.name && type == other.type;

  @override
  int get hashCode => Object.hash(name, type);
}

/// Publisher and subscriber node lists for a single ROS 2 topic.
class RosTopicDetails {
  final List<String> publishers;
  final List<String> subscribers;

  const RosTopicDetails({
    required this.publishers,
    required this.subscribers,
  });
}

/// Manages a single rosbridge WebSocket connection to the currently selected
/// robot, providing `rosapi` topic discovery, on-demand topic inspection, and
/// velocity command publishing.
class RosbridgeService extends ChangeNotifier {
  static const String twistMessageType = 'geometry_msgs/msg/Twist';

  /// Raw JSON character threshold above which `publish` frames are NOT decoded
  /// on the UI isolate to prevent network/memory stalls.
  static const int maxPreviewBytes = 24 * 1024;

  static const Set<String> heavyMessageTypes = {
    'sensor_msgs/msg/Image',
    'sensor_msgs/msg/CompressedImage',
    'sensor_msgs/msg/PointCloud2',
    'sensor_msgs/msg/PointCloud',
    'sensor_msgs/msg/LaserScan',
    'nav_msgs/msg/OccupancyGrid',
    'map_msgs/msg/OccupancyGridUpdate',
    'octomap_msgs/msg/Octomap',
    'visualization_msgs/msg/MarkerArray',
  };

  static bool isHeavyMessageType(String type) =>
      heavyMessageTypes.contains(type);

  static final RegExp _topicHeaderRegex =
      RegExp(r'"topic"\s*:\s*"([^"]+)"');
  static final RegExp _publishOpRegex =
      RegExp(r'"op"\s*:\s*"publish"');

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  RobotConnectionState _state = RobotConnectionState.disconnected;
  String? _errorMessage;
  RobotConfig? _activeRobot;

  List<RosTopicInfo> _topics = const [];
  bool _isDiscoveringTopics = false;

  int _serviceCounter = 0;
  Future<void> _serviceQueue = Future.value();
  int _inflightServiceCount = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingServices = {};
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers =
      {};
  final Set<String> _metadataOnlyTopics = {};

  RobotConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  RobotConfig? get activeRobot => _activeRobot;
  List<RosTopicInfo> get topics => _topics;
  bool get isDiscoveringTopics => _isDiscoveringTopics;
  bool get isConnected => _state == RobotConnectionState.connected;

  /// True when at least one rosapi service call is currently awaiting a
  /// response. Use to avoid queuing additional calls that could pile up behind
  /// a blocked Zenoh query.
  bool get hasInflightService => _inflightServiceCount > 0;

  /// Filters [topics] to those with exact message type `geometry_msgs/msg/Twist`
  /// belonging to [namespace].
  ///
  /// When [namespace] is non-empty (e.g. `/ugv_03`), only topics starting with
  /// `/ugv_03/` are returned, preventing partial matches such as `/ugv_03_extra`.
  /// When [namespace] is empty, root-level topics (e.g. `/cmd_vel`) are returned.
  static List<RosTopicInfo> filterVelocityTopics(
    List<RosTopicInfo> topics,
    String namespace,
  ) {
    final ns = RobotConfig.normalizeNamespace(namespace);
    return topics.where((t) {
      if (t.type != twistMessageType) return false;
      if (ns.isEmpty) {
        return t.name.startsWith('/') && t.name.indexOf('/', 1) == -1;
      }
      return t.name.startsWith('$ns/');
    }).toList();
  }

  /// Connects to [robot]'s rosbridge WebSocket endpoint, disconnecting any
  /// previous connection first. Never throws unhandled async exceptions.
  Future<bool> connect(
    RobotConfig robot, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await disconnect();

    _activeRobot = robot;
    _state = RobotConnectionState.connecting;
    _errorMessage = null;
    _topics = const [];
    notifyListeners();

    final uri = Uri.parse('ws://${robot.ip}:${robot.port}');
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      // Attach stream listener immediately so async socket errors are always
      // caught even if they surface on the stream before `ready` settles.
      _subscription = channel.stream.listen(
        _onMessage,
        onError: _onStreamError,
        onDone: _onStreamDone,
        cancelOnError: false,
      );

      await channel.ready.timeout(timeout);

      // Verify this connection attempt wasn't superseded by disconnect/switch.
      if (_channel != channel) return false;

      _state = RobotConnectionState.connected;
      _errorMessage = null;
      notifyListeners();
      return true;
    } on TimeoutException {
      await _cleanupFailedConnection(
        'Connection timed out (${robot.endpoint})',
      );
      return false;
    } on WebSocketChannelException catch (e) {
      await _cleanupFailedConnection(_formatError(e.message ?? '$e', robot));
      return false;
    } on SocketException catch (e) {
      await _cleanupFailedConnection(_formatError(e.message, robot));
      return false;
    } catch (e) {
      await _cleanupFailedConnection(_formatError('$e', robot));
      return false;
    }
  }

  String _formatError(String raw, RobotConfig robot) {
    if (raw.toLowerCase().contains('connection refused')) {
      return 'Connection refused at ${robot.endpoint}';
    }
    return 'Connection failed (${robot.endpoint}): $raw';
  }

  Future<void> _cleanupFailedConnection(String message) async {
    await _closeSocketOnly();
    _state = RobotConnectionState.error;
    _errorMessage = message;
    notifyListeners();
  }

  /// Cleanly closes the current WebSocket connection and resets session state.
  Future<void> disconnect() async {
    await _closeSocketOnly();
    _activeRobot = null;
    _topics = const [];
    _isDiscoveringTopics = false;
    _state = RobotConnectionState.disconnected;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _closeSocketOnly() async {
    for (final topic in _topicControllers.keys.toList()) {
      _sendJson({'op': 'unsubscribe', 'topic': topic});
      await _topicControllers[topic]?.close();
    }
    _topicControllers.clear();
    _metadataOnlyTopics.clear();

    for (final completer in _pendingServices.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('WebSocket disconnected'));
      }
    }
    _pendingServices.clear();
    // Reset the queue so a timed-out / poisoned chain doesn't block future calls.
    _serviceQueue = Future.value();
    _inflightServiceCount = 0;

    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }

    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {}
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    // Pre-decode guard: never run jsonDecode on multi-KB/MB `publish` frames
    // (cameras, point clouds, occupancy grids) on the UI isolate.
    // `service_response` messages (e.g. /rosapi/topics with 300+ topics) MUST
    // still be decoded even when > maxPreviewBytes.
    if (raw.length > maxPreviewBytes) {
      final head = raw.length > 512 ? raw.substring(0, 512) : raw;
      final tail = raw.length > 256 ? raw.substring(raw.length - 256) : raw;
      if (_publishOpRegex.hasMatch(head) || _publishOpRegex.hasMatch(tail)) {
        final topic = _topicHeaderRegex.firstMatch(head)?.group(1) ??
            _topicHeaderRegex.firstMatch(tail)?.group(1);
        if (topic != null && _topicControllers.containsKey(topic)) {
          final controller = _topicControllers[topic]!;
          if (!controller.isClosed) {
            controller.add({
              '_omitted': true,
              '_bytes': raw.length,
              '_reason':
                  'Payload (${(raw.length / 1024).toStringAsFixed(1)} KB) exceeds preview limit',
            });
          }
        }
        return;
      }
    }

    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final op = msg['op'];
    if (op == 'service_response') {
      final id = msg['id'] as String?;
      if (id != null && _pendingServices.containsKey(id)) {
        final completer = _pendingServices.remove(id)!;
        if (!completer.isCompleted) {
          completer.complete(msg);
        }
      }
    } else if (op == 'publish') {
      final topic = msg['topic'] as String?;
      final payload = msg['msg'];
      if (topic != null && _topicControllers.containsKey(topic)) {
        final controller = _topicControllers[topic]!;
        if (!controller.isClosed) {
          if (_metadataOnlyTopics.contains(topic)) {
            controller.add({
              '_omitted': true,
              '_bytes': raw.length,
              '_reason': 'Heavy message type (metadata-only mode)',
            });
          } else if (payload is Map<String, dynamic>) {
            controller.add(payload);
          }
        }
      }
    }
  }

  void _onStreamError(Object error) {
    if (_state == RobotConnectionState.error ||
        _state == RobotConnectionState.disconnected) {
      return;
    }
    final robot = _activeRobot;
    final msg = robot != null
        ? _formatError('$error', robot)
        : 'WebSocket error: $error';
    _closeSocketOnly();
    _state = RobotConnectionState.error;
    _errorMessage = msg;
    notifyListeners();
  }

  void _onStreamDone() {
    if (_state == RobotConnectionState.disconnected ||
        _state == RobotConnectionState.error) {
      return;
    }
    _closeSocketOnly();
    _state = RobotConnectionState.disconnected;
    notifyListeners();
  }

  void _sendJson(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || _state != RobotConnectionState.connected) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (_) {
      // Ignore write failures during unexpected socket teardown.
    }
  }

  /// Calls a ROS 2 service via rosbridge and awaits its `service_response`.
  /// Calls are serialized so single-threaded rosbridge (`call_services_in_new_thread: False`)
  /// is never hit with concurrent service requests.
  Future<Map<String, dynamic>> callService(
    String service, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final next = _serviceQueue.then((_) => _callServiceInternal(
          service,
          args: args,
          timeout: timeout,
        ));
    _serviceQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<Map<String, dynamic>> _callServiceInternal(
    String service, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected || _channel == null) {
      throw StateError('Not connected to rosbridge');
    }

    final id = 'svc_${++_serviceCounter}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingServices[id] = completer;
    _inflightServiceCount++;

    _sendJson({
      'op': 'call_service',
      'id': id,
      'service': service,
      'args': ?args,
    });

    try {
      final response = await completer.future.timeout(timeout);
      if (response['result'] == false) {
        throw StateError('Service $service returned result=false');
      }
      final values = response['values'];
      return values is Map<String, dynamic> ? values : <String, dynamic>{};
    } finally {
      _pendingServices.remove(id);
      _inflightServiceCount = (_inflightServiceCount - 1).clamp(0, 999999);
    }
  }

  /// Discovers all ROS 2 topics and their message types via `/rosapi/topics`.
  Future<List<RosTopicInfo>> discoverTopics() async {
    if (!isConnected) return [];

    _isDiscoveringTopics = true;
    notifyListeners();

    try {
      final values = await callService(
        '/rosapi/topics',
        timeout: const Duration(seconds: 8),
      );
      final rawTopics = (values['topics'] as List?)?.cast<dynamic>() ?? const [];
      final rawTypes = (values['types'] as List?)?.cast<dynamic>() ?? const [];

      final discovered = <RosTopicInfo>[];
      for (var i = 0; i < rawTopics.length; i++) {
        final name = '${rawTopics[i]}';
        final type = i < rawTypes.length ? '${rawTypes[i]}' : '';
        discovered.add(RosTopicInfo(name: name, type: type));
      }
      discovered.sort((a, b) => a.name.compareTo(b.name));
      _topics = List.unmodifiable(discovered);
      return discovered;
    } finally {
      _isDiscoveringTopics = false;
      notifyListeners();
    }
  }

  /// Fetches publisher and subscriber lists for a single [topic] via `rosapi`
  /// sequentially so rosbridge's service thread is never overloaded.
  ///
  /// Uses a 4-second per-call timeout — tighter than [callService]'s default
  /// 5-second so the two sequential calls complete or fail within 8s total,
  /// matching [discoverTopics]' budget and preventing Zenoh 600s query pile-up.
  Future<RosTopicDetails> getTopicDetails(String topic) async {
    const detailTimeout = Duration(seconds: 4);
    final pubRes = await callService(
      '/rosapi/publishers',
      args: {'topic': topic},
      timeout: detailTimeout,
    );
    final subRes = await callService(
      '/rosapi/subscribers',
      args: {'topic': topic},
      timeout: detailTimeout,
    );

    final pubs = (pubRes['publishers'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];
    final subs = (subRes['subscribers'] as List?)
            ?.map((e) => '$e')
            .toList() ??
        const <String>[];

    return RosTopicDetails(publishers: pubs, subscribers: subs);
  }

  /// Subscribes to a single [topic] for live inspection with rosbridge-side
  /// throttling (`throttle_rate`) and `queue_length: 1` to avoid network lag.
  Stream<Map<String, dynamic>> subscribeTopic(
    String topic, {
    String? type,
    int throttleRateMs = 500,
    int queueLength = 1,
    bool metadataOnly = false,
  }) {
    if (metadataOnly || (type != null && isHeavyMessageType(type))) {
      _metadataOnlyTopics.add(topic);
    }

    final existing = _topicControllers[topic];
    if (existing != null && !existing.isClosed) {
      return existing.stream;
    }

    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _topicControllers[topic] = controller;

    _sendJson({
      'op': 'subscribe',
      'topic': topic,
      if (type != null && type.isNotEmpty) 'type': type,
      'throttle_rate': throttleRateMs,
      'queue_length': queueLength,
    });

    return controller.stream;
  }

  /// Unsubscribes from [topic] and closes its inspection stream.
  Future<void> unsubscribeTopic(String topic) async {
    _metadataOnlyTopics.remove(topic);
    _sendJson({'op': 'unsubscribe', 'topic': topic});
    final controller = _topicControllers.remove(topic);
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  /// Advertises a velocity topic before publishing joystick commands.
  void advertise(String topic, {String type = twistMessageType}) {
    _sendJson({
      'op': 'advertise',
      'topic': topic,
      'type': type,
    });
  }

  /// Unadvertises a velocity topic when leaving the joystick controller.
  void unadvertise(String topic) {
    _sendJson({
      'op': 'unadvertise',
      'topic': topic,
    });
  }

  /// Publishes a `geometry_msgs/msg/Twist` message to [topic].
  void publishTwist(String topic, double linearX, double angularZ) {
    _sendJson({
      'op': 'publish',
      'topic': topic,
      'msg': {
        'linear': {'x': linearX, 'y': 0.0, 'z': 0.0},
        'angular': {'x': 0.0, 'y': 0.0, 'z': angularZ},
      },
    });
  }

  @override
  void dispose() {
    _closeSocketOnly();
    super.dispose();
  }
}
