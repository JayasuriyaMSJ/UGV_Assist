# UGV Assist (`amr_assist`)

A Flutter application for multi-robot ROS 2 control and monitoring across desktop and mobile, built for UGV/AMR fleets over `rosbridge_websocket` (with Zenoh DDS support) and a companion robot HTTP/SSE API.

## Features

- **Multi-Robot Selector (`lib/robot_selector.dart`)**
  - Add, edit, and persist multiple robot profiles (`name`, `ip`, `port` for rosbridge, `apiPort` for the companion Flask API, and optional ROS 2 `namespace`) using `shared_preferences`.
  - Responsive grid layout across portrait, landscape, mobile, and desktop viewports.

- **Workspace & Auto-Discovered Teleop (`lib/robot_workspace.dart`, `lib/robot_controller.dart`)**
  - Connects to the selected robot's rosbridge WebSocket with graceful error handling (no unhandled async socket exceptions).
  - Automatically discovers `geometry_msgs/msg/Twist` velocity topics via `/rosapi/topics`, filtered by the robot's namespace.
  - Responsive joystick controller (`control_pad_plus`) with 20 Hz `Twist` publishing, E-Stop, and keyboard control support.

- **Live Topic Explorer & Safe Heavy-Topic Handling (`lib/services/rosbridge_service.dart`)**
  - Fast, debounced search across 300+ dynamic ROS 2 topics.
  - Tap any topic to inspect live publisher/subscriber node counts (`/rosapi/publishers`, `/rosapi/subscribers`) and live message data.
  - **Serialized `rosapi` queue**: Prevents concurrent service calls from deadlocking single-threaded rosbridge instances (`call_services_in_new_thread: False`).
  - **Heavy-topic protection**: Automatically detects heavy message types (`Image`, `CompressedImage`, `PointCloud2`, `PointCloud`, `LaserScan`, `OccupancyGrid`, `OccupancyGridUpdate`, `Octomap`, `MarkerArray`), skips `jsonDecode` on frames exceeding 24 KB on the UI isolate, throttles subscriptions, and auto-unsubscribes after verifying publishing status.

- **Control & System Info (`lib/widgets/robot_control_info_tab.dart`, `lib/services/robot_api_service.dart`)**
  - Dynamic API port configuration (default `5000`).
  - System telemetry (CPU, RAM, free disk), Docker container & stack management, map/localization SSE updates, sensor URDF offset calibration, and multi-robot placement.

## Project Structure

```text
lib/
├── main.dart                          # App entry point (RobotSelector home)
├── init_dependencies.dart             # Startup initialization
├── ip_fetcher.dart                    # Legacy/helper IP configuration
├── models/
│   └── robot_config.dart              # RobotConfig model & namespace normalization
├── services/
│   ├── rosbridge_service.dart         # Rosbridge WebSocket, serialized rosapi, heavy-topic guard
│   └── robot_api_service.dart         # HTTP + SSE client for the robot Flask API
├── widgets/
│   └── robot_control_info_tab.dart    # Telemetry, Docker/stack controls, calibration & placement
├── robot_selector.dart                # Multi-robot selector front page
├── robot_workspace.dart               # 3-tab workspace (Teleop, Topics, Control & Info)
└── robot_controller.dart              # Joystick & keyboard Twist teleop controller
test/
└── widget_test.dart                   # Unit & responsive widget tests
```

## Getting Started

1. **Install dependencies**
   ```bash
   flutter pub get
   ```

2. **Run tests**
   ```bash
   flutter test
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

4. **Robot Requirements**
   - `rosbridge_websocket` + `rosapi` running on the robot (default port `9090`).
   - Optional companion Flask API running on the robot (default port `5000`, configurable per robot).
