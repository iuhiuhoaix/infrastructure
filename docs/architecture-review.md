# 架构审查报告 + 最终架构基线 v1.1

> 审查对象：客户驱动研发 + DevOps + 项目资产管理 + AI 知识平台
> 审查立场：不推翻现有架构，只做边界校准、冲突排查、遗漏补齐、基线固化
> 约束：简单、清晰、可维护、可扩展、AI-friendly；不为"完整"引入不必要系统
> v1.1 变更：剥离公司 CRM——CRM 属公司层面，开发部门不用，本平台缩为 6 组件。Customer 维度保留，ID 由开发平台自维护，非来自 CRM。

---

## 〇、一句话结论

**当前架构在"克制"这件事上做得对——6 个组件各司其职，没有为堆砌而堆砌。需要补的不是新系统，而是几条边界规则的显式化（GitLab Release vs Nexus、Plane Issue vs GitLab Issue、GitLab Registry 关闭、Secrets 策略、环境维度）。把这些钉死，架构就稳了。**

---

## A. 当前架构完整维度树

```
Platform Layer (横向)
├── Nginx          宿主机统一 TLS 入口 / 反向代理
├── Docker Compose 单 Host 多独立 Compose
└── devops-internal external network (跨服务互访)

Application Layer (纵向, 各自 SoT)   [公司 CRM 属公司层面, 开发部门不用, 不纳入本平台]
├── Plane          What / Work                   项目·需求·任务·进度
├── GitLab         Engineering Assets            代码·文档·配置·MR·Release 声明
├── Jenkins        Execution                     Build·Test·Package·Deploy
├── Nexus          Artifacts                     依赖·包·制品·Docker Registry
├── RagFlow        Knowledge Retrieval           索引·检索·RAG (可重建)
└── AI Agent       Intelligent Interface         跨系统理解·检索·自动化 (不持有数据)

Business Dimensions (核心实体)
Customer → Project → Product/Customization → Repository → Build → Artifact → Deployment
                                          └→ Documentation → Knowledge
```

> Customer 仍是贯穿全链路的核心业务维度。Customer ID 由开发平台自维护（在 Plane / GitLab Group 创建时定义，如 C0001+），**不与公司 CRM 打通**。客户商业信息（合同、商机、客户关系）归公司 CRM，本平台不涉及、不重复建设。

---

## B. 核心实体关系图

```
                        ┌──────────┐
                        │ Customer │  (业务维度, 非系统用户; 100+, 不占席位)
                        │  C0001+  │  (ID 由开发平台自维护, 非来自公司 CRM)
                        └────┬─────┘
                             │ 1:N
              ┌──────────────┼──────────────┐
              ↓              ↓              ↓
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │ Project  │   │ Project  │   │ Project  │   (Plane Project)
        │ (客户定制) │   │ (通用产品) │   │ (通用组件) │
        └────┬─────┘   └────┬─────┘   └────┬─────┘
             │              │              │
             │  引用         │  被引用       │  被依赖
             ↓              │              ↓
        ┌──────────┐        │        ┌──────────┐
        │Product/  │←───────┘        │Component │
        │Customiz. │                 │ (Library)│
        └────┬─────┘                 └────┬─────┘
             │                            │
             └──────────┬─────────────────┘
                        ↓
                  ┌───────────┐  1:N
                  │Repository │──────→ Requirement (Plane)
                  │ (GitLab)  │──────→ Work Item   (Plane)
                  └─────┬─────┘──────→ Tech Issue  (GitLab, 代码侧)
                        │ 1:N
                        ↓
                  ┌───────────┐  1:N
                  │   Build   │──────→ Test Result
                  │ (Jenkins) │
                  └─────┬─────┘
                        │ 1:N
                        ↓
                  ┌───────────┐  1:N
                  │  Artifact │──────→ Deployment
                  │  (Nexus)  │         (SaaS / 客户现场 / 离线包)
                  └───────────┘
                        │
                        ↓
                  ┌───────────────┐
                  │ Documentation │  (GitLab docs/, 随代码版本化)
                  └──────┬────────┘
                         ↓
                  ┌───────────┐
                  │ Knowledge │  (RagFlow 索引, 从 GitLab 重建)
                  └───────────┘
```

**关系基数速查：**

