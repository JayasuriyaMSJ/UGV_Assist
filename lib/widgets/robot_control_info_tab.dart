import 'dart:async';
import 'dart:convert';

import 'package:amr_assist/models/robot_config.dart';
import 'package:amr_assist/services/robot_api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RobotControlInfoTab extends StatefulWidget {
  final RobotConfig robot;
  final RobotApiService? apiService;

  const RobotControlInfoTab({
    super.key,
    required this.robot,
    this.apiService,
  });

  @override
  State<RobotControlInfoTab> createState() => _RobotControlInfoTabState();
}

class _RobotControlInfoTabState extends State<RobotControlInfoTab> {
  static const Color _accent = Color.fromARGB(255, 30, 63, 172);

  late RobotApiService _apiService;
  bool _loading = true;
  String? _connectionError;

  SystemStats? _stats;
  List<DockerContainerInfo> _containers = [];
  List<String> _mapFiles = [];
  List<StartupContainerConfig> _startupContainers = [];
  List<SensorCalibration> _sensors = [];
  List<RobotPeerPose> _peers = [];

  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? RobotApiService(widget.robot);
    _loadAll();
  }

  Future<void> _editApiPort() async {
    final portCtrl = TextEditingController(text: '${widget.robot.apiPort}');
    final formKey = GlobalKey<FormState>();

    final newPort = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Configure Control API Port',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: portCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'HTTP API Port (${widget.robot.ip})',
              hintText: 'e.g. 5000',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1 || n > 65535) {
                return 'Enter a valid port (1–65535)';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, int.parse(portCtrl.text.trim()));
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (newPort == null || newPort == widget.robot.apiPort) return;

    widget.robot.apiPort = newPort;
    if (widget.apiService == null) {
      _apiService = RobotApiService(widget.robot);
    }

    // Persist updated apiPort in SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('robots_list');
      if (raw != null) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => RobotConfig.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        for (final r in list) {
          if (r.name == widget.robot.name &&
              r.ip == widget.robot.ip &&
              r.port == widget.robot.port) {
            r.apiPort = newPort;
          }
        }
        await prefs.setString(
          'robots_list',
          jsonEncode(list.map((r) => r.toMap()).toList()),
        );
      }
    } catch (_) {}

    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _connectionError = null;
    });

    try {
      final stats = await _apiService.getSystemStats();
      final results = await Future.wait([
        _apiService.getDockerContainers().catchError((_) => <DockerContainerInfo>[]),
        _apiService.listMapFiles().catchError((_) => <String>[]),
        _apiService.getStartupContainers().catchError((_) => <StartupContainerConfig>[]),
        _apiService.getSensors().catchError((_) => <SensorCalibration>[]),
        _apiService.getRobotPlacement().catchError((_) => <RobotPeerPose>[]),
      ]);

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _containers = results[0] as List<DockerContainerInfo>;
        _mapFiles = results[1] as List<String>;
        _startupContainers = results[2] as List<StartupContainerConfig>;
        _sensors = results[3] as List<SensorCalibration>;
        _peers = results[4] as List<RobotPeerPose>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionError =
            'Control API unreachable at ${widget.robot.apiBaseUrl}\n($e)';
        _loading = false;
      });
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red.shade900 : Colors.grey[800],
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _runContainerAction(String name, String action) async {
    setState(() => _busyAction = true);
    try {
      await _apiService.dockerContainerAction(name, action);
      _showSnack('$action executed on $name');
      final updated = await _apiService.getDockerContainers();
      if (mounted) setState(() => _containers = updated);
    } catch (e) {
      _showSnack('Failed to $action $name: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _showContainerLogs(String name) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LogsSheet(apiService: _apiService, name: name),
    );
  }

  Future<void> _confirmAndRunStackAction(String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} Robot Stack?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will run start_containers.py $action on ${widget.robot.name}.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action.toUpperCase()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyAction = true);
    try {
      final msg = await _apiService.runStackAction(action);
      _showSnack(msg);
    } catch (e) {
      _showSnack('Stack $action failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _launchLocalization(String dbName) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LocalizationProgressDialog(
        apiService: _apiService,
        dbName: dbName,
      ),
    );
    await _loadAll();
  }

  Future<void> _editSensor(SensorCalibration sensor) async {
    final xCtrl = TextEditingController(text: sensor.x);
    final yCtrl = TextEditingController(text: sensor.y);
    final zCtrl = TextEditingController(text: sensor.z);
    final rCtrl = TextEditingController(text: sensor.roll);
    final pCtrl = TextEditingController(text: sensor.pitch);
    final yawCtrl = TextEditingController(text: sensor.yaw);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text(
          'Calibrate ${sensor.name}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numField(xCtrl, 'X (m)'),
              _numField(yCtrl, 'Y (m)'),
              _numField(zCtrl, 'Z (m)'),
              _numField(rCtrl, 'Roll (rad)'),
              _numField(pCtrl, 'Pitch (rad)'),
              _numField(yawCtrl, 'Yaw (rad)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    sensor.x = xCtrl.text.trim();
    sensor.y = yCtrl.text.trim();
    sensor.z = zCtrl.text.trim();
    sensor.roll = rCtrl.text.trim();
    sensor.pitch = pCtrl.text.trim();
    sensor.yaw = yawCtrl.text.trim();

    try {
      await _apiService.updateSensor(sensor);
      _showSnack('Updated ${sensor.name}');
      setState(() {});
    } catch (e) {
      _showSnack('Failed to update sensor: $e', error: true);
    }
  }

  Future<void> _editPeerPose(RobotPeerPose peer) async {
    final xCtrl = TextEditingController(text: '${peer.x}');
    final yCtrl = TextEditingController(text: '${peer.y}');
    final yawCtrl = TextEditingController(text: '${peer.yawDeg}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Text(
          'Placement: ${peer.robotId}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField(xCtrl, 'X (m)'),
            _numField(yCtrl, 'Y (m)'),
            _numField(yawCtrl, 'Yaw (deg)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    peer.x = double.tryParse(xCtrl.text.trim()) ?? peer.x;
    peer.y = double.tryParse(yCtrl.text.trim()) ?? peer.y;
    peer.yawDeg = double.tryParse(yawCtrl.text.trim()) ?? peer.yawDeg;

    try {
      await _apiService.updateRobotPeerPose(peer);
      _showSnack('Updated placement for ${peer.robotId}');
      setState(() {});
    } catch (e) {
      _showSnack('Failed to update placement: $e', error: true);
    }
  }

  Widget _numField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: Colors.grey[800],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    if (_connectionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  size: 56, color: Colors.white24),
              const SizedBox(height: 14),
              Text(
                _connectionError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _loadAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Control API'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editApiPort,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text('Change Port (${widget.robot.apiPort})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Control API: ${widget.robot.apiBaseUrl}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editApiPort,
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text('Port ${widget.robot.apiPort}',
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.lightBlueAccent,
                  side: const BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_busyAction) const LinearProgressIndicator(),
          _buildTelemetryCard(),
          const SizedBox(height: 12),
          _buildStackControlsCard(),
          const SizedBox(height: 12),
          _buildDockerCard(),
          const SizedBox(height: 12),
          _buildMapLocalizationCard(),
          const SizedBox(height: 12),
          _buildSensorsCard(),
          const SizedBox(height: 12),
          _buildPlacementCard(),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard() {
    final s = _stats;
    return _SectionCard(
      title: 'System Telemetry',
      icon: Icons.memory_outlined,
      trailing: IconButton(
        icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
        onPressed: _loadAll,
      ),
      child: s == null
          ? const Text('No telemetry available',
              style: TextStyle(color: Colors.white54))
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatTile(
                  label: 'CPU',
                  value: '${s.cpuPercent.toStringAsFixed(1)}%',
                  color: Colors.lightBlueAccent,
                ),
                _StatTile(
                  label: 'RAM',
                  value: '${s.ramPercent.toStringAsFixed(1)}%',
                  color: Colors.orangeAccent,
                ),
                _StatTile(
                  label: 'Disk Free',
                  value: '${s.diskFreeGb.toStringAsFixed(1)} GB',
                  color: Colors.greenAccent,
                ),
              ],
            ),
    );
  }

  Widget _buildStackControlsCard() {
    return _SectionCard(
      title: 'Robot Stack Control',
      icon: Icons.layers_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _busyAction
                    ? null
                    : () => _confirmAndRunStackAction('start'),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start Stack'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _busyAction
                    ? null
                    : () => _confirmAndRunStackAction('restart'),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Restart'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _busyAction
                    ? null
                    : () => _confirmAndRunStackAction('stop'),
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop Stack'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          if (_startupContainers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Startup Sequence (container_startup.yaml)',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 6),
            ..._startupContainers.map(
              (c) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  c.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  'Order: ${c.order ?? "-"}  •  Wait: ${c.waitTime ?? 0}s',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                value: c.present,
                activeThumbColor: Colors.lightBlueAccent,
                onChanged: (val) async {
                  setState(() => c.present = val);
                  try {
                    await _apiService.updateStartupContainers({
                      c.name: c.toUpdatePayload(),
                    });
                    _showSnack('Updated ${c.name}');
                  } catch (e) {
                    _showSnack('Failed: $e', error: true);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDockerCard() {
    return _SectionCard(
      title: 'Docker Containers (${_containers.length})',
      icon: Icons.dns_outlined,
      child: _containers.isEmpty
          ? const Text('No containers reported',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              children: _containers.map((c) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c.isRunning
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            c.status,
                            style: TextStyle(
                              color: c.isRunning
                                  ? Colors.greenAccent
                                  : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (!c.isRunning)
                            _miniBtn('Start', Icons.play_arrow,
                                () => _runContainerAction(c.name, 'start')),
                          if (c.isRunning)
                            _miniBtn('Stop', Icons.stop,
                                () => _runContainerAction(c.name, 'stop')),
                          _miniBtn('Restart', Icons.refresh,
                              () => _runContainerAction(c.name, 'restart')),
                          _miniBtn('Logs', Icons.article_outlined,
                              () => _showContainerLogs(c.name)),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _miniBtn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: _busyAction ? null : onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildMapLocalizationCard() {
    return _SectionCard(
      title: 'Map DBs & Localization Mode',
      icon: Icons.map_outlined,
      child: _mapFiles.isEmpty
          ? const Text('No map files found in /ros2_ws/db',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _mapFiles.map((file) {
                return ActionChip(
                  avatar: const Icon(Icons.my_location,
                      size: 16, color: Colors.lightBlueAccent),
                  label: Text(
                    file,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: Colors.grey[900],
                  onPressed: () => _launchLocalization(file),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildSensorsCard() {
    return _SectionCard(
      title: 'Sensor URDF Offsets (${_sensors.length})',
      icon: Icons.sensors_outlined,
      child: _sensors.isEmpty
          ? const Text('No sensors loaded from URDF',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              children: _sensors.map((s) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'xyz: (${s.x}, ${s.y}, ${s.z})  rpy: (${s.roll}, ${s.pitch}, ${s.yaw})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white70, size: 18),
                    onPressed: () => _editSensor(s),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildPlacementCard() {
    return _SectionCard(
      title: 'Multi-Robot Placement (${_peers.length})',
      icon: Icons.grid_on_outlined,
      child: _peers.isEmpty
          ? const Text('No peer placement entries found',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              children: _peers.map((p) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    p.robotId,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'x: ${p.x},  y: ${p.y},  yaw: ${p.yawDeg}°',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white70, size: 18),
                    onPressed: () => _editPeerPose(p),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.lightBlueAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsSheet extends StatefulWidget {
  final RobotApiService apiService;
  final String name;

  const _LogsSheet({required this.apiService, required this.name});

  @override
  State<_LogsSheet> createState() => _LogsSheetState();
}

class _LogsSheetState extends State<_LogsSheet> {
  String? _logs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final logs = await widget.apiService.getDockerLogs(widget.name);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Logs: ${widget.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: _error != null
                    ? Text(_error!,
                        style: const TextStyle(color: Colors.redAccent))
                    : _logs == null
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            controller: ctrl,
                            child: SelectableText(
                              _logs!.isEmpty ? '(no logs)' : _logs!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
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

class _LocalizationProgressDialog extends StatefulWidget {
  final RobotApiService apiService;
  final String dbName;

  const _LocalizationProgressDialog({
    required this.apiService,
    required this.dbName,
  });

  @override
  State<_LocalizationProgressDialog> createState() =>
      _LocalizationProgressDialogState();
}

class _LocalizationProgressDialogState
    extends State<_LocalizationProgressDialog> {
  final List<LocalizationProgressEvent> _events = [];
  bool _done = false;
  StreamSubscription<LocalizationProgressEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.apiService.startLocalizationMode(widget.dbName).listen(
      (ev) {
        if (!mounted) return;
        setState(() {
          _events.add(ev);
          if (ev.status == 'success' || ev.status == 'error') _done = true;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _events.add(
            LocalizationProgressEvent(status: 'error', message: '$e'),
          );
          _done = true;
        });
      },
      onDone: () {
        if (mounted) setState(() => _done = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text(
        'Localization: ${widget.dbName}',
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_done) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            ..._events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '[${e.status}] ${e.message}',
                  style: TextStyle(
                    color: e.status == 'error'
                        ? Colors.redAccent
                        : e.status == 'success'
                            ? Colors.greenAccent
                            : Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _done ? () => Navigator.pop(context) : null,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
