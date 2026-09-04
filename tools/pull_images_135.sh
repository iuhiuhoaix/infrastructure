#!/usr/bin/env bash
# 135 预拉镜像：全部按 digest/tag 锁定，与 131 运行版本一致
set -uo pipefail

IMAGES=(
  # docker.io 锁 tag
  "elasticsearch:8.11.3"
  "gitlab/gitlab-ce:19.1.3-ce.0"
  "jenkins/jenkins:2.568.2-jdk21"
  "mysql:8.0.40"
  "postgres:15-alpine"
  "rabbitmq:3.13.6-alpine"
  "redis:7-alpine"
  "valkey/valkey:8"
  "pgsty/silo:RELEASE.2026-08-06T00-00-00Z"
  # docker.io 锁 digest（floating tag）
  "sonatype/nexus3@sha256:c480a686375bd15a76d9011b7ae263ddffe3897659d183ce88c3a53998453aa2"
  "minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e"
  "makeplane/plane-backend@sha256:fbd4b3cea455df88e5473d01e56162286d5f61991898903d9142a7f502799481"
  "makeplane/plane-frontend@sha256:8f0f5ee02169c3435fa178aa60707920bfc398bff2ebbe83e72881c029d5fe56"
  "makeplane/plane-admin@sha256:db215110ef79ab4048334086c891e1499f4c0d30724030a884f6fb61df162d8d"
  "makeplane/plane-live@sha256:02fd23645fa0f84a68ccfdbab8ba6ceaac5deca6c482bff041880b02295ae76c"
  "makeplane/plane-space@sha256:741cd5d6bbfaa94bac4a28837d5fab3f7459b014a6c9066728a3b3cfe76fc6c8"
  # ghcr.io 直连
  "ghcr.io/huggingface/text-embeddings-inference:cpu-1.8.3"
  # ragflow 大镜像：先试 pull，失败则走 docker save 传输
  "infiniflow/ragflow:v0.26.4"
)

FAILED=()
for img in "${IMAGES[@]}"; do
  echo "=== [pull] $img ==="
  if docker pull "$img"; then
    echo "OK: $img"
  else
    echo "FAIL: $img"
    FAILED+=("$img")
  fi
done

# digest 拉的镜像补打 tag（compose 用的是 tag 引用）
docker tag sonatype/nexus3@sha256:c480a686375bd15a76d9011b7ae263ddffe3897659d183ce88c3a53998453aa2 sonatype/nexus3:latest 2>/dev/null
docker tag minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e minio/minio:latest 2>/dev/null
docker tag makeplane/plane-backend@sha256:fbd4b3cea455df88e5473d01e56162286d5f61991898903d9142a7f502799481 makeplane/plane-backend:stable 2>/dev/null
docker tag makeplane/plane-frontend@sha256:8f0f5ee02169c3435fa178aa60707920bfc398bff2ebbe83e72881c029d5fe56 makeplane/plane-frontend:stable 2>/dev/null
docker tag makeplane/plane-admin@sha256:db215110ef79ab4048334086c891e1499f4c0d30724030a884f6fb61df162d8d makeplane/plane-admin:stable 2>/dev/null
docker tag makeplane/plane-live@sha256:02fd23645fa0f84a68ccfdbab8ba6ceaac5deca6c482bff041880b02295ae76c makeplane/plane-live:stable 2>/dev/null
docker tag makeplane/plane-space@sha256:741cd5d6bbfaa94bac4a28837d5fab3f7459b014a6c9066728a3b3cfe76fc6c8 makeplane/plane-space:stable 2>/dev/null

echo ""
echo "========== SUMMARY =========="
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "ALL OK"
else
  echo "FAILED: ${FAILED[*]}"
fi