| 实体 | 关系 | 基数 | 说明 |
|---|---|---|---|
| Customer → Project | 1:N | 一个客户多个项目 | 也存在纯通用产品项目(无特定客户) |
| Product → Project | 1:N | 一个产品多个项目 | mes-core / mes-web / mes-api / plugins |
| Project → Repository | 1:N | 一个项目多个仓库 | 主仓库 + 配置仓库 + 部署脚本仓库 |
| Repository → Build | 1:N | 多次构建 | Build 是时间点事件 |
| Build → Artifact | 1:N | 一次构建多个产物 | dll / zip / image / nuget |
| Artifact → Deployment | 1:N | 一个制品多次部署 | Dev / Staging / Prod / 客户现场 |
| Repository → Documentation | 1:N | 文档随仓库版本化 | docs/ 目录结构化 |
| Documentation → Knowledge | 1:1(索引) | RagFlow 索引 GitLab 文档 | 知识是文档的检索投影 |

---

## C. 系统职责矩阵

| 系统 | 唯一职责 (做这个) | 禁止职责 (不做这个) | 数据是否 SoT |
|---|---|---|---|
| **Plane** | 项目、需求、Work Item、Issue(业务侧)、进度、里程碑 | 不存代码、不存制品、不存技术文档、不做代码侧 Issue | ✅ 项目工作 |
| **GitLab** | 代码、MR、Release 声明、技术文档、配置、DB脚本、CI 配置、客户定制源码 | 不存二进制制品、不做长期制品存储、不做需求管理 | ✅ 工程资产 |
| **Jenkins** | Build、Test、Package、Deploy 执行、Agent 调度 | 不存源码、不存长期制品、不做需求 | ❌ (执行层, 状态可从 GitLab+Jenkinsfile 重建) |
| **Nexus** | 依赖代理、依赖缓存、内部包、构建产物、发布制品、Docker Registry | 不存源码、不做文档 SoT、不做需求 | ✅ 制品 |
| **RagFlow** | 文档解析、分块、向量索引、知识检索、跨仓库搜索 | 不做原始文档 SoT、不做代码 SoT | ❌ (索引层, 可从 GitLab 重建) |
| **AI Agent** | 跨系统自然语言入口、检索、自动化、辅助 | 不持有数据、不绕过权限、不做任何 SoT | ❌ (无状态) |
| **Nginx** | TLS、反代、域名、WebSocket、外部访问控制 | 不做业务逻辑、不做服务发现 | ❌ |

> 公司 CRM 不在此矩阵内——客户关系 / 商业信息归公司层面，开发部门不用，本平台不重复建设。

---

## D. 数据 / 资产 Source of Truth 矩阵

| 资产类型 | Source of Truth | 备份策略 | 可否重建 |
|---|---|---|---|
| 源代码 | GitLab | 每日 + 异地 | ❌ 不可丢 |
| 技术文档 | GitLab (docs/, 随代码版本化) | 随 GitLab | ❌ 不可丢 |
| 配置文件 | GitLab | 随 GitLab | ❌ 不可丢 |
| 数据库脚本 | GitLab | 随 GitLab | ❌ 不可丢 |
| 部署脚本 | GitLab (deploy/) | 随 GitLab | ❌ 不可丢 |
| 构建配置 (Jenkinsfile) | GitLab | 随 GitLab | ❌ 不可丢 |
| project.yaml (项目元数据) | GitLab (仓库根) | 随 GitLab | ❌ 不可丢 |
| CI 流水线定义 | GitLab (Jenkinsfile) + Jenkins (job 配置) | GitLab 主; Jenkins job 可从 JCasC 重建 | ✅ 可重建 |
| 构建产物 / 制品 | Nexus | 每日 + 异地 | ⚠️ 可从源码重建, 但耗时 |
| Docker Image | Nexus Docker Registry | 随 Nexus | ⚠️ 可从源码重建 |
| 依赖包 (第三方) | Nexus Proxy (缓存) | 无需备份 (可重新拉取) | ✅ 可重建 |
| 项目需求 / Work Item | Plane | 每日 + 异地 | ❌ 不可丢 |
| 项目进度 / 里程碑 | Plane | 随 Plane | ❌ 不可丢 |
| 知识索引 / 向量 | RagFlow | 无需备份 (可从 GitLab 重建) | ✅ 可重建 |
| 构建环境 (Agent) | Jenkins Agent 配置 + GitLab (环境描述) | Jenkins 配置备份 | ⚠️ 环境可重建, 但 Windows Agent 环境需手动 |
| 部署状态 | Jenkins (部署记录) + GitLab (部署脚本) | Jenkins 配置备份 | ⚠️ 历史记录可丢, 当前状态需重新采集 |
| Secrets / 密钥 | `.env` 文件 (chmod 600) + 异地加密备份 | GPG 加密 + 异地 | ❌ 不可丢, 不可明文入库 |
| Release 声明 (发布事件) | GitLab Release (元数据 + Release Notes) | 随 GitLab | ❌ 不可丢 |
| GitLab Container Registry | **关闭, 不使用** | — | 统一走 Nexus |

