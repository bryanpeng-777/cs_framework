import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'auth/auth_manager.dart';
import 'config/config_manager.dart';
import 'data/data_manager.dart';
import 'notifications/push_manager.dart';
import 'storage/storage_manager.dart';

/// 运行环境
enum CsEnvironment { dev, staging, prod }

/// cs_framework 全局配置
class CsConfig {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String appId;
  final CsEnvironment environment;
  final String locale;

  const CsConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.appId,
    this.environment = CsEnvironment.prod,
    this.locale = 'all',
  });

  String get environmentName => environment.name;
}

/// cs_framework 主入口
/// 负责初始化所有子模块，业务项目只需调用一次 [initialize]
class CsClient {
  CsClient._();

  static CsConfig? _config;
  static bool _initialized = false;

  static CsConfig get config {
    assert(_initialized, 'CsClient.initialize() 未调用');
    return _config!;
  }

  static SupabaseClient get supabase => Supabase.instance.client;

  static bool get isInitialized => _initialized;

  /// 初始化框架，在 main() 中 runApp 之前调用
  ///
  /// ```dart
  /// await CsClient.initialize(
  ///   supabaseUrl: 'https://xxx.supabase.co',
  ///   supabaseAnonKey: 'your-anon-key',
  ///   appId: 'your-app-id',
  ///   environment: CsEnvironment.prod,
  /// );
  /// ```
  static Future<void> initialize({
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String appId,
    CsEnvironment environment = CsEnvironment.prod,
    String locale = 'all',
    bool enablePushNotifications = true,
  }) async {
    if (_initialized) return;

    _config = CsConfig(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      appId: appId,
      environment: environment,
      locale: locale,
    );

    // 初始化 Hive 本地缓存
    await Hive.initFlutter();

    // 初始化 Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    // 初始化各子模块（顺序不可颠倒）
    await AuthManager.initialize();
    await ConfigManager.initialize();
    await DataManager.initialize();
    await StorageManager.initialize();

    if (enablePushNotifications) {
      await PushManager.initialize();
    }

    _initialized = true;

    if (kDebugMode) {
      debugPrint('[CsClient] 初始化完成 appId=$appId env=${environment.name}');
    }
  }

  /// 切换 locale（国际化场景下动态切换语言）
  static Future<void> setLocale(String locale) async {
    _config = CsConfig(
      supabaseUrl: _config!.supabaseUrl,
      supabaseAnonKey: _config!.supabaseAnonKey,
      appId: _config!.appId,
      environment: _config!.environment,
      locale: locale,
    );
    await ConfigManager.onLocaleChanged(locale);
  }

  /// 释放资源（通常不需要手动调用）
  static Future<void> dispose() async {
    await ConfigManager.dispose();
    await Hive.close();
    _initialized = false;
  }
}
