import 'dart:async';
import 'dart:convert';

import 'package:amr_assist/models/robot_config.dart';
import 'package:amr_assist/robot_controller.dart';
import 'package:amr_assist/services/robot_api_service.dart';
import 'package:amr_assist/services/rosbridge_service.dart';
import 'package:amr_assist/widgets/robot_control_info_tab.dart';
import 'package:flutter/material.dart';

class RobotWorkspacePage extends StatefulWidget {
  final RobotConfig robot;
  final RosbridgeService? service;
  final RobotApiService? apiService;

  const RobotWorkspacePage({
    super.key,
    required this.robot,
    this.service,
    this.apiService,
  });

  @override
  State<RobotWorkspacePage> createState() => _RobotWorkspacePageState();
}

class _RobotWorkspacePageState extends State<RobotWorkspacePage> {
  static const Color _accentColor = Color.fromARGB(255, 30, 63, 172);

  late final RosbridgeService _service;
  late final bool _ownsService;

  int _currentTab = 0;
  bool _controlTabMounted = false;
  String? _selectedVelocityTopic;
  String? _discoveryError;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? RosbridgeService();
    _service.addListener(_onServiceChanged);
    _connectAndDiscover();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connectAndDiscover() async {
    setState(() {
      _selectedVelocityTopic = null;
      _discoveryError = null;
    });
    final ok = await _service.connect(widget.robot);
    if (!ok || !mounted) return;
    await _refreshTopics();
  }

  Future<void> _refreshTopics() async {
    if (!_service.isConnected) return;
    setState(() {
      _discoveryError = null;
      _selectedVelocityTopic = null;
    });
    try {
      await _service.discoverTopics();
    } catch (e) {
      if (mounted) {
        setState(() {
          _discoveryError = 'Topic discovery failed (rosapi): $e';
        });
      }
    }
  }