> 客户商业信息（合同、商机、客户关系）的 SoT 是公司 CRM，但 CRM 不在本平台范围，故不列入上表。

### ⚠️ 关键边界裁定（必须在基线钉死）

| 潜在冲突 | 裁定 |
|---|---|
| **GitLab Release vs Nexus Artifact** | GitLab Release = 发布事件声明 (版本号 + Notes + Nexus 坐标引用); **不存二进制**。二进制制品物理存储只在 Nexus。Release Notes 里写 `nexus://repository/path:tag` 引用。 |
| **GitLab Registry vs Nexus Docker Registry** | **关闭 GitLab 内置 Container Registry**。所有 Docker Image 统一进 Nexus。一个制品 SoT。 |
| **Plane Issue vs GitLab Issue** | Plane Issue = 业务需求 / 工作项 / 项目协作 (做什么); GitLab Issue = 代码侧技术跟踪 (bug / 技术债 / 代码相关)。**划线原则**: 能在 Plane 说清的不开 GitLab Issue; 纯代码层面的才进 GitLab。两者可互相引用 URL。 |
| **GitLab Docs vs RagFlow Knowledge** | GitLab = 原始文档 SoT; RagFlow = 索引投影, 可丢弃可重建。RagFlow 永远不是文档权威来源。 |

---

## E. 人员角色 → 系统使用矩阵

| 角色 | 人数 | Plane | GitLab | Jenkins | Nexus | RagFlow | AI Agent | 主要职责 |
|---|---|---|---|---|---|---|---|---|
| **业务 / 销售** | ~3 | ✅ 读+写需求 | ❌ | ❌ | ❌ | ❌ | ✅ 入口 | 需求输入、商业背景传达（客户关系归公司 CRM） |
| **实施** | ~2 | ✅ 读+写反馈 | ✅ 读文档 | ❌ | ✅ 拉制品 | ❌ | ✅ 入口 | 客户现场、配置、部署协助、问题反馈 |
| **研发** | ~6 | ✅ 主 | ✅ 主 | ✅ 主 | ✅ 主 | ✅ 配置 | ✅ 主 | 需求理解、技术拆解、开发、CI/CD、资产 Owner |
| **管理员** | ~1 | ✅ 管控 | ✅ 管控 | ✅ 管控 | ✅ 管控 | ✅ 管控 | ✅ 管控 | 平台运维、备份、权限 |
| **PM / 管理** | ~0-1 | ✅ 读进度 | ✅ 读 | ✅ 读 | ❌ | ❌ | ✅ 入口 | 查看 Progress / Milestone / Risk, **不监控到人** |

> 研发是项目工程资产的主要 Owner。PM 角色被弱化为"看进度"而非"管人"。总内部用户 ~12 人。业务/销售的客户关系维护走公司 CRM，不在本平台。

---

## F. Business → Engineering 流程

```
客户需求
    │
    ↓
业务/实施 (携带 Customer ID)
    │
    ↓
Plane 创建 Requirement (关联 Customer ID)
    │
    ↓  ─── 不经过 PM 层层转译 ───
    │
研发团队理解 / 分析 / 技术拆解
    │
    ├──→ Plane Work Item (技术任务, 关联 Requirement)
    │
    └──→ GitLab (建分支 / 建 Tech Issue 如需)
            │
            ↓
        开发 → MR → Code Review
            │
            ↓
        Merge → 触发 Jenkins (见 G)
```

