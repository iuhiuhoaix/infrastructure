#!/usr/bin/env bash
# 统一备份调度：调用各应用热备逻辑 → 汇总打包加密 → 推异地
# 用法：backup-all.sh [daily|weekly|monthly]  默认 daily
# 保留策略：daily 7 / weekly 4 / monthly 6，超出自动清理
# 由 cron 调度：crontab -e
#   0 2 * * *   /opt/devops/backup/backup-all.sh daily
#   0 3 * * 0   /opt/devops/backup/backup-all.sh weekly
#   0 4 1 * *   /opt/devops/backup/backup-all.sh monthly
set -euo pipefail

TYPE="${1:-daily}"
case "$TYPE" in
  daily)   KEEP=7 ;;
  weekly)  KEEP=4 ;;
  monthly) KEEP=6 ;;
  *) echo "usage: $0 [daily|weekly|monthly]"; exit 1 ;;
esac

ROOT="/opt/devops"
STAMP=$(date +%Y%m%d-%H%M%S)
STAGE="${ROOT}/backup/staging/${TYPE}-${STAMP}"
REMOTE="${BACKUP_REMOTE:-}"   # 形如 user@nas:/path/ ，需配置免密 ssh key

mkdir -p "$STAGE"

echo "=== [backup] ${TYPE} @ ${STAMP} ==="

# ---------- 1. 各应用热备 ----------
# GitLab：内置备份（含仓库/PG/uploads），secrets 需单独备份
if docker ps --format '{{.Names}}' | grep -qx gitlab; then
  echo "[gitlab] backup create ..."
  docker exec -t gitlab gitlab-backup create BACKUP="${STAMP}" CRON=1
  # 备份产物在 gitlab 容器 /var/opt/gitlab/backups/，secrets 在 /etc/gitlab
  docker cp gitlab:/var/opt/gitlab/backups/${STAMP}_gitlab_backup.tar "${STAGE}/" 2>/dev/null || true
  cp -a "${ROOT}/gitlab/data/config/gitlab.rb"        "${STAGE}/gitlab.rb"  2>/dev/null || true
  cp -a "${ROOT}/gitlab/data/config/gitlab-secrets.json" "${STAGE}/"        2>/dev/null || true
fi

# Plane：pg_dump + minio 快照
if docker ps --format '{{.Names}}' | grep -qx plane-postgres; then
  echo "[plane] pg_dump ..."
  docker exec -t plane-postgres pg_dumpall -U plane > "${STAGE}/plane_pg.sql"
  tar -C "${ROOT}/plane/data/minio" -czf "${STAGE}/plane_minio.tar.gz" . 2>/dev/null || true
fi

# Jenkins：停写后 tar JENKINS_HOME（流水线定义在 GitLab 可重建，但凭证/插件状态需备）
if docker ps --format '{{.Names}}' | grep -qx jenkins; then
  echo "[jenkins] tar home ..."
  tar -C "${ROOT}/jenkins/data" -czf "${STAGE}/jenkins_home.tar.gz" . 2>/dev/null || true
fi

# Nexus：blob store tar（运行时一致性好于纯 cp；如需严格一致可先停 Nexus）
if docker ps --format '{{.Names}}' | grep -qx nexus; then
  echo "[nexus] tar blob ..."
  tar -C "${ROOT}/nexus/data" -czf "${STAGE}/nexus_blob.tar.gz" . 2>/dev/null || true
fi

# RagFlow：pg_dump + ES snapshot + minio
if docker ps --format '{{.Names}}' | grep -qx ragflow-postgres; then
  echo "[ragflow] pg_dump + minio ..."
  docker exec -t ragflow-postgres pg_dumpall -U ragflow > "${STAGE}/ragflow_pg.sql"
  tar -C "${ROOT}/ragflow/data/minio" -czf "${STAGE}/ragflow_minio.tar.gz" . 2>/dev/null || true
  # ES 索引重，建议走 ES snapshot API 到 minio；此处 tar 作为兜底
  tar -C "${ROOT}/ragflow/data/es" -czf "${STAGE}/ragflow_es.tar.gz" . 2>/dev/null || true
fi

# ---------- 2. 配置 + .env + compose + nginx ----------
echo "[config] tar compose/.env/nginx ..."
tar -C "${ROOT}" -czf "${STAGE}/configs.tar.gz" \
  --exclude='*/data' --exclude='*/backup' \
  gitlab/compose.yaml plane/compose.yaml jenkins/compose.yaml nexus/compose.yaml ragflow/compose.yaml \
  gitlab/.env plane/.env jenkins/.env nexus/.env ragflow/.env \
  nginx/conf.d 2>/dev/null || true
tar -C /etc -czf "${STAGE}/letsencrypt.tar.gz" letsencrypt 2>/dev/null || true

# ---------- 3. 加密打包 ----------
echo "[pack] gpg encrypt ..."
ARCHIVE="${ROOT}/backup/${TYPE}-${STAMP}.tar.gpg"
tar -C "$STAGE" -c . | gpg --batch --yes --passphrase "${BACKUP_GPG_PASSPHRASE:-change-me}" \
  --symmetric --cipher-algo AES256 > "$ARCHIVE"
rm -rf "$STAGE"

# ---------- 4. 推异地 ----------
if [ -n "$REMOTE" ]; then
  echo "[remote] rsync to ${REMOTE} ..."
  rsync -az "$ARCHIVE" "${REMOTE}/${TYPE}/"
fi

# ---------- 5. 清理过期 ----------
cd "${ROOT}/backup"
ls -1t ${TYPE}-*.tar.gpg 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -v

echo "=== [backup] done → ${ARCHIVE} ==="