  void _openJoystick(String topic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RobotController(
          service: _service,
          robot: widget.robot,
          topic: topic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      '${widget.robot.name}  •  Teleop',
      '${widget.robot.name}  •  Topics',
      '${widget.robot.name}  •  Control & Info',
    ];

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () {
            _service.disconnect();
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titles[_currentTab],
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'ws://${widget.robot.endpoint}  ${widget.robot.normalizedNamespace.isEmpty ? "(root)" : widget.robot.normalizedNamespace}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _StatusBadge(state: _service.state)),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _currentTab,
          children: [
            _buildTeleopTab(),
            _TopicsExplorerTab(
              robot: widget.robot,
              service: _service,
              onReconnect: _connectAndDiscover,
              onRefresh: _refreshTopics,
            ),
            if (_controlTabMounted)
              RobotControlInfoTab(
                robot: widget.robot,
                apiService: widget.apiService,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() {
          _currentTab = i;
          if (i == 2) _controlTabMounted = true;
        }),
        backgroundColor: Colors.grey[850],
        selectedItemColor: const Color.fromARGB(255, 100, 140, 255),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_esports_outlined),
            activeIcon: Icon(Icons.sports_esports),
            label: 'Teleop',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            activeIcon: Icon(Icons.radar),
            label: 'Topics',
          ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.tune_outlined),
          //   activeIcon: Icon(Icons.tune),
          //   label: 'Control & Info',
          // ),
        ],
      ),
    );
  }

  // ── Tab 0: Teleop (Velocity Topic Selection + Joystick) ────────
  Widget _buildTeleopTab() {
    final velocityTopics = RosbridgeService.filterVelocityTopics(
      _service.topics,
      widget.robot.normalizedNamespace,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sports_esports_outlined,
                    color: Colors.lightBlueAccent,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Velocity Topic Selection',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_service.isConnected)
                    IconButton(
                      tooltip: 'Refresh topics',
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: _service.isDiscoveringTopics
                          ? null
                          : _refreshTopics,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_service.state == RobotConnectionState.connecting)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Connecting to rosbridge...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              else if (_service.state == RobotConnectionState.error ||
                  _service.state == RobotConnectionState.disconnected)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _service.errorMessage ??
                          'Disconnected from ${widget.robot.endpoint}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _connectAndDiscover,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reconnect'),
                    ),
                  ],
                )
              else if (_service.isDiscoveringTopics)
                const Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Discovering geometry_msgs/msg/Twist topics...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              else if (_discoveryError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _discoveryError!,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _refreshTopics,
                      child: const Text('Retry Discovery'),
                    ),
                  ],
                )
              else if (velocityTopics.isEmpty)
                Text(
                  'No geometry_msgs/msg/Twist topics found for ${widget.robot.normalizedNamespace.isEmpty ? "root namespace" : widget.robot.normalizedNamespace}.',
                  style: const TextStyle(color: Colors.white54),
                )
              else ...[
                const Text(
                  'Select the velocity topic to control:',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ...velocityTopics.map((t) {
                  final selected = _selectedVelocityTopic == t.name;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected
                          ? _accentColor.withValues(alpha: 0.35)
                          : Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? Colors.lightBlueAccent
                                : Colors.white12,
                          ),
                        ),
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? Colors.lightBlueAccent
                              : Colors.white38,
                        ),
                        title: Text(
                          t.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          t.type,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        onTap: () =>
                            setState(() => _selectedVelocityTopic = t.name),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _selectedVelocityTopic == null
                        ? null
                        : () => _openJoystick(_selectedVelocityTopic!),
                    icon: const Icon(Icons.sports_esports),
                    label: Text(
                      _selectedVelocityTopic == null
                          ? 'Select a topic above'
                          : 'OPEN JOYSTICK (${_selectedVelocityTopic!})',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      disabledBackgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Tab 1: Isolated, debounced ROS 2 Topic Explorer ──────────────────
class _TopicsExplorerTab extends StatefulWidget {
  final RobotConfig robot;
  final RosbridgeService service;
  final VoidCallback onReconnect;
  final VoidCallback onRefresh;

  const _TopicsExplorerTab({
    required this.robot,
    required this.service,
    required this.onReconnect,
    required this.onRefresh,
  });

  @override
  State<_TopicsExplorerTab> createState() => _TopicsExplorerTabState();
}

class _TopicsExplorerTabState extends State<_TopicsExplorerTab> {
  static const Color _accentColor = Color.fromARGB(255, 30, 63, 172);

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _debouncedQuery = ValueNotifier('');
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _debouncedQuery.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _debouncedQuery.value = value.trim().toLowerCase();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _debouncedQuery.value = '';
  }

  void _openTopicInspector(RosTopicInfo topic) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) =>
          _TopicInspectorSheet(service: widget.service, topic: topic),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.radar_outlined, size: 56, color: Colors.white24),
              const SizedBox(height: 14),
              Text(
                widget.service.errorMessage ??
                    'Not connected to ${widget.robot.endpoint}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: widget.onReconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Reconnect'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search 300+ topics by name or type...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    suffixIcon: ValueListenableBuilder<String>(
                      valueListenable: _debouncedQuery,
                      builder: (_, q, _) =>
                          q.isNotEmpty || _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: _clearSearch,
                            )
                          : const SizedBox.shrink(),
                    ),
                    filled: true,
                    fillColor: Colors.grey[850],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh topics',
                onPressed: widget.service.isDiscoveringTopics
                    ? null
                    : widget.onRefresh,
                icon: widget.service.isDiscoveringTopics
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _debouncedQuery,
            builder: (context, query, _) {
              final allTopics = widget.service.topics;
              final filtered = query.isEmpty
                  ? allTopics
                  : allTopics
                        .where(
                          (t) =>
                              t.nameLower.contains(query) ||
                              t.typeLower.contains(query),
                        )
                        .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${filtered.length} of ${allTopics.length} topics',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Tap to inspect live status',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching topics found.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: filtered.length,
                            itemExtent: 74,
                            itemBuilder: (context, index) {
                              final topic = filtered[index];
                              final isTwist =
                                  topic.type ==
                                  RosbridgeService.twistMessageType;
                              final isHeavy = topic.isHeavy;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openTopicInspector(topic),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[850],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isTwist
                                            ? _accentColor.withValues(
                                                alpha: 0.6,
                                              )
                                            : Colors.white12,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isTwist
                                              ? Icons.sports_esports_outlined
                                              : isHeavy
                                              ? Icons.data_array
                                              : Icons.sensors,
                                          color: isTwist
                                              ? Colors.lightBlueAccent
                                              : isHeavy
                                              ? Colors.orangeAccent
                                              : Colors.white54,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                topic.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontFamily: 'monospace',
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                topic.type.isEmpty
                                                    ? 'unknown type'
                                                    : topic.type,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontFamily: 'monospace',
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isHeavy)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orangeAccent
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.orangeAccent
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: const Text(
                                              'HEAVY',
                                              style: TextStyle(
                                                color: Colors.orangeAccent,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.chevron_right,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final RobotConnectionState state;
  const _StatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    switch (state) {
      case RobotConnectionState.connected:
        color = Colors.greenAccent;
        text = 'Connected';
      case RobotConnectionState.connecting:
        color = Colors.amberAccent;
        text = 'Connecting';
      case RobotConnectionState.error:
        color = Colors.redAccent;
        text = 'Error';
      case RobotConnectionState.disconnected:
        color = Colors.grey;
        text = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Live Topic Inspector (with Pub/Sub polling & safe heavy-topic mode) ──
class _TopicInspectorSheet extends StatefulWidget {
  final RosbridgeService service;
  final RosTopicInfo topic;

  const _TopicInspectorSheet({required this.service, required this.topic});

  @override
  State<_TopicInspectorSheet> createState() => _TopicInspectorSheetState();
}

class _TopicInspectorSheetState extends State<_TopicInspectorSheet> {
  static const int _maxPrettyChars = 6000;
  static const int _heavyAutoStopSamples = 3;

  RosTopicDetails? _details;
  String? _detailsError;
  bool _loadingDetails = true;
  bool _fetchingDetails = false;
  Timer? _detailsTimer;

  StreamSubscription<Map<String, dynamic>>? _topicSub;
  Map<String, dynamic>? _latestMessage;
  DateTime? _lastReceived;
  DateTime? _prevReceived;
  double? _estimatedHz;
  int _sampleCount = 0;
  bool _paused = false;
  bool _streamActive = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    // Heavy topics: pub/sub metadata never changes rapidly — poll once then stop.
    // Light topics: poll every 10s max (was 5s) to avoid queue pile-up.
    if (!widget.topic.isHeavy) {
      _detailsTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _loadDetails(),
      );
    }
    _startSubscription();
  }

  Future<void> _loadDetails() async {
    // Skip if another fetch is already in-flight (either here or discoverTopics).
    if (_fetchingDetails ||
        !widget.service.isConnected ||
        widget.service.hasInflightService) {
      return;
    }
    _fetchingDetails = true;
    try {
      final details = await widget.service.getTopicDetails(widget.topic.name);
      if (mounted) {
        setState(() {
          _details = details;
          _detailsError = null;
          _loadingDetails = false;
        });
      }
      // For heavy topics one successful fetch is enough — cancel the (non-existent)
      // timer since we never started one, but cancel defensively just in case.
      if (widget.topic.isHeavy) {
        _detailsTimer?.cancel();
      }
    } catch (e) {
      // Stop polling if rosapi stops responding so we don't queue blocked calls.
      _detailsTimer?.cancel();
      if (mounted) {
        setState(() {
          _detailsError = 'Unable to load publisher/subscriber counts: $e';
          _loadingDetails = false;
        });
      }
    } finally {
      _fetchingDetails = false;
    }
  }

  void _startSubscription() {
    _topicSub?.cancel();
    setState(() {
      _streamActive = true;
      _paused = false;
      _sampleCount = 0;
    });

    final isHeavy = widget.topic.isHeavy;
    _topicSub = widget.service
        .subscribeTopic(
          widget.topic.name,
          type: widget.topic.type,
          throttleRateMs: isHeavy ? 1000 : 400,
          queueLength: 1,
          metadataOnly: isHeavy,
        )
        .listen((msg) {
          if (_paused || !mounted) return;

          final now = DateTime.now();
          double? hz;
          if (_prevReceived != null) {
            final dtMs = now.difference(_prevReceived!).inMilliseconds;
            if (dtMs > 0) {
              hz = 1000.0 / dtMs;
            }
          }

          setState(() {
            _prevReceived = _lastReceived ?? now;
            _lastReceived = now;
            _estimatedHz = hz;
            _sampleCount++;
            _latestMessage = msg;
          });

          // For heavy topics (camera/pointcloud/map), auto-unsubscribe after
          // verifying publishing status so network & app stay fast.
          if ((isHeavy || msg['_omitted'] == true) &&
              _sampleCount >= _heavyAutoStopSamples) {
            _stopSubscription();
          }
        });
  }

  Future<void> _stopSubscription() async {
    await _topicSub?.cancel();
    _topicSub = null;
    await widget.service.unsubscribeTopic(widget.topic.name);
    if (mounted) {
      setState(() => _streamActive = false);
    }
  }

  @override
  void dispose() {
    _detailsTimer?.cancel();
    _topicSub?.cancel();
    widget.service.unsubscribeTopic(widget.topic.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOmitted = _latestMessage?['_omitted'] == true;
    String? prettyJson;
    if (_latestMessage != null && !isOmitted) {
      final raw = const JsonEncoder.withIndent('  ').convert(_latestMessage);
      prettyJson = raw.length > _maxPrettyChars
          ? '${raw.substring(0, _maxPrettyChars)}\n... (truncated for display)'
          : raw;
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.68,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.topic.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.topic.type,
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.topic.isHeavy && _streamActive)
                    IconButton(
                      tooltip: _paused ? 'Resume stream' : 'Pause stream',
                      icon: Icon(
                        _paused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white70,
                      ),
                      onPressed: () => setState(() => _paused = !_paused),
                    )
                  else
                    IconButton(
                      tooltip: 'Re-check publishing',
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: _startSubscription,
                    ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              if (_loadingDetails)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (_detailsError != null)
                Text(
                  _detailsError!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                )
              else if (_details != null) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _CountChip(
                      label: 'Publishers (live)',
                      count: _details!.publishers.length,
                      color: Colors.greenAccent,
                    ),
                    _CountChip(
                      label: 'Subscribers (live)',
                      count: _details!.subscribers.length,
                      color: Colors.lightBlueAccent,
                    ),
                  ],
                ),
                if (_details!.publishers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Pubs: ${_details!.publishers.join(", ")}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                if (_details!.subscribers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Subs: ${_details!.subscribers.join(", ")}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    widget.topic.isHeavy || isOmitted
                        ? 'PUBLISHING STATUS (METADATA ONLY)'
                        : 'LIVE MESSAGE DATA',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const Spacer(),
                  if (_lastReceived != null)
                    Text(
                      'Updated ${_lastReceived!.hour.toString().padLeft(2, '0')}:${_lastReceived!.minute.toString().padLeft(2, '0')}:${_lastReceived!.second.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: isOmitted
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                color: Colors.greenAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Publishing Active ($_sampleCount sample${_sampleCount == 1 ? "" : "s"} received)',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Reason: ${_latestMessage?['_reason'] ?? "Heavy topic"}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (_latestMessage?['_bytes'] != null)
                            Text(
                              'Frame size: ${((_latestMessage!['_bytes'] as num) / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          if (_estimatedHz != null)
                            Text(
                              'Throttled sample rate: ${_estimatedHz!.toStringAsFixed(2)} Hz',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          if (!_streamActive) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Auto-unsubscribed after verification to protect network & app performance.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      )
                    : SelectableText(
                        prettyJson ??
                            'Waiting for messages on ${widget.topic.name}...',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