**关键原则**: Plane 是 Business → Engineering 的唯一协作入口。业务侧只碰 Plane + AI, 不直接碰 GitLab。研发在 Plane 里完成"需求→技术任务"的拆解, 不需要中间人翻译。客户商业背景由业务/实施口头或文档带入，不在本平台建客户关系库（那是公司 CRM 的事）。

---

## G. Engineering → Deployment 流程

```
GitLab Merge → main 分支
    │
    ↓
Jenkins 读取 project.yaml (Customer / Product / Build Strategy / Agent / Artifact Target / Deploy Target)
    │
    ├── Label 路由 → 选 Build Agent (customer-a / dotnet-framework / linux / docker ...)
    │
    ├── Build (Windows / Linux / Docker)
    │
    ├── Test
    │
    ├── Package → Push to Nexus (NuGet / Maven / npm / Docker Registry / Generic)
    │
    ├── GitLab Release 声明 (版本号 + Notes + Nexus 坐标引用, 不存二进制)
    │
    └── Deploy
         ├── SaaS:          Nexus → 拉取 → Deploy 到 SaaS Server
         ├── 客户现场:       Nexus → 打 Offline Package (zip/exe/installer) → 交付实施
         └── Docker:        Nexus Docker Registry → docker pull → deploy
```

**环境维度补充（原架构未显式提及，建议钉入基线）:**

| 环境 | 用途 | 部署触发 | 数据来源 |
|---|---|---|---|
| Dev | 研发自测 | 每次 merge 自动 | Nexus snapshot |
| Staging | 集成验证 | 手动 / 定期 | Nexus release candidate |
| Prod (SaaS) | SaaS 生产 | 手动审批 | Nexus release |
| Customer Site | 客户现场 | 实施 + 离线包 | Nexus release → offline package |

---

## H. GitLab → RagFlow → AI 流程

```
GitLab Repository
    │
    ├── docs/                    ← 文档源 (Markdown / Mermaid / PlantUML)
    ├── src/                     ← 代码 (可选索引)
    ├── README.md
    └── project.yaml             ← 元数据 (customer / product / rag scope)
            │
            ↓  (Webhook / 定时同步)
        RagFlow
            │
            ├── Parse (按文档类型)
            ├── Chunk (按语义/标题)
            ├── Embedding (灰灰选型, 本地化)
            ├── Index (按 Customer / Product / Project / Repository 分 scope)
            └── 权限映射 (尽量对齐 GitLab 仓库可见性)
                    │
                    ↓
                AI Agent
                    │
                    ├── 跨仓库检索
                    ├── 客户知识检索 ("C1023 以前解决过这个问题吗?")
                    ├── 技术文档问答
                    └── 不绕过 RagFlow 权限 → 不绕过 GitLab 权限
```

**知识 scope 分层:**

```
Customer Knowledge     ← 该客户所有仓库的文档聚合
    └── Project Knowledge  ← 单个项目仓库的文档
        └── Repository Knowledge  ← 单仓库
            └── Cross-Repository Search  ← 跨仓库 (受权限约束)
```

---

## I. Docker 部署拓扑

```
                        Internet
                           │
                    ┌──────┴──────┐
                    │  宿主机 Nginx │  (Docker 外, 统一 TLS)
                    │  :80 :443    │
                    │  :2222 (SSH) │
                    └──────┬──────┘
                           │  反代到各容器
            ┌──────────────┼──────────────────────────┐
            │              │              │            │
     git.example    plane.example   jenkins.example  nexus/reg/rag.example
            │              │              │            │
    ╔═══════╧══════════════╧══════════════╧════════════╧══════╗
    ║          external network: devops-internal              ║
    ║   (容器名互访: gitlab / plane / jenkins / nexus / ragflow) ║
    ╚═══════════╤══════════╤══════════╤══════════╤════════════╝
                │          │          │          │
         ┌──────┴───┐ ┌────┴────┐ ┌───┴────┐ ┌───┴────┐ ┌────────┐
         │ gitlab/  │ │ plane/  │ │jenkins/│ │ nexus/ │ │ragflow/│
         │ compose  │ │ compose │ │compose │ │compose │ │compose │
         │ +PG+Redis│ │+PG+Redis│ │ (无依赖)│ │(单容器) │ │+ES+PG  │
         │          │ │ +MinIO  │ │        │ │        │ │+Redis  │
         │ default  │ │ default │ │ default│ │ default│ │+MinIO  │
         │ network  │ │ network │ │ network│ │ network│ │ default│
         └──────────┘ └─────────┘ └────────┘ └────────┘ └────────┘
         data/bind    data/bind   data/bind  data/bind  data/bind
         mount        mount       mount      mount      mount

    Build Agent:
    ├── Linux Docker Agent  (同 Host 容器, 挂 devops-internal)
    └── Windows Agent       (独立 Windows Server, WebSocket inbound to Jenkins)
```

