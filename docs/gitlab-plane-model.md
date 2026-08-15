# GitLab 与 Plane 组织模型映射

> 架构基线 v1.1 配套文档 | 2026-08-15 敲定
> GitLab 管工程资产，Plane 管项目工作，两者按客户维度对齐

---

## 一、GitLab 组织模型

### 结构

```
dev-team/                        ← 顶层 Group [internal · 研发全员共享]
├── c0108/                       ← 客户 Subgroup（虚拟分类，不做权限隔离）
│   ├── erp-invoice-plugin/         ① 客户插件
│   ├── mes-report-custom/          ① 客户定制
│   ├── config/                     ② 客户资料
│   └── docs/                       ② 客户资料
├── c0109/                       ← 客户 Subgroup
├── c0200/
└── assets/                      ← 自有资产 Subgroup [internal · 研发共享]
    ├── core-lib/                   ③ 自有产品
    ├── common-utils/               ④ 通用组件/工具
    └── dev-tools/                  ④ 通用组件/工具
```

### 设计要点

- **单顶层 Group** `dev-team/`，internal 可见，研发全员共享所有项目资产
- **客户 Subgroup**（`c0108/`）= 虚拟分类标签（命名空间），**不做权限隔离**
- **assets Subgroup** = 自有资产集中管理
- **三层封顶**：Group → Subgroup → Project，不出现第四层
- **四小类**：
  - 客户区：① 客户插件/定制 ② 客户资料（config/docs，最需隔离的，但现在全员共享）
  - assets 区：③ 自有产品 ④ 通用组件/工具
- **通用插件归 assets**：被多个客户复用的插件不依附特定客户，归 `assets/`，避免复制分叉

### 权限模型

| 角色 | 实例级 | 项目级（dev-team/） | 说明 |
|---|---|---|---|
| 平台管理员（1人） | Administrator | — | 管实例、建顶层 Group、备份、用户管理 |
| 研发（N人） | Regular | Maintainer | 合并 MR、发 Release、管项目设置，继承全可见 |

- 客户**不参与**，不占席位，Customer 是业务维度不是系统用户
- **现阶段全员共享**所有项目资产，Customer ID 只是分类标签不是权限墙
- 关闭 Regular 创建顶层 Group 的能力（Admin Area → Settings → Visibility），防命名空间污染
- **将来按需局部升级**：某客户要隔离（外包介入等），把该 Subgroup 单独改 private + invite，不影响全局

---

## 二、Plane 组织模型

### 结构

```
Plane workspace                      ← 整个 Plane 实例
├── Project: c0108                   ← 客户工作（对应 GitLab c0108/）
│   ├── Module: erp                     产品线/系统分组
│   ├── Module: mes
│   ├── Issue (需求/任务/bug)            关联 Customer ID C0108
│   ├── Cycle (Sprint)                  双周迭代
│   └── Page (协作文档)                  工作层面文档，技术文档仍在 GitLab
├── Project: c0109
├── Project: c0200
└── Project: assets                  ← 自有资产工作（对应 GitLab assets/）
    ├── Module: core-lib
    ├── Module: common-utils
    └── Issue / Cycle / Page
```

### 设计要点

| Plane 实体 | 用途 | 映射 |
|---|---|---|
| **Project** | 工作单元 | = 客户（c0108）或 自有资产（assets），与 GitLab Subgroup 对齐 |
| **Module** | Project 内分组 | = 产品线/系统（erp / mes / common） |
| **Cycle** | 时间盒 | = Sprint（双周），跨 Issue 排期 |
| **Label** | 分类标记 | = 工作类型（插件/定制/资料/需求/bug）+ 优先级（P0/P1/P2） |
| **Issue** | 工作项 | = 需求/任务/bug，关联 Customer ID，与 GitLab Issue URL 互引 |
| **Page** | 协作文档 | = 工作层面文档（会议纪要/方案讨论），技术文档仍在 GitLab docs/ |
| **Milestone** | 交付里程碑 | = 客户交付节点 |

---

## 三、GitLab ↔ Plane 映射关系

| 业务维度 | GitLab 实体 | Plane 实体 | 关系 |
|---|---|---|---|
| 开发组全部 | `dev-team/` (顶层 Group) | Plane workspace | 各自实例顶层 |
| 客户 | `c0108/` (Subgroup) | Project: c0108 | 同一客户，不同视角 |
| 自有资产 | `assets/` (Subgroup) | Project: assets | 同一资产域 |
| 仓库 / 工作项 | Project (代码仓库) | Issue (工作项) | 不一一对应，靠 Customer ID + URL 互引 |
| 产品线 | —（命名前缀） | Module (erp/mes) | Plane 显式分，GitLab 靠命名 |
| 迭代 | — | Cycle (Sprint) | Plane 独有 |
| 代码侧技术跟踪 | GitLab Issue | — | GitLab 独有（bug/技术债） |
| 业务需求 | — | Plane Issue | Plane 独有（做什么） |

### 关联键

- **Customer ID**（如 C0108）贯穿 GitLab Subgroup 名 ↔ Plane Project 名，是跨系统对齐的核心键
- **Issue URL 互引**：Plane Issue 描述里贴 GitLab Issue/MR 链接；GitLab Issue 描述里贴 Plane Issue 链接
- 不做数据同步，靠引用关联（各系统自治，SoT 不重叠）

---

## 四、分工边界（零重叠）

| 维度 | GitLab | Plane |
|---|---|---|
| 代码 | ✅ SoT | ❌ |
| 技术文档 | ✅ SoT（docs/） | ❌（Page 只放协作文档） |
| 配置/DB脚本 | ✅ SoT | ❌ |
| MR/Release声明 | ✅ SoT | ❌ |
| 需求 | ❌ | ✅ SoT |
| 任务/Work Item | ❌ | ✅ SoT |
| 进度/里程碑 | ❌ | ✅ SoT |
| Sprint/Cycle | ❌ | ✅ SoT |

**一句话**：GitLab 管"工程资产是什么"，Plane 管"项目要做什么"。同一个客户（C0108）在 GitLab 是 `c0108/` 代码仓库群，在 Plane 是 `Project: c0108` 工作项群，靠 Customer ID 对齐，靠 URL 互引，数据不同步。
