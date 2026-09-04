# 命名约定（Naming Conventions）

> 2026-08-29 敲定 | 自研 .NET 项目 + GitLab repo 的命名规则
> **规则稳定，代号可换**：代号是当前实例，换代号不换规则。

## 背景

公司后续产品围绕金蝶流程嵌入，自建金蝶各产品 SDK 封装层（不用金蝶官方 SDK，因后续开发需要 SDK 的可控性）。这一组 SDK 性质统一：易用性优化 + 可控性封装。后续会有金蝶多个产品（星辰、星空等）的 SDK 进来，命名要为兄弟 SDK 留扩展位。

## 一、GitLab repo 命名

| 类型 | 规则 | 示例 |
|---|---|---|
| 金蝶产品 SDK | `kingdee-<代号>` | `kingdee-settler` |
| 自研单点服务 | 直接代号 | `knotify` |

- 落位：`kdev/assets/<repo>`（assets 下平级，无中间 subgroup，守三层封顶）
- 金蝶系带 `kingdee-` 前缀：assets 下 repo 列表按字母排序时金蝶系自动聚拢，一眼能分组
- 自研单点服务不带前缀（notify 类就 knotify 一个，前缀冗余）
- repo 名一律小写连字符（.NET 仓库名惯例）

## 二、.NET 命名空间

| 类型 | 规则 | 示例 |
|---|---|---|
| 金蝶产品 SDK | `JSD.Kingdee.<代号>` | `JSD.Kingdee.Settler` |
| 自研单点服务 | `JSD.<代号>` | `JSD.Notify` |

- 公司前缀统一 `JSD`（公司缩写）
- 金蝶系走产品线层 `Kingdee`：未来星空等其他金蝶产品 SDK 归 `JSD.Kingdee.*`，兄弟整齐归类
- 自研单点服务两层够（knotify 这类，非金蝶系不需要产品线层）
- 命名空间装**归属**（公司 → 产品线 → 产品），不装性质（"是 SDK"靠 repo 名 + 文档说明）
- 三层 `<公司>.<产品线>.<代号>` 是 .NET 标准姿势（参照 `Microsoft.AspNetCore.*`）

## 三、代号策略

- 用独立代号而非金蝶产品名（星辰 / 星空 / K3Cloud），原因：
  - 金蝶产品名会变（版本升级 / 改名 / 换包装），代号稳定
  - 避免商标绑定
- 代号要在 repo README 顶部写 footnote 注明对应金蝶哪个产品
- 代号可换；换代号时 repo 名 + 命名空间同步改，**规则不变**

## 四、当前实例

| 组件 | GitLab repo | .NET namespace | 性质 | 对应金蝶产品 |
|---|---|---|---|---|
| settler | `kdev/assets/kingdee-settler` | `JSD.Kingdee.Settler` | 金蝶 SDK 易用性 + 可控性封装 | 星辰（与星空同级，面向中小微） |
| knotify | `kdev/assets/knotify` | `JSD.Notify` | 自研通知网关 | — |

> settler = 金蝶星辰连接 SDK 的代号。代号临用，后续可能换。

## 五、一致性收口

- knotify 现状命名空间 `Company.Notify` 中 `Company` 是占位词 → 统一改 `JSD.Notify`
- 所有自研 .NET 项目公司前缀必须用 `JSD`，禁止再用 `Company` / `KDev` 等其他前缀

## 六、为什么不走 `JSD.SDK.<代号>`

曾考虑 `JSD.SDK.Settler`，否决：

- "SDK"是性质层，"金蝶"是归属层
- 未来金蝶多个产品 SDK 进来时，归属层（金蝶）能把兄弟 SDK 归类；性质层（SDK）会把金蝶系和非金蝶系 SDK 混一起，丢了"金蝶"这层关键归属
- "是 SDK"这性质靠 repo 名后缀 + NuGet 包描述说明即可，不占命名空间
- 结论：**归属层进命名空间，性质层进文档**

---

_本约定随自研项目增长持续演进。新增组件类型（如非金蝶外部系统 SDK、纯前端组件库等）按"归属层进命名空间"原则扩展。_
