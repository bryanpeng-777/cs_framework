# cs_framework & cs_infra 项目知识库

## 项目概述

这是一套「纯客户端 App → Client-Server 架构」的通用基础设施，允许 Flutter 业务项目以最小接入成本获得后端能力（配置下发、用户认证、数据存储、推送通知）。

**核心设计理念：重逻辑在客户端，后端只做数据和配置存储。**

---

## 仓库结构

```
work3/cursorAGIProject/cs/
├── cs_framework/     ← Flutter SDK（GitHub: bryanpeng-777/cs_framework）
└── cs_infra/         ← 基础设施（GitHub: bryanpeng-777/cs_infra）
    ├── supabase/migrations/   ← 数据库迁移脚本
    ├── mcp-server/            ← MCP Server（部署在 Railway）
    ├── supabase/functions/    ← Edge Functions（推送通知）
    └── demo/                  ← Flutter Demo App（验证用）
```

---

## 技术栈

| 层 | 技术 | 说明 |
|----|------|------|
| 客户端 SDK | Flutter / Dart | cs_framework package |
| 数据库 | Supabase (PostgreSQL + RLS) | 新加坡节点 |
| 配置存储 | `app_configs` 表 (JSONB) | 公共 schema |
| 用户数据 | `business` schema | 用户隔离 |
| 文件存储 | Supabase Storage | CDN 加速 |
| 实时推送 | Supabase Realtime (WebSocket) | 配置变更实时同步 |
| 推送通知 | FCM + Supabase Edge Function | |
| AI 管理接口 | MCP Server (TypeScript / Express) | Railway 部署 |

---

## 部署信息

| 服务 | URL |
|------|-----|
| Supabase 项目 | https://ljmkxoptnzimpompabsq.supabase.co |
| MCP Server | https://csinfra-production.up.railway.app |
| MCP 健康检查 | https://csinfra-production.up.railway.app/health |
| MCP 端点 | https://csinfra-production.up.railway.app/mcp |

---

## MCP Server 工具列表

cs-admin MCP 共 17 个工具，Cursor 中可直接调用：

**配置管理**：`list_configs` / `get_config` / `update_config` / `toggle_feature_flag` / `delete_config` / `batch_update`

**图片/存储**：`upload_image` / `list_images` / `delete_image`

**推送通知**：`send_notification` / `trigger_config_sync` / `list_devices`

**审计回滚**：`view_audit_log` / `rollback_config` / `register_app`

**发布流程**：`diff_envs` / `promote_to_prod`

**默认环境**：所有工具默认 `environment: dev`，发布时用 `promote_to_prod`。

---

## 核心架构约定

### 配置层 vs 业务数据层

- **配置层**（`public.app_configs`）：AI 管理，下发到所有用户，JSONB 存储，支持 dev/prod 环境隔离
- **业务数据层**（`business` schema）：用户私有数据，通过 RLS 隔离，每个 App 有独立业务表

### 三级缓存（ConfigManager）

```
读取优先级：L1 内存（TTL 24h）→ L2 Hive（持久化）→ L3 Supabase → Bundled Defaults
写入：所有层同时写
失效：服务端 version 变化时触发增量同步
```

### 环境管理

- `CsEnvironment.dev`：开发测试
- `CsEnvironment.prod`：线上用户
- 推荐：`kReleaseMode ? CsEnvironment.prod : CsEnvironment.dev`
- 运行时切换：`CsClient.switchEnvironment(env)`（会清空缓存重新同步）

### 新 App 接入步骤

1. `pubspec.yaml` 引入 cs_framework（Git URL）
2. `main.dart` 调用 `CsClient.initialize(appId: 'your-app')`
3. 让 AI 执行：`register_app(app_id: 'your-app')`
4. 用 MCP 工具初始化配置数据

---

## MCP Server 开发约定

### 构建方式（重要）

使用 **esbuild 打包成单文件**，不用 tsc 直接编译：

```bash
cd cs_infra/mcp-server
npm run build   # esbuild src/index.ts --bundle --platform=node --target=node18 --outfile=dist/bundle.js
npm start       # node dist/bundle.js
```

原因：`@modelcontextprotocol/sdk` 1.x 的 exports map 通配符缺 `.js` 后缀，tsc 编译后 Node.js 无法解析模块路径。

### MCP SDK import 写法

```typescript
// 必须加 .js 后缀
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js'
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js'
```

### Express 路由顺序（重要）

```typescript
app.get('/health', ...)    // 1. 健康检查（必须最先，在 auth 之前）
app.use(authMiddleware)    // 2. 鉴权中间件
app.post('/mcp', ...)      // 3. MCP 端点
app.get('/mcp', ...)
app.delete('/mcp', ...)
```

`/health` 在 auth 之前是因为 Railway healthcheck 请求无 `x-mcp-secret` header。

### Session 管理

Cursor 使用 Streamable HTTP 协议，需要维护 session Map：
- POST /mcp + 无 sessionId + isInitializeRequest → 新建 session
- POST /mcp + 有 sessionId → 路由到已有 session
- GET /mcp → SSE 流
- DELETE /mcp → 清理 session

---

## Railway 部署

- 触发方式：push 到 GitHub main 分支自动部署
- 构建命令：`npm run build`（esbuild 打包）
- 启动命令：`npm start`（`node dist/bundle.js`）
- 健康检查路径：`/health`（返回 200 JSON）
- 环境变量：`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` / `MCP_SECRET` / `FCM_PROJECT_ID` / `FCM_SERVICE_ACCOUNT_JSON`

---

## cs_framework SDK 发布

```bash
cd cs_framework
git tag v1.x.x
git push origin v1.x.x
```

Flutter 项目引用：
```yaml
cs_framework:
  git:
    url: https://github.com/bryanpeng-777/cs_framework.git
    ref: main  # 或指定 tag
```

---

## Demo App

位于 `cs_infra/demo/`，用于验证整套架构：
- 连接 Supabase cs-demo 项目
- 包含环境切换按钮（DEV / PROD）
- 覆盖验证点：配置读取、Realtime 实时更新、图片 CDN、业务数据 CRUD、Auth

运行：`flutter run`（需在 `demo/` 目录下）

---

## 已知踩坑

1. **匿名登录未开启**：Supabase Dashboard → Authentication → Providers → 开启 Anonymous
2. **Supabase Realtime 未开启**：Table Editor → `app_configs` 表 → 开启 Realtime
3. **Firebase 未配置时**：`enablePushNotifications: false`，否则崩溃
4. **MCP Server 默认环境**：工具默认 `dev`，操作 prod 需显式指定或用 `promote_to_prod`
