import 'dart:convert';

import 'package:amr_assist/models/robot_config.dart';
import 'package:amr_assist/robot_workspace.dart';
import 'package:amr_assist/services/robot_api_service.dart';
import 'package:amr_assist/services/rosbridge_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsRobotsKey = 'robots_list';
const String _prefsLegacyIpKey = 'ip_address';

class RobotSelector extends StatefulWidget {
  final RosbridgeService? service;
  final RobotApiService Function(RobotConfig robot)? apiServiceFactory;

  const RobotSelector({
    super.key,
    this.service,
    this.apiServiceFactory,
  });

  @override
  State<RobotSelector> createState() => _RobotSelectorState();
}

class _RobotSelectorState extends State<RobotSelector> {
  static const Color _accentColor = Color.fromARGB(255, 30, 63, 172);

  List<RobotConfig> _robots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRobots();
  }

  // ── Persistence ────────────────────────────────────────────────
  Future<void> _loadRobots() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyIp = prefs.getString(_prefsLegacyIpKey)?.trim();
    final fallbackIp =
        (legacyIp != null && legacyIp.isNotEmpty) ? legacyIp : '127.0.0.1';

    final raw = prefs.getString(_prefsRobotsKey);
    if (raw == null) {
      _robots = defaultRobots(defaultIp: fallbackIp);
      await _saveRobots();
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _robots = list
            .map(
              (e) => RobotConfig.fromMap(
                Map<String, dynamic>.from(e as Map),
                fallbackIp: fallbackIp,
              ),
            )
            .toList();
      } catch (_) {
        _robots = defaultRobots(defaultIp: fallbackIp);
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveRobots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsRobotsKey,
      jsonEncode(_robots.map((r) => r.toMap()).toList()),
    );
  }

  void _openWorkspace(RobotConfig robot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RobotWorkspacePage(
          robot: robot,
          service: widget.service,
          apiService: widget.apiServiceFactory?.call(robot),
        ),
      ),
    );
  }

  // ── Add / Edit dialog ──────────────────────────────────────────
  Future<void> _openDialog({RobotConfig? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.ip ?? '127.0.0.1');
    final portCtrl = TextEditingController(
      text: existing != null ? existing.port.toString() : '9090',
    );
    final apiPortCtrl = TextEditingController(
      text: existing != null ? existing.apiPort.toString() : '5000',
    );
    final nsCtrl = TextEditingController(text: existing?.namespace ?? '/ugv_');

    final recentNs = _robots
        .map((r) => r.namespace)
        .where((ns) => ns.isNotEmpty)
        .toSet()
        .toList();

    final formKey = GlobalKey<FormState>();
    bool saved = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            existing == null ? 'Add Robot' : 'Edit Robot',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogField(
                      controller: nameCtrl,
                      label: 'Robot Name',
                      hint: 'e.g. UGV-03',
                      icon: Icons.smart_toy_outlined,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    _DialogField(
                      controller: ipCtrl,
                      label: 'IP Address',
                      hint: 'e.g. 192.168.3.66 or 127.0.0.1',
                      icon: Icons.lan_outlined,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!RobotConfig.isValidIp(v)) {
                          return 'Enter a valid IPv4 address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DialogField(
                            controller: portCtrl,
                            label: 'ROS Port',
                            hint: '9090',
                            icon: Icons.settings_ethernet,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              if (n == null || n < 1 || n > 65535) {
                                return '1–65535';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DialogField(
                            controller: apiPortCtrl,
                            label: 'API Port',
                            hint: '5000',
                            icon: Icons.http,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final n = int.tryParse(v ?? '');
                              if (n == null || n < 1 || n > 65535) {
                                return '1–65535';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DialogField(
                      controller: nsCtrl,
                      label: 'Namespace',
                      hint: 'e.g. /ugv_03 (leave empty for root)',
                      icon: Icons.folder_outlined,
                    ),
                    if (recentNs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Recent namespaces:',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: recentNs.map((ns) {
                          return GestureDetector(
                            onTap: () {
                              nsCtrl.text = ns;
                              setStateDialog(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _accentColor,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                ns,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  saved = true;
                  Navigator.pop(ctx);
                }
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (!saved) return;

    final newConfig = RobotConfig(
      name: nameCtrl.text.trim(),
      ip: ipCtrl.text.trim(),
      port: int.parse(portCtrl.text.trim()),
      apiPort: int.parse(apiPortCtrl.text.trim()),
      namespace: RobotConfig.normalizeNamespace(nsCtrl.text),
    );

    setState(() {
      if (index != null) {
        _robots[index] = newConfig;
      } else {
        _robots.add(newConfig);
      }
    });
    await _saveRobots();
  }

  // ── Delete with undo ───────────────────────────────────────────
  Future<void> _deleteRobot(int index) async {
    final removed = _robots[index];
    setState(() => _robots.removeAt(index));
    await _saveRobots();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.grey[800],
        content: Text(
          '${removed.name} removed',
          style: const TextStyle(color: Colors.white),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color.fromARGB(255, 100, 140, 255),
          onPressed: () async {
            setState(() => _robots.insert(index, removed));
            await _saveRobots();
          },
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accentColor.withValues(alpha: 0.6)),
              ),
              child: const Icon(
                Icons.precision_manufacturing_outlined,
                color: Colors.lightBlueAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'AMR_ASSIST',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  letterSpacing: 2.2,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _accentColor),
              )
            : _robots.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.smart_toy_outlined,
                            size: 64,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No robots configured.\nTap Add Robot to create one.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: Colors.white.withValues(alpha: 0.04),
                        child: const Text(
                          'Select a robot to open Teleop, Topics & Controls  •  Long-press to edit or delete',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth <= 32 ||
                                constraints.maxHeight <= 32) {
                              return const SizedBox.shrink();
                            }
                            return GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 88),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 230,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 196,
                              ),
                              itemCount: _robots.length,
                              itemBuilder: (context, index) {
                                final r = _robots[index];
                                return _RobotCard(
                                  robot: r,
                                  onTap: () => _openWorkspace(r),
                                  onEdit: () =>
                                      _openDialog(existing: r, index: index),
                                  onDelete: () => _deleteRobot(index),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Robot',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Individual robot card ──────────────────────────────────────────────
class _RobotCard extends StatelessWidget {
  final RobotConfig robot;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RobotCard({
    required this.robot,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white70),
              title: const Text('Edit', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color.fromARGB(255, 30, 63, 172);
    final hasNs = robot.normalizedNamespace.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => _showOptions(context),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[700],
                border: Border.all(color: accent, width: 2),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 24,
                color: Colors.lightBlueAccent,
              ),
            ),
            Text(
              robot.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                robot.endpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (hasNs)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  robot.normalizedNamespace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.lightBlueAccent,
                    fontFamily: 'monospace',
                  ),
                ),
              )
            else
              const Text(
                'root namespace',
                style: TextStyle(fontSize: 9, color: Colors.white30),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable dialog text field ─────────────────────────────────────────
class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _DialogField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: Colors.grey[800],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: Color.fromARGB(255, 30, 63, 172),
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}