**设计校验:**

| 检查项 | 结论 |
|---|---|
| 每应用独立 Compose | ✅ 生命周期/升级/备份/故障隔离全最优 |
| 双网络 (external + default) | ✅ 跨服务互访走 devops-internal, 内部依赖锁 default, 不串扰 |
| 宿主机 Nginx | ✅ TLS 集中, 应用不各自管证书; 仅暴露 80/443/2222 |
| bind mount | ✅ tar 即搬迁, 无需 volume driver |
| GitLab SSH 2222 | ✅ 单独暴露, 不走 Nginx (SSH 无法反代) |
| Windows Agent 独立 | ✅ 客户编译环境隔离, WebSocket inbound 不需开放额外端口 |

---

## J. Platform Bootstrap 流程

```
1. 宿主机准备 (Docker / Docker Compose / Nginx / certbot)
2. bash network/setup-network.sh          → 创建 external devops-internal
3. 各应用准备 .env (chmod 600)            → gitlab / plane / jenkins / nexus / ragflow
4. 按依赖顺序 docker compose up -d:
       nexus → gitlab → plane → ragflow → jenkins
5. Nginx 站点配置 + certbot 签证书
6. Jenkins JCasC (Configuration as Code)  → job 模板 / agent 注册 / 凭据
7. Nexus 初始化仓库 (nuget/maven/npm/docker hosted + proxy)
8. GitLab 初始化 Group 结构 (Customers / Products / Components / Internal)
9. RagFlow 初始化 embedding 模型 + 同步策略
10. 首次 backup-all.sh 验证
```

> 已有 `deploy/` 骨架覆盖 1-5、8、10。JCasC / Nexus 初始化脚本 / GitLab Group 自动化建议补充为脚本, 减少"逐个点击"。

---

## K. Project Bootstrap 流程

```
project init --customer C0108 --product MES --type customization
    │
    ├──→ GitLab: 在 Customers/C0108/ 下创 Project (从模板)
    │       ├── src/
    │       ├── docs/{architecture,api,database,deployment,troubleshooting}/
    │       ├── config/
    │       ├── deploy/
    │       ├── scripts/
    │       ├── Dockerfile / Jenkinsfile / project.yaml / README.md
    │       └── 继承 Customers/C0108 Group 权限
    │
    ├──→ Plane: 创建 Project, 关联 Customer ID C0108
    │       └── 初始化 Module / Cycle / 默认 Issue 模板
    │
    ├──→ Jenkins: 基于项目模板注册 Pipeline (读 project.yaml)
    │       └── Label 路由 (按 project.yaml.agent)
    │
    ├──→ Nexus: 确认目标 repository 存在 (按 project.yaml.artifact)
    │
    └──→ RagFlow: 注册知识 scope (Customer C0108 + Repository)
            └── 首次同步触发
```

**project.yaml 是项目元数据唯一声明, 全链路读取它:**

```yaml
customer: C0108
product: MES
project: mes-c0108-customization
type: customization          # customization | product | component
build:
  strategy: docker           # docker | msbuild | dotnet | maven | npm
  agent: customer-a          # Jenkins label
artifact:
  repository: mes-c0108      # Nexus repo
  type: nuget                # nuget | maven | npm | docker | generic
deployment:
  targets: [saas, offline]   # saas | customer-site | offline
  environments: [dev, staging, prod]
documents:
  rag_sync: true
rag:
  scope: [customer, project]
```

---

## L. 权限模型

