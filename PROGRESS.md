# 项目进度与换机交接（2026-08-17）

> 用途：切换电脑时给新机器 WorkBuddy 看的交接文档。工作产物全在 git，本文件描述"当前做到哪 + 哪些东西要手动带"。

## 项目一句话

自建 DevOps 平台（单 Docker Host + 5 份独立 Compose）：Plane（项目管理）/ GitLab（代码 SoT）/ Jenkins（CI/CD）/ Nexus（制品+Registry）/ RagFlow（知识检索）+ 宿主机 Nginx。服务 100+ 客户的 ERP/MES 插件场景，4 人研发团队。

## 当前进度总览

### 已完成 ✅
| 项 | 状态 |
|---|---|
| 架构设计基线 v1.1（6 组件，剥离公司 CRM） | `docs/architecture-review.md` |
| GitLab/Plane 组织模型敲定 | `docs/gitlab-plane-model.md` |
| 部署骨架 deploy/ 齐备（compose + .env.example + 备份/恢复脚本） | 已入库 |
| 服务器 GitLab 19.1.3-ce 部署 | `192.168.199.131:8080`（SSH 2222） |
| 服务器 Plane 1.4.0 部署（微服务 4 前端 + MinIO 图片上传修复） | `192.168.199.131:3000` |
| 服务器 Nexus 接管（锁 digest，UI/Registry 双端口） | `8081` UI / `8083` Registry |
| 服务器 BGE-M3 embedding 留用 | `:7997`（RagFlow 对接） |
| 服务器 git 化切换 | `/opt/devops` → 软链 `/opt/infrastructure/deploy` |
| Dify 已停、SVN 已删 | 80/443 释放 |

### 待办 🔜
- **RagFlow**：灰灰基于官方 compose（MySQL 8.0.39 + nginx 9380:80）重写，我的骨架仅占位
- **Jenkins**：尚未部署（下一步）
- **Nginx 反代 / TLS**：等有外网地址再统一接（现阶段内网直连）
- 待深入：Nexus repo 划分策略 / Jenkins Label·Agent·Folder 组织 / RagFlow 权限 scope

## 服务器现状（192.168.199.131，Fedora 42，16C/31G）

| 组件 | 端口 | 说明 |
|---|---|---|
| GitLab | 8080 + 2222 | 数据 `/dockerData/gitlab`，root 密码在 `/opt/infrastructure/deploy/gitlab/.env` |
| Plane | 3000 | 数据 `/dockerData/plane`，9 容器全健康，`.env` 密码同侧 |
| Nexus | 8081 / 8083 | 数据 `/opt/infrastructure/deploy/nexus/data`（719M） |
| BGE-M3 | 7997 | `michaelf34/infinity:latest`，HF_HUB_OFFLINE=1 |
| mihomo | 7897 HTTP / 7898 SOCKS5 | 服务器拉镜像/拉 git 走 7897 代理 |

**服务器更新流程（已确立）**：本地改 → commit → push → 服务器 `cd /opt/infrastructure && git pull`（仓库级已配 http.proxy=127.0.0.1:7897）。

## 换机迁移清单

### 在 git 里的 — clone 即得，无需手动带
- `deploy/`（全部 compose、.env.example、脚本）— 唯一准绳
- `docs/`（架构文档 + 2 个 HTML）+ `README.md` + `PROGRESS.md`（本文件）
- 远程 `git@ssh.github.com:443/iuhiuhoaix/infrastructure.git`，HEAD = 本地 `407261d`，完全同步

### 不进 git — 必须手动带（3 样）
| 路径 | 内容 | 为什么 |
|---|---|---|
| 本项目 `.workbuddy/memory/` | MEMORY.md + 每日日志 | 项目记忆，`.gitignore` 排除，clone 不带 |
| 用户级 `~/.workbuddy/`（可选） | SOUL.md / IDENTITY.md / USER.md / MEMORY.md、skills/、mcp.json、workbuddy.db | 人设 + 全部技能 + 自动化，跨项目 |
| `~/.ssh/` 密钥 | id_ed25519 / id_rsa | GitHub push 用（或新机重新生成 key 加进 GitHub） |

### 不用带的
- 服务器上任何东西（`.env`、data、dockerData 都在 192.168.199.131，不在这台电脑）
- 本机 `deploy/*/data|backup|logs/`（本地无运行时数据，全在服务器）

## 推荐迁移路径

**git clone + 手动带 3 样**，不要整目录复制：

1. 新电脑装好 WorkBuddy + git
2. 把上表"必须手动带"的 3 样拷过去（`.workbuddy/memory/` 放进新 clone 的项目里，用户级配置放 `~/.workbuddy/`）
3. 把下面的 bootstrap prompt 粘给新电脑的 WorkBuddy，让它 clone 并自检

### Bootstrap prompt（复制给新电脑）

```text
我是灰灰。现在要把"好大一个基建"项目迁移到这台电脑继续做。

背景：这是自建 DevOps 平台项目（Plane/GitLab/Jenkins/Nexus/RagFlow 部署骨架 + 架构文档），
git 仓库在 GitHub：git@ssh.github.com:443/iuhiuhoaix/infrastructure.git（SSH，443 端口）。
服务器是 192.168.199.131（Fedora 42，GitLab 8080 / Plane 3000 / Nexus 8081+8083 已跑）。

请按顺序执行：
1. 在合适位置（建议 D:\好大一个基建\）git clone git@ssh.github.com:443/iuhiuhoaix/infrastructure.git
   如果 ssh 443 不通，试 https://github.com/iuhiuhoaix/infrastructure.git（仓库 public）
2. clone 后检查 .workbuddy/memory/ 是否被我手动拷贝过来了（MEMORY.md + 日志）；
   如果项目根目录有 .workbuddy/ 就确认它存在；没有的话提醒我从旧机器拷
3. 读 README.md、PROGRESS.md、.workbuddy/memory/MEMORY.md，重建上下文
4. 对照 PROGRESS.md 的"当前进度总览"确认我的认知一致，列出当前待办
5. 检查 git remote -v 是 ssh://git@ssh.github.com:443/...，本地分支 main 跟踪 origin/main

完成后汇报：clone 结果 + 记忆文件是否齐全 + 当前待办清单。不要动服务器。
```
