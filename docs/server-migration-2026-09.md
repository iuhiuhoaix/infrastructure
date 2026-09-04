# 服务器整机迁移复盘 + 可复现 Runbook（2026-09-04）

> **一句话**：整套栈是「配置在 git、数据在 bind mount」的分离架构，所以换机不需要重建，只要把 `/opt/infrastructure/deploy`（配置）、`/dockerData`（数据）、`/etc/nginx`（入口）、镜像四样搬过去即可——本次 ~15.9GB 数据 + 20 个镜像，字节级校验一致，业务零改造。
>
> **适用场景**：同机房整机换机 / 硬件升级 / 主机故障转移（Linux + Docker Compose 多项目 + bind mount）。
> **不适用**：跨机房（走异地备份 + `deploy/dr/restore-from-scratch.sh` 更合适）。

---

## 一、本次迁移的两端

| | 旧机 | 新机 |
|---|---|---|
| 地址（迁移期） | `192.168.199.131` | `192.168.199.135`（临时，迁移后切换为 `.131`） |
| 形态 | **KVM 虚拟机**（QEMU，hostname `docker.kingstar.local`） | 物理机（hostname `docker01`） |
| CPU | 32 vCPU（2×Xeon E5-4650 v2） | i9-14900K |
| 内存 | **96G vRAM**（6×16G） | 31G → 后期加到 **62G** |
| 登录账号 | root（密钥） | **xhh**（密钥 + sudo 密码），root 账号锁定 |
| 数据盘 | `/dockerData/` | 同路径 |

迁移规模：7 套独立 compose（gitlab / plane / jenkins / nexus / ragflow / ragflow-models / knotify）+ 宿主机 nginx，**22 个容器、约 15.9GB 数据、20 个镜像**。

---

## 二、为什么选「搬盘」而不是 `restore-from-scratch.sh`

| 方案 | 做法 | 本次结论 |
|---|---|---|
| A. DR 脚本恢复 | `restore-from-scratch.sh <backup.tar.gpg>` | 面向**异地备份**：加密归档 → 传 → 解密 → 重建。多一轮打包/解包与 GPG 依赖，适合跨机房 |
| B. **直接搬盘**（采用） | rsync 配置 + 数据 + nginx，镜像 `docker save` 直传 | 面向**同机房在线**：省一轮归档，可边传边校验，停服窗口最短 |

选择 B 的两个前提（本架构天然满足）：
1. **配置全部在 git**（`deploy/`），服务器上只是落地，丢了也能拉回；
2. **数据全部 bind mount 到宿主机**（`/dockerData/<app>/`），不依赖 docker volume，可直接 rsync。

---

## 三、迁移前核对清单（Pre-flight）

- [ ] 两边 `docker version` / `docker compose version` 大版本一致（避免 compose 语法不兼容）
- [ ] 新机磁盘 ≥ 旧机数据 2 倍（`df -h / /opt /var`）
- [ ] 新机已跑过 `deploy/backup/backup-all.sh` 之外的**独立备份**（换机前先留后路）
- [ ] 记录旧机 `docker images` 清单（含 digest，防 floating tag 漂移）
- [ ] 记录旧机端口占用（`ss -tlnp`），避免新机端口冲突
- [ ] 确认新机到 docker.io 的可达性（**本次新机没有代理，直连超时**，这是最大坑）

---

## 四、执行步骤（可复现）

### 1. 打通登录通道

新机是普通用户（非 root），且 ssh agent forwarding 在 root 会话下不可靠，**用临时专用密钥最稳**：

```bash
# 旧机 root 生成临时密钥
ssh-keygen -t ed25519 -f /root/.ssh/migration_tmp_key -N ''
ssh-copy-id -i /root/.ssh/migration_tmp_key.pub xhh@<新机IP>
```

新机侧为 rsync 开临时免密（**迁移完必须删除**）：

```bash
echo 'xhh ALL=(root) NOPASSWD: /usr/bin/rsync' | sudo tee /etc/sudoers.d/migration-rsync
```

### 2. 清理新机旧容器

```bash
docker ps -aq | xargs -r docker stop
docker system prune -af --volumes   # 确认这台机器上的数据确实不要了再执行
```

### 3. 同步配置（含 .env）

配置以 git 仓库为准，服务器之间直接 rsync 落地目录：

```bash
rsync -a --numeric-ids --info=progress2 \
  --rsync-path="sudo rsync" \
  -e "ssh -i /root/.ssh/migration_tmp_key -o BatchMode=yes" \
  /opt/infrastructure/deploy/ xhh@<新机IP>:/opt/infrastructure/deploy/
```