| 层 | 权限主体 | 粒度 | 来源 |
|---|---|---|---|
| Plane | Plane 用户 (~12) | Project / Module | Plane 自管 |
| GitLab | GitLab 用户 (~12) | Group / Project | GitLab 自管 (LDAP 可选) |
| Jenkins | Jenkins 用户 / Agent | Job / Credential | Jenkins 自管 + JCasC |
| Nexus | Nexus 用户 | Repository | Nexus 自管 |
| RagFlow | RagFlow 用户 / API | 知识 scope | **尽量映射 GitLab 仓库可见性** |
| AI Agent | 继承当前用户身份 | = 该用户在各系统的权限 | **不绕过任何系统权限** |

**核心原则:**
- Customer 是业务维度, 不是系统用户, **不占任何席位**。Customer ID 由开发平台自维护, 不依赖公司 CRM。
- AI Agent 没有独立权限, 永远以"当前操作者"身份访问各系统。
- RagFlow 权限尽量对齐 GitLab (客户 A 的研发看不到客户 B 的知识)。
- 12 人规模不需要复杂 IAM / SSO, 各系统自管用户即可。未来如需统一, LDAP 是第一选择, 不上 Vault/Consul。

---

## M. 备份 / 恢复模型

| 系统 | 持久化数据 | 备份方式 | 频率 | 可重建? |
|---|---|---|---|---|
| **GitLab** | PG + Redis + Repos (data/) + Config | `gitlab-backup create` + PG dump + data tar + secrets 文件 | 每日 + 异地 | ❌ 不可丢 |
| **Plane** | PG + Redis + MinIO (附件) | PG dump + MinIO mc mirror + data tar | 每日 + 异地 | ❌ 不可丢 |
| **Nexus** | data/ (blob + DB + orient) | data tar (停机或热备) | 每日 + 异地 | ⚠️ 可从源码重建但耗时 |
| **RagFlow** | ES + PG + Redis + MinIO | **无需备份** (可从 GitLab 重建) | — | ✅ 可重建 |
| **Jenkins** | JENKINS_HOME (job 配置 + 构建记录 + 凭据) | JENKINS_HOME tar + JCasC 定义 | 每日 | ⚠️ JCasC 可重建, 历史记录可丢 |
| **Nginx** | conf.d/ | 随 deploy/ 入 Git | — | ✅ 可重建 |
| **Secrets** | 各应用 .env | GPG 加密 + 异地, chmod 600 | 每次变更 | ❌ 不可丢, 不明文入库 |

**恢复优先级（灾难恢复顺序）:**
1. Secrets (.env) — 没有它什么都起不来
2. GitLab — 工程资产 SoT, 一切的根
3. Nexus — 制品 SoT
4. Plane — 项目工作
5. Jenkins — 配置可从 JCasC 重建
6. RagFlow — 最后, 从 GitLab 重建索引

> 已有 `deploy/backup/backup-all.sh` + `deploy/dr/restore-from-scratch.sh` 覆盖核心流程。

---

## N. 最终架构原则

1. **6 组件上限**: Plane / GitLab / Jenkins / Nexus / RagFlow / AI Agent / Nginx(+Docker)。新增系统须证明现有组件无法承担, 否则拒绝。CRM 属公司层面, 不在本平台范围。
2. **每类数据只有一个 SoT**: 代码→GitLab, 制品→Nexus, 工作→Plane, 知识索引→RagFlow(可重建)。不重叠。客户商业信息归公司 CRM, 本平台不涉及。
3. **Customer ID 是贯穿全链路的核心业务键**: Plane→GitLab→project.yaml→Jenkins→Nexus→RagFlow, 全程携带。Customer ID 由开发平台自维护 (Plane/GitLab 创建时定义), **非来自公司 CRM, 也不与 CRM 打通**。
4. **project.yaml 是项目元数据唯一声明**: Jenkins / Nexus / RagFlow 全部读取它, 不在多处重复定义。
5. **配置优先于复制**: 客户定制用 config/plugin/extension/SDK, **禁止产品源码复制分叉**。这是防止技术债爆炸的红线。
6. **文档随代码版本化**: 技术文档放 GitLab docs/, 不引入独立 Wiki / 文档系统。
7. **RagFlow 是索引层不是存储层**: 可丢弃可重建, 永远不是文档权威来源。
8. **AI Agent 是横向入口不持有数据**: 以当前用户身份访问各系统, 不绕过权限, 不做 SoT。
9. **不引入**: K8s / Swarm / Vault / Consul / Service Mesh / 独立 IAM / 独立 CMDB / 独立 PMO / 独立 Wiki / 独立文档系统 / 独立客户关系系统（CRM 用公司的）。
10. **Secrets = 文件系统 + 权限**: .env + chmod 600 + GPG 加密异地备份, 不上 Vault。
11. **Plane 管"做什么", GitLab 管"代码层面技术跟踪"**: 业务需求进 Plane, 纯代码 bug/技术债进 GitLab Issue, 互相引用 URL。
12. **GitLab Release 不存二进制**: 只声明发布事件 + Notes + Nexus 坐标引用。二进制只在 Nexus。

