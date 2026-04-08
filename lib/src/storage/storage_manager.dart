import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

import '../cs_client.dart';

/// 文件存储管理器 - 图片上传、CDN URL 获取
class StorageManager {
  StorageManager._();

  static SupabaseClient get _supabase => CsClient.supabase;
  static CsConfig get _config => CsClient.config;

  /// 运营图片 Bucket（由 AI / 管理员上传，公开可读）
  static const String configsBucket = 'configs';

  /// 用户上传 Bucket（私有，RLS 控制）
  static const String userUploadsBucket = 'user-uploads';

  static Future<void> initialize() async {
    if (kDebugMode) {
      debugPrint('[StorageManager] 初始化完成');
    }
  }

  /// 上传用户文件（头像、UGC 等）
  /// 返回公开可访问的 CDN URL
  static Future<String> uploadUserFile(
    File file, {
    String? path,
    String contentType = 'image/jpeg',
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('用户未登录');

    final fileName = p.basename(file.path);
    final storagePath = path ?? '$userId/$fileName';

    await _supabase.storage.from(userUploadsBucket).upload(
          storagePath,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _supabase.storage.from(userUploadsBucket).getPublicUrl(storagePath);
  }

  /// 获取运营配置图片的公开 CDN URL
  static String getConfigImageUrl(String storagePath) {
    return _supabase.storage.from(configsBucket).getPublicUrl(storagePath);
  }

  /// 获取 App 专属的 Storage 路径前缀
  static String get appStoragePath => _config.appId;

  /// 删除用户文件
  static Future<void> deleteUserFile(String storagePath) async {
    await _supabase.storage.from(userUploadsBucket).remove([storagePath]);
  }

  /// 列出用户文件列表
  static Future<List<FileObject>> listUserFiles({String? folder}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('用户未登录');

    final path = folder != null ? '$userId/$folder' : userId;
    return _supabase.storage.from(userUploadsBucket).list(path: path);
  }
}