> `--numeric-ids` 必须带：两侧 UID/GID 不一致会让 GitLab、Nexus 等容器内权限错乱。
> `--rsync-path="sudo rsync"` 的引号是整体参数，写错会报 `connection unexpectedly closed`。

### 4. 迁移 `/etc/nginx`

```bash
# 新机先装同版本 nginx，备份原配置
sudo cp -a /etc/nginx /etc/nginx.ubuntu-bak
rsync -a --rsync-path="sudo rsync" -e "ssh ..." /etc/nginx/ xhh@<新机IP>:/tmp/nginx_etc/
sudo rsync -a --delete /tmp/nginx_etc/ /etc/nginx/
```

### 5. 传输镜像（关键坑位）

**新机直连 docker.io 会超时**（旧机有 `socks5://127.0.0.1:7898` 代理，新机没有）。因此不能用 `docker pull`，改为从旧机 `docker save` 内网直传：

```bash
docker save <image:tag> | gzip | ssh -i /root/.ssh/migration_tmp_key xhh@<新机IP> \
  'gunzip | docker load'
```

要点：
- 后台执行请用 `nohup ... < /dev/null > log 2>&1 &`，**不要** `ssh host "cmd &"`——会话断开会连带杀掉子进程；
- 完成后用 `docker images --digests` 逐条核对，floating tag（如 `minio/minio:latest`）需在新机 `docker tag <digest> <repo>:<tag>` 补标签。

### 6. 数据同步（停服窗口）

停服顺序（**先停依赖方，后停被依赖方**）：

```
knotify → jenkins → ragflow-models → ragflow → plane → gitlab → nexus
```

同步（逐目录，便于核对与断点续传）：

```bash
for d in gitlab jenkins nexus plane RagFlow ragflow_bak; do
  rsync -a --numeric-ids --info=progress2 \
    --rsync-path="sudo rsync" -e "ssh -i ... " \
    /dockerData/$d/ xhh@<新机IP>:/dockerData/$d/
done
```

### 7. 启动

```bash
# 外部网络必须先手工创建，compose 不会自动建 external
docker network create devops-internal
docker network create ragflow_ragflow

# 启动顺序：数据层 → 应用 → 模型服务
cd /opt/infrastructure/deploy/network && ./setup-network.sh
for app in gitlab nexus jenkins plane ragflow ragflow-models knotify; do
  (cd /opt/infrastructure/deploy/$app && docker compose up -d)
done
```

### 8. 验证

**数据字节级核对**（比 `du` 更可靠的是同口径统计）：

```bash
# 两侧各跑一次，比对「字节数 + 文件数」
du -sb /dockerData/<dir> && find /dockerData/<dir> -type f | wc -l
```

**HTTP 冒烟**（注意端口，见第六节速查表，很多端口不是直觉值）：

```bash
for p in 8080 3000 8081 8082 9380; do
  curl -s -o /dev/null -w "$p -> %{http_code}\n" http://127.0.0.1:$p/
done
```

**GitLab SSH 通道**（这是最有价值的端到端验证）：

```bash
ssh -T -p 2222 git@<新机IP>          # 期望：Welcome to GitLab, @<用户名>!
git ls-remote gitlab                  # 期望：列出 refs
```

**TEI 模型服务**（别用 8080，那是 GitLab）：

```bash
curl -s -X POST http://127.0.0.1:6101/embed \
  -H 'Content-Type: application/json' -d '{"inputs":["测试"]}'
# 期望：返回 1024 维向量数组
```

---

## 五、踩坑与解法（本次实录）

| # | 现象 | 根因 | 解法 |
|---|---|---|---|
| 1 | 新机 `docker pull` 全部 `i/o timeout` | 新机没有 docker.io 代理（旧机有 socks5） | 旧机 `docker save \| ssh \| docker load` 内网传输 |
| 2 | ssh agent forwarding 传镜像 `Permission denied` | agent 没传播到 root 会话 | 改用临时专用密钥 |
| 3 | 后台传镜像中断 | `ssh host "cmd &"` 随会话断连被杀 | `nohup ... < /dev/null > log 2>&1 &` |
| 4 | rsync `connection unexpectedly closed` (code 12) | `--rsync-path=sudo rsync` 引号/拼接写错 | 写成函数统一拼接，见第四节 |
| 5 | nexus/jenkins 启动仍去拉 docker.io | compose 里 image 写死 `@sha256:...`，本地 tag 对不上 | 在 `.env` 加 `NEXUS_IMAGE=sonatype/nexus3:latest` 等变量覆盖 |
| 6 | ragflow 启动报 network `ragflow_ragflow` not found | external 网络不会自动创建 | 手工 `docker network create ragflow_ragflow` |
| 7 | nginx `stream` 指令 unknown directive | `/etc/nginx/modules-enabled` 目录缺失，导致 `libnginx-mod-stream` 安装后配置失败 | `mkdir /etc/nginx/modules-enabled` → `dpkg --configure -a` → nginx.conf 顶部加 `include /etc/nginx/modules-enabled/*.conf;` |
| 8 | **TEI embedding 容器反复 OOM（exit 137）** | warmup 预分配随 `--max-batch-tokens` 增长，`16384` 时需 ~12.5G，超过 12g 的 cgroup 上限（**与宿主机内存无关**） | 见第七节内存基线 |
| 9 | 冒烟时 `8080/health` 返回 302、`8081/health` 返回 404 | 8080 是 GitLab、8081 是 Nexus，**TEI 实际端口是 6101/6102** | 按 `.env` 的 `EMBEDDING_PORT`/`RERANKER_PORT` 测 |

