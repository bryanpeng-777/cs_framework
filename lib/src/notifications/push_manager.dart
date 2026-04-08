import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/auth_manager.dart';
import '../config/config_manager.dart';
import '../cs_client.dart';

/// 推送通知管理器 - FCM token 注册 + 消息接收 + silent push 处理
class PushManager {
  PushManager._();

  static SupabaseClient get _supabase => CsClient.supabase;
  static CsConfig get _config => CsClient.config;

  static FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  /// 前台消息回调
  static void Function(RemoteMessage message)? onForegroundMessage;

  /// 通知点击回调
  static void Function(RemoteMessage message)? onNotificationTap;

  static Future<void> initialize() async {
    // 请求通知权限
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) {
        debugPrint('[PushManager] 用户拒绝通知权限');
      }
      return;
    }

    // 获取 FCM token 并注册到 devices 表
    final token = await _fcm.getToken();
    if (token != null) {
      await _registerDevice(token);
    }

    // 监听 token 刷新
    _fcm.onTokenRefresh.listen(_registerDevice);

    // 前台消息处理
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 通知点击处理（App 在后台被点击打开）
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // App 完全关闭时被通知打开
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    if (kDebugMode) {
      debugPrint('[PushManager] 初始化完成 token=${token?.substring(0, 20)}...');
    }
  }

  /// 注册设备到 Supabase devices 表
  static Future<void> _registerDevice(String fcmToken) async {
    try {
      final deviceId = await AuthManager.getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();

      await _supabase.from('devices').upsert({
        'app_id': _config.appId,
        'device_id': deviceId,
        'fcm_token': fcmToken,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'app_version': packageInfo.version,
        'locale': _config.locale,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'app_id,device_id');

      if (kDebugMode) {
        debugPrint('[PushManager] 设备注册成功 deviceId=$deviceId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PushManager] 设备注册失败: $e');
      }
    }
  }

  /// 处理前台消息
  static void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('[PushManager] 收到前台消息: ${message.data}');
    }

    // 处理 silent push（配置同步触发）
    if (message.data['type'] == 'config_sync') {
      ConfigManager.forceRefresh();
      return;
    }

    onForegroundMessage?.call(message);
  }

  /// 处理通知点击
  static void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('[PushManager] 通知被点击: ${message.data}');
    }
    onNotificationTap?.call(message);
  }

  /// 获取当前设备的 FCM token
  static Future<String?> getToken() => _fcm.getToken();
}
