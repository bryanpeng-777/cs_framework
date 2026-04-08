/// cs_framework - 通用 Client-Server 基础架构 Flutter SDK
///
/// 使用方式：
/// ```dart
/// import 'package:cs_framework/cs_framework.dart';
///
/// // main.dart 初始化
/// await CsClient.initialize(
///   supabaseUrl: 'https://xxx.supabase.co',
///   supabaseAnonKey: 'your-anon-key',
///   appId: 'your-app-id',
///   environment: CsEnvironment.prod,
/// );
///
/// // 读取配置
/// final banner = await ConfigManager.getString('home_banner_image');
/// final enabled = await ConfigManager.getBool('new_feature');
///
/// // 业务数据
/// await DataManager.insert('my_table', {'field': 'value'});
/// final list = await DataManager.select('my_table');
///
/// // 用户认证
/// await AuthManager.signInAnonymously();
/// await AuthManager.linkWithEmail('user@example.com', 'password');
/// ```
library cs_framework;

export 'src/cs_client.dart' show CsClient, CsConfig, CsEnvironment;
export 'src/config/config_manager.dart' show ConfigManager;
export 'src/config/config_models.dart' show ConfigChangeEvent;
export 'src/data/data_manager.dart' show DataManager;
export 'src/auth/auth_manager.dart' show AuthManager;
export 'src/storage/storage_manager.dart' show StorageManager;
export 'src/notifications/push_manager.dart' show PushManager;
