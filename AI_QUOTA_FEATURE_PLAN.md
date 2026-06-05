# Boring.Notch — AI 额度显示功能计划

> **v2** — 整合 Codex 审核反馈，修正 sandbox / 布局 / 生命周期 / 设置入口问题

## 功能概述

在 boring.notch 的 notch 展开视图中新增一个 **AI Quota** 面板，实时显示 Claude (Anthropic) 和 Codex (OpenAI/ChatGPT) 账号的使用率（已用百分比）。

参考项目：[cc-switch](https://github.com/farion1231/cc-switch)

---

## 核心原理（来自 cc-switch 的逆向分析）

### Claude 额度查询

- **凭据来源**：优先从 macOS Keychain（service: `"Claude Code-credentials"`）读取，回退到 `~/.claude/.credentials.json`
- **JSON 格式**：
  ```json
  {"claudeAiOauth": {"accessToken": "...", "expiresAt": ...}}
  // 或
  {"claude.ai_oauth": {"accessToken": "...", "expiresAt": ...}}
  ```
- **API 端点**：`GET https://api.anthropic.com/api/oauth/usage`
- **请求头**：
  - `Authorization: Bearer {token}`
  - `anthropic-beta: oauth-2025-04-20`
  - `Accept: application/json`
- **返回数据**：按窗口维度的 `utilization`（0-100%），已知窗口类型包括：
  - `five_hour` — 5 小时滑动窗口
  - `seven_day` — 7 天窗口
  - `seven_day_opus` — 7 天 Opus 模型窗口
  - `seven_day_sonnet` — 7 天 Sonnet 模型窗口
  - `extra_usage` — 超额使用信息（is_enabled, monthly_limit, used_credits, utilization, currency）
  - API 可能返回未知窗口类型，需要兼容解析

### Codex 额度查询

- **凭据来源**：优先从 macOS Keychain（service: `"Codex Auth"`）读取，回退到 `~/.codex/auth.json`
- **JSON 格式**：
  ```json
  {"auth_mode": "chatgpt", "tokens": {"access_token": "...", "account_id": "..."}, "last_refresh": "..."}
  ```
- **前提条件**：仅在 `auth_mode == "chatgpt"` (OAuth 模式) 时有效，API key 模式不支持用量查询
- **API 端点**：`GET https://chatgpt.com/backend-api/wham/usage`
- **请求头**：
  - `Authorization: Bearer {token}`
  - `User-Agent: codex-cli`
  - `ChatGPT-Account-Id: {account_id}`（可选）
  - `Accept: application/json`
- **返回数据**：`rate_limit` 对象中包含 `primary_window` 和 `secondary_window`：
  - `used_percent` — 使用百分比
  - `limit_window_seconds` — 窗口秒数（18000 = 5h, 604800 = 7d，其他值动态映射）
  - `reset_at` — Unix 时间戳（重置时间）

---

## 架构约束（审核修正）

### 约束 1：App Sandbox

主 app `boringNotch` 是 sandboxed（`com.apple.security.app-sandbox: true`），**无法**直接：
- 调用 `security find-generic-password` 访问其他 app 写入的 Keychain 条目
- 读取 `~/.claude/`、`~/.codex/` 等任意文件系统路径

项目已有一个 **unsandboxed XPC Helper**（`BoringNotchXPCHelper`，`app-sandbox: false`），
目前提供 accessibility、keyboard brightness、screen brightness 服务。

**方案**：凭据读取必须通过 XPC Helper 完成，扩展 `BoringNotchXPCHelperProtocol`。

### 约束 2：Notch 布局空间

展开 notch 固定尺寸为 **640×190**（`matters.swift:16`）。当前 `NotchHomeView` 已在 HStack 中横排：
- MusicPlayer（~250pt）
- Calendar（170-215pt）
- Camera（可变）

再横向加 180pt 面板会溢出。

**方案**：AI Quota 作为独立的 `NotchViews` tab（与 `.home` / `.shelf` 并列），通过 header 中的 tab 切换进入，拥有 640pt 全宽空间，不挤压现有布局。

### 约束 3：刷新生命周期

功能默认关闭（`showAIQuota` default: false），不应常驻刷新。

**方案**：
- 仅当 `Defaults[.showAIQuota] == true` 时启动定时刷新
- 关闭设置时取消 timer
- 切换到 AI Quota tab 时立即刷新一次
- 提供手动刷新按钮
- 使用 `Task` + cancellable 管理后台任务

---

## 实现步骤

### 第 1 步：新增数据模型 — `AIQuotaModels.swift`

**文件位置**：`boringNotch/models/AIQuotaModels.swift`

定义以下类型：

- `AIProvider` 枚举（`.claude`, `.codex`）
- `CredentialStatus` 枚举（`.valid`, `.expired`, `.notFound`, `.parseError`）
- `QuotaTier` 结构体
  - `name: String` — 窗口标识（five_hour, seven_day 等，保留未知窗口兼容）
  - `utilization: Double` — 已用百分比 0-100
  - `resetsAt: Date?` — 重置时间
- `ExtraUsage` 结构体（需声明 `CodingKeys` 映射 snake_case）
  - `isEnabled: Bool`
  - `monthlyLimit: Double?`
  - `usedCredits: Double?`
  - `utilization: Double?`
  - `currency: String?`
- `AIQuotaResult` 结构体
  - `provider: AIProvider`
  - `credentialStatus: CredentialStatus`
  - `success: Bool`
  - `tiers: [QuotaTier]`
  - `extraUsage: ExtraUsage?`
  - `error: String?`
  - `queriedAt: Date?`

**解析兼容逻辑**：
- Claude：解析已知窗口（five_hour, seven_day, seven_day_opus, seven_day_sonnet），同时遍历响应 JSON 所有顶层 key，将未知的、包含 `utilization` 字段的 object 也作为 tier 保留
- Codex：`limit_window_seconds` 动态映射 tier name（18000→five_hour, 604800→seven_day, 其他→`{n}_hour` 或 `{n}_day`）
- Token 过期检测兼容秒/毫秒时间戳和 ISO 8601 格式

### 第 2 步：扩展 XPC Helper — 凭据读取

**关键变更**：凭据读取逻辑放在 XPC Helper 中，而非主 app。

#### 2a. 扩展 XPC Protocol

**修改文件**：`BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift`（及主 app 中的副本 `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift`）

新增方法：

```swift
func readClaudeCredentials(with reply: @escaping (String?, String?, String?) -> Void)
// 返回: (accessToken?, credentialStatus, errorMessage?)

func readCodexCredentials(with reply: @escaping (String?, String?, String?, String?) -> Void)
// 返回: (accessToken?, accountId?, credentialStatus, errorMessage?)
```

#### 2b. 在 XPC Helper 中实现凭据读取

**新建文件**：`BoringNotchXPCHelper/AICredentialReader.swift`

在 unsandboxed 环境中：
1. Claude：先 `security find-generic-password -s "Claude Code-credentials" -w`，失败则读 `~/.claude/.credentials.json`，解析 `claudeAiOauth` / `claude.ai_oauth` 下的 accessToken 和 expiresAt
2. Codex：先 `security find-generic-password -s "Codex Auth" -w`，失败则读 `~/.codex/auth.json`，验证 `auth_mode == "chatgpt"`，解析 tokens

**修改文件**：`BoringNotchXPCHelper/BoringNotchXPCHelper.swift` — 实现新 protocol 方法，委托给 `AICredentialReader`

#### 2c. 扩展 XPC Client

**修改文件**：`boringNotch/XPCHelperClient/XPCHelperClient.swift`

新增：

```swift
nonisolated func readClaudeCredentials() async -> (accessToken: String?, status: String, message: String?)
nonisolated func readCodexCredentials() async -> (accessToken: String?, accountId: String?, status: String, message: String?)
```

遵循现有模式（`ensureRemoteService()` → `withContinuation`）。

### 第 3 步：额度查询管理器 — `AIQuotaManager.swift`

**文件位置**：`boringNotch/managers/AIQuotaManager.swift`

作为 `ObservableObject` 单例：

- `@Published var claudeQuota: AIQuotaResult?`
- `@Published var codexQuota: AIQuotaResult?`
- `@Published var isLoading: Bool`
- `static let shared = AIQuotaManager()`

**生命周期管理**：

```swift
private var refreshTask: Task<Void, Never>?

func startAutoRefresh() {
    // 仅当 showAIQuota == true 时调用
    refreshTask?.cancel()
    refreshTask = Task { ... 每 300 秒循环 fetchAll ... }
}

func stopAutoRefresh() {
    refreshTask?.cancel()
    refreshTask = nil
}
```

- 监听 `Defaults.observe(.showAIQuota)` 的变化，开/关时自动 start/stop
- **不在 app 启动时无条件初始化**

**核心方法**：

- `fetchAll()` — 使用 `async let` 并发请求两个 API
- `fetchClaudeQuota()` — 通过 XPCHelperClient 读凭据 → URLSession 调 Anthropic API → 解析所有 tier 窗口（含未知窗口）和 extra_usage
- `fetchCodexQuota()` — 通过 XPCHelperClient 读凭据 → URLSession 调 ChatGPT API → 解析 rate_limit 窗口（动态映射 window_seconds → tier name）
- 网络请求使用 `URLSession`，10 秒超时
- 主 app 已有 `com.apple.security.network.client` 权限，网络请求可在主 app 中发起

### 第 4 步：UI 视图

#### 布局方案：独立 Tab

AI Quota 作为 `NotchViews.quota` 独立 tab，拥有完整 640×190 展开空间。

#### `AIQuotaView.swift`

**文件位置**：`boringNotch/components/AIQuota/AIQuotaView.swift`

主面板视图，水平排列 Claude 和 Codex 的额度卡片，右上角手动刷新按钮：

```
┌─────────────────────────────────────────────────────┐
│  ☁ Claude                    ◎ Codex           ↻   │
│  ┌────────────────────┐      ┌────────────────────┐ │
│  │ 5h  ●━━━━━━○  23%  │      │ 5h  ●━━━━━━━○ 45% │ │
│  │ 7d  ●━━━━━━━━○ 67% │      │ 7d  ●━○       12% │ │
│  │ Opus ●━━○     35%  │      │                    │ │
│  └────────────────────┘      └────────────────────┘ │
│  Resets in 3h 12m            Resets in 1h 05m       │
└─────────────────────────────────────────────────────┘
```

**UI 文案**：API 返回的是 `utilization` / `used_percent`（已用百分比），UI 显示为 **"已用 X%"**，进度条表示已用量。

#### `QuotaCardView.swift`

**文件位置**：`boringNotch/components/AIQuota/QuotaCardView.swift`

单个 provider 的额度卡片，显示：

- Provider 图标和名称
- 各窗口使用率（水平进度条 + 百分比文字）
  - `five_hour` → "5h"
  - `seven_day` → "7d"
  - `seven_day_opus` → "Opus"
  - `seven_day_sonnet` → "Sonnet"
  - 未知窗口 → 原始 name
- 最近的重置倒计时
- 状态提示：
  - 凭据未找到 → "Run `claude`/`codex` CLI to login"
  - 凭据过期 → "Token expired, re-login required"
  - 查询失败 → 显示错误信息
  - 加载中 → ProgressView

#### `QuotaProgressBar.swift`

**文件位置**：`boringNotch/components/AIQuota/QuotaProgressBar.swift`

水平进度条（类似现有 MusicSlider 风格）：

- 颜色随使用率变化：0-50% 绿色 → 50-80% 黄色 → 80-100% 红色
- 高度 6pt，圆角

视觉风格与现有 UI 保持一致（深色背景、圆角、紧凑布局）。

### 第 5 步：集成到 Notch 导航

#### 5a. 扩展 NotchViews 枚举

**修改文件**：`boringNotch/enums/generic.swift`

```swift
public enum NotchViews {
    case home
    case shelf
    case quota  // 新增
}
```

#### 5b. 在 ContentView 中路由

**修改文件**：`boringNotch/ContentView.swift`

在 `NotchLayout` 的 `switch coordinator.currentView` 中添加：

```swift
case .quota:
    AIQuotaView()
```

#### 5c. 在 Tab 栏中添加入口

**修改文件**：`boringNotch/components/Tabs/TabSelectionView.swift` 或 `BoringHeader.swift`

当 `Defaults[.showAIQuota]` 为 true 时，在 header tab 区域添加 quota tab 按钮。切换到 quota tab 时触发立即刷新。

### 第 6 步：设置项

**修改文件**：`boringNotch/models/Constants.swift`

```swift
extension Defaults.Keys {
    static let showAIQuota = Key<Bool>("showAIQuota", default: false)
}
```

**修改文件**：`boringNotch/components/Settings/SettingsView.swift`

在 Appearance 页面的 **"Additional features"** section（与 `showMirror`、`showNotHumanFace` 同区）添加：

```swift
Defaults.Toggle(key: .showAIQuota) {
    Text("Show AI quota (Claude & Codex)")
}
```

### 第 7 步：生命周期连接

**修改文件**：`boringNotch/boringNotchApp.swift`

监听 `Defaults[.showAIQuota]` 变化：
- 变为 true → `AIQuotaManager.shared.startAutoRefresh()`
- 变为 false → `AIQuotaManager.shared.stopAutoRefresh()`
- 启动时检查一次初始值

---

## 文件变更清单

| 操作 | 文件路径 | 说明 |
|------|----------|------|
| **新建** | `boringNotch/models/AIQuotaModels.swift` | 数据模型（含 CodingKeys） |
| **新建** | `BoringNotchXPCHelper/AICredentialReader.swift` | XPC Helper 端凭据读取（Keychain + 文件） |
| **新建** | `boringNotch/managers/AIQuotaManager.swift` | 网络请求 + 状态管理 + 生命周期控制 |
| **新建** | `boringNotch/components/AIQuota/AIQuotaView.swift` | UI 主视图 |
| **新建** | `boringNotch/components/AIQuota/QuotaCardView.swift` | 单 provider 额度卡片 |
| **新建** | `boringNotch/components/AIQuota/QuotaProgressBar.swift` | 水平进度条组件 |
| **修改** | `BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift` | 新增凭据读取 protocol 方法 |
| **修改** | `boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift` | 同步 protocol 副本 |
| **修改** | `BoringNotchXPCHelper/BoringNotchXPCHelper.swift` | 实现新 protocol 方法 |
| **修改** | `boringNotch/XPCHelperClient/XPCHelperClient.swift` | 新增凭据读取 client 方法 |
| **修改** | `boringNotch/models/Constants.swift` | 添加 `showAIQuota` 配置项 |
| **修改** | `boringNotch/enums/generic.swift` | NotchViews 新增 `.quota` |
| **修改** | `boringNotch/ContentView.swift` | 路由 `.quota` 视图 |
| **修改** | `boringNotch/components/Notch/BoringHeader.swift` | 添加 quota tab 入口 |
| **修改** | `boringNotch/components/Settings/SettingsView.swift` | Additional features 添加开关 |
| **修改** | `boringNotch/boringNotchApp.swift` | 生命周期连接 |
| **修改** | `boringNotch.xcodeproj` | 将新文件添加到 Xcode 项目 |

---

## 注意事项

1. **只读凭据**：我们只读取已有的 OAuth token，不实现登录/刷新流程。如果 token 过期，UI 提示用户重新运行 `claude` / `codex` CLI 登录
2. **Sandbox 安全**：凭据读取全部在 unsandboxed XPC Helper 中完成；主 app 仅通过 XPC 接口获取 token 字符串，token 仅在内存中使用，不持久化到磁盘
3. **网络权限**：主 app 已有 `com.apple.security.network.client` 权限，可直接调用 Anthropic 和 ChatGPT API
4. **优雅降级**：如果凭据不存在或查询失败，不影响 notch 其他功能，quota tab 中显示提示状态
5. **性能**：网络请求在后台 Task 执行，不阻塞 UI；仅在功能开启时刷新；5 分钟间隔避免频繁请求
6. **隐私**：默认关闭（`showAIQuota` default: false），用户需手动在 Settings > Appearance > Additional features 中启用
7. **兼容性**：解析逻辑保留对未知 API 响应窗口的前向兼容；UI 文案显示"已用 X%"（非"剩余额度"），准确反映 API 语义
