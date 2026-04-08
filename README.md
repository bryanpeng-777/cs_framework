# cs_framework

通用 Client-Server 基础架构 Flutter SDK。

新项目引入此 SDK，无需从零搭建后端，立刻获得：
- ✅ 配置下发（三级缓存 + 实时更新）
- ✅ 业务数据 CRUD（RLS 用户隔离）
- ✅ 用户认证（匿名 + 邮箱 + 账号升级）
- ✅ 图片文件存储（CDN）
- ✅ 推送通知（FCM）

## 接入

**pubspec.yaml**：
```yaml
dependencies:
  cs_framework:
    git:
      url: https://github.com/your-org/cs_framework.git
      ref: v1.0.0
```

## 初始化

```dart
await CsClient.initialize(
  supabaseUrl: 'https://xxx.supabase.co',
  supabaseAnonKey: 'your-anon-key',
  appId: 'your-app-id',
  environment: CsEnvironment.prod,
);
```

## 使用

```dart
// 读配置（AI 下发的通用数据）
final url = await ConfigManager.getString('home_banner_image');
final on = await ConfigManager.getBool('enable_feature');

// 监听实时变更
ConfigManager.listen('home_banner_image').listen((e) {
  setState(() => bannerUrl = e.newValue['url']);
});

// 业务数据 CRUD
await DataManager.insert('my_favorites', {'item_id': 'xxx'});
final list = await DataManager.select('my_favorites');

// 用户认证
await AuthManager.signInAnonymously();              // 自动调用
await AuthManager.linkWithEmail('a@b.com', 'pwd'); // 升级账号

// 文件上传
final cdnUrl = await StorageManager.uploadUserFile(file);
```

## 版本历史

- `v1.0.0` — 初始版本（配置层 + 业务数据层 + Auth + Storage + Push）
