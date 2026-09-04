#!/usr/bin/env bash
# 131 停服 + 数据 rsync 到 135
# 用法: bash migrate_data_131.sh [stop|sync|all]
set -uo pipefail

TARGET="xhh@192.168.199.135"
SSH_OPTS="-i /root/.ssh/migration_tmp_key -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

PHASE="${1:-all}"

rsync_to() {
  # $1 = 源（以 / 结尾）, $2 = 目标路径
  rsync -a --numeric-ids --info=progress2 \
    --rsync-path="sudo rsync" \
    -e "ssh $SSH_OPTS" \
    "$1" "$TARGET:$2"
}

do_stop() {
  echo "===== [1/2] 停服（应用层 → 数据层） ====="
  echo "--- knotify ---";   docker stop -t 60 knotify
  echo "--- jenkins ---";   docker stop -t 60 jenkins
  echo "--- ragflow-models ---"
  (cd /opt/infrastructure/deploy/ragflow-models && docker compose stop -t 60)
  echo "--- ragflow (ES flush 慢，给 120s) ---"
  (cd /opt/infrastructure/deploy/ragflow && docker compose stop -t 120)
  echo "--- plane ---"
  (cd /opt/devops/plane && docker compose stop -t 60)
  echo "--- gitlab (内部服务多，给 240s) ---"
  docker stop -t 240 gitlab
  echo "--- nexus (blob flush，给 180s) ---"
  docker stop -t 180 nexus
  echo "===== 停服完成，剩余运行容器： ====="
  docker ps --format '{{.Names}}'
}

do_sync() {
  echo "===== [2/2] 数据 rsync → 135 ====="
  local failed=0
  for dir in gitlab jenkins nexus plane RagFlow ragflow_bak; do
    echo "=== /dockerData/$dir ==="
    rsync_to "/dockerData/$dir/" "/dockerData/$dir/" | tail -1 || failed=1
  done
  echo "=== knotify data（compose 目录内） ==="
  rsync_to /opt/infrastructure/deploy/knotify/data/ /opt/infrastructure/deploy/knotify/data/ | tail -1 || failed=1
  if [ "$failed" -eq 0 ]; then
    echo "===== 数据同步完成 ====="
  else
    echo "===== 数据同步存在失败项，检查日志 ====="
    return 1
  fi
}

case "$PHASE" in
  stop) do_stop ;;
  sync) do_sync ;;
  all)  do_stop && do_sync ;;
  *) echo "usage: $0 [stop|sync|all]"; exit 1 ;;
esac
