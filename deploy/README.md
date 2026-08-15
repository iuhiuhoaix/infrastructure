# DevOps 平台 · Docker Compose 部署骨架

自建 DevOps 平台的可落地部署骨架。配套架构设计文档见上级目录 `../deploy-architecture.html`。

## 架构一句话

**5 份独立 Compose（gitlab/plane/jenkins/nexus/ragflow，各自管内部依赖）+ 1 个 external network `devops-internal`（仅各应用"对外服务容器"接入）+ 宿主机 Nginx 统一 TLS 入口 + 仅暴露 80/443/2222 + bind mount 持久化 + 应用级热备 + .env(GPG) 管密钥。**

## 目录结构（对应宿主机 /opt/devops/）

```
deploy/
├── network/setup-network.sh      # 创建 external network devops-internal
├── gitlab/        compose.yaml + .env.example   (PG+Redis 自管)
├── plane/         compose.yaml + .env.example   (PG+Redis+MinIO 自管)
├── jenkins/       compose.yaml + .env.example   (无内部依赖)
├── nexus/         compose.yaml + .env.example   (单容器)
├── ragflow/       compose.yaml + .env.example   (ES+PG+Redis+MinIO 自管)
├── nginx/conf.d/devops.conf + README.md          (宿主机 Nginx)
├── backup/backup-all.sh          # 统一备份调度(daily/weekly/monthly)
└── dr/restore-from-scratch.sh    # 灾难恢复 8 步
```

## 端口策略（核心）

| 服务 | 宿主机绑定 | 对外? | 说明 |
|---|---|---|---|
| Nginx | :80 :443 | 是 | 唯一对外 Web 入口 |
| GitLab SSH | :2222 | 是 | git clone ssh://git@git.example.com:2222 |
| GitLab Web | 127.0.0.1:8080 | 否 | Nginx 反代 |
| Plane | 127.0.0.1:3000 | 否 | Nginx 反代 |
| Jenkins | 127.0.0.1:8082 | 否 | Nginx 反代 |
| Nexus UI | 127.0.0.1:8081 | 否 | Nginx 反代 |
| Nexus Registry | 127.0.0.1:8083 | 否 | Nginx 反代 reg.example.com |
| RagFlow | 127.0.0.1:9380 | 否 | Nginx 反代 |
| 各 PG/Redis/ES/MinIO | — | 否 | 仅各自 default network |

容器间内部通信走 `devops-internal` 容器名（如 `http://gitlab`、`http://nexus:8081`），不经这些端口、不经 Nginx。

## 首次部署步骤

```bash
# 0. 拷贝本目录到宿主机 /opt/devops
sudo cp -r deploy /opt/devops && cd /opt/devops

# 1. 创建 external network
bash network/setup-network.sh

# 2. 各应用准备 .env（从 .env.example 拷贝并改密码，权限 600）
for app in gitlab plane jenkins nexus ragflow; do
  cp $app/.env.example $app/.env && chmod 600 $app/.env
  $EDITOR $app/.env
done

# 3. 启动各应用（顺序无关，但建议 nexus 先起供 CI 拉依赖）
cd nexus && docker compose up -d && cd ..
cd gitlab && docker compose up -d && cd ..
cd plane && docker compose up -d && cd ..
cd ragflow && docker compose up -d && cd ..
cd jenkins && docker compose up -d && cd ..

# 4. 配置宿主机 Nginx + 证书
apt install -y nginx certbot python3-certbot-nginx
ln -s /opt/devops/nginx/conf.d/devops.conf /etc/nginx/conf.d/devops.conf
nginx -t && systemctl reload nginx
certbot --nginx -d git.example.com -d reg.git.example.com -d plane.example.com \
        -d jenkins.example.com -d nexus.example.com -d reg.example.com -d rag.example.com

# 5. 注册备份定时任务
crontab -e
#   0 2 * * *   /opt/devops/backup/backup-all.sh daily
#   0 3 * * 0   /opt/devops/backup/backup-all.sh weekly
#   0 4 1 * *   /opt/devops/backup/backup-all.sh monthly
```

## 升级（单应用零牵连）

```bash
cd /opt/devops/ragflow
# 改 compose.yaml 里 image tag（或直接 latest）后：
docker compose pull && docker compose up -d
# 其他应用零感知、零重启
```
> 升级前先跑对应应用备份。GitLab 跨大版本需按官方次序逐 minor 升级，不可跳级。

## 灾难恢复

```bash
# 新机装好 docker/nginx/certbot 后：
/opt/devops/dr/restore-from-scratch.sh <异地备份文件.tar.gpg>
```

## 关键设计决策（详见 deploy-architecture.html）

1. **每应用独立 Compose**：升级/备份/迁移/故障隔离全最优。
2. **双网络模型**：`devops-internal`(external，跨服务通信) + 各应用 `default`(锁内部依赖)。
3. **Nginx 宿主机运行**：证书/升级链路最短，与编排解耦。
4. **bind mount 持久化**：tar 即可整应用搬迁。
5. **.env + GPG**：中小规模不需要 Vault。
6. **不引入 K8s/Swarm/Vault/Consul/Service Mesh**：当前规模用不上，引入只增负担。

## 逻辑访问白名单（服务间调用收敛）

```
GitLab   → Jenkins   (Webhook)
Jenkins  → GitLab    (拉代码/回写状态)
Jenkins  → Nexus     (推制品/拉依赖)
GitLab   → RagFlow   (文档同步)
RagFlow  → GitLab    (检索文档源)
Plane    → GitLab    (关联仓库/MR)
Nexus    → Build Agent (反向: Agent 拉 Nexus)
```
