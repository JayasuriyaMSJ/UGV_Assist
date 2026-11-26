import 'dart:async';
import 'dart:io';

import 'package:amr_assist/models/robot_config.dart';
import 'package:amr_assist/robot_controller.dart';
import 'package:amr_assist/robot_selector.dart';
import 'package:amr_assist/robot_workspace.dart';
import 'package:amr_assist/services/robot_api_service.dart';
import 'package:amr_assist/services/rosbridge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRosbridgeService extends RosbridgeService {
  RobotConnectionState _fakeState = RobotConnectionState.disconnected;
  RobotConfig? _fakeRobot;
  List<RosTopicInfo> _fakeTopics = [];
  String? _fakeError;
  final List<String> advertisedTopics = [];
  final List<String> unadvertisedTopics = [];
  final List<String> subscribedTopics = [];
  final List<String> unsubscribedTopics = [];
  final List<(String topic, double linear, double angular)> publishedTwists =
      [];

  Map<String, List<RosTopicInfo>> topicsByEndpoint = {};
  bool shouldFailConnect = false;

  @override
  RobotConnectionState get state => _fakeState;

  @override
  RobotConfig? get activeRobot => _fakeRobot;

  @override
  List<RosTopicInfo> get topics => List.unmodifiable(_fakeTopics);

  @override
  String? get errorMessage => _fakeError;

  @override
  bool get isConnected => _fakeState == RobotConnectionState.connected;

  @override
  Future<bool> connect(
    RobotConfig robot, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _fakeRobot = robot;
    if (shouldFailConnect) {
      _fakeState = RobotConnectionState.error;
      _fakeError = 'Connection refused at ${robot.endpoint}';
      _fakeTopics = [];
      notifyListeners();
      return false;
    }
    _fakeState = RobotConnectionState.connected;
    _fakeError = null;
    _fakeTopics = [];
    notifyListeners();
    return true;
  }

  @override
  Future<void> disconnect() async {
    _fakeState = RobotConnectionState.disconnected;
    _fakeRobot = null;
    _fakeTopics = [];
    _fakeError = null;
    notifyListeners();
  }

  @override
  Future<List<RosTopicInfo>> discoverTopics() async {
    final endpoint = _fakeRobot?.endpoint ?? '';
    _fakeTopics = topicsByEndpoint[endpoint] ?? _fakeTopics;
    notifyListeners();
    return _fakeTopics;
  }

  @override
  Future<RosTopicDetails> getTopicDetails(String topic) async {
    return const RosTopicDetails(
      publishers: ['/nav2_controller'],
      subscribers: ['/robot_base'],
    );
  }

  @override
  Stream<Map<String, dynamic>> subscribeTopic(
    String topic, {
    String? type,
    int throttleRateMs = 500,
    int queueLength = 1,
    bool metadataOnly = false,
  }) {
    subscribedTopics.add(topic);
    if (metadataOnly || (type != null && RosbridgeService.isHeavyMessageType(type))) {
      return Stream.value({
        '_omitted': true,
        '_bytes': 1024 * 512,
        '_reason': 'Heavy message type (metadata-only mode)',
      });
    }
    return Stream.value({
      'linear': {'x': 0.25, 'y': 0.0, 'z': 0.0},
      'angular': {'x': 0.0, 'y': 0.0, 'z': 0.1},
    });
  }

  @override
  Future<void> unsubscribeTopic(String topic) async {
    unsubscribedTopics.add(topic);
  }

  @override
  void advertise(
    String topic, {
    String type = RosbridgeService.twistMessageType,
  }) {
    advertisedTopics.add(topic);
  }

  @override
  void unadvertise(String topic) {
    unadvertisedTopics.add(topic);
  }

  @override
  void publishTwist(String topic, double linearX, double angularZ) {
    publishedTwists.add((topic, linearX, angularZ));
  }
}

class FakeRobotApiService extends RobotApiService {
  FakeRobotApiService(super.robot);

  @override
  Future<SystemStats> getSystemStats() async => const SystemStats(
        cpuPercent: 24.5,
        ramPercent: 51.2,
        diskFreeGb: 42.8,
      );

  @override
  Future<List<DockerContainerInfo>> getDockerContainers() async => const [
        DockerContainerInfo(
          id: 'abc123',
          name: 'slam_localization',
          status: 'running',
          image: 'ugv:latest',
        ),
      ];

  @override
  Future<List<String>> listMapFiles() async => ['warehouse.db'];

  @override
  Future<List<StartupContainerConfig>> getStartupContainers() async => [
        StartupContainerConfig(
          name: 'rosbridge',
          present: true,
          order: 1,
          waitTime: 2,
        ),
      ];

