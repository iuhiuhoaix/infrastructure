#!/usr/bin/env bash
# 灾难恢复：在新 Linux 服务器上从异地备份恢复全套 DevOps 服务。
# 对应 deploy-architecture.html §15 的 8 步流程。
# 前置：新机已就绪、异地备份可达、域名 DNS 可切换、.env 的 GPG 密钥可用。
# 用法：restore-from-scratch.sh <backup-file.tar.gpg>
set -euo pipefail

ARCHIVE="${1:?usage: $0 <backup-file.tar.gpg>}"
ROOT="/opt/devops"
GPG_PASS="${BACKUP_GPG_PASSPHRASE:-change-me}"
REMOTE="${BACKUP_REMOTE:-}"

echo "########## DR: restore from scratch ##########"
echo "backup: $ARCHIVE"

# ---------- 1. 环境检查 ----------
echo "[1/8] check docker / nginx / certbot ..."
command -v docker >/dev/null || { echo "install docker first"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "install docker compose plugin"; exit 1; }
command -v nginx >/dev/null || apt install -y nginx
command -v certbot >/dev/null || apt install -y certbot python3-certbot-nginx

# ---------- 2. 创建 external network ----------
echo "[2/8] create devops-internal ..."
bash "${ROOT}/network/setup-network.sh"

# ---------- 3. 解密恢复 compose + .env ----------
echo "[3/8] decrypt & restore configs ..."
STAGE=$(mktemp -d)
gpg --batch --yes --passphrase "$GPG_PASS" --decrypt "$ARCHIVE" | tar -C "$STAGE" -x
# 恢复各应用 compose + .env
for app in gitlab plane jenkins nexus ragflow; do
  mkdir -p "${ROOT}/${app}"
  cp "${STAGE}/${app}/compose.yaml" "${ROOT}/${app}/" 2>/dev/null || true
  install -m 600 "${STAGE}/${app}/.env" "${ROOT}/${app}/.env" 2>/dev/null || true
done
mkdir -p "${ROOT}/nginx"
cp -r "${STAGE}/nginx/conf.d" "${ROOT}/nginx/" 2>/dev/null || true

# ---------- 4. 恢复数据卷 ----------
echo "[4/8] restore data volumes ..."
# GitLab
[ -f "${STAGE}/${STAMP:-}_gitlab_backup.tar" ] && cp "${STAGE}/"*_gitlab_backup.tar "${ROOT}/gitlab/data/app/backups/" 2>/dev/null || true
cp "${STAGE}/gitlab.rb" "${ROOT}/gitlab/data/config/" 2>/dev/null || true
cp "${STAGE}/gitlab-secrets.json" "${ROOT}/gitlab/data/config/" 2>/dev/null || true
# Plane
[ -f "${STAGE}/plane_pg.sql" ] && mkdir -p "${ROOT}/plane/data" || true
[ -f "${STAGE}/plane_minio.tar.gz" ] && mkdir -p "${ROOT}/plane/data/minio" && tar -C "${ROOT}/plane/data/minio" -xzf "${STAGE}/plane_minio.tar.gz" || true
# Jenkins
[ -f "${STAGE}/jenkins_home.tar.gz" ] && mkdir -p "${ROOT}/jenkins/data" && tar -C "${ROOT}/jenkins/data" -xzf "${STAGE}/jenkins_home.tar.gz" || true
# Nexus
[ -f "${STAGE}/nexus_blob.tar.gz" ] && mkdir -p "${ROOT}/nexus/data" && tar -C "${ROOT}/nexus/data" -xzf "${STAGE}/nexus_blob.tar.gz" || true
# RagFlow
[ -f "${STAGE}/ragflow_pg.sql" ] && mkdir -p "${ROOT}/ragflow/data" || true
[ -f "${STAGE}/ragflow_minio.tar.gz" ] && mkdir -p "${ROOT}/ragflow/data/minio" && tar -C "${ROOT}/ragflow/data/minio" -xzf "${STAGE}/ragflow_minio.tar.gz" || true
[ -f "${STAGE}/ragflow_es.tar.gz" ] && mkdir -p "${ROOT}/ragflow/data/es" && tar -C "${ROOT}/ragflow/data/es" -xzf "${STAGE}/ragflow_es.tar.gz" || true

# ---------- 5. 按依赖顺序启动 ----------
echo "[5/8] start compose: nexus → gitlab → plane → ragflow → jenkins ..."
for app in nexus gitlab plane ragflow jenkins; do
  echo "  → ${app}"
  ( cd "${ROOT}/${app}" && docker compose up -d )
done

# 恢复 PG 数据库内容（容器启动后导入）
[ -f "${STAGE}/plane_pg.sql" ]   && docker exec -i plane-postgres   psql -U plane   < "${STAGE}/plane_pg.sql"   || true
[ -f "${STAGE}/ragflow_pg.sql" ] && docker exec -i ragflow-postgres psql -U ragflow < "${STAGE}/ragflow_pg.sql" || true

# GitLab 备份恢复（容器内执行）
GB=$(ls "${ROOT}/gitlab/data/app/backups/"*_gitlab_backup.tar 2>/dev/null | head -1)
if [ -n "$GB" ]; then
  docker exec -t gitlab gitlab-backup restore BACKUP=$(basename "$GB" _gitlab_backup.tar) force=yes || true
fi

# ---------- 6. 恢复 Nginx + 证书 ----------
echo "[6/8] restore nginx + certs ..."
[ -f "${STAGE}/letsencrypt.tar.gz" ] && tar -C /etc -xzf "${STAGE}/letsencrypt.tar.gz" || \
  echo "  (无证书备份，需重新 certbot 签发或 DNS 就绪后执行)"
ln -sf "${ROOT}/nginx/conf.d/devops.conf" /etc/nginx/conf.d/devops.conf 2>/dev/null || true
nginx -t && systemctl reload nginx || systemctl restart nginx

# ---------- 7. DNS + 冒烟验证 ----------
echo "[7/8] verify (请确认 DNS 已切到本机) ..."
for d in git plane jenkins nexus rag; do
  echo "  → curl -kI https://${d}.example.com"
  curl -kI "https://${d}.example.com" 2>/dev/null | head -1 || echo "  (未就绪，检查 DNS/Nginx)"
done

# ---------- 8. 恢复 Agent ----------
echo "[8/8] reattach build agents ..."
echo "  Linux Docker Agent: docker restart jenkins-linux-agent（或重新 compose up）"
echo "  Windows Agent: 在 Windows Server 上重启 agent.jar，Controller WebSocket 自动重连"

rm -rf "$STAGE"
echo "########## DR done. 逐项人工验证登录/clone/build ##########"
