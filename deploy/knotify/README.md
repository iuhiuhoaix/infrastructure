# knotify 通知网关（Company.Notify）运维手册

> 定位：外围组件 + 公共设施。**自研统一消息推送网关**，替换原 ntfy。
> 挂 `devops-internal`（容器名 `knotify`），Web/API 内网直连 `192.168.199.131:8084`。
> 源码独立仓库：`git@192.168.199.131:kdev/assets/knotify.git`（本目录只放编排，不复制源码）。

## 架构一句话

业务系统一条 REST 调用（`X-Api-Key`）→ 网关落库即回 202 → SQL Outbox 至少一次投递 → SignalR 实时推给接收人 → 客户端 ACK 推进 `Accepted→Persisted→Queued→Dispatched→Delivered→Read` 状态机。**零中间件依赖**（不引入 Kafka/RabbitMQ），单节点试点（SQLite + Local 模式），可水平扩展（Processor 模式 + Worker）。

## 为什么替换 ntfy（差异要点）

| 维度 | ntfy（旧） | knotify（新） |
|---|---|---|
| 投递模型 | topic 广播，无"接收人"概念 | 按**接收人**（`user:10021` / `role:ops`）定向投递，逐人独立投递记录 |
| 送达确认 | 无服务端状态机 | `Delivered / Read / Failed / Expired` 全状态机，服务端可查 |
| 离线补拉 | topic 级 `since` | 用户级 `sync` 游标，断线重连按人补拉 |
| 发布方认证 | token/ACL | `X-Api-Key` + HMAC 防重放 + 限流 |
| Windows 客户端 | 无官方版 | WPF 桌面代理（托盘/Toast/未读角标/免打扰） |
| 技术栈 | Go（外来） | C#/.NET 10（自有资产，同栈维护） |
| 接入代价 | 客户端自带 | 客户端需按新 API 接入（CLI/WPF/Web 三端已备） |

完整评估见 knotify repo `docs/ADR-001-ntfy-evaluation.md`。

## 首次部署（服务器 192.168.199.131）

```bash
# 1. 同步基建编排（本目录）——沿用服务器更新流程
cd /opt/infrastructure && git pull

# 2. clone knotify 源码（build context 指向这里，基建 repo 不复制源码）
git clone git@192.168.199.131:kdev/assets/knotify.git /opt/knotify

# 3. 准备 .env（强密钥；openssl rand -hex 32 生成，chmod 600）
cd /opt/infrastructure/deploy/knotify
cp .env.example .env && chmod 600 .env && $EDITOR .env

# 4. 构建 + 启动（首次构建需拉 mcr.microsoft.com/dotnet sdk/aspnet 10.0 镜像，走 mihomo 代理，约几分钟）
docker compose up -d --build

# 5. 验证
curl -s http://localhost:8084/health                      # 期望 200（含 DB 探针）
docker compose ps                                          # knotify healthy
curl -s http://192.168.199.131:8084/swagger/index.html    # Swagger 在线文档

# 6. 全部验证通过后，停掉旧 ntfy（回滚见文末）
cd /opt/infrastructure/deploy/notify && docker compose down
```

> docker daemon 已配 proxies（走 mihomo）+ no-proxy 内网段，`mcr.microsoft.com` 属于需代理域名，构建前确认代理可用。

## 发消息（pub，业务系统侧）

发布方认证：`X-Api-Key: <Seed__ApiKey>`。落库即回 202，实际投递异步。

```bash
# 定向发给指定接收人（用户/角色，见 knotify repo docs/API.md）
curl -s -X POST http://192.168.199.131:8084/api/v1/notifications \
  -H "X-Api-Key: <api-key>" -H "Content-Type: application/json" \
  -d '{
    "source": "jenkins",
    "eventType": "ci.done",
    "title": "构建完成",
    "body": "GNA_K3CloudPlugin #42 SUCCESS",
    "recipients": ["user:10021"],
    "priority": "high",
    "actionUrl": "http://192.168.199.131:8082/job/GNA_K3CloudPlugin/42"
  }'

# 容器内互访（devops-internal，无需走宿主端口）
curl -s -X POST http://knotify:8080/api/v1/notifications \
  -H "X-Api-Key: <api-key>" -H "Content-Type: application/json" -d '{...}'
```

- `recipients` 与 `topic` 至少其一；带 `topic` 时该 topic 当前订阅者全收。
- `priority`：`low/normal/default/high/urgent` 或 `1-5`。
- `deduplicationKey`：相同 `(source, deduplicationKey)` 视为同一条（幂等，重复发布 `deduped=true`）。

## 收消息（sub，客户端侧）

客户端流程：持 ApiKey 签 `connect-token`（按接收人）→ 拿 Bearer accessToken → 查询 / Hub / Ack。

```bash
# 1. 签发连接令牌
curl -s -X POST http://192.168.199.131:8084/api/v1/connect-token \
  -H "X-Api-Key: <api-key>" -H "Content-Type: application/json" \
  -d '{"recipient":"user:10021"}'
#   → { "accessToken": "...", "expiresAt": "..." }

# 2. 查未读 / 补拉
curl -s "http://192.168.199.131:8084/api/v1/notifications?status=unread" \
  -H "Authorization: Bearer <accessToken>"

# 3. 客户端程序（多端已备）：
#   CLI    src/Company.Notify.Client.Cli   dotnet run -- listen / sync / ack-delivered / ack-read
#   WPF    src/Company.Notify.Client.Desktop  托盘/Toast/未读角标/免打扰/自启
#   Web    Client.Web/index.html  自包含页面（内置 SignalR 实时接收 + 自动 Ack）
```

> 接收的**客户客户端程序正在开发中**（面向客户的接收端），接入就按上面三端模式走。

## 已知接入方迁移（原 ntfy 接入方，见 docs/tools-registry.md）

| 接入方 | 原（ntfy） | 新（knotify） |
|---|---|---|
| Jenkins pipeline `post` 块 | curl POST `:8084/<topic>` + Bearer token | curl POST `:8084/api/v1/notifications` + `X-Api-Key`，`recipients` 定向或 `topic` 广播 |
| AI Agent | 同上 topic 广播 | 同上，`source=agent` |
| 轻量转换器（GitLab/Plane/Nexus webhook） | 重组后 POST topic | 重组后 POST `/api/v1/notifications` |
| 本地订阅脚本 | `tools/ntfy-sub.py`（已退役） | knotify CLI / WPF / Web |

## 升级 / 维护

```bash
# 升级网关：改 compose.yaml 里 image tag（或源码改动后重 build）
docker compose up -d --build

# 健康检查：GET /health（200/503，含 DB 探针），compose 已配 healthcheck
```

## 备份

```bash
# 只有 SQLite notify.db 是状态（消息+投递+审计）；bind mount 在 ./data（或 KNOTIFY_DATA_DIR）
cd /opt/infrastructure/deploy/knotify && tar czf knotify-backup.tgz data/
# 统一备份调度 deploy/backup/backup-all.sh 需补 knotify 钩子（待加）
```

## 回滚（换回 ntfy）

```bash
cd /opt/infrastructure/deploy/notify && docker compose up -d   # 旧 ntfy 编排仍保留
cd /opt/infrastructure/deploy/knotify && docker compose down
# 客户端/接入方把地址改回 ntfy 用法即可；两个编排文件并存，互不影响
```

> ntfy 编排 `deploy/notify/` 保留（标注已退役），knotify 稳定运行一段后确认无回滚需求再删除。
