#!/bin/bash
# =============================================================================
# Biya Indexer 健康检查脚本
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 默认配置
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.all-in-one.yaml"

# 统计
TOTAL=0
PASSED=0
FAILED=0

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_failed() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 检查服务健康状态
check_service() {
    local service_name="$1"
    local check_cmd="$2"
    local description="$3"
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "  检查 ${description}... "
    
    if eval "$check_cmd" &> /dev/null; then
        print_success "正常"
        PASSED=$((PASSED + 1))
        return 0
    else
        print_failed "异常"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# 检查容器状态
check_container_status() {
    local container_name="$1"
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "  容器状态 [${container_name}]... "
    
    local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not found")
    
    if [ "$status" = "running" ]; then
        print_success "运行中"
        PASSED=$((PASSED + 1))
        return 0
    else
        print_failed "$status"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# 检查 Dragonfly
check_dragonfly() {
    echo ""
    print_info "Dragonfly (Redis 缓存)"
    echo "-------------------------------------------"
    
    check_container_status "dragonfly"
    check_service "dragonfly" "docker exec dragonfly redis-cli ping | grep -q PONG" "Redis PING"
    
    # 显示额外信息
    local info=$(docker exec dragonfly redis-cli INFO server 2>/dev/null | head -5)
    if [ -n "$info" ]; then
        echo "  版本信息:"
        echo "$info" | grep -E "redis_version|dragonfly_version" | sed 's/^/    /'
    fi
}

# 检查 Zookeeper
check_zookeeper() {
    echo ""
    print_info "Zookeeper"
    echo "-------------------------------------------"
    
    check_container_status "zookeeper"
    check_service "zookeeper" "docker exec zookeeper nc -z localhost 2181" "Zookeeper 端口"
}

# 检查 Kafka
check_kafka() {
    echo ""
    print_info "Kafka"
    echo "-------------------------------------------"
    
    check_container_status "kafka"
    check_service "kafka" "docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092" "Kafka Broker API"
    
    # 显示 Topic 列表
    echo "  Topic 列表:"
    docker exec kafka kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | sed 's/^/    /' || echo "    (无法获取)"
}

# 检查 ScyllaDB
check_scylladb() {
    echo ""
    print_info "ScyllaDB"
    echo "-------------------------------------------"
    
    check_container_status "scylla"
    check_service "scylla" "docker exec scylla nodetool status | grep -q '^UN'" "节点状态"
    
    # 显示集群状态
    echo "  集群状态:"
    docker exec scylla nodetool status 2>/dev/null | grep -E "^(UN|DN|UJ|UL)" | sed 's/^/    /' || echo "    (无法获取)"
}

# 检查 Kafka UI (如果存在)
check_kafka_ui() {
    if docker ps --format '{{.Names}}' | grep -q "^kafka-ui$"; then
        echo ""
        print_info "Kafka UI"
        echo "-------------------------------------------"
        
        check_container_status "kafka-ui"
        check_service "kafka-ui" "curl -sf http://localhost:8080 > /dev/null" "Web 界面"
    fi
}

# 检查网络连通性
check_network() {
    echo ""
    print_info "网络连通性"
    echo "-------------------------------------------"
    
    # 检查 Docker 网络
    TOTAL=$((TOTAL + 1))
    echo -n "  Docker 网络 [biya-net]... "
    if docker network inspect biya-net &> /dev/null; then
        print_success "存在"
        PASSED=$((PASSED + 1))
    else
        print_failed "不存在"
        FAILED=$((FAILED + 1))
    fi
}

# 检查磁盘空间
check_disk_space() {
    echo ""
    print_info "磁盘空间"
    echo "-------------------------------------------"
    
    local data_path="${PROJECT_DIR}/data"
    
    if [ -d "$data_path" ]; then
        local usage=$(df -h "$data_path" | tail -1 | awk '{print $5}' | tr -d '%')
        local available=$(df -h "$data_path" | tail -1 | awk '{print $4}')
        
        TOTAL=$((TOTAL + 1))
        echo -n "  数据目录空间... "
        
        if [ "$usage" -lt 80 ]; then
            print_success "正常 (使用: ${usage}%, 可用: ${available})"
            PASSED=$((PASSED + 1))
        elif [ "$usage" -lt 90 ]; then
            print_warning "警告 (使用: ${usage}%, 可用: ${available})"
            PASSED=$((PASSED + 1))
        else
            print_failed "严重 (使用: ${usage}%, 可用: ${available})"
            FAILED=$((FAILED + 1))
        fi
    fi
}

# 显示汇总
show_summary() {
    echo ""
    echo "==========================================="
    echo "                 检查汇总"
    echo "==========================================="
    echo ""
    echo "  总检查项: $TOTAL"
    echo -e "  ${GREEN}通过${NC}: $PASSED"
    echo -e "  ${RED}失败${NC}: $FAILED"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}所有检查通过！系统运行正常。${NC}"
    else
        echo -e "${RED}有 $FAILED 项检查失败，请检查相关服务。${NC}"
    fi
    echo ""
}

# 显示帮助信息
show_help() {
    cat << EOF
Biya Indexer 健康检查脚本

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -f, --file FILE     指定 docker-compose 文件
    --json              以 JSON 格式输出结果
    --quiet             静默模式，仅输出汇总

示例:
    $0                  执行完整健康检查
    $0 --quiet          仅显示检查结果汇总

EOF
    exit 0
}

# 主函数
main() {
    local quiet=false
    local json=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -f|--file)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            --json)
                json=true
                shift
                ;;
            --quiet)
                quiet=true
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                ;;
        esac
    done
    
    echo ""
    echo "==========================================="
    echo "     Biya Indexer 健康检查"
    echo "==========================================="
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 执行检查
    check_dragonfly
    check_zookeeper
    check_kafka
    check_scylladb
    check_kafka_ui
    check_network
    check_disk_space
    
    # 显示汇总
    show_summary
    
    # 返回状态码
    if [ $FAILED -gt 0 ]; then
        exit 1
    fi
    exit 0
}

# 执行主函数
main "$@"

