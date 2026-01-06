# =============================================================================
# Biya Indexer Makefile
# 
# 快速命令参考:
#   make help         - 显示帮助信息
#   make start        - 启动所有服务
#   make stop         - 停止所有服务
#   make status       - 查看服务状态
#   make logs         - 查看所有日志
#   make health       - 执行健康检查
# =============================================================================

.PHONY: help init build-images deploy start stop restart status logs health clean

# 默认配置
COMPOSE_FILE := docker-compose.all-in-one.yaml
ENV_FILE := .env

# 颜色定义
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# 默认目标
.DEFAULT_GOAL := help

# 帮助信息
help:
	@echo ""
	@echo "$(BLUE)═══════════════════════════════════════════$(NC)"
	@echo "$(BLUE)       Biya Indexer 部署命令$(NC)"
	@echo "$(BLUE)═══════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)初始化:$(NC)"
	@echo "  make init              初始化环境（创建目录和配置文件）"
	@echo ""
	@echo "$(GREEN)构建和部署:$(NC)"
	@echo "  make build-images      构建所有索引服务镜像（从源码编译）"
	@echo "  make deploy            一键部署（构建镜像 + 启动服务）"
	@echo ""
	@echo "$(GREEN)服务管理:$(NC)"
	@echo "  make start             启动所有服务"
	@echo "  make start-ui          启动所有服务（包含 Kafka UI）"
	@echo "  make stop              停止所有服务"
	@echo "  make restart           重启所有服务"
	@echo "  make down              停止并删除容器"
	@echo "  make destroy           停止并删除容器和数据（危险！）"
	@echo ""
	@echo "$(GREEN)中间件单独管理:$(NC)"
	@echo "  make start-dragonfly   启动 Dragonfly"
	@echo "  make start-kafka       启动 Kafka + Zookeeper"
	@echo "  make start-scylla      启动 ScyllaDB"
	@echo ""
	@echo "$(GREEN)监控和日志:$(NC)"
	@echo "  make status            查看服务状态"
	@echo "  make logs              查看所有日志"
	@echo "  make logs-dragonfly    查看 Dragonfly 日志"
	@echo "  make logs-kafka        查看 Kafka 日志"
	@echo "  make logs-scylla       查看 ScyllaDB 日志"
	@echo "  make health            执行健康检查"
	@echo ""
	@echo "$(GREEN)数据管理:$(NC)"
	@echo "  make backup            备份数据"
	@echo "  make clean-logs        清理日志文件"
	@echo ""

# 初始化环境
init:
	@echo "$(BLUE)[INFO]$(NC) 初始化环境..."
	@if [ ! -f .env ]; then \
		cp env.example .env; \
		echo "$(GREEN)[SUCCESS]$(NC) 已创建 .env 文件"; \
	else \
		echo "$(YELLOW)[SKIP]$(NC) .env 文件已存在"; \
	fi
	@mkdir -p data/dragonfly data/kafka data/zookeeper/data data/zookeeper/logs data/scylla/data logs/dragonfly
	@echo "$(GREEN)[SUCCESS]$(NC) 数据目录已创建"
	@echo ""
	@echo "$(YELLOW)请编辑 .env 文件配置环境变量，然后运行 'make start' 启动服务$(NC)"

# 构建所有索引服务镜像
build-images:
	@echo "$(BLUE)[INFO]$(NC) 构建索引服务镜像..."
	@./scripts/build-images.sh

# 一键部署（构建镜像 + 启动服务）
deploy: build-images
	@echo "$(BLUE)[INFO]$(NC) 构建完成，启动服务..."
	@./scripts/start.sh

# 启动所有服务
start:
	@echo "$(BLUE)[INFO]$(NC) 启动所有服务..."
	@./scripts/start.sh
	
# 启动所有服务（包含 UI）
start-ui:
	@echo "$(BLUE)[INFO]$(NC) 启动所有服务（包含 Kafka UI）..."
	@./scripts/start.sh --with-ui

