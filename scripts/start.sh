#!/bin/bash

# =============================================================================
# Biya Indexer 启动脚本
# 
# 功能：
#   1. 检查环境配置
#   2. 启动所有服务（使用 docker-compose）
#   3. 可选：启动包含 Kafka UI 的服务
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
COMPOSE_FILE="docker-compose.all-in-one.yaml"
ENV_FILE=".env"

# 检查 .env 文件
if [ ! -f "$ENV_FILE" ]; then
    echo "${YELLOW}[WARNING]${NC} .env 文件不存在，使用默认配置"
    if [ -f "env.example" ]; then
        echo "${BLUE}[INFO]${NC} 从 env.example 创建 .env 文件..."
        cp env.example "$ENV_FILE"
        echo "${YELLOW}[INFO]${NC} 请编辑 .env 文件配置环境变量"
    fi
fi

# 检查 docker-compose 文件
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "${RED}[ERROR]${NC} 找不到 $COMPOSE_FILE 文件"
    exit 1
fi

# 检查 Docker 是否可用
if ! command -v docker &> /dev/null; then
    echo "${RED}[ERROR]${NC} Docker 未安装或不可用"
    exit 1
fi

# 检查是否有 --with-ui 参数
WITH_UI=false
if [ "$1" = "--with-ui" ]; then
    WITH_UI=true
fi

echo ""
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo "${BLUE}       启动 Biya Indexer 服务${NC}"
echo "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# 创建必要的目录
echo "${BLUE}[INFO]${NC} 创建数据目录..."
mkdir -p data/dragonfly data/kafka data/zookeeper/data data/zookeeper/logs data/scylla/data
mkdir -p logs/dragonfly logs/indexer-client logs/indexer-consumer

# 启动服务
if [ "$WITH_UI" = true ]; then
    echo "${BLUE}[INFO]${NC} 启动所有服务（包含 Kafka UI）..."
    docker compose -f "$COMPOSE_FILE" --profile ui up -d
else
    echo "${BLUE}[INFO]${NC} 启动所有服务..."
    docker compose -f "$COMPOSE_FILE" up -d
fi

# 等待服务启动
echo ""
echo "${BLUE}[INFO]${NC} 等待服务启动..."
sleep 5

# 显示服务状态
echo ""
echo "${BLUE}[INFO]${NC} 服务状态:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "${GREEN}[SUCCESS]${NC} 服务启动完成！"
echo ""
echo "${YELLOW}提示:${NC}"
echo "  - 查看服务状态: make status 或 docker compose -f $COMPOSE_FILE ps"
echo "  - 查看日志: make logs 或 docker compose -f $COMPOSE_FILE logs -f"
echo "  - 健康检查: make health"
echo ""

