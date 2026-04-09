import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../cs_client.dart';

/// 用户认证管理器
/// 支持匿名登录、邮箱登录、Apple/Google 登录、账号升级
class AuthManager {
  AuthManager._();

  static bool _initialized = false;

  static SupabaseClient get _supabase => CsClient.supabase;

  /// 当前用户（未登录时为 null）
  static User? get currentUser => _supabase.auth.currentUser;

  /// 当前用户 ID
  static String? get currentUserId => currentUser?.id;

  /// 是否已登录（包括匿名登录）
  static bool get isLoggedIn => currentUser != null;

  /// 是否为匿名用户
  static bool get isAnonymous => currentUser?.isAnonymous ?? false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // 如果未登录，自动匿名登录
    if (currentUser == null) {
      try {
        await signInAnonymously();
      } catch (e) {
        // 匿名登录失败时不阻塞启动（未开启匿名登录、无网络等场景）
        if (kDebugMode) {
          debugPrint('[AuthManager] 匿名登录失败（可在 Supabase Dashboard 开启匿名登录）: $e');
        }
      }
    }

    _initialized = true;
    if (kDebugMode) {
      debugPrint('[AuthManager] 初始化完成 userId=${currentUserId ?? 'none'}');
    }
  }

  /// 匿名登录（首次使用时自动调用）
  static Future<AuthResponse> signInAnonymously() async {
    final response = await _supabase.auth.signInAnonymously();

    if (response.user != null) {
      await _upsertBusinessUser(response.user!);
    }

    if (kDebugMode) {
      debugPrint('[AuthManager] 匿名登录成功 userId=${response.user?.id}');
    }
    return response;
  }

  /// 邮箱密码注册
  static Future<AuthResponse> signUpWithEmail(
    String email,
    String password,
  ) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );
    if (response.user != null) {
      await _upsertBusinessUser(response.user!);
    }
    return response;
  }

  /// 邮箱密码登录
  static Future<AuthResponse> signInWithEmail(
    String email,
    String password,
  ) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user != null) {
      await _upsertBusinessUser(response.user!);
    }
    return response;
  }

  /// 将匿名账号升级为邮箱账号（保留历史数据）
  /// 调用此方法后 userId 不变，所有历史数据自动保留
  static Future<UserResponse> linkWithEmail(
    String email,
    String password,
  ) async {
    final response = await _supabase.auth.updateUser(
      UserAttributes(email: email, password: password),
    );
    if (kDebugMode) {
      debugPrint('[AuthManager] 匿名账号已升级为邮箱账号 email=$email');
    }
    return response;
  }

  /// 退出登录
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// 监听认证状态变化
  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  /// 获取设备唯一 ID（用于 devices 表注册）
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? const Uuid().v4();
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id;
      }
    } catch (_) {}
    return const Uuid().v4();
  }

  /// 在 business.users 表中同步用户记录
  static Future<void> _upsertBusinessUser(User user) async {
    try {
      await _supabase.from('business.users').upsert({
        'id': user.id,
        'app_id': CsClient.config.appId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      // business schema 可能还未建立（配置层独立使用场景），忽略错误
      if (kDebugMode) {
        debugPrint('[AuthManager] upsert business.users 跳过: $e');
      }
    }
  }
}