# 启动 Dragonfly
start-dragonfly:
	@echo "$(BLUE)[INFO]$(NC) 启动 Dragonfly..."
	docker compose -f $(COMPOSE_FILE) up -d dragonfly

# 启动 Kafka
start-kafka:
	@echo "$(BLUE)[INFO]$(NC) 启动 Kafka + Zookeeper..."
	docker compose -f $(COMPOSE_FILE) up -d zookeeper kafka

# 启动 ScyllaDB
start-scylla:
	@echo "$(BLUE)[INFO]$(NC) 启动 ScyllaDB..."
	docker compose -f $(COMPOSE_FILE) up -d scylla

# 停止所有服务
stop:
	@echo "$(BLUE)[INFO]$(NC) 停止所有服务..."
	docker compose -f $(COMPOSE_FILE) stop

# 重启所有服务
restart:
	@echo "$(BLUE)[INFO]$(NC) 重启所有服务..."
	docker compose -f $(COMPOSE_FILE) restart

# 停止并删除容器
down:
	@echo "$(BLUE)[INFO]$(NC) 停止并删除容器..."
	docker compose -f $(COMPOSE_FILE) down

# 停止并删除容器和数据卷
destroy:
	@echo "$(YELLOW)[WARNING]$(NC) 此操作将删除所有数据！"
	@read -p "确认删除？[y/N] " confirm && [ "$$confirm" = "y" ] && \
		docker compose -f $(COMPOSE_FILE) down -v && \
		rm -rf data/* && \
		echo "$(GREEN)[SUCCESS]$(NC) 已删除所有容器和数据" || \
		echo "$(BLUE)[INFO]$(NC) 操作已取消"

# 查看服务状态
status:
	@echo "$(BLUE)[INFO]$(NC) 服务状态:"
	@echo ""
	@docker compose -f $(COMPOSE_FILE) ps
	@echo ""

# 查看所有日志
logs:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=100

# 查看 Dragonfly 日志
logs-dragonfly:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=100 dragonfly

# 查看 Kafka 日志
logs-kafka:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=100 kafka zookeeper

# 查看 ScyllaDB 日志
logs-scylla:
	docker compose -f $(COMPOSE_FILE) logs -f --tail=100 scylla

# 健康检查
health:
	@./scripts/health-check.sh

# 备份数据
backup:
	@echo "$(BLUE)[INFO]$(NC) 备份数据..."
	@mkdir -p backups
	@BACKUP_DIR="backups/backup_$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p "$$BACKUP_DIR"; \
	echo "备份 Dragonfly..."; \
	docker exec dragonfly redis-cli BGSAVE 2>/dev/null || true; \
	sleep 2; \
	cp -r data/dragonfly "$$BACKUP_DIR/" 2>/dev/null || true; \
	echo "备份 ScyllaDB..."; \
	docker exec scylla nodetool snapshot -t backup_$$(date +%Y%m%d) 2>/dev/null || true; \
	cp -r data/scylla "$$BACKUP_DIR/" 2>/dev/null || true; \
	echo "$(GREEN)[SUCCESS]$(NC) 备份完成: $$BACKUP_DIR"

# 清理日志
clean-logs:
	@echo "$(BLUE)[INFO]$(NC) 清理日志文件..."
	@rm -rf logs/*
	@echo "$(GREEN)[SUCCESS]$(NC) 日志已清理"

# 拉取最新镜像
pull:
	@echo "$(BLUE)[INFO]$(NC) 拉取最新镜像..."
	docker compose -f $(COMPOSE_FILE) pull

# 验证配置
validate:
	@echo "$(BLUE)[INFO]$(NC) 验证配置文件..."
	docker compose -f $(COMPOSE_FILE) config --quiet && \
		echo "$(GREEN)[SUCCESS]$(NC) 配置文件有效" || \
		echo "$(RED)[ERROR]$(NC) 配置文件有误"

# 显示资源使用
resources:
	@echo "$(BLUE)[INFO]$(NC) 资源使用情况:"
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

