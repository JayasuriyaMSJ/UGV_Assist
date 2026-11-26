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
  late final bool _ownsApiService;
  bool _loading = true;
  String? _connectionError;

  SystemStats? _stats;
  List<DockerContainerInfo> _containers = [];
  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _ownsApiService = widget.apiService == null;
    _apiService = widget.apiService ?? RobotApiService(widget.robot);
    _loadOverview();
  }

  @override
  void dispose() {
    if (_ownsApiService) {
      _apiService.dispose();
    }
    super.dispose();
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
              hintText: 'e.g. 5051',
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
    if (_ownsApiService) {
      _apiService.dispose();
      _apiService = RobotApiService(widget.robot);
    }

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

    await _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = true;
      _connectionError = null;
    });

    try {
      final stats = await _apiService.getSystemStats();
      final containers = await _apiService
          .getDockerContainers()
          .catchError((_) => <DockerContainerInfo>[]);

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _containers = containers;
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

  void _showContainerLogs(String name) {
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

  void _openSubPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
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
                    onPressed: _loadOverview,
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
      onRefresh: _loadOverview,
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
          _buildConfigPagesCard(),
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
        onPressed: _loadOverview,
      ),
      child: s == null
          ? const Text('No telemetry available',
              style: TextStyle(color: Colors.white54))
          : Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'CPU',
                    value: '${s.cpuPercent.toStringAsFixed(1)}%',
                    color: Colors.lightBlueAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: 'RAM',
                    value: '${s.ramPercent.toStringAsFixed(1)}%',
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: 'Disk Free',
                    value: '${s.diskFreeGb.toStringAsFixed(1)} GB',
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStackControlsCard() {
    return _SectionCard(
      title: 'Robot Stack Control',
      icon: Icons.layers_outlined,
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  _busyAction ? null : () => _confirmAndRunStackAction('start'),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start', overflow: TextOverflow.ellipsis),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _busyAction
                  ? null
                  : () => _confirmAndRunStackAction('restart'),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restart', overflow: TextOverflow.ellipsis),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed:
                  _busyAction ? null : () => _confirmAndRunStackAction('stop'),
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop', overflow: TextOverflow.ellipsis),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
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

  Widget _buildConfigPagesCard() {
    return _SectionCard(
      title: 'Robot Configuration',
      icon: Icons.settings_outlined,
      child: Column(
        children: [
          _NavRow(
            icon: Icons.playlist_play_outlined,
            title: 'Startup Sequence',
            subtitle: 'Enable/disable containers in container_startup.yaml',
            onTap: () => _openSubPage(
              StartupSequencePage(
                robotName: widget.robot.name,
                apiService: _apiService,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 12),
          _NavRow(
            icon: Icons.sensors_outlined,
            title: 'Sensor URDF Offsets',
            subtitle: 'View and calibrate sensor xyz / rpy transforms',
            onTap: () => _openSubPage(
              SensorOffsetsPage(
                robotName: widget.robot.name,
                apiService: _apiService,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 12),
          _NavRow(
            icon: Icons.grid_on_outlined,
            title: 'Multi-Robot Placement',
            subtitle: 'Configure peer x, y, yaw poses',
            onTap: () => _openSubPage(
              RobotPlacementPage(
                robotName: widget.robot.name,
                apiService: _apiService,
              ),
            ),
          ),
        ],
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
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.lightBlueAccent, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}

// ── Shared On-Demand Sub-Page Shell ──────────────────────────────────────────

class _OnDemandSubPage<T> extends StatefulWidget {
  final String title;
  final Future<T> Function() loader;
  final Widget Function(BuildContext context, T data, VoidCallback refresh)
      builder;

  const _OnDemandSubPage({
    required this.title,
    required this.loader,
    required this.builder,
  });

  @override
  State<_OnDemandSubPage<T>> createState() => _OnDemandSubPageState<T>();
}

class _OnDemandSubPageState<T> extends State<_OnDemandSubPage<T>> {
  static const Color _accent = Color.fromARGB(255, 30, 63, 172);

  bool _loading = true;
  String? _error;
  T? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.loader();
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _load,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: widget.builder(context, _data as T, _load),
                  ),
      ),
    );
  }
}

// ── Dedicated On-Demand Configuration Pages ──────────────────────────────────

class StartupSequencePage extends StatelessWidget {
  final String robotName;
  final RobotApiService apiService;

  const StartupSequencePage({
    super.key,
    required this.robotName,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return _OnDemandSubPage<List<StartupContainerConfig>>(
      title: '$robotName • Startup Sequence',
      loader: apiService.getStartupContainers,
      builder: (ctx, containers, refresh) {
        if (containers.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              Center(
                child: Text(
                  'No startup containers found in container_startup.yaml',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          );
        }
        return StatefulBuilder(
          builder: (context, setLocalState) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: containers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = containers[i];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    c.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Order: ${c.order ?? "-"}  •  Wait: ${c.waitTime ?? 0}s',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  value: c.present,
                  activeThumbColor: Colors.lightBlueAccent,
                  onChanged: (val) async {
                    setLocalState(() => c.present = val);
                    try {
                      await apiService.updateStartupContainers({
                        c.name: c.toUpdatePayload(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Updated ${c.name}')),
                        );
                      }
                    } catch (e) {
                      setLocalState(() => c.present = !val);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red.shade900,
                            content: Text('Failed: $e'),
                          ),
                        );
                      }
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class SensorOffsetsPage extends StatelessWidget {
  final String robotName;
  final RobotApiService apiService;

  const SensorOffsetsPage({
    super.key,
    required this.robotName,
    required this.apiService,
  });

  Future<void> _editSensor(
    BuildContext context,
    SensorCalibration sensor,
    VoidCallback onSaved,
  ) async {
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
              _dialogNumField(xCtrl, 'X (m)'),
              _dialogNumField(yCtrl, 'Y (m)'),
              _dialogNumField(zCtrl, 'Z (m)'),
              _dialogNumField(rCtrl, 'Roll (rad)'),
              _dialogNumField(pCtrl, 'Pitch (rad)'),
              _dialogNumField(yawCtrl, 'Yaw (rad)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 30, 63, 172),
            ),
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
      await apiService.updateSensor(sensor);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated ${sensor.name}')),
        );
      }
      onSaved();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Failed to update sensor: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnDemandSubPage<List<SensorCalibration>>(
      title: '$robotName • Sensor Offsets',
      loader: apiService.getSensors,
      builder: (ctx, sensors, refresh) {
        if (sensors.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              Center(
                child: Text(
                  'No sensors loaded from URDF',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          );
        }
        return StatefulBuilder(
          builder: (context, setLocalState) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sensors.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = sensors[i];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'xyz: (${s.x}, ${s.y}, ${s.z})\nrpy: (${s.roll}, ${s.pitch}, ${s.yaw})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: Colors.white70, size: 18),
                    onPressed: () =>
                        _editSensor(context, s, () => setLocalState(() {})),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class RobotPlacementPage extends StatelessWidget {
  final String robotName;
  final RobotApiService apiService;

  const RobotPlacementPage({
    super.key,
    required this.robotName,
    required this.apiService,
  });

  Future<void> _editPeerPose(
    BuildContext context,
    RobotPeerPose peer,
    VoidCallback onSaved,
  ) async {
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
            _dialogNumField(xCtrl, 'X (m)'),
            _dialogNumField(yCtrl, 'Y (m)'),
            _dialogNumField(yawCtrl, 'Yaw (deg)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 30, 63, 172),
            ),
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
      await apiService.updateRobotPeerPose(peer);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated placement for ${peer.robotId}')),
        );
      }
      onSaved();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Failed to update placement: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _OnDemandSubPage<List<RobotPeerPose>>(
      title: '$robotName • Multi-Robot Placement',
      loader: apiService.getRobotPlacement,
      builder: (ctx, peers, refresh) {
        if (peers.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: const [
              Center(
                child: Text(
                  'No peer placement entries found',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          );
        }
        return StatefulBuilder(
          builder: (context, setLocalState) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: peers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = peers[i];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    p.robotId,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
                    onPressed: () =>
                        _editPeerPose(context, p, () => setLocalState(() {})),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Widget _dialogNumField(TextEditingController c, String label) {
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

// ── Shared UI Components ─────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
              fontSize: 15,
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