---

## 审查结论：12 项判断

### 1. 当前架构是否完整？✅ 完整
6 组件覆盖了"客户→研发→交付→知识→AI"全链路, 没有断点。需要补的不是系统, 是几条边界规则。CRM 属公司层面, 已剥离, 不在本平台范围。

### 2. 是否存在职责冲突？⚠️ 有 3 处需显式裁定（已在 D 节裁定）
- GitLab Release vs Nexus Artifact → Release 只声明不存二进制
- GitLab Registry vs Nexus Registry → 关闭 GitLab Registry, 统一 Nexus
- Plane Issue vs GitLab Issue → 业务侧 Plane, 代码侧 GitLab, 互相引用

### 3. 是否存在数据 SoT 冲突？✅ 裁定后无冲突
核心是"每类数据一个 SoT"原则。RagFlow 明确为可重建索引层, 不与 GitLab 冲突。客户商业信息归公司 CRM, 不进本平台, 无交叉。

### 4. Customer 作为核心维度是否合理？✅ 合理且必要
100+ 客户 vs 12 内部用户, Customer 必须是业务维度而非系统用户。Customer ID 由开发平台自维护并贯穿全链路, 是唯一能把"研发工作(Plane)→工程资产(GitLab)→制品(Nexus)→知识(RagFlow)"串起来的键。客户商业信息(合同/商机)归公司 CRM, 本平台不管, 也不与之打通——开发部门只需要"哪个客户对应哪些项目/仓库/制品/知识"。

### 5. Plane 的定位是否合理？✅ 合理
"研发项目工作管理 + 项目资产索引"而非"PM 监控工具", 完全匹配当前组织（研发是资产 Owner, PM 弱化）。Plane 不碰工程资产, 只管"做什么"。

### 6. GitLab 的定位是否合理？✅ 合理
"工程资产 SoT"包括代码+文档+配置+DB脚本+CI配置, 文档随代码版本化, 不引入独立文档系统——这是对的。唯一要钉死的是"不存二进制制品"和"关闭内置 Registry"。

### 7. Jenkins / Nexus 的边界是否合理？✅ 合理
Jenkins = 执行层 (不长期存制品), Nexus = 制品 SoT。project.yaml 驱动 Jenkins 决策是好的单一声明点。Build Agent 按 Label 路由适配多客户环境, 正确。客户专属编译环境作为工程资产管理 (Jenkins Agent 配置 + GitLab 环境描述), 合理。

### 8. RagFlow 是否应该只做知识索引？✅ 是
RagFlow = 检索层, 数据来自 GitLab, 可重建可丢弃。如果 RagFlow 变成文档存储, 就会和 GitLab 形成 SoT 冲突。保持"索引投影"定位, 架构就干净。

### 9. AI Agent 是否应该作为横向入口？✅ 是
AI Agent 连接所有系统做自然语言入口, 对"不熟悉 GitLab 的业务/实施同事"尤其关键。但必须坚守"不持有数据 + 不绕过权限 + 不做 SoT"三条红线。

### 10. 是否有明显缺失的核心维度？⚠️ 2 处建议补齐（不新增系统）
- **环境维度**: 原 Deployment 未显式区分 Dev/Staging/Prod/Customer-Site。建议在 project.yaml.deployment.environments 钉死, 不新增系统。
- **客户问题回流回路**: 客户现场问题→实施→Plane Requirement→研发。这条回路要在流程里显式化, 不新增系统。
- (轻量监控: 12 人规模可暂靠 docker stats + 各应用日志, 不引入 Prometheus 全套。作为未来轻量扩展点, 不阻塞当前。)

