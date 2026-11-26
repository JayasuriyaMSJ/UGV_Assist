import 'dart:async';
import 'dart:math';

import 'package:amr_assist/models/robot_config.dart';
import 'package:amr_assist/services/rosbridge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RobotController extends StatefulWidget {
  final RosbridgeService service;
  final RobotConfig robot;
  final String topic;

  const RobotController({
    super.key,
    required this.service,
    required this.robot,
    required this.topic,
  });

  @override
  State<RobotController> createState() => _RobotControllerState();
}

class _RobotControllerState extends State<RobotController> {
  double _linearSpeed = 0.0;
  double _angularSpeed = 0.0;
  final double _speedMultiplier = 0.5;

  Timer? _publishTimer;
  DateTime _lastPublishTime = DateTime.now();

  double _lastSentLinear = 0.0;
  double _lastSentAngular = 0.0;

  bool _advertised = false;
  bool _exiting = false;

  // ── Keyboard state ─────────────────────────────────────────────
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);

    if (widget.service.isConnected) {
      widget.service.advertise(widget.topic);
      _advertised = true;
    }

    // 20 Hz publish loop
    _publishTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateKeyboardVelocity();
      if (widget.service.isConnected) _publishVelocity();
    });
  }

  void _onServiceChanged() {
    if (!mounted) return;
    if (widget.service.isConnected && !_advertised) {
      widget.service.advertise(widget.topic);
      _advertised = true;
    }
    setState(() {});
  }

  void _stopAndLeave({bool disconnectSocket = false}) {
    if (_exiting) return;
    _exiting = true;

    _linearSpeed = 0.0;
    _angularSpeed = 0.0;
    _pressedKeys.clear();

    if (widget.service.isConnected) {
      widget.service.publishTwist(widget.topic, 0.0, 0.0);
      if (_advertised) {
        widget.service.unadvertise(widget.topic);
        _advertised = false;
      }
    }

    if (disconnectSocket) {
      widget.service.disconnect();
    }

    if (mounted) Navigator.pop(context);
  }

  void _publishVelocity() {
    if (!widget.service.isConnected) return;

    final currentLinear = _linearSpeed * _speedMultiplier;
    final currentAngular = _angularSpeed * _speedMultiplier;

    // Skip if nothing changed (but always send zeros)
    const threshold = 0.01;
    if ((currentLinear - _lastSentLinear).abs() < threshold &&
        (currentAngular - _lastSentAngular).abs() < threshold &&
        currentLinear != 0.0 &&
        currentAngular != 0.0) {
      return;
    }

    _lastSentLinear = currentLinear;
    _lastSentAngular = currentAngular;

    widget.service.publishTwist(widget.topic, currentLinear, currentAngular);
    _lastPublishTime = DateTime.now();
  }

  void _immediatePublish() {
    if (widget.service.isConnected) _publishVelocity();
  }

  void _triggerEmergencyStop() {
    setState(() {
      _linearSpeed = 0.0;
      _angularSpeed = 0.0;
      _pressedKeys.clear();
    });
    _immediatePublish();
  }

  // ── Keyboard helpers ───────────────────────────────────────────
  bool _isKeyActive(List<LogicalKeyboardKey> keys) =>
      keys.any((k) => _pressedKeys.contains(k));

  void _updateKeyboardVelocity() {
    if (_pressedKeys.isEmpty && _linearSpeed == 0.0 && _angularSpeed == 0.0) {
      return;
    }

    final forward = _isKeyActive([
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.arrowUp,
    ]);
    final backward = _isKeyActive([
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.arrowDown,
    ]);
    final left = _isKeyActive([
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.arrowLeft,
    ]);
    final right = _isKeyActive([
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.arrowRight,
    ]);

    // Only override joystick values when keyboard keys are actively pressed,
    // or when resetting from a keyboard press.
    if (!forward && !backward && !left && !right && _pressedKeys.isEmpty) {
      return;
    }

    double linear = 0.0;
    double angular = 0.0;

    if (forward) linear = 1.0;
    if (backward) linear = -1.0;
    if (left) angular = 1.0;
    if (right) angular = -1.0;

    if (mounted) {
      setState(() {
        _linearSpeed = linear;
        _angularSpeed = angular;
      });
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _triggerEmergencyStop();
        return KeyEventResult.handled;
      }
      _pressedKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
      if (_pressedKeys.isEmpty && mounted) {
        setState(() {
          _linearSpeed = 0.0;
          _angularSpeed = 0.0;
        });
        _immediatePublish();
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _focusNode.dispose();
    _pressedKeys.clear();
    _publishTimer?.cancel();

    if (!_exiting && widget.service.isConnected) {
      widget.service.publishTwist(widget.topic, 0.0, 0.0);
      if (_advertised) {
        widget.service.unadvertise(widget.topic);
      }
    }
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isConnected = widget.service.isConnected;
    final errorMsg = widget.service.errorMessage;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          backgroundColor: Colors.grey[900],
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => _stopAndLeave(disconnectSocket: false),
          ),
          title: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.robot.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.topic,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  widget.robot.endpoint,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!isConnected)
                MaterialBanner(
                  backgroundColor: Colors.red.shade900.withValues(alpha: 0.9),
                  content: Text(
                    errorMsg ?? 'Disconnected from ${widget.robot.endpoint}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        final ok = await widget.service.connect(widget.robot);
                        if (ok && mounted) {
                          widget.service.advertise(widget.topic);
                          _advertised = true;
                        }
                      },
                      child: const Text('RETRY',
                          style: TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                      onPressed: () => _stopAndLeave(disconnectSocket: false),
                      child: const Text('BACK',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPortraitOrNarrow = constraints.maxWidth < 600 ||
                        constraints.maxHeight > constraints.maxWidth * 1.15;

                    if (isPortraitOrNarrow) {
                      return _buildPortraitLayout(constraints);
                    }
                    return _buildLandscapeLayout(constraints);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(BoxConstraints constraints) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    final joystickSize = min(maxW * 0.28, maxH - 115).clamp(84.0, 200.0);
    final compact = maxH < 340;

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _buildLinearJoystick(joystickSize, compact: compact),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.all(compact ? 6 : 12),
            child: SingleChildScrollView(
              child: _buildCenterControls(compact: compact),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _buildAngularJoystick(joystickSize, compact: compact),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(BoxConstraints constraints) {
    final maxW = constraints.maxWidth;
    final maxH = constraints.maxHeight;
    final joystickSize = min(maxW * 0.36, maxH * 0.28).clamp(84.0, 175.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildLinearJoystick(joystickSize, compact: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAngularJoystick(joystickSize, compact: true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCenterControls(compact: true),
        ],
      ),
    );
  }

  Widget _buildLinearJoystick(double size, {required bool compact}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'FORWARD / BACKWARD',
            style: TextStyle(
              fontSize: compact ? 12 : 15,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 14),
        CustomJoystick(
          size: size,
          onChanged: (x, y) {
            setState(() {
              _linearSpeed = -y * 1.0;
            });
            _immediatePublish();
          },
          backgroundColor: Colors.blue.withValues(alpha: 0.2),
          knobColor: Colors.blue,
        ),
        SizedBox(height: compact ? 8 : 12),
        _SpeedBadge(
          label: 'Linear',
          value: _linearSpeed * _speedMultiplier,
          unit: 'm/s',
          color: Colors.blue,
          lastPublish: _lastPublishTime,
          compact: compact,
        ),
      ],
    );
  }

  Widget _buildAngularJoystick(double size, {required bool compact}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'TURN LEFT / RIGHT',
            style: TextStyle(
              fontSize: compact ? 12 : 15,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 14),
        CustomJoystick(
          size: size,
          onChanged: (x, y) {
            setState(() {
              _angularSpeed = -x * 2.0;
            });
            _immediatePublish();
          },
          backgroundColor: Colors.orange.withValues(alpha: 0.2),
          knobColor: Colors.orange,
        ),
        SizedBox(height: compact ? 8 : 12),
        _SpeedBadge(
          label: 'Angular',
          value: _angularSpeed * _speedMultiplier,
          unit: 'rad/s',
          color: Colors.orange,
          lastPublish: _lastPublishTime,
          compact: compact,
        ),
      ],
    );
  }

  Widget _buildCenterControls({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SpeedSliderPanel(value: _speedMultiplier, compact: compact),
        SizedBox(height: compact ? 10 : 14),
        SizedBox(
          width: double.infinity,
          height: compact ? 54 : 64,
          child: ElevatedButton(
            onPressed: _triggerEmergencyStop,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emergency, size: compact ? 22 : 26),
                  const SizedBox(height: 2),
                  const Text(
                    'EMERGENCY STOP',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        const _KeyboardHintsPanel(),
        SizedBox(height: compact ? 10 : 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () => _stopAndLeave(disconnectSocket: true),
            icon: const Icon(Icons.power_off, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('DISCONNECT'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[700],
              foregroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Keyboard hints panel ───────────────────────────────────────────────────
class _KeyboardHintsPanel extends StatelessWidget {
  const _KeyboardHintsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'KEYBOARD CONTROLS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
          ),
          SizedBox(height: 8),
          _KeyRow(keys: ['W', '↑'], label: 'Forward'),
          _KeyRow(keys: ['S', '↓'], label: 'Backward'),
          _KeyRow(keys: ['A', '←'], label: 'Turn Left'),
          _KeyRow(keys: ['D', '→'], label: 'Turn Right'),
          _KeyRow(keys: ['Space'], label: 'E-Stop'),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final String label;
  const _KeyRow({required this.keys, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: keys
                .map(
                  (k) => Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      k,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Reusable speed badge below each joystick ──────────────────────
class _SpeedBadge extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final DateTime lastPublish;
  final bool compact;

  const _SpeedBadge({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.lastPublish,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 16,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            Text(
              '$label: ${value.toStringAsFixed(2)} $unit',
              style: TextStyle(
                fontSize: compact ? 13 : 15,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Latency: ${DateTime.now().difference(lastPublish).inMilliseconds}ms',
              style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Speed slider panel ─────────────────────────────────────────────
class _SpeedSliderPanel extends StatelessWidget {
  final double value;
  final bool compact;

  const _SpeedSliderPanel({required this.value, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'SPEED CONTROL LOCKED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom Joystick widget ─────────────────────────────────────────
class CustomJoystick extends StatefulWidget {
  final double size;
  final Function(double x, double y) onChanged;
  final Color backgroundColor;
  final Color knobColor;

  const CustomJoystick({
    super.key,
    required this.size,
    required this.onChanged,
    required this.backgroundColor,
    required this.knobColor,
  });

  @override
  State<CustomJoystick> createState() => _CustomJoystickState();
}

class _CustomJoystickState extends State<CustomJoystick> {
  double _x = 0;
  double _y = 0;

  void _updatePosition(Offset localPosition) {
    final center = widget.size / 2;
    final dx = localPosition.dx - center;
    final dy = localPosition.dy - center;
    final distance = sqrt(dx * dx + dy * dy);
    final maxDistance = center * 0.8;

    if (distance > maxDistance) {
      final angle = atan2(dy, dx);
      _x = cos(angle) * maxDistance / center;
      _y = sin(angle) * maxDistance / center;
    } else {
      _x = dx / center;
      _y = dy / center;
    }

    if (mounted) setState(() {});
    widget.onChanged(_x, _y);
  }

  void _resetPosition() {
    _x = 0;
    _y = 0;
    if (mounted) setState(() {});
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => _updatePosition(d.localPosition),
      onPanUpdate: (d) => _updatePosition(d.localPosition),
      onPanEnd: (_) => _resetPosition(),
      onPanCancel: () => _resetPosition(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.backgroundColor,
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _CrossPainter(),
            ),
            Transform.translate(
              offset: Offset(_x * widget.size * 0.4, _y * widget.size * 0.4),
              child: Container(
                width: widget.size * 0.3,
                height: widget.size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.knobColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(size.width * 0.2, size.height / 2),
      Offset(size.width * 0.8, size.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * 0.2),
      Offset(size.width / 2, size.height * 0.8),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
