# 好大一个基建 · 自建 DevOps 平台

中小型研发团队自建的 DevOps / 研发交付平台，单 Docker Host 多独立 Compose 部署。

## 平台组成

| 服务 | 角色 | 域名 |
|---|---|---|
| Nginx | 宿主机统一 TLS 入口 / 反向代理 | — |
| GitLab | 代码仓库 / MR / Registry / SSH | git.example.com |
| Plane | 项目管理 / 需求 / 任务 | plane.example.com |
| Jenkins | CI/CD 流水线 / 构建 | jenkins.example.com |
| Nexus | 依赖代理 + 制品仓库 + Docker Registry | nexus.example.com / reg.example.com |
| RagFlow | 知识库 / 文档检索 / RAG | rag.example.com |

构建基础设施：Linux Docker Agent（同 Host 容器）、Windows Agent（独立 Windows Server，WebSocket inbound）。

## 目录结构

```
.
├── docs/                       # 架构设计文档（HTML，浏览器打开）
│   ├── architecture.html           业务架构：Customer→Plane→GitLab→Jenkins→Nexus→Deploy
│   └── deploy-architecture.html    部署架构：Compose 划分 / Network / Nginx / 备份 / 灾难恢复
├── deploy/                     # 部署骨架（对应宿主机 /opt/devops/）
│   ├── network/setup-network.sh     创建 external network devops-internal
│   ├── gitlab/   compose.yaml + .env.example   (PG+Redis 自管)
│   ├── plane/    compose.yaml + .env.example   (PG+Redis+MinIO 自管)
│   ├── jenkins/  compose.yaml + .env.example   (无内部依赖)
│   ├── nexus/    compose.yaml + .env.example   (单容器)
│   ├── ragflow/  compose.yaml + .env.example   (ES+PG+Redis+MinIO 自管)
│   ├── nginx/conf.d/devops.conf     宿主机 Nginx 站点配置
│   ├── backup/backup-all.sh         统一备份调度
│   ├── dr/restore-from-scratch.sh   灾难恢复 8 步
│   └── README.md                    部署/升级/恢复指引
└── .gitignore
```

> `deploy/<app>/data/`、`backup/`、`.env` 是运行时产物，不入库（见 `.gitignore`）。

## 架构核心决策

- **每应用独立 Compose**，内部依赖自管 → 升级/备份/迁移/故障隔离全最优
- **双网络**：external `devops-internal`（跨服务容器名互访）+ 各应用 `default`（锁内部依赖）
- **宿主机 Nginx** 统一 TLS 入口，仅暴露 `80/443` + GitLab SSH `2222`
- **bind mount** 持久化到 `/opt/devops/<app>/data/`，tar 即搬迁
- **应用级热备** + GPG 加密 + rsync 异地；`.env` chmod 600 管密钥
- 不引入 K8s / Swarm / Vault / Consul / Service Mesh

详见 `docs/deploy-architecture.html`。

## 快速开始

```bash
# 拷贝 deploy/ 到宿主机
sudo cp -r deploy /opt/devops && cd /opt/devops

bash network/setup-network.sh                    # 建 devops-internal
for a in gitlab plane jenkins nexus ragflow; do  # 准备 .env
  cp $a/.env.example $a/.env && chmod 600 $a/.env && $EDITOR $a/.env
done
for a in nexus gitlab plane ragflow jenkins; do cd $a && docker compose up -d && cd ..; done

# Nginx + 证书
apt install -y nginx certbot python3-certbot-nginx
ln -s /opt/devops/nginx/conf.d/devops.conf /etc/nginx/conf.d/devops.conf
nginx -t && systemctl reload nginx
certbot --nginx -d git.example.com -d plane.example.com -d jenkins.example.com \
        -d nexus.example.com -d reg.example.com -d rag.example.com -d reg.git.example.com
```

完整指引见 `deploy/README.md`。
