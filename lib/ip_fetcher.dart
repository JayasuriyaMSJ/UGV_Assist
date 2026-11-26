import 'package:amr_assist/robot_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IpFetcher extends StatefulWidget {
  const IpFetcher({super.key});

  @override
  State<IpFetcher> createState() => _IpFetcherState();
}

class _IpFetcherState extends State<IpFetcher> {
  final TextEditingController _ipController = TextEditingController();
  late SharedPreferences prefs;
  bool _isConnecting = false;
  String? _error;

  final String PREFS_IP_KEY = 'ip_address';

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    prefs = await SharedPreferences.getInstance();

    final savedIp = prefs.getString(PREFS_IP_KEY);

    print(savedIp);

    setState(() {
      _ipController.text = savedIp ?? '192.168.';
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  // Basic IP format validation
  bool _isValidIp(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  void _connect() {
    final ip = _ipController.text.trim();

    if (ip.isEmpty) {
      setState(() => _error = 'Please enter an IP address');
      return;
    }

    if (!_isValidIp(ip)) {
      setState(() => _error = 'Invalid IP format (e.g. 192.168.1.100)');
      return;
    }

    setState(() {
      _error = null;
      _isConnecting = true;
      prefs.setString(PREFS_IP_KEY, ip);
    });

    // Small delay so the user sees the loading state, then navigate
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isConnecting = false);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RobotSelector()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Icon ──
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[800],
                    border: Border.all(
                      color: const Color.fromARGB(255, 30, 63, 172),
                      width: 2.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.smart_toy_outlined,
                    size: 44,
                    color: Color.fromARGB(255, 30, 63, 172),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Title ──
                const Text(
                  'AMR Assist',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 6),

                // ── Subtitle ──
                const Text(
                  'Robot Fleet Controller',
                  style: TextStyle(fontSize: 14, color: Colors.white54),
                ),

                const SizedBox(height: 40),

                // ── IP Input ──
                TextField(
                  controller: _ipController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                  decoration: InputDecoration(
                    labelText: 'System IP Address',
                    labelStyle: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                    hintText: '192.168.1.100',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.lan_outlined,
                      color: Colors.white38,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color.fromARGB(255, 30, 63, 172),
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                    ),
                    errorText: _error,
                    errorStyle: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.grey[800],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onSubmitted: (_) => _connect(),
                ),

                const SizedBox(height: 24),

                // ── Connect Button ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isConnecting ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 30, 63, 172),
                      disabledBackgroundColor: Colors.grey[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isConnecting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'CONNECT',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 40),

                // ── Footer hint ──
                const Text(
                  'Enter the host machine IP where\nDocker containers are running',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white38,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
