# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **通用 Client-Server 基础架构** — a production-ready backend framework for Flutter mobile apps. It has three components:

- **`cs_framework/`** — Flutter SDK package that apps integrate
- **`cs_infra/`** — Supabase migrations, MCP admin server, and a demo Flutter app
- **`cs_infra/mcp-server/`** — Node.js/TypeScript MCP server deployed to Railway for AI-assisted admin

## Commands

### cs_framework (Flutter SDK)
```bash
cd cs_framework
flutter pub get
flutter test                  # Run all tests
flutter test test/cs_framework_test.dart  # Run single test file
flutter analyze               # Lint
dart format lib/ test/        # Format
```

### cs_infra/mcp-server (Node.js MCP Server)
```bash
cd cs_infra/mcp-server
npm install
npm run build       # Bundle TypeScript via esbuild → dist/bundle.js
npm start           # Run production bundle
npm run typecheck   # tsc --noEmit (no output, just type checking)
npm run dev         # ts-node --esm (development)
```

### cs_infra/demo (Flutter Demo App)
```bash
cd cs_infra/demo
flutter pub get
flutter run
flutter test
```

## Architecture

### Three-Tier Caching (cs_framework)

The core design of `ConfigManager` is a cascading fallback:
1. **L1**: In-memory cache (fastest)
2. **L2**: Hive (SQLite-backed local persistence)
3. **L3**: Supabase (remote database)
4. **L4**: Bundled `assets/default_configs.json` (offline fallback)

Config updates propagate via Supabase Realtime WebSocket subscriptions. Sync is incremental (version-based via `config_sync_versions` table) with full-sync fallback.

### Framework Entry Point (`cs_client.dart`)

`CsClient` is the singleton orchestrator. Apps call `CsClient.initialize()` once in `main()` before `runApp()`. It wires up all sub-managers:
- `ConfigManager` — remote config with three-tier cache
- `AuthManager` — anonymous + email/OAuth login; auto-creates business user record on first login
- `DataManager` — user-private CRUD with RLS (`business` schema); no manual `user_id` binding needed
- `StorageManager` — CDN file uploads to Supabase Storage
- `PushManager` — FCM device token registration (optional; disable with `enablePushNotifications: false`)

### Database Schema (Supabase)

Two migration layers in `cs_infra/supabase/migrations/`:
- **`001_config_layer.sql`**: `app_configs`, `config_sync_versions`, `config_audit_log`, `devices` tables in `public` schema. Configs are multi-dimensional: `(app_id, config_key, environment, locale)` unique constraint; support platform targeting, version range targeting, and soft-delete.
- **`002_business_layer.sql`**: `business` schema for user data tables; every table has `user_id` + RLS policy ensuring users see only their own rows.

### MCP Server (`cs_infra/mcp-server/src/`)

Express.js + MCP SDK server exposing AI-friendly tools for Cursor/Claude integration. Tools live in `src/tools/`:
- `config-tools.ts` — list/get/set/delete app configs
- `storage-tools.ts` — upload images to `configs` bucket
- `notification-tools.ts` — send FCM push notifications
- `audit-tools.ts` — view audit log, rollback configs
- `promote-tools.ts` — register new apps

MCP endpoints: `POST /mcp` (JSON-RPC), `GET /mcp` (SSE stream), `DELETE /mcp` (close session), `GET /health`.

Built with esbuild into a single `dist/bundle.js`. Deployed to Railway; auto-deploys on git push.

### Multi-Tenancy

A single Supabase instance hosts multiple apps via `app_id` isolation in the config layer and RLS in the business layer.

## Key Dependencies

| Component | Key Packages |
|-----------|-------------|
| cs_framework | `supabase_flutter ^2.0.0`, `hive_flutter ^1.1.0`, `firebase_messaging ^15.0.0`, `device_info_plus`, `package_info_plus` |
| mcp-server | `@modelcontextprotocol/sdk ^1.0.0`, `@supabase/supabase-js ^2.0.0`, `express ^4.18.0`, `zod ^3.22.0` |

## Environment Configuration

The MCP server requires a `.env` file (see `.env.example`):
```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
FCM_PROJECT_ID=
FCM_SERVICE_ACCOUNT_JSON=
PORT=3000
MCP_SECRET=   # optional auth token
```

Flutter apps configure Supabase credentials in `CsClient.initialize()`.

## Onboarding a New App

See `cs_infra/docs/integration-guide.md` for the full 7-step guide (~50 min). Short version:
1. Register app via MCP tool `register_app`
2. Add `cs_framework` to `pubspec.yaml`
3. Call `CsClient.initialize()` in `main()`
4. Provide `assets/default_configs.json`
5. Run SQL from `003_new_app_template.sql` for business tables
6. Seed initial configs via AI (Cursor + MCP)
7. Write business code using the managers
