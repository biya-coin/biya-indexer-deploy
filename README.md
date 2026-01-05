# Biya Indexer 部署指南

本文档提供 Biya Indexer 的完整部署指南，包括单节点（All-in-One）部署模式。

## 📋 目录

- [概述](#概述)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [组件说明](#组件说明)
- [配置详解](#配置详解)
- [运维操作](#运维操作)
- [故障排查](#故障排查)
- [监控与告警](#监控与告警)

## 概述

Biya Indexer 是一个区块链索引服务，用于索引和查询链上数据。系统包含以下核心组件：

| 组件 | 说明 |
|------|------|
| **biya-indexer-rs** | 核心索引服务（Rust 实现） |
| **ScyllaDB** | 高性能分布式数据库（Cassandra 兼容） |
| **Kafka** | 消息队列，用于事件流处理 |
| **Dragonfly** | 高性能缓存（Redis 兼容） |

### 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                       Biya Indexer Stack                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Blockchain │───▶│  Indexer    │───▶│  ScyllaDB   │         │
│  │    Node     │    │  (Rust)     │    │  (Storage)  │         │
│  └─────────────┘    └──────┬──────┘    └─────────────┘         │
│                            │                                    │
│                            ▼                                    │
│                     ┌─────────────┐                             │
│                     │    Kafka    │                             │
│                     │  (Events)   │                             │
│                     └──────┬──────┘                             │
│                            │                                    │
│                            ▼                                    │
│                     ┌─────────────┐                             │
│                     │  Dragonfly  │                             │
│                     │  (Cache)    │                             │
│                     └─────────────┘                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 系统要求

### 硬件要求

| 配置项 | 最低要求 | 推荐配置 |
|--------|----------|----------|
| CPU | 4 核 | 8 核+ |
| 内存 | 16 GB | 32 GB+ |
| 存储 | 500 GB SSD | 1 TB+ NVMe SSD |
| 网络 | 1 Gbps | 5 Gbps+ |

### 软件要求

| 软件 | 版本要求 |
|------|----------|
| Docker Engine | 20.10+ |
| Docker Compose | 2.0+ |
| Git | 2.0+ |

### 端口要求

确保以下端口可用：

| 端口 | 服务 | 用途 |
|------|------|------|
| 6379 | Dragonfly | Redis 协议 |
| 9042 | ScyllaDB | CQL 协议 |
| 9092 | Kafka | Kafka Broker |
| 2181 | Zookeeper | Zookeeper 客户端 |
| 8080 | Kafka UI | Web 管理界面（可选） |
| 9180 | ScyllaDB | Prometheus 指标 |

## 快速开始

### 1. 克隆项目

```bash
git clone --recursive https://github.com/biya-coin/biya-indexer-deploy.git
cd biya-indexer-deploy
```

### 2. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件
vim .env
```

### 3. 启动中间件服务

```bash
# 使用 All-in-One 配置启动所有服务
docker-compose -f docker-compose.all-in-one.yaml up -d
```

### 4. 验证部署

```bash
# 检查所有服务状态
docker-compose -f docker-compose.all-in-one.yaml ps

# 验证 Dragonfly (Redis)
redis-cli -h localhost -p 6379 ping
# 期望输出: PONG

# 验证 ScyllaDB
docker exec scylla nodetool status
# 期望看到 UN (Up Normal) 状态

# 验证 Kafka
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
```

## 组件说明

### ScyllaDB

ScyllaDB 是高性能的 NoSQL 数据库，兼容 Apache Cassandra。

**配置文件位置**: `deploy/scylladb/`

```bash
# 启动 ScyllaDB（单节点）
docker-compose -f deploy/scylladb/docker-compose.scylladb.yaml up -d

# 连接到 CQL Shell
docker exec -it scylla cqlsh

# 检查状态
docker exec scylla nodetool status
```

**主要配置参数**:
- `--smp 2`: CPU 核心数
- `--memory 2G`: 内存限制
- `--developer-mode 1`: 开发模式（生产环境设为 0）

详细文档: [ScyllaDB 部署指南](deploy/scylladb/README.md)

### Kafka

Kafka 用于处理区块链事件流。

**配置文件位置**: `deploy/kafka/`

```bash
# 启动 Kafka（单节点）
docker-compose -f deploy/kafka/docker-compose.kafka.yaml up -d

# 启动带 UI 的 Kafka
docker-compose -f deploy/kafka/docker-compose.kafka.yaml --profile ui up -d

# 创建 Topic
docker exec kafka kafka-topics --create \
  --bootstrap-server localhost:9092 \
  --topic biya-events \
  --partitions 3 \
  --replication-factor 1
```

**服务端点**:
- Kafka Broker: `localhost:9092`
- Zookeeper: `localhost:2181`
- Kafka UI: `http://localhost:8080`（可选）

详细文档: [Kafka 部署指南](deploy/kafka/README.md)

### Dragonfly

Dragonfly 是高性能的 Redis 替代品，用于缓存。

**配置文件位置**: `deploy/dragonfly/`

```bash
# 启动 Dragonfly（单节点）
docker-compose -f deploy/dragonfly/docker-compose.dragonfly.yaml up -d

# 测试连接
redis-cli -h localhost -p 6379 ping
```

**主要配置参数**:
- `--maxmemory 2gb`: 最大内存
- `--cache_mode=true`: 启用缓存模式
- `--proactor_threads 4`: 工作线程数

详细文档: [Dragonfly 部署指南](deploy/dragonfly/README.md)

## 配置详解

### 环境变量说明

```bash
# ===== 网络配置 =====
NETWORK=mainnet                    # 网络类型: mainnet / testnet
CHAIN_ID=biya-1                    # 链 ID

# ===== 服务版本 =====
INDEXER_VERSION=latest             # Indexer 版本
SCYLLA_VERSION=latest              # ScyllaDB 版本
KAFKA_VERSION=7.5.0                # Kafka 版本
DRAGONFLY_VERSION=latest           # Dragonfly 版本

# ===== 资源限制 =====
SCYLLA_MEMORY=2G                   # ScyllaDB 内存限制
DRAGONFLY_MEMORY=2gb               # Dragonfly 内存限制
KAFKA_MEMORY_LIMIT=4G              # Kafka 内存限制

# ===== 数据路径 =====
DATA_PATH=./data                   # 数据存储根目录
SCYLLA_DATA_PATH=./data/scylla     # ScyllaDB 数据路径
DRAGONFLY_DATA_PATH=./data/dragonfly # Dragonfly 数据路径

# ===== 日志配置 =====
LOG_LEVEL=info                     # 日志级别: debug/info/warn/error

# ===== 链接配置 =====
INDEXER_CHAIN_RPC=http://localhost:26657  # 区块链 RPC 地址
INDEXER_CHAIN_GRPC=tcp://localhost:9090   # 区块链 gRPC 地址

# ===== 数据库连接 =====
SCYLLA_HOSTS=scylla:9042           # ScyllaDB 连接地址
KAFKA_BROKERS=kafka:29092          # Kafka Broker 地址
REDIS_URL=dragonfly:6379           # Redis/Dragonfly 连接地址
```

### 目录结构

```
biya-indexer-deploy/
├── README.md                          # 本文档
├── .env.example                       # 环境变量模板
├── docker-compose.all-in-one.yaml     # All-in-One 部署配置
├── deploy/                            # 中间件部署配置
│   ├── dragonfly/                     # Dragonfly 配置
│   │   ├── docker-compose.dragonfly.yaml
│   │   ├── docker-compose.dragonfly.cluster.yaml
│   │   └── README.md
│   ├── kafka/                         # Kafka 配置
│   │   ├── docker-compose.kafka.yaml
│   │   ├── docker-compose.kafka-cluster.yaml
│   │   └── README.md
│   └── scylladb/                      # ScyllaDB 配置
│       ├── docker-compose.scylladb.yaml
│       ├── docker-compose.scylladb.cluster.yaml
│       └── README.md
├── biya-indexer-rs/                   # 核心索引服务项目
└── scripts/                           # 运维脚本
    ├── start.sh                       # 启动脚本
    ├── stop.sh                        # 停止脚本
    └── health-check.sh                # 健康检查脚本
```

## 运维操作

### 服务管理

```bash
# ===== 启动服务 =====
# 启动所有服务
docker-compose -f docker-compose.all-in-one.yaml up -d

# 启动单个服务
docker-compose -f docker-compose.all-in-one.yaml up -d scylla

# ===== 停止服务 =====
# 停止所有服务
docker-compose -f docker-compose.all-in-one.yaml stop

# 停止并删除容器
docker-compose -f docker-compose.all-in-one.yaml down

# 停止并删除数据卷（危险操作！）
docker-compose -f docker-compose.all-in-one.yaml down -v

# ===== 重启服务 =====
docker-compose -f docker-compose.all-in-one.yaml restart

# ===== 查看日志 =====
# 查看所有日志
docker-compose -f docker-compose.all-in-one.yaml logs -f

# 查看特定服务日志
docker-compose -f docker-compose.all-in-one.yaml logs -f scylla
docker-compose -f docker-compose.all-in-one.yaml logs -f kafka
docker-compose -f docker-compose.all-in-one.yaml logs -f dragonfly
```

### 数据备份

```bash
# ===== ScyllaDB 备份 =====
# 创建快照
docker exec scylla nodetool snapshot -t backup_$(date +%Y%m%d)

# 备份数据目录
cp -r ./data/scylla ./backup/scylla_$(date +%Y%m%d)

# ===== Dragonfly 备份 =====
# 触发 RDB 保存
redis-cli -h localhost -p 6379 BGSAVE

# 备份 RDB 文件
cp ./data/dragonfly/dump.rdb ./backup/dragonfly_$(date +%Y%m%d).rdb

# ===== Kafka 备份 =====
# 备份 Kafka 数据目录
cp -r ./data/kafka ./backup/kafka_$(date +%Y%m%d)
```

### 数据恢复

```bash
# ===== ScyllaDB 恢复 =====
# 停止服务
docker-compose -f docker-compose.all-in-one.yaml stop scylla

# 恢复数据
cp -r ./backup/scylla_YYYYMMDD/* ./data/scylla/

# 重启服务
docker-compose -f docker-compose.all-in-one.yaml start scylla

# ===== Dragonfly 恢复 =====
# 停止服务
docker-compose -f docker-compose.all-in-one.yaml stop dragonfly

# 恢复 RDB 文件
cp ./backup/dragonfly_YYYYMMDD.rdb ./data/dragonfly/dump.rdb

# 重启服务
docker-compose -f docker-compose.all-in-one.yaml start dragonfly
```

## 故障排查

### 常见问题

#### 1. 服务无法启动

```bash
# 检查 Docker 状态
docker info

# 检查端口占用
netstat -tuln | grep -E '6379|9042|9092|2181'
# 或
ss -tuln | grep -E '6379|9042|9092|2181'

# 检查磁盘空间
df -h

# 查看详细错误日志
docker-compose -f docker-compose.all-in-one.yaml logs --tail=100
```

#### 2. ScyllaDB 连接失败

```bash
# 检查 ScyllaDB 状态
docker exec scylla nodetool status

# 检查网络连通性
docker exec scylla cqlsh -e "DESCRIBE KEYSPACES"

# 查看 ScyllaDB 日志
docker logs scylla --tail=100
```

#### 3. Kafka 连接问题

```bash
# 检查 Zookeeper 状态
docker exec zookeeper zkServer.sh status

# 检查 Kafka Broker
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092

# 列出所有 Topic
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
```

#### 4. Dragonfly/Redis 连接问题

```bash
# 测试连接
redis-cli -h localhost -p 6379 ping

# 查看信息
redis-cli -h localhost -p 6379 INFO

# 检查内存使用
redis-cli -h localhost -p 6379 INFO memory
```

### 日志分析

```bash
# 实时监控所有服务日志
docker-compose -f docker-compose.all-in-one.yaml logs -f --tail=100

# 搜索错误日志
docker-compose -f docker-compose.all-in-one.yaml logs 2>&1 | grep -i error

# 导出日志到文件
docker-compose -f docker-compose.all-in-one.yaml logs > logs_$(date +%Y%m%d_%H%M%S).txt
```

## 监控与告警

### Prometheus 指标

各服务暴露的 Prometheus 指标端点：

| 服务 | 指标端点 | 说明 |
|------|----------|------|
| ScyllaDB | `:9180/metrics` | 数据库指标 |
| Kafka | 需要配置 JMX Exporter | Broker 指标 |
| Dragonfly | 使用 Redis INFO 命令 | 缓存指标 |

### 健康检查

```bash
# 创建健康检查脚本
cat > scripts/health-check.sh << 'EOF'
#!/bin/bash

echo "=== Biya Indexer Health Check ==="

# 检查 Dragonfly
echo -n "Dragonfly: "
if redis-cli -h localhost -p 6379 ping > /dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

# 检查 ScyllaDB
echo -n "ScyllaDB: "
if docker exec scylla nodetool status 2>/dev/null | grep -q "^UN"; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

# 检查 Kafka
echo -n "Kafka: "
if docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

echo "================================"
EOF

chmod +x scripts/health-check.sh
```

### 推荐监控方案

1. **Prometheus + Grafana**: 收集和可视化指标
2. **AlertManager**: 告警管理
3. **Loki**: 日志聚合

## 升级指南

### 升级流程

1. **备份数据**
   ```bash
   ./scripts/backup.sh
   ```

2. **拉取新版本镜像**
   ```bash
   docker-compose -f docker-compose.all-in-one.yaml pull
   ```

3. **停止服务**
   ```bash
   docker-compose -f docker-compose.all-in-one.yaml stop
   ```

4. **更新环境变量**
   ```bash
   # 更新 .env 中的版本号
   vim .env
   ```

5. **启动服务**
   ```bash
   docker-compose -f docker-compose.all-in-one.yaml up -d
   ```

6. **验证升级**
   ```bash
   ./scripts/health-check.sh
   ```

## 安全建议

### 生产环境配置

1. **网络安全**
   - 使用防火墙限制端口访问
   - 配置 TLS/SSL 加密
   - 限制容器网络访问范围

2. **认证授权**
   - 为 ScyllaDB 配置认证
   - 为 Dragonfly 设置密码 (`--requirepass`)
   - 配置 Kafka SASL 认证

3. **数据安全**
   - 定期备份数据
   - 配置数据加密
   - 设置适当的文件权限

4. **资源限制**
   - 配置容器资源限制
   - 监控资源使用情况
   - 设置 ulimits

## 参考资料

- [ScyllaDB 官方文档](https://docs.scylladb.com/)
- [Kafka 官方文档](https://kafka.apache.org/documentation/)
- [Dragonfly 官方文档](https://www.dragonflydb.io/docs)
- [Docker Compose 文档](https://docs.docker.com/compose/)

## 社区支持

- GitHub Issues: 提交问题和功能请求
- 技术交流群: 加入社区讨论

---

**提示**: 在生产环境部署前，请仔细阅读各组件的官方文档，并根据实际需求调整配置参数。
