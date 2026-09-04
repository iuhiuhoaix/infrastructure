# tools/ — 本地工具集

> 本目录收容**本地 / 客户端侧**的小工具：跑在开发机上、消费服务器服务（ntfy、Plane、GitLab 等）的脚本与程序。
>
> 与 `deploy/` 的分工：
> - `deploy/` — **服务器部署骨架**（唯一准绳，同步到服务器 `/opt/infrastructure`），进备份、进灾难恢复
> - `tools/` — **客户端工具**，不进服务器编排、不进备份，坏了重写不心疼（对齐"玩具不进编排"原则）

## 工具清单

| 工具 | 作用 | 对应组件 / 基建 | 依赖 |
|---|---|---|---|
| `knotify-pub.py` | knotify 通知发布：POST `/api/v1/notifications`（`X-Api-Key`，按接收人定向 / topic 广播） | **notify 通知中心**（knotify 自研网关，`192.168.199.131:8084`，部署位 `deploy/knotify/`） | Python 3.9+，标准库零第三方依赖 |
| `knotify-sub.py` | knotify 通知订阅：签 connect-token → 查未读 → 自动回执；`--listen` 轮询监听 / `--test` 自测链路 | 同上 | Python 3.9+，标准库零第三方依赖 |
| `ntfy-sub.py` | ~~ntfy 消息订阅客户端~~（**已退役**：ntfy 已被自研网关 knotify 替换，见 `deploy/knotify/`；订阅改用本目录 knotify-sub.py 或 knotify 官方 CLI/WPF/Web 客户端） | notify 通知中心（历史：ntfy v2.26.3） | Python 3.9+，标准库零第三方依赖 |

---

## knotify-pub.py / knotify-sub.py

### 是什么

notify 通知中心（knotify 自研网关）的发布/订阅脚本，Python 标准库零依赖，替代已退役的 ntfy-sub.py。

### 对应组件

- **notify 通知中心**（knotify / Company.Notify，.NET 10）
  - 服务地址：`http://192.168.199.131:8084`
  - 部署骨架（compose / .env.example / 运维手册）：`deploy/knotify/`
  - 服务端密钥（ApiKey / ConnectTokenSecret 等）：服务器 `/opt/infrastructure/deploy/knotify/.env`
  - 完整 API：knotify repo `docs/API.md`

### 用法

```bash
# 环境变量
set KNOTIFY_SERVER=http://192.168.199.131:8084
set KNOTIFY_API_KEY=<服务器 deploy/knotify/.env 的 Seed__ApiKey>
set KNOTIFY_RECIPIENT=user:10021

# 发送（按接收人定向 / topic 广播）
python knotify-pub.py --title "构建完成" --body "v1.0 SUCCESS" --recipient user:10021 --priority high
python knotify-pub.py --body "下午 4 点周会" --topic ops.alerts --source meeting

# 接收（拉一次未读并自动回执）
python knotify-sub.py --recipient user:10021

# 接收（轮询监听，新消息即打印）
python knotify-sub.py --recipient user:10021 --listen

# 自测链路（发一条给自己再拉回验证）
python knotify-sub.py --test
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `KNOTIFY_SERVER` | `http://192.168.199.131:8084` | 网关地址 |
| `KNOTIFY_API_KEY` | 空 | 发布方 ApiKey（必填，`X-Api-Key` 头） |
| `KNOTIFY_RECIPIENT` | 空 | 默认接收人（如 `user:10021`） |

> 接收人格式：`user:<id>` / `role:<name>`；`--listen` 是轮询替代 SignalR（实时推送走 `/hubs/notifications`，零依赖脚本用轮询够用）。

### 接收人 / topic 约定

knotify 是**按接收人定向投递**模型（区别于 ntfy 的 topic 广播）：
- 定向：`--recipient user:10021`（逐人独立投递记录 + 状态机）
- 广播：`--topic ops.alerts`（该 topic 当前订阅者全收）
- 事件类型沿用 `{项目/客户}.{事件类型}` 约定（如 `c0108.ci`），放 `--event-type` 字段

---

## ntfy-sub.py

### 是什么

ntfy 通知中心的订阅端脚本：挂后台实时收指定 topic 的消息（每个 topic 一个长连接线程，断线自动 5 秒重连），支持通配符订阅。附带 `--test` 自测链路、`--once` 一次性拉取。

### 对应组件

- **notify 通知中心**（ntfy v2.26.3，token + deny-all 鉴权）
  - 服务地址：`http://192.168.199.131:8084`
  - 部署骨架（compose / .env.example / 运维手册）：`deploy/notify/`
  - 服务端密钥（admin 密码 / ops token）：服务器 `/opt/infrastructure/deploy/notify/.env`

### 用法

```bash
# 实时订阅（多 topic、支持通配符；Ctrl+C 退出）
set NTFY_TOKEN=tk_xxx
python ntfy-sub.py devops-test *.ci

# 自测链路（发一条测试消息 + 拉回验证，验证完退出）
python ntfy-sub.py --test

# 一次性拉最近一条，不常驻
python ntfy-sub.py --once devops-test
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `NTFY_SERVER` | `http://192.168.199.131:8084` | ntfy 服务地址 |
| `NTFY_TOKEN` | 空 | 访问 token（deny-all 下必填，从服务器 `.env` 的 `NOTIFY_OPS_TOKEN` 取） |

> 已知坑（已内置规避）：HTTP 头只支持 ASCII，中文标题自动丢弃、消息正文不受影响；`json?poll=1` 返回 NDJSON 需逐行解析。

> ⚠️ **退役说明（2026-08-29）**：notify 通知中心已由自研网关 **knotify（Company.Notify）** 替换（选型与差异见 `deploy/knotify/README.md` 及 knotify repo `docs/ADR-001-ntfy-evaluation.md`）。本脚本所依赖的 ntfy 服务下线后即失效，**冻结不再维护**；订阅需求改用 knotify 客户端（CLI `src/Company.Notify.Client.Cli` / WPF `src/Company.Notify.Client.Desktop` / Web `Client.Web/index.html`），接入示例见 `deploy/knotify/README.md`。

### topic 命名规范（约定）

统一 `{项目/客户}.{事件类型}`，用 `.` 分隔（**别用 `/`**，会跟 URL 路径冲突）：

| 示例 topic | 含义 |
|---|---|
| `c0108.ci` | c0108 客户构建通知 |
| `assets.ci` | 自有产品（assets）构建 |
| `infra.ci` | 基建平台自身构建 |
| `ops.alerts` | 服务器 / 服务告警 |
| `devops-test` | 测试频道 |

订阅端可用通配符：`*.ci` 收全部构建，`c0108.*` 收某客户全部事件，`*` 全收。
频道零管理：发第一条消息即自动创建，不需要任何人批准。

### 扩展方向（待办）

- Windows 桌面弹窗（win10toast / plyer 一行依赖，或自写横幅/弹幕样式）
- 桌面弹幕插件（Tauri/Electron，见 `docs/tools-registry.md` 玩具区）

---

_新增工具时：在此清单加一行 + 一节说明，注明"做什么用 + 对应哪个组件/基建"。_