  @override
  Future<List<SensorCalibration>> getSensors() async => [
        SensorCalibration(
          name: 'lidar_joint',
          link: 'lidar_link',
          x: '0.1',
          y: '0',
          z: '0.2',
          roll: '0',
          pitch: '0',
          yaw: '0',
        ),
      ];

  @override
  Future<List<RobotPeerPose>> getRobotPlacement() async => [
        RobotPeerPose(robotId: 'ugv_03', x: 1.5, y: -0.5, yawDeg: 90.0),
      ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RobotConfig & Namespace', () {
    test('normalizes namespaces consistently', () {
      expect(RobotConfig.normalizeNamespace(''), '');
      expect(RobotConfig.normalizeNamespace('/'), '');
      expect(RobotConfig.normalizeNamespace('ugv_03'), '/ugv_03');
      expect(RobotConfig.normalizeNamespace('/ugv_03/'), '/ugv_03');
      expect(RobotConfig.normalizeNamespace('  /ugv_01/// '), '/ugv_01');
    });

    test('validates IPv4 addresses', () {
      expect(RobotConfig.isValidIp('192.168.3.66'), isTrue);
      expect(RobotConfig.isValidIp('127.0.0.1'), isTrue);
      expect(RobotConfig.isValidIp('999.168.1.1'), isFalse);
      expect(RobotConfig.isValidIp('192.168.1'), isFalse);
    });

    test('migrates legacy RobotConfig map with hostPort and missing ip', () {
      final migrated = RobotConfig.fromMap(
        {'name': 'UGV-03', 'hostPort': 9093, 'namespace': '/ugv_03'},
        fallbackIp: '192.168.3.66',
      );
      expect(migrated.name, 'UGV-03');
      expect(migrated.ip, '192.168.3.66');
      expect(migrated.port, 9093);
      expect(migrated.apiPort, 5000);
      expect(migrated.namespace, '/ugv_03');
    });
  });

  group('RosbridgeService topic filtering & error handling', () {
    test('classifies heavy message types for metadata-only inspection', () {
      expect(
        RosbridgeService.isHeavyMessageType('sensor_msgs/msg/Image'),
        isTrue,
      );
      expect(
        RosbridgeService.isHeavyMessageType('sensor_msgs/msg/PointCloud2'),
        isTrue,
      );
      expect(
        RosbridgeService.isHeavyMessageType('nav_msgs/msg/OccupancyGrid'),
        isTrue,
      );
      expect(
        RosbridgeService.isHeavyMessageType('geometry_msgs/msg/Twist'),
        isFalse,
      );
      expect(
        RosbridgeService.isHeavyMessageType('std_msgs/msg/String'),
        isFalse,
      );
    });

    test('filters geometry_msgs/msg/Twist topics with exact namespace match',
        () {
      final allTopics = [
        RosTopicInfo(name: '/ugv_01/cmd_vel', type: 'geometry_msgs/msg/Twist'),
        RosTopicInfo(name: '/ugv_02/cmd_vel', type: 'geometry_msgs/msg/Twist'),
        RosTopicInfo(name: '/ugv_03/cmd_vel', type: 'geometry_msgs/msg/Twist'),
        RosTopicInfo(
          name: '/ugv_03/cmd_vel_nav',
          type: 'geometry_msgs/msg/Twist',
        ),
        RosTopicInfo(
          name: '/ugv_03/cmd_vel_smoothed',
          type: 'geometry_msgs/msg/Twist',
        ),
        RosTopicInfo(
          name: '/ugv_03_extra/cmd_vel',
          type: 'geometry_msgs/msg/Twist',
        ),
        RosTopicInfo(name: '/ugv_03/odom', type: 'nav_msgs/msg/Odometry'),
        RosTopicInfo(name: '/ugv_04/cmd_vel', type: 'geometry_msgs/msg/Twist'),
        RosTopicInfo(name: '/cmd_vel', type: 'geometry_msgs/msg/Twist'),
      ];

      final ugv03 = RosbridgeService.filterVelocityTopics(allTopics, '/ugv_03');
      expect(
        ugv03.map((t) => t.name).toList(),
        ['/ugv_03/cmd_vel', '/ugv_03/cmd_vel_nav', '/ugv_03/cmd_vel_smoothed'],
      );

      final root = RosbridgeService.filterVelocityTopics(allTopics, '');
      expect(root.map((t) => t.name).toList(), ['/cmd_vel']);
    });

    test('connect handles connection refused gracefully without throwing',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final unusedPort = server.port;
      await server.close();

      final service = RosbridgeService();
      addTearDown(service.dispose);

      final ok = await service.connect(
        RobotConfig(
          name: 'TestBot',
          ip: '127.0.0.1',
          port: unusedPort,
          namespace: '/ugv_03',
        ),
        timeout: const Duration(seconds: 2),
      );

      expect(ok, isFalse);
      expect(service.state, RobotConnectionState.error);
      expect(service.errorMessage, isNotNull);
    });
  });

  group('AMR_ASSIST Navigation & Workspace UI', () {
    testWidgets(
      'front page shows AMR_ASSIST without bottom nav, navigates to workspace with 3 tabs',
      (tester) async {
        final fakeService = FakeRosbridgeService();
        fakeService.topicsByEndpoint['127.0.0.1:9093'] = [
          RosTopicInfo(
            name: '/ugv_01/cmd_vel',
            type: 'geometry_msgs/msg/Twist',
          ),
          RosTopicInfo(
            name: '/ugv_03/cmd_vel',
            type: 'geometry_msgs/msg/Twist',
          ),
          RosTopicInfo(
            name: '/ugv_03/cmd_vel_nav',
            type: 'geometry_msgs/msg/Twist',
          ),
          RosTopicInfo(
            name: '/ugv_03/cmd_vel_smoothed',
            type: 'geometry_msgs/msg/Twist',
          ),
          RosTopicInfo(
            name: '/ugv_03/odom',
            type: 'nav_msgs/msg/Odometry',
          ),
          RosTopicInfo(
            name: '/ugv_03/camera/image_raw',
            type: 'sensor_msgs/msg/Image',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: RobotSelector(
              service: fakeService,
              apiServiceFactory: (r) => FakeRobotApiService(r),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('AMR_ASSIST'), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(find.text('UGV-03'), findsOneWidget);

        // Tap UGV-03 to enter RobotWorkspacePage
        await tester.tap(find.text('UGV-03'));
        await tester.pumpAndSettle();

        expect(find.byType(RobotWorkspacePage), findsOneWidget);
        expect(find.byType(BottomNavigationBar), findsOneWidget);
        expect(find.text('Teleop'), findsOneWidget);
        expect(find.text('Topics'), findsOneWidget);
        expect(find.text('Control & Info'), findsOneWidget);

        // Only /ugv_03 Twist topics appear in Teleop tab
        expect(find.text('/ugv_03/cmd_vel'), findsOneWidget);
        expect(find.text('/ugv_03/cmd_vel_nav'), findsOneWidget);
        expect(find.text('/ugv_03/cmd_vel_smoothed'), findsOneWidget);
        expect(find.text('/ugv_01/cmd_vel'), findsNothing);

        // Select /ugv_03/cmd_vel_nav and open joystick
        await tester.tap(find.text('/ugv_03/cmd_vel_nav'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('OPEN JOYSTICK'));
        await tester.pumpAndSettle();

        expect(find.byType(RobotController), findsOneWidget);
        expect(fakeService.advertisedTopics, contains('/ugv_03/cmd_vel_nav'));

        // Back to workspace
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(fakeService.unadvertisedTopics, contains('/ugv_03/cmd_vel_nav'));

        // Switch to Topics tab
        await tester.tap(find.text('Topics'));
        await tester.pumpAndSettle();
        expect(find.text('/ugv_03/odom'), findsOneWidget);
        expect(find.text('HEAVY'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'odom');
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pumpAndSettle();
        expect(find.text('/ugv_03/odom'), findsOneWidget);
        expect(find.text('/ugv_03/cmd_vel_nav'), findsNothing);

        // Switch to Control & Info tab and verify dynamic port button
        await tester.tap(find.text('Control & Info'));
        await tester.pumpAndSettle();
        expect(find.text('System Telemetry'), findsOneWidget);
        expect(find.text('Port 5000'), findsOneWidget);
        expect(find.text('24.5%'), findsOneWidget);
        expect(find.text('slam_localization'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('warehouse.db'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('warehouse.db'), findsOneWidget);
      },
    );

    testWidgets('renders without overflow on mobile, tablet, and desktop sizes',
        (tester) async {
      final fakeService = FakeRosbridgeService();
      final sizes = [
        const Size(360, 640),
        const Size(640, 360),
        const Size(800, 1280),
        const Size(1280, 800),
      ];

      final testRobot = RobotConfig(
        name: 'UGV-03',
        ip: '192.168.3.66',
        port: 9090,
        namespace: '/ugv_03',
      );

      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(home: RobotSelector(service: fakeService)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            home: RobotWorkspacePage(
              robot: testRobot,
              service: fakeService,
              apiService: FakeRobotApiService(testRobot),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            home: RobotController(
              service: fakeService,
              robot: testRobot,
              topic: '/ugv_03/cmd_vel_nav',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
