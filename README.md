# 好大一个基建 · 自建 DevOps 平台

中小型研发团队自建的 DevOps / 研发交付平台，单 Docker Host 多独立 Compose 部署。
服务 100+ 客户的 ERP/MES 插件场景，4 人研发团队。

## 服务一览

服务器：`192.168.199.131`（Fedora 42，32C/94G）。现阶段内网直连，暂未接 Nginx/TLS（等外网地址再统一接）。

| 服务 | 职能 | 地址 | SoT? | 备注 |
|---|---|---|---|---|
| GitLab | 工程资产（代码/文档/配置/MR/Release 声明） | `:8080` HTTP · `:2222` SSH | ✅ | 19.1.3-ce，数据 `/dockerData/gitlab` |
| Plane | 项目工作（需求/任务/进度/里程碑） | `:3000` | ✅ | 1.4.0，workspace=`kdev` |
| Jenkins | 执行层（Build/Test/Package/Deploy） | `:8082` | ❌ | 2.568.2-jdk21，2 job + win-build 节点 |
| Nexus | 制品（包/镜像/依赖/Registry） | `:8081` UI · `:8083` Registry | ✅ | 数据 `/dockerData/nexus` |
| RagFlow | 知识索引（检索/RAG，可重建投影） | `:9380` | ❌ | 本体对接中（模型层已就绪） |
| AI Agent | 横向智能入口（不持有数据/不绕过权限） | — | ❌ | MCP 接入各组件 |

**辅助服务**：

| 服务 | 地址 | 用途 |
|---|---|---|
| RagFlow 模型服务 · embedding | `:6101` | TEI 1.8.3，BGE-M3（1024 维） |
| RagFlow 模型服务 · reranker | `:6102` | TEI 1.8.3，bge-reranker-v2-m3 |
| win-build agent | `192.168.199.249` | Jenkins Windows 构建节点（Windows Server 2022） |
| mihomo 代理 | `:7897` HTTP · `:7898` SOCKS5 | 服务器拉镜像/拉 git 走代理（select 组固定 HKT01） |

## 架构基线 v1.1

**7 层主链路**：Customer → Plane → GitLab → Jenkins → Build Infra → Nexus → Deployment

**6 组件职能划分（各司其职，零重叠）**：
- GitLab Release 只声明不存二进制（二进制只在 Nexus）
- 关闭 GitLab 内置 Registry（Docker Image 统一 Nexus）
- Plane Issue=业务需求 / GitLab Issue=代码侧，互相引用
- 不引入 K8s / Swarm / Vault / Consul / Service Mesh / Wiki / CMDB / PMO
- 配置优先于复制（禁止产品源码分叉）；Customer 不占席位

详见 `docs/architecture-review.md`（A–N 14 部分 + 12 项判断 + 基线 v1.1）。

## 部署形态

- **单 Docker Host + 5 份独立 Compose**：每应用独立 Compose，内部依赖自管 → 升级/备份/迁移/故障隔离全最优
- **双网络**：external `devops-internal`（跨服务容器名互访）+ 各应用 `default`（锁内部依赖）
- **bind mount** 持久化到 `/dockerData/<app>/`，tar 即搬迁
- 仅暴露 `80/443` + GitLab SSH `2222`（现阶段内网直连 0.0.0.0）
- 应用级热备 + GPG 加密 + rsync 异地；`.env` chmod 600 管密钥

详见 `docs/deploy-architecture.html`。

## GitLab 组织模型

```
kdev/                          (顶层 Group · 研发共享)
├── 客户/<slug>/               (真实客户 · 外部交付)
│   ├── 客户插件
│   └── 客户资料
└── assets/                    (虚拟客户=公司 · 内部自有)
    ├── products/              (自有产品)
    ├── components/            (通用组件)
    └── docs/                  (公共知识) ← 本仓库
```

- 三层封顶：Group → Subgroup → repo
- 权限：1 Admin + N Regular(Maintainer)；客户不参与不占席位
- Plane 对齐：Project=客户/assets；Module=产品线(erp/mes)；Cycle=Sprint；Label=工作类型
- GitLab Issue(代码侧) ↔ Plane Issue(业务侧) URL 互引；数据不同步，各系统自治

详见 `docs/gitlab-plane-model.md`。

## 目录结构

```
.
├── docs/                       # 架构设计文档
│   ├── architecture-review.md      架构基线 v1.1（6 组件职能 + 12 项判断）
│   ├── gitlab-plane-model.md       GitLab/Plane 组织模型
│   ├── architecture.html           业务架构（Customer→Plane→GitLab→Jenkins→Nexus→Deploy）
│   └── deploy-architecture.html    部署架构（Compose/Network/Nginx/备份/灾难恢复）
├── deploy/                     # 部署骨架（对应宿主机 /opt/infrastructure/deploy/）
│   ├── network/setup-network.sh    创建 external network devops-internal
│   ├── gitlab/   compose.yaml + .env.example   (PG+Redis 自管)
│   ├── plane/    compose.yaml + .env.example   (PG+Redis+MinIO 自管)
│   ├── jenkins/  compose.yaml + .env.example   (无内部依赖)
│   ├── nexus/    compose.yaml + .env.example   (单容器)
│   ├── ragflow/  compose.yaml + .env.example   (官方 v0.26.4，ES+PG+Redis+MinIO)
│   ├── ragflow-models/             TEI 模型服务（embedding + reranker，独立 compose）
│   ├── nginx/conf.d/devops.conf    宿主机 Nginx 站点配置
│   ├── backup/backup-all.sh        统一备份调度
│   ├── dr/restore-from-scratch.sh  灾难恢复 8 步
│   └── README.md                   部署/升级/恢复指引
├── PROGRESS.md                 # 项目进度与服务器实况
└── README.md                   # 本文件
```

> `deploy/<app>/data/`、`backup/`、`.env` 是运行时产物，不入库（见 `.gitignore`）。

## 服务器更新流程

**所有 docker-compose 的修改一律在 git 仓库进行**，不得直接在服务器上改 compose；服务器 `/opt/infrastructure/` 仅为部署落地，以 git 为唯一准绳。

变更闭环：本地改 → commit → push → 服务器 `cd /opt/infrastructure && git pull`。

- GitHub 直连不稳定（时通时断），服务器 pull 走 mihomo 代理：`http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897 git pull`
- Linux 上 git 忽略大写 `HTTP_PROXY`/`HTTPS_PROXY`（curl 惯例防注入），必须用小写或 `git -c http.proxy=`
- 勿写死 `git config http.proxy`（网络切换时反而卡死）

## 快速开始

```bash
# 拷贝 deploy/ 到宿主机
sudo cp -r deploy /opt/infrastructure && cd /opt/infrastructure

bash network/setup-network.sh                    # 建 devops-internal
for a in gitlab plane jenkins nexus ragflow ragflow-models; do
  cp $a/.env.example $a/.env && chmod 600 $a/.env && $EDITOR $a/.env
done
for a in nexus gitlab plane ragflow-models ragflow jenkins; do
  cd $a && docker compose up -d && cd ..
done
```

完整指引见 `deploy/README.md`，当前实况见 `PROGRESS.md`。
