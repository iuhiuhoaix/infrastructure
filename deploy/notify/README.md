# notify 通知中心（ntfy）运维手册

> 定位：外围组件 + 公共设施。事件 → 推送 转发层，不存消息、不做聊天、可重建。
> 挂 `devops-internal`（容器名 `ntfy`），Web/API 内网直连 `192.168.199.131:8084`。

## 首次部署

```bash
# 1. 准备 .env（从 .env.example 拷贝，chmod 600）
cp .env.example .env && chmod 600 .env

# 2. 启动
docker compose up -d

# 3. 创建管理员用户 + API token
docker exec ntfy ntfy user add --role=admin admin <强密码>
docker exec ntfy ntfy token add admin ops
#    ↑ 输出形如 tk_xxxxxxxx 的 token，即为 API 凭据
```

> 注意：`deny-all` 已内置在 .env.example，容器起来就拒绝未认证访问；
> 用户/token 用 `docker exec` 命令行直接写 auth.db，不受 HTTP 层 deny-all 影响。

## 发消息（pub）

```bash
# 最简单（topic 名随意，持 token 即可创建/订阅自己的 topic）
curl -d "构建完成" -H "Authorization: Bearer tk_xxx" \
  http://192.168.199.131:8084/build-finished

# 带标题 + 优先级
curl -H "Authorization: Bearer tk_xxx" \
  -H "Title: Jenkins" -H "Priority: high" -d "MR #42 构建失败" \
  http://192.168.199.131:8084/build-finished

# 容器内互访（devops-internal，无需走宿主端口）
curl -d "hi" -H "Authorization: Bearer tk_xxx" http://ntfy/ci-events
```

## 收消息（sub）

```bash
# 轮询拉最近一条（JSON）
curl -s -H "Authorization: Bearer tk_xxx" \
  "http://192.168.199.131:8084/build-finished/json?poll=1"

# SSE 实时订阅（保持连接，新消息即时推送）
curl -N -H "Authorization: Bearer tk_xxx" \
  http://192.168.199.131:8084/build-finished/sse

# Web UI：浏览器打开 http://192.168.199.131:8084 直接订阅查看
```

## 接收端订阅（开放，零成本）

| 接收端 | 方案 |
|---|---|
| Android / iOS | ntfy 官方 App，填服务器地址 + token |
| 浏览器 | Web UI 订阅，弹桌面通知 |
| 企业微信 / 钉钉群 | webhook 转换（轻量转换器） |
| 邮件 | ntfy 自带 SMTP 转发 |
| 本地脚本 | `tools/ntfy-sub.py`（零依赖 Python 订阅客户端） |

## topic 命名规范（约定）

统一 `{项目/客户}.{事件类型}`，用 `.` 分隔（**别用 `/`**，会跟 URL 路径冲突）：

| 示例 topic | 含义 |
|---|---|
| `c0108.ci` | c0108 客户构建通知 |
| `assets.ci` | 自有产品（assets）构建 |
| `infra.ci` | 基建平台自身构建 |
| `ops.alerts` | 服务器 / 服务告警 |
| `devops-test` | 测试频道 |

订阅端支持通配符：`*.ci` 收全部构建、`c0108.*` 收某客户全部事件、`*` 全收。
频道零管理：发第一条消息即自动创建，不需要创建/审批。

## 升级 / 维护

```bash
# 升级（先备份 auth.db）
docker compose pull && docker compose up -d

# 备份（只 auth.db 有状态；消息缓存可丢）
tar czf ntfy-auth-backup.tgz data/auth.db
```

## 已知接入方（待启动，见 docs/tools-registry.md）

- Jenkins pipeline `post` 块 curl 一行（原生直连）
- AI Agent 执行完任务 POST 通知（原生直连）
- GitLab / Plane / Nexus webhook → 轻量转换器（JSON payload 重组）
