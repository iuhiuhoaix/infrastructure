#!/usr/bin/env bash
# 创建跨 Compose 共享的 external network。
# 所有应用的"对外服务容器"加入此网络，实现容器名互访。
# 幂等：已存在则跳过。
set -euo pipefail

NETWORK_NAME="devops-internal"

if docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
  echo "[skip] network '$NETWORK_NAME' already exists"
else
  docker network create --driver bridge "$NETWORK_NAME"
  echo "[ok] created network '$NETWORK_NAME'"
fi

docker network inspect "$NETWORK_NAME" --format 'name={{.Name}} driver={{.Driver}} id={{.Id}}'
