import 'auth_manager.dart';

/// go_router 路由守卫工具类
///
/// 提供可以直接挂到 `GoRouter.redirect` 或 `GoRoute.redirect` 的回调函数。
/// 由于 cs_framework 不依赖 go_router，此处将回调签名定义为通用 typedef，
/// 业务方将函数直接传给 `GoRouter(redirect: ...)` 即可。
///
/// ## 使用方式
///
/// ```dart
/// import 'package:go_router/go_router.dart';
/// import 'package:cs_framework/cs_framework.dart';
///
/// GoRouter(
///   // 未登录（连匿名也没有）则跳登录页
///   redirect: AuthGuard.requireAnySession,
///   routes: [
///     GoRoute(path: '/home', builder: ...),
///     GoRoute(path: '/login', builder: ...),
///   ],
/// )
///
/// // 保护只有邮箱用户才能访问的路由
/// GoRoute(
///   path: '/profile',
///   redirect: AuthGuard.requireEmailUser,
///   builder: (context, state) => const ProfilePage(),
/// )
/// ```
///
/// 注意：回调参数类型与 go_router 的 `GoRouterRedirect` 一致：
/// `String? Function(BuildContext context, GoRouterState state)`
/// 此处声明为 `Function` 是为了避免直接 import go_router。
class AuthGuard {
  AuthGuard._();

  /// 要求实名（邮箱）账号的路由守卫
  ///
  /// 已绑定邮箱 → 放行（返回 null）
  /// 匿名或未登录 → 跳转 `/login?redirect=<原路径>`
  ///
  /// 类型签名与 `GoRouterRedirect` 兼容，直接传给 `GoRouter(redirect:...)` 即可。
  static String? requireEmailUser(dynamic context, dynamic state) {
    if (AuthManager.isEmailUser) return null;

    final uri = (state as dynamic).uri?.toString() ?? '/';
    return '/login?redirect=${Uri.encodeComponent(uri)}';
  }

  /// 未登录守卫（匿名用户视为已登录）
  ///
  /// 有任意 session（邮箱或匿名）→ 放行
  /// 完全无 session → 跳转 `/login`
  static String? requireAnySession(dynamic context, dynamic state) {
    if (AuthManager.isLoggedIn) return null;
    final uri = (state as dynamic).uri?.toString() ?? '/';
    return '/login?redirect=${Uri.encodeComponent(uri)}';
  }
}
