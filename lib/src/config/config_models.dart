/// 本地缓存中的配置条目（含 TTL）
class CacheEntry {
  final dynamic value;
  final DateTime expiredAt;
  final int serverVersion;

  const CacheEntry({
    required this.value,
    required this.expiredAt,
    required this.serverVersion,
  });

  bool get isExpired => DateTime.now().isAfter(expiredAt);

  Map<String, dynamic> toJson() => {
        'value': value,
        'expiredAt': expiredAt.toIso8601String(),
        'serverVersion': serverVersion,
      };

  factory CacheEntry.fromJson(Map<String, dynamic> json) => CacheEntry(
        value: json['value'],
        expiredAt: DateTime.parse(json['expiredAt'] as String),
        serverVersion: (json['serverVersion'] as num?)?.toInt() ?? 0,
      );
}

/// 配置变更通知
class ConfigChangeEvent {
  final String configKey;
  final dynamic newValue;
  final DateTime changedAt;

  const ConfigChangeEvent({
    required this.configKey,
    required this.newValue,
    required this.changedAt,
  });
}
