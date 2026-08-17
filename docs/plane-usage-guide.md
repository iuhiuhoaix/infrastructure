# Plane 使用说明

> 以基建项目实际规划为例，说明 Plane 在本平台怎么用。

## 1. 定位

Plane 是**项目工作 SoT**（做什么 / Why / 进度），不是工程文档库。

| 放 ✅ | 不放 ❌ |
|---|---|
| 需求、任务、进度、里程碑 | 工程技术文档（→ GitLab `docs/`） |
| Sprint 规划、项目协作上下文 | 代码、MR（→ GitLab） |
| Issue 之间的业务关联 | 制品、二进制（→ Nexus） |

**红线**：文档沉淀走 GitLab，Plane 只引用不沉淀。Plane Pages 只放项目协作上下文（会议纪要、决策记录、Sprint 计划），正文内容贴 GitLab URL。

## 2. 实例与组织

- **地址**：http://192.168.199.131:3000
- **Workspace**：`kdev`（与 GitLab 顶层 Group 对齐，统一命名）
- **层级**：Workspace → Project → Module → Issue

## 3. Project 划分（对齐 GitLab 组织模型）

Plane Project 与 GitLab repo 一一对应：

| Plane Project | identifier | 对应 GitLab | 用途 |
|---|---|---|---|
| 基建平台 | `INFRA` | `kdev/assets/infrastructure` | 公司公共基建 |
| 客户项目（如 C0108） | `C0108` | `kdev/客户/c0108` | 客户交付 |
| 产品项目 | `ERP` / `MES` | `kdev/assets/products/xxx` | 自有产品 |

> identifier 即 work item 编号前缀（如 `INFRA-1`、`C0108-12`），用客户/产品代号，团队一眼能认出属于谁。

## 4. Module 划分（工作方向）

Module 按**工作维度**分，不是按技术组件分。以基建平台 INFRA 为例：

| Module | 覆盖范围 |
|---|---|
| 部署与运维 | Compose 部署、服务器、Nginx、备份恢复、/dockerData、代理 |
| CI/CD 流水线 | Jenkins、构建节点、Nexus、webhook、代码迁移 |
| 知识与检索 | RagFlow、模型服务、docs 仓库、MCP 接入 |
| 架构与治理 | 架构基线、组织模型、AI Agent 横向层 |

客户/产品项目的 Module 按**产品线**分（如 `erp` / `mes` / `插件公共`），与 Plane 的 Module=产品线约定一致。

## 5. Cycle（Sprint）

- **Cycle = Sprint**，建议 2 周一个 Cycle
- 每个 Cycle 开始时规划本期工作项，把 Issue 加进 Cycle
- Cycle 结束复盘，未完成的挪到下个 Cycle

## 6. Issue 规范

### 命名
动词开头，明确动作：
- ✅ `RagFlow 本体对接（注册 provider + 配置）`
- ✅ `代码仓库迁 GitLab（131）`
- ❌ `RagFlow`（太模糊）
- ❌ `关于代码迁移的问题`（不像可执行的任务）

### 描述
```markdown
背景：<为什么做>
具体步骤：
- step 1
- step 2
关联资源：
- GitLab: http://192.168.199.131:8080/kdev/assets/infrastructure
- 文档: docs/xxx.md
- commit: abc1234
```

### priority
| 级别 | 用法 |
|---|---|
| urgent | 阻塞生产/关键故障 |
| high | 本 Sprint 必做 |
| medium | 计划内待办 |
| low | 有空再做/等外部条件 |
| none | 未评估 |

### 关联
- **Module**：每个 Issue 归属一个工作方向 Module
- **GitLab Issue 互引**：Plane Issue（业务侧）↔ GitLab Issue（代码侧）URL 互引，数据不同步各系统自治

## 7. 与其他系统的边界

| 系统 | 职能 | Plane 关系 |
|---|---|---|
| GitLab | 工程资产 SoT（代码/文档/MR） | Issue URL 互引；文档在 GitLab 不在 Plane |
| Jenkins | 执行层（Build/Test/Deploy） | Plane Issue 描述里引用 Jenkins job |
| Nexus | 制品 SoT | Plane Issue 描述里引用制品坐标 |
| RagFlow | 知识索引 | 检索 GitLab 文档，不直接碰 Plane |
| AI Agent | 横向智能层 | 通过 plane MCP 操作 Plane |

## 8. AI Agent / MCP 接入

plane MCP 已接入 WorkBuddy，AI 可直接操作 Plane：

- **配置**：`~/.workbuddy/mcp.json`，`uvx plane-mcp-server stdio`，需 `PLANE_API_KEY` + `PLANE_WORKSPACE_SLUG=kdev` + `PLANE_BASE_URL`
- **能力**：28 tools，覆盖 Project/Module/Issue/Cycle/Label/Workitem 等 CRUD + PQL 查询
- **API Key**：Workspace Settings → API Tokens 生成，认证头 `x-api-key`
- **已知坑**：Plane 1.4 的 MCP `update_features` endpoint 报 404，开 project features 要走 REST API `PATCH /api/v1/workspaces/kdev/projects/{id}/` 设 `module_view` 等字段

## 9. 已建内容速查（基建平台 INFRA）

- **4 Module**：部署与运维 / CI/CD 流水线 / 知识与检索 / 架构与治理
- **5 Issue**：INFRA-1 RagFlow 本体对接 / INFRA-2 代码仓库迁 GitLab / INFRA-3 Nginx 反代TLS / INFRA-4 Nexus repo 划分 / INFRA-5 GitLab MCP 接入

详见：http://192.168.199.131:3000/kdev/INFRA

---

相关文档：
- 架构基线：`docs/architecture-review.md`
- GitLab/Plane 组织模型：`docs/gitlab-plane-model.md`
- 项目进度：`PROGRESS.md`