### 11. 是否有可以删除的组件？✅ 无冗余
6 个组件每个都有不可替代的职责。GitLab Registry 需"关闭"而非"删除组件"。CRM 已剥离(公司层面, 开发部门不用)。架构克制得当。

### 12. 是否适合 100+ Customer、少量内部研发人员的组织模式？✅ 适合
- Customer 不占席位 (业务维度) → 100+ 客户不增加系统成本
- 研发是资产 Owner, 砍掉 PM 层层转译 → 适配少量研发
- AI Agent 做自然语言入口 → 降低业务/实施使用门槛
- 配置优先于复制 → 100+ 客户不会导致 100+ 代码分叉
- project.yaml + Project Bootstrap → 新客户接入自动化, 不依赖人工逐个点击
- Customer ID 平台自维护, 不依赖公司 CRM → 开发部门自治, 无跨部门耦合

**唯一风险点**: 客户定制分叉。一旦开始复制产品源码给每个客户, 100+ 客户 = 100+ 分叉 = 技术债爆炸。基线第 5 条"配置优先于复制"是红线, 必须守住。

---

## 《最终架构基线 v1.1》

> 以下为后续所有架构设计的约束。新增系统、新增流程、新增数据类型时, 以此为准。
> v1.1 相对 v1.0: 剥离公司 CRM, 本平台缩为 6 组件; Customer ID 改为开发平台自维护, 不与公司 CRM 打通。

### 固定组件（上限 6）

| # | 组件 | 定位 | SoT? |
|---|---|---|---|
| 1 | Plane | What / Work | ✅ 项目工作 |
| 2 | GitLab | Engineering Assets | ✅ 工程资产 |
| 3 | Jenkins | Execution | ❌ 执行层 |
| 4 | Nexus | Artifacts | ✅ 制品 |
| 5 | RagFlow | Knowledge Retrieval | ❌ 可重建索引 |
| 6 | AI Agent | Intelligent Interface | ❌ 无状态 |
| + | Nginx + Docker | 平台层 | ❌ |

> 公司 CRM 不在此表——客户关系/商业信息归公司层面, 开发部门不用, 本平台不重复建设。

### SoT 唯一性（每类数据一个）

| 数据类型 | SoT |
|---|---|
| 代码 / 文档 / 配置 / DB脚本 / CI配置 / project.yaml | GitLab |
| 二进制制品 / Docker Image / 依赖 | Nexus |
| 需求 / Work Item / 进度 | Plane |
| 知识索引 / 向量 | RagFlow (可重建) |

> 客户商业信息（合同/商机/客户关系）SoT = 公司 CRM, 但不在本平台范围。

### 核心业务键

**Customer ID** 贯穿: Plane → GitLab → project.yaml → Jenkins → Nexus → RagFlow
（ID 由开发平台自维护, 在 Plane/GitLab 创建时定义; **非来自公司 CRM, 也不与 CRM 打通**）

### 项目元数据唯一声明

**project.yaml** 被 Jenkins / Nexus / RagFlow 共同读取, 不在多处重复定义项目元数据。

### 禁止清单

- ❌ 产品源码复制分叉（配置/插件/扩展优先）
- ❌ GitLab Release 存二进制（只声明 + 引用 Nexus 坐标）
- ❌ 使用 GitLab 内置 Container Registry（统一 Nexus）
- ❌ 引入独立 Wiki / 文档系统（文档随代码版本化）
- ❌ RagFlow 作为文档权威来源（只是索引投影）
- ❌ AI Agent 持有数据 / 绕过权限 / 做任何 SoT
- ❌ K8s / Swarm / Vault / Consul / Service Mesh / 复杂 IAM / 独立 CMDB / 独立 PMO
- ❌ Customer 占用系统用户席位
- ❌ 在本平台重建客户关系/商业信息系统（用公司 CRM, 开发部门不碰）

### 新增系统准入条件

新增任何系统前, 必须证明:
1. 现有 6 组件均无法承担该职责
2. 不与现有 SoT 冲突
3. 不引入新的数据重复
4. 不破坏 Customer ID 贯穿链路
5. 不违反"配置优先于复制"

否则拒绝引入。

---

_基线版本: v1.1 (v1.0 基础上剥离公司 CRM, 本平台缩为 6 组件) | 审查日期: 2026-08-15 | 后续变更须升版本号_
