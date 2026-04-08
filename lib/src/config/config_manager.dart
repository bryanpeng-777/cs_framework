import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cs_client.dart';
import 'config_models.dart';

/// 配置管理器 - 三级缓存 + 增量同步 + Realtime 推送
///
/// 读取优先级：L1 内存 → L2 Hive → L3 Supabase → Bundled Defaults
///
/// 使用示例：
/// ```dart
/// final url = await ConfigManager.getString('home_banner_image');
/// final enabled = await ConfigManager.getBool('enable_feature');
/// final list = await ConfigManager.getList('wallpaper_collection');
/// ```
class ConfigManager {
  ConfigManager._();

  // L1 内存缓存
  static final Map<String, CacheEntry> _memoryCache = {};

  // L2 Hive 持久化缓存
  static Box? _hiveBox;
  static const String _hiveBoxName = 'cs_config_cache';
  static const String _syncVersionKey = '__sync_version__';

  // Bundled defaults（从 assets/default_configs.json 加载）
  static Map<String, dynamic> _bundledDefaults = {};

  // 配置变更通知流
  static final StreamController<ConfigChangeEvent> _changeController =
      StreamController<ConfigChangeEvent>.broadcast();

  // Realtime 订阅
  static RealtimeChannel? _realtimeChannel;

  // 默认 TTL（各 key 可单独配置）
  static const Duration _defaultTTL = Duration(hours: 24);
  static final Map<String, Duration> _customTTLs = {};

  static bool _initialized = false;

  static SupabaseClient get _supabase => CsClient.supabase;
  static CsConfig get _config => CsClient.config;

  /// 初始化（由 CsClient 自动调用）
  static Future<void> initialize() async {
    if (_initialized) return;

    // 打开 Hive box
    _hiveBox = await Hive.openBox(_hiveBoxName);

    // 加载 bundled defaults
    await _loadBundledDefaults();

    // 启动增量同步（后台，不阻塞 UI）
    _syncInBackground();

    // 启动 Realtime 监听（前台实时推送）
    _subscribeRealtime();

    // 监听 App 生命周期（回前台时触发增量同步）
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver());

