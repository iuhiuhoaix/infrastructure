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
- 远程 `git@ssh.github.com:443/iuhiuhoaix/infrastructure.git`，HEAD = 本地 `4ae2c33`，完全同步

### 不进 git — 必须手动带（3 样）
| 路径 | 内容 | 为什么 |
|---|---|---|
| 本项目 `.workbuddy/memory/` | MEMORY.md + 每日日志 | 项目记忆，`.gitignore` 排除，clone 不带 |
| 用户级 `~/.workbuddy/`（可选） | SOUL.md / IDENTITY.md / USER.md / MEMORY.md、skills/、mcp.json、workbuddy.db | 人设 + 全部技能 + 自动化，跨项目 |
| `~/.ssh/` 密钥 | id_ed25519 / id_rsa | GitHub push 用（或新机重新生成 key 加进 GitHub） |

### 不用带的
- 服务器上任何东西（`.env`、data、dockerData 都在 192.168.199.131，不在这台电脑）
- 本机 `deploy/*/data|backup|logs/`（本地无运行时数据，全在服务器）

## 推荐迁移路径（2026-08-17 更新：灰灰选定整目录复制）

**方案 A：整目录复制（已选）** —— 本项目本地无运行时数据（data/.env/logs 全在服务器），整目录 copy 干净，`.workbuddy/memory/` 随目录自动带上，最省事：

1. 复制前确认旧机 `git status` 干净（当前 `4ae2c33` 已 push，是干净的）
2. 复制用 `robocopy "D:\好大一个基建" "<新机路径>" /E /COPYALL /DCOPY:DAT`（或资源管理器复制，确认带上隐藏的 `.git`）
3. 新机配置 SSH 密钥：生成 key → 加到 GitHub → 验证 `ssh -T -p 443 git@ssh.github.com`；remote 已是 `ssh://git@ssh.github.com:443`，**无需改 URL**
4. 新机 `git pull` 确认与远端一致，读 README/PROGRESS.md/记忆重建上下文
5. **旧机退役或只读，严禁两机同时改**——防 git 分叉

> 注意：用户级 `~/.workbuddy/`（SOUL/技能/mcp.json/自动化）不在项目目录内，整目录复制**不会**带；要保留需单独拷，否则新机重新配。

**方案 B：git clone（备选）** —— 拿不到 .git 时用。clone 后需手动拷 `.workbuddy/memory/`。

### Bootstrap prompt（复制给新电脑）

```text
我是灰灰。这台电脑已通过整目录复制拿到"好大一个基建"项目（含 .git 和 .workbuddy/memory/）。

背景：这是自建 DevOps 平台项目（Plane/GitLab/Jenkins/Nexus/RagFlow 部署骨架 + 架构文档），
git 仓库在 GitHub：git@ssh.github.com:443/iuhiuhoaix/infrastructure.git（SSH，443 端口）。
服务器是 192.168.199.131（Fedora 42，GitLab 8080 / Plane 3000 / Nexus 8081+8083 已跑）。

请按顺序执行：
1. 确认当前目录是 git 仓库（git status），检查 .workbuddy/memory/ 存在（MEMORY.md + 日志）
2. git pull 确认与远端一致；检查 remote -v 是 ssh://git@ssh.github.com:443/...
3. 读 README.md、PROGRESS.md、.workbuddy/memory/MEMORY.md，重建上下文
4. 对照 PROGRESS.md 的"当前进度总览"确认我的认知一致，列出当前待办

完成后汇报：git 状态 + 记忆文件是否齐全 + 当前待办清单。不要动服务器。
```
