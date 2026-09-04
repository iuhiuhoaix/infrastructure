#!/bin/bash
# knotify 服务器构建脚本（宿主机 SDK 发布路径，绕开 mcr sdk 镜像拉取难题）
# 背景：mcr.microsoft.com 在国内直连极慢、机场代理对大层不稳，docker pull sdk 镜像经常失败；
#       实测"SDK tar 并行分段下载（dl-parallel.py）+ 宿主机 dotnet publish + aspnet 镜像构建"最稳。
# 用法（服务器 192.168.199.131，root）：
#   1. 同步 knotify 源码到 /opt/knotify（git clone 或 scp）
#   2. 下载 SDK：python3 deploy/dl-parallel.py（并行分段下载，完成后自动合并）
#   3. bash deploy/build.sh
#   4. cd .. && docker compose up -d   # 用已有 knotify-gateway 镜像，不触发 build
set -e

KNOTIFY_SRC="${KNOTIFY_SRC:-/opt/knotify}"
SDK_TGZ="${SDK_TGZ:-/opt/dotnet-sdk-10.0.302-linux-x64.tar.gz}"
SDK_DIR="${SDK_DIR:-/opt/dotnet}"
PUBLISH_DIR="${PUBLISH_DIR:-/opt/knotify-publish}"
IMAGE_TAG="${IMAGE_TAG:-knotify-gateway:0.1.0}"

if [ ! -f "$SDK_TGZ" ]; then
  echo "缺少 SDK 包: $SDK_TGZ —— 先跑: python3 deploy/dl-parallel.py" >&2
  exit 1
fi

echo "[1/4] 解压 SDK..."
rm -rf "$SDK_DIR" && mkdir -p "$SDK_DIR"
tar xzf "$SDK_TGZ" -C "$SDK_DIR"
export DOTNET_ROOT="$SDK_DIR"
export PATH="$SDK_DIR:$PATH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
dotnet --version

echo "[2/4] restore + publish..."
cd "$KNOTIFY_SRC"
rm -rf "$PUBLISH_DIR"
dotnet publish src/Company.Notify.Api/Company.Notify.Api.csproj -c Release -o "$PUBLISH_DIR"

echo "[3/4] 构建运行镜像（FROM aspnet:10.0，服务器本地已有）..."
cat > "$PUBLISH_DIR/Dockerfile" << 'EOF'
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY . .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Company.Notify.Api.dll"]
EOF
docker build -t "$IMAGE_TAG" "$PUBLISH_DIR"

echo "[4/4] 完成。下一步: cd /opt/infrastructure/deploy/knotify && docker compose up -d"