    _initialized = true;
    if (kDebugMode) {
      debugPrint('[ConfigManager] 初始化完成');
    }
  }

  // ==================== 对外公共 API ====================

  /// 获取字符串配置
  static Future<String?> getString(String key) async {
    final value = await _get(key);
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map && value.containsKey('url')) return value['url'] as String?;
    return value.toString();
  }

  /// 获取布尔配置
  static Future<bool?> getBool(String key) async {
    final value = await _get(key);
    if (value == null) return null;
    if (value is bool) return value;
    if (value is Map && value.containsKey('enabled')) {
      return value['enabled'] as bool?;
    }
    return null;
  }

  /// 获取整数配置
  static Future<int?> getInt(String key) async {
    final value = await _get(key);
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Map && value.containsKey('value')) {
      return (value['value'] as num?)?.toInt();
    }
    return null;
  }

  /// 获取 Map 配置（JSON 对象）
  static Future<Map<String, dynamic>?> getMap(String key) async {
    final value = await _get(key);
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  /// 获取 List 配置
  static Future<List<dynamic>?> getList(String key) async {
    final value = await _get(key);
    if (value == null) return null;
    if (value is List) return value;
    if (value is Map && value.containsKey('items')) {
      return value['items'] as List?;
    }
    return null;
  }

  /// 监听某个配置 key 的变更
  static Stream<ConfigChangeEvent> listen(String key) {
    return _changeController.stream.where((e) => e.configKey == key);
  }

  /// 监听所有配置变更
  static Stream<ConfigChangeEvent> get onChange => _changeController.stream;

  /// 为特定 key 设置自定义 TTL
  static void setTTL(String key, Duration ttl) {
    _customTTLs[key] = ttl;
  }

  /// 强制刷新（跳过缓存，直接从 Supabase 拉取）
  static Future<void> forceRefresh() async {
    _memoryCache.clear();
    await _fullSync();
  }

  /// locale 切换时清空缓存并重新同步
  static Future<void> onLocaleChanged(String newLocale) async {
    _memoryCache.clear();
    await _hiveBox?.clear();
    await _syncInBackground();
  }

  // ==================== 内部实现 ====================

  /// 三级缓存读取
  static Future<dynamic> _get(String key) async {
    // L1 内存缓存
    final memEntry = _memoryCache[key];
    if (memEntry != null && !memEntry.isExpired) {
      return memEntry.value;
    }

    // L2 Hive 持久化缓存
    final hiveRaw = _hiveBox?.get(key);
    if (hiveRaw != null) {
      try {
        final hiveEntry = CacheEntry.fromJson(
          Map<String, dynamic>.from(hiveRaw as Map),
        );
        if (!hiveEntry.isExpired) {
          // 命中 L2，写回 L1
          _memoryCache[key] = hiveEntry;
          return hiveEntry.value;
        }
      } catch (_) {}
    }

    // L3 Supabase 远端拉取
    try {
      final value = await _fetchFromSupabase(key);
      if (value != null) {
        await _writeCache(key, value);
        return value;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ConfigManager] L3 拉取失败: $e，使用 bundled defaults');
      }
    }

    // Bundled defaults 兜底
    return _bundledDefaults[key];
  }

  /// 从 Supabase 拉取单个配置
  static Future<dynamic> _fetchFromSupabase(String key) async {
    final locale = _config.locale;

    // 优先精确 locale 匹配，找不到则回退到 'all'
    PostgrestList? rows;

    if (locale != 'all') {
      rows = await _supabase
          .from('app_configs')
          .select('value')
          .eq('app_id', _config.appId)
          .eq('config_key', key)
          .eq('environment', _config.environmentName)
          .eq('is_active', true)
          .eq('locale', locale)
          .limit(1);
    }

    if (rows == null || rows.isEmpty) {
      rows = await _supabase
          .from('app_configs')
          .select('value')
          .eq('app_id', _config.appId)
          .eq('config_key', key)
          .eq('environment', _config.environmentName)
          .eq('is_active', true)
          .eq('locale', 'all')
          .limit(1);
    }

    if (rows.isNotEmpty) {
      return rows.first['value'];
    }
    return null;
  }

  /// 增量同步（启动时 + 回前台时）
  static Future<void> _syncInBackground() async {
    try {
      // 获取服务端版本号
      final versionRows = await _supabase
          .from('config_sync_versions')
          .select('version')
          .eq('app_id', _config.appId)
          .eq('environment', _config.environmentName)
          .limit(1);

      if (versionRows.isEmpty) return;

      final serverVersion = (versionRows.first['version'] as num).toInt();
      final localVersion = _hiveBox?.get(_syncVersionKey) as int? ?? 0;

      if (serverVersion <= localVersion) {
        if (kDebugMode) {
          debugPrint('[ConfigManager] 版本一致 v$localVersion，跳过同步');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('[ConfigManager] 增量同步 v$localVersion → v$serverVersion');
      }

      await _fullSync();
      await _hiveBox?.put(_syncVersionKey, serverVersion);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ConfigManager] 增量同步失败: $e');
      }
    }
  }

  /// 全量同步（拉取此 App 所有激活配置）
  static Future<void> _fullSync() async {
    final locale = _config.locale;

    var query = _supabase
        .from('app_configs')
        .select('config_key, value')
        .eq('app_id', _config.appId)
        .eq('environment', _config.environmentName)
        .eq('is_active', true);

    if (locale != 'all') {
      query = query.inFilter('locale', [locale, 'all']);
    } else {
      query = query.eq('locale', 'all');
    }

    final rows = await query;

    for (final row in rows) {
      final key = row['config_key'] as String;
      final value = row['value'];
      await _writeCache(key, value);
    }

    if (kDebugMode) {
      debugPrint('[ConfigManager] 全量同步完成，共 ${rows.length} 条配置');
    }
  }

  /// 写入 L1 + L2 缓存
  static Future<void> _writeCache(String key, dynamic value) async {
    final ttl = _customTTLs[key] ?? _defaultTTL;
    final entry = CacheEntry(
      value: value,
      expiredAt: DateTime.now().add(ttl),
      serverVersion: 0,
    );

    _memoryCache[key] = entry;
    await _hiveBox?.put(key, entry.toJson());
  }

  /// 订阅 Realtime（App 在前台时实时接收配置变更）
  static void _subscribeRealtime() {
    _realtimeChannel = _supabase
        .channel('config_changes_${_config.appId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_configs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'app_id',
            value: _config.appId,
          ),
          callback: (payload) {
            _handleRealtimeChange(payload);
          },
        )
        .subscribe();

    if (kDebugMode) {
      debugPrint('[ConfigManager] Realtime 订阅已启动');
    }
  }

  /// 处理 Realtime 推送的配置变更
  static Future<void> _handleRealtimeChange(
      PostgresChangePayload payload) async {
    final newRecord = payload.newRecord;
    if (newRecord.isEmpty) return;

    final key = newRecord['config_key'] as String?;
    final value = newRecord['value'];
    final isActive = newRecord['is_active'] as bool? ?? true;

    if (key == null) return;

    if (!isActive) {
      // 配置被下线，清除缓存
      _memoryCache.remove(key);
      await _hiveBox?.delete(key);
    } else {
      await _writeCache(key, value);
    }

    // 通知监听者
    _changeController.add(ConfigChangeEvent(
      configKey: key,
      newValue: isActive ? value : null,
      changedAt: DateTime.now(),
    ));

    if (kDebugMode) {
      debugPrint('[ConfigManager] Realtime 配置已更新: $key');
    }
  }

  /// 加载 bundled defaults
  static Future<void> _loadBundledDefaults() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/default_configs.json');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      _bundledDefaults = decoded
        ..remove('_comment')
        ..remove('_version');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ConfigManager] bundled defaults 加载失败: $e');
      }
      _bundledDefaults = {};
    }
  }

  /// 释放资源
  static Future<void> dispose() async {
    await _realtimeChannel?.unsubscribe();
    await _changeController.close();
    _memoryCache.clear();
    _initialized = false;
  }
}

/// App 生命周期观察者：回前台时触发增量同步
class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ConfigManager._syncInBackground();
    }
  }
}
