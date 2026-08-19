# tools/ — 本地工具集

> 本目录收容**本地 / 客户端侧**的小工具：跑在开发机上、消费服务器服务（ntfy、Plane、GitLab 等）的脚本与程序。
>
> 与 `deploy/` 的分工：
> - `deploy/` — **服务器部署骨架**（唯一准绳，同步到服务器 `/opt/infrastructure`），进备份、进灾难恢复
> - `tools/` — **客户端工具**，不进服务器编排、不进备份，坏了重写不心疼（对齐"玩具不进编排"原则）

## 工具清单

| 工具 | 作用 | 对应组件 / 基建 | 依赖 |
|---|---|---|---|
| `ntfy-sub.py` | ntfy 消息订阅客户端：实时收通知 / 发测试消息 / 拉最近消息 | **notify 通知中心**（ntfy v2.26.3，`192.168.199.131:8084`，部署位 `deploy/notify/`） | Python 3.9+，标准库零第三方依赖 |

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
