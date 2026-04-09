import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cs_client.dart';

/// 业务数据管理器 - 用户私有数据的通用 CRUD 封装
///
/// 所有操作自动绑定当前登录用户（通过 Supabase Auth + RLS）
/// 业务代码无需手动传 user_id，RLS 策略自动隔离
///
/// 使用示例：
/// ```dart
/// // 插入
/// await DataManager.insert('demo_favorites', {'item_id': 'wp_001'});
///
/// // 查询
/// final list = await DataManager.select('demo_favorites',
///   orderBy: 'created_at', ascending: false, limit: 20);
///
/// // 更新
/// await DataManager.update('demo_favorites',
///   data: {'metadata': {'note': 'best'}},
///   match: {'item_id': 'wp_001'});
///
/// // 删除
/// await DataManager.delete('demo_favorites', match: {'item_id': 'wp_001'});
/// ```
class DataManager {
  DataManager._();

  static SupabaseClient get _supabase => CsClient.supabase;

  static Future<void> initialize() async {
    if (kDebugMode) {
      debugPrint('[DataManager] 初始化完成');
    }
  }

  /// 插入一条记录
  /// [table] 不需要加 business. 前缀，自动补充
  static Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> data,
  ) async {
    final result = await _supabase
        .schema('business')
        .from(table)
        .insert(data)
        .select()
        .single();
    return result;
  }

  /// 查询记录列表
  static Future<List<Map<String, dynamic>>> select(
    String table, {
    String? columns,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = false,
    int? limit,
    int? offset,
  }) async {
    // 先构建 filter 阶段的查询
    var filterQuery = _supabase
        .schema('business')
        .from(table)
        .select(columns ?? '*');

    if (filters != null) {
      for (final entry in filters.entries) {
        filterQuery = filterQuery.eq(entry.key, entry.value);
      }
    }

    // 进入 transform 阶段（order/limit/range 返回不同类型，用 dynamic 承接）
    dynamic q = filterQuery;

    if (orderBy != null) {
      q = (q as dynamic).order(orderBy, ascending: ascending);
    }
    if (limit != null) {
      q = (q as dynamic).limit(limit);
    }
    if (offset != null) {
      q = (q as dynamic).range(offset, offset + (limit ?? 20) - 1);
    }

    final result = await (q as dynamic);
    return List<Map<String, dynamic>>.from(result as List);
  }

  /// 查询单条记录
  static Future<Map<String, dynamic>?> selectOne(
    String table, {
    Map<String, dynamic>? filters,
  }) async {
    var query = _supabase
        .schema('business')
        .from(table)
        .select();

    if (filters != null) {
      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }

    final result = await query.limit(1).maybeSingle();
    return result;
  }

  /// 更新记录
  static Future<List<Map<String, dynamic>>> update(
    String table, {
    required Map<String, dynamic> data,
    Map<String, dynamic>? match,
  }) async {
    var query = _supabase
        .schema('business')
        .from(table)
        .update(data);

    if (match != null) {
      for (final entry in match.entries) {
        query = query.eq(entry.key, entry.value) as dynamic;
      }
    }

    final result = await (query as dynamic).select();
    return List<Map<String, dynamic>>.from(result as List);
  }

  /// 插入或更新（upsert）
  static Future<Map<String, dynamic>> upsert(
    String table,
    Map<String, dynamic> data, {
    String? onConflict,
  }) async {
    final result = await _supabase
        .schema('business')
        .from(table)
        .upsert(data, onConflict: onConflict)
        .select()
        .single();
    return result;
  }

  /// 删除记录
  static Future<void> delete(
    String table, {
    Map<String, dynamic>? match,
  }) async {
    var query = _supabase.schema('business').from(table).delete();

    if (match != null) {
      for (final entry in match.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }

    await query;
  }

  /// 统计记录数
  static Future<int> count(
    String table, {
    Map<String, dynamic>? filters,
  }) async {
    var query = _supabase
        .schema('business')
        .from(table)
        .select();

    if (filters != null) {
      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }

    final result = await query.count(CountOption.exact);
    return result.count;
  }

  /// 订阅实时变更（业务数据的多设备同步）
  static RealtimeChannel subscribe(
    String table, {
    String? filter,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _supabase
        .channel('business_${table}_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'business',
          table: table,
          filter: filter != null
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: filter.split('=').first,
                  value: filter.split('=').last,
                )
              : null,
          callback: onChange,
        )
        .subscribe();
  }
}