---

## 六、新机端口与账号速查

| 端口 | 服务 | 备注 |
|---|---|---|
| 22 | 宿主机 ssh | ⚠️ 本地 ssh config 把 `.131` 默认指向 2222，**登机必须显式 `ssh -p 22 xhh@192.168.199.131`** |
| 2222 | GitLab SSH（git 通道） | `ssh://git@192.168.199.131:2222/...` |
| 8080 | GitLab Web | external_url |
| 8081 | Nexus UI | |
| 8082 | Jenkins | 未登录返回 403 属正常 |
| 8083 | Nexus Docker Registry | |
| 3000 | Plane | |
| 9380 | RagFlow | |
| **6101 / 6102** | **TEI embedding / reranker** | 仅在 127.0.0.1，nginx 不代理 |

**账号**：一律 `xhh`（密钥 + sudo 密码）。root 账号为锁定状态（`passwd -S root` → `L`），root 直登不可用，需要 root 走 `sudo -i`。

---

## 七、内存基线（62G 配置实测）

| 组件 | 空转占用 | 说明 |
|---|---|---|
| embedding-cpu (TEI) | ~20G（上限） | 见下方结论 |
| reranker-cpu (TEI) | ~11G | |
| gitlab | 7~9G | omnibus 全默认，未做瘦身 |
| ragflow 主程序 | 2.6~4.5G | |
| elasticsearch | 2~4.5G | RagFlow 的文档/向量引擎 |
| nexus | ~1.2G | JVM 堆 1200m（.env 里本就有） |
| jenkins | ~0.4G | |

**TEI 内存的两层行为（重要）**：
1. **warmup 固定开销**随 `--max-batch-tokens` 增长：`16384` → 约 12.5G；`8192` → 约 11.5G。**这一步超过 `mem_limit` 就是 cgroup OOM**，与宿主机有多少内存无关；
2. warmup 后**分配器会继续保留内存逼近上限**（给 16g 吃 15.7g、给 20g 吃 19.6g）。这是 arena 驻留而非真实需求，**看到"贴顶"不必恐慌，也不要继续追加上限**。

经验值：
- 小内存机（≤32G）：`EMBEDDING_MAX_BATCH_TOKENS=8192` + `EMBEDDING_MEMORY_LIMIT=12g`
- 内存宽裕（≥64G）：`16384` + `20g`
- 该参数在服务器上通过 `deploy/ragflow-models/.env` 覆盖（compose 默认值未改）

---

## 八、回滚与恢复

- **换机期间旧机只停服不删数据**：新机验证不通过时，把服务在旧机起回来即可，成本极低；
- **新机要从零重来**：`deploy/dr/restore-from-scratch.sh <backup.tar.gpg>`（异地备份路径）；
- **定期备份**：`deploy/backup/backup-all.sh`，含各组件数据 + `.env`（GPG 加密）；
- **配置永远可以重建**：`deploy/` 在 git 里，服务器只是部署落地，改配置请回 git 仓库，不要在服务器上直接改。

---

## 九、本次遗留与建议

| 项 | 状态 |
|---|---|
| 新机内存 31G → 62G | ✅ 已完成 |
| IP 切换（新机接管 `.131`） | ✅ 已完成（hostname `docker01`） |
| GitLab 双远端同步（GitHub + GitLab） | ✅ 已推送对齐 |
| nginx 启用 | ✅ active，配置校验通过 |
| 建议长期内存水位 | ≥64G（当前 62G 用了 49G） |
| 迁移临时授权清理 | sudoers 条目、135 侧临时公钥、/tmp 脚本 ✅ 已清 |
