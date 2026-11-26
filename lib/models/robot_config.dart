/// Configuration for a single ROS 2 robot / simulation instance.
class RobotConfig {
  String name;
  String ip;
  int port;
  int apiPort;
  String namespace;

  RobotConfig({
    required this.name,
    required this.ip,
    required this.port,
    this.apiPort = 5000,
    required this.namespace,
  });

  /// Returns a normalized namespace (e.g. `/ugv_03` or `''` if empty).
  String get normalizedNamespace => normalizeNamespace(namespace);

  /// Human-readable WebSocket endpoint.
  String get endpoint => '$ip:$port';

  /// Human-readable Flask UI API base URL.
  String get apiBaseUrl => 'http://$ip:$apiPort';

  /// Normalizes a ROS 2 namespace so it has a single leading `/` and no
  /// trailing `/`, or returns `''` for root/empty namespaces.
  static String normalizeNamespace(String raw) {
    var ns = raw.trim();
    if (ns.isEmpty || ns == '/') return '';
    if (!ns.startsWith('/')) ns = '/$ns';
    while (ns.length > 1 && ns.endsWith('/')) {
      ns = ns.substring(0, ns.length - 1);
    }
    return ns;
  }

  /// Validates an IPv4 address string.
  static bool isValidIp(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  factory RobotConfig.fromMap(
    Map<String, dynamic> m, {
    String fallbackIp = '127.0.0.1',
  }) {
    final rawIp = (m['ip'] as String?)?.trim();
    final rawPort = m['port'] ?? m['hostPort'];
    final rawApiPort = m['apiPort'];
    return RobotConfig(
      name: (m['name'] as String?) ?? 'Robot',
      ip: (rawIp != null && rawIp.isNotEmpty) ? rawIp : fallbackIp,
      port: rawPort is int ? rawPort : int.tryParse('$rawPort') ?? 9090,
      apiPort: rawApiPort is int
          ? rawApiPort
          : int.tryParse('$rawApiPort') ?? 5000,
      namespace: (m['namespace'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ip': ip,
        'port': port,
        'apiPort': apiPort,
        'namespace': namespace,
      };

  RobotConfig copyWith({
    String? name,
    String? ip,
    int? port,
    int? apiPort,
    String? namespace,
  }) =>
      RobotConfig(
        name: name ?? this.name,
        ip: ip ?? this.ip,
        port: port ?? this.port,
        apiPort: apiPort ?? this.apiPort,
        namespace: namespace ?? this.namespace,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RobotConfig &&
          name == other.name &&
          ip == other.ip &&
          port == other.port &&
          apiPort == other.apiPort &&
          namespace == other.namespace;

  @override
  int get hashCode => Object.hash(name, ip, port, apiPort, namespace);
}

/// Default simulation robots seeded on first launch.
List<RobotConfig> defaultRobots({String defaultIp = '127.0.0.1'}) => [
      RobotConfig(name: 'UGV', ip: defaultIp, port: 9090, namespace: ''),
      RobotConfig(
          name: 'UGV-01_WO', ip: defaultIp, port: 9090, namespace: '/ugv_01'),
      RobotConfig(
          name: 'UGV-02_WO', ip: defaultIp, port: 9090, namespace: '/ugv_02'),
      RobotConfig(
          name: 'UGV-01', ip: defaultIp, port: 9091, namespace: '/ugv_01'),
      RobotConfig(
          name: 'UGV-02', ip: defaultIp, port: 9092, namespace: '/ugv_02'),
      RobotConfig(
          name: 'UGV-03', ip: defaultIp, port: 9093, namespace: '/ugv_03'),
      RobotConfig(
          name: 'UGV-04', ip: defaultIp, port: 9094, namespace: '/ugv_04'),
      RobotConfig(
          name: 'UGV-05', ip: defaultIp, port: 9095, namespace: '/ugv_05'),
      RobotConfig(
          name: 'UGV-06', ip: defaultIp, port: 9096, namespace: '/ugv_06'),
    ];
