#!/bin/bash

# =============================================================================
# Biya Indexer 镜像构建脚本
# 
# 功能：
#   1. 检查并初始化 Git 子模块
#   2. 从 .env 文件读取代理配置（可选）
#   3. 构建三个索引服务镜像：
#      - indexer-client (grpc client)
#      - indexer-consumer (injective-consumer)
#      - indexer-server (indexer-grpc-server)
# =============================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 切换到项目根目录
cd "$PROJECT_ROOT"

# 默认配置
INDEXER_VERSION="${INDEXER_VERSION:-latest}"
BIYA_INDEXER_RS_DIR="${BIYA_INDEXER_RS_DIR:-biya-indexer-rs}"

echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE}       Biya Indexer 镜像构建${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# 检查 Docker 是否可用
if ! command -v docker &> /dev/null; then
    echo "${RED}[ERROR]${NC} Docker 未安装或不可用"
    exit 1
fi

# 检查子模块目录是否存在
if [ ! -d "$BIYA_INDEXER_RS_DIR" ]; then
    echo "${YELLOW}[WARNING]${NC} 子模块目录 $BIYA_INDEXER_RS_DIR 不存在，尝试初始化..."
    if [ -f ".gitmodules" ]; then
        echo "${BLUE}[INFO]${NC} 初始化 Git 子模块..."
        git submodule update --init --recursive
    else
        echo "${RED}[ERROR]${NC} 找不到 .gitmodules 文件，请确保已正确克隆项目"
        exit 1
    fi
fi

# 检查 Dockerfile 是否存在
if [ ! -f "$BIYA_INDEXER_RS_DIR/Dockerfile.grpc.client" ] || \
   [ ! -f "$BIYA_INDEXER_RS_DIR/Dockerfile.consumer" ] || \
   [ ! -f "$BIYA_INDEXER_RS_DIR/Dockerfile.grpc.server" ]; then
    echo "${RED}[ERROR]${NC} 找不到 Dockerfile 文件，请确保子模块已正确初始化"
    exit 1
fi

# 读取 .env 文件中的代理配置（如果存在）
BUILD_ARGS=()
if [ -f ".env" ]; then
    echo "${BLUE}[INFO]${NC} 读取 .env 文件中的代理配置..."
    # 使用 source 或 export 来读取环境变量
    set -a
    source .env 2>/dev/null || true
    set +a
    
    # 如果配置了代理，添加到构建参数
    if [ -n "$HTTP_PROXY" ]; then
        BUILD_ARGS+=("--build-arg" "HTTP_PROXY=$HTTP_PROXY")
        echo "${GREEN}[INFO]${NC} 使用 HTTP_PROXY: $HTTP_PROXY"
    fi
    if [ -n "$HTTPS_PROXY" ]; then
        BUILD_ARGS+=("--build-arg" "HTTPS_PROXY=$HTTPS_PROXY")
        echo "${GREEN}[INFO]${NC} 使用 HTTPS_PROXY: $HTTPS_PROXY"
    fi
    if [ -n "$NO_PROXY" ]; then
        BUILD_ARGS+=("--build-arg" "NO_PROXY=$NO_PROXY")
        echo "${GREEN}[INFO]${NC} 使用 NO_PROXY: $NO_PROXY"
    fi
fi

# 构建函数
build_image() {
    local dockerfile=$1
    local image_name=$2
    local description=$3
    
    echo ""
    echo "${BLUE}[INFO]${NC} 构建镜像: $image_name"
    echo "${BLUE}[INFO]${NC} 描述: $description"
    echo "${BLUE}[INFO]${NC} Dockerfile: $dockerfile"
    
    if docker build \
        "${BUILD_ARGS[@]}" \
        -f "$dockerfile" \
        -t "$image_name:$INDEXER_VERSION" \
        "$BIYA_INDEXER_RS_DIR"; then
        echo "${GREEN}[SUCCESS]${NC} 镜像 $image_name:$INDEXER_VERSION 构建成功"
        return 0
    else
        echo "${RED}[ERROR]${NC} 镜像 $image_name:$INDEXER_VERSION 构建失败"
        return 1
    fi
}

# 构建 indexer-client 镜像
echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE} 构建 indexer-client 镜像${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
build_image \
    "$BIYA_INDEXER_RS_DIR/Dockerfile.grpc.client" \
    "indexer-client" \
    "从链上获取数据并写入 Kafka 的服务"

# 构建 indexer-consumer 镜像
echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE} 构建 indexer-consumer 镜像${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
build_image \
    "$BIYA_INDEXER_RS_DIR/Dockerfile.consumer" \
    "indexer-consumer" \
    "从 Kafka 消费数据并写入 ScyllaDB 和 Dragonfly 的服务"

# 构建 indexer-server 镜像
echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE} 构建 indexer-server 镜像${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
build_image \
    "$BIYA_INDEXER_RS_DIR/Dockerfile.grpc.server" \
    "indexer-server" \
    "对外提供 gRPC 查询服务的服务"

# 显示构建结果
echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE} 构建完成${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo "${GREEN}已构建的镜像:${NC}"
docker images | grep -E "indexer-client|indexer-consumer|indexer-server" | grep "$INDEXER_VERSION" || true
echo ""
echo "${GREEN}[SUCCESS]${NC} 所有镜像构建完成！"
echo ""
echo "${YELLOW}提示:${NC} 使用 'make start' 或 'docker-compose -f docker-compose.all-in-one.yaml up -d' 启动服务"
echo ""

