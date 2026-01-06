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
- [升级指南](#升级指南)
- [安全建议](#安全建议)

## 概述

Biya Indexer 是一个区块链索引服务，用于索引和查询链上数据。系统包含以下核心组件：

| 组件 | 说明 |
|------|------|
| **indexer-client** | 链上数据采集服务，从区块链节点获取数据并写入 Kafka |
| **indexer-consumer** | 数据消费服务，从 Kafka 消费数据并写入 ScyllaDB 和 Dragonfly |
| **indexer-grpc-server** | gRPC 查询服务，对外提供数据查询接口 |
| **ScyllaDB** | 高性能分布式数据库（Cassandra 兼容） |
| **Kafka** | 消息队列，用于事件流处理 |
| **Dragonfly** | 高性能缓存（Redis 兼容） |

### 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                       Biya Indexer Stack                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                               │
│  │  Blockchain │                                               │
│  │    Node     │                                               │
│  └──────┬──────┘                                               │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────────┐                                           │
│  │ indexer-client  │───▶┌─────────────┐                       │
│  │  (数据采集)      │    │    Kafka    │                       │
│  └─────────────────┘    │  (Events)   │                       │
│                         └──────┬──────┘                       │
│                                │                               │
│                                ▼                               │
│                         ┌─────────────────┐                    │
│                         │ indexer-consumer│                    │
│                         │  (数据消费)      │                    │
│                         └──────┬──────────┘                    │
│                                │                                │
│                    ┌───────────┴───────────┐                   │
│                    ▼                       ▼                   │
│            ┌─────────────┐         ┌─────────────┐            │
│            │  ScyllaDB   │         │  Dragonfly  │            │
│            │  (Storage)  │         │  (Cache)    │            │
│            └──────┬──────┘         └──────┬──────┘            │
│                   │                       │                    │
│                   └───────────┬───────────┘                    │
│                               ▼                                │
│                      ┌─────────────────┐                       │
│                      │indexer-grpc-server│                     │
│                      │  (查询服务)       │                      │
│                      └─────────┬───────┘                       │
│                                │                                │
│                                ▼                                │
│                         ┌─────────────┐                        │
│                         │   Clients   │                        │
│                         └─────────────┘                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 数据流向

1. **indexer-client**: 从区块链节点（gRPC）获取区块和交易数据，写入 Kafka
2. **indexer-consumer**: 从 Kafka 消费数据，处理后写入 ScyllaDB（持久化）和 Dragonfly（缓存）
3. **indexer-grpc-server**: 从 ScyllaDB 和 Dragonfly 读取数据，对外提供 gRPC 查询服务

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
| 50052 | indexer-grpc-server | gRPC 服务端口 |
| 50053 | indexer-grpc-server | gRPC-Web 服务端口 |
| 6379 | Dragonfly | Redis 协议 |
| 9042 | ScyllaDB | CQL 协议 |
| 9092 | Kafka | Kafka Broker |
| 2181 | Zookeeper | Zookeeper 客户端 |
| 8080 | Kafka UI | Web 管理界面（可选） |
| 9180 | ScyllaDB | Prometheus 指标 |

## 快速开始

### 方式一：一键部署（推荐）✨

这是最简单快捷的部署方式，会自动完成从源码编译到服务启动的全过程：

```bash
# 1. 克隆项目（包含子模块）
git clone --recursive https://github.com/biya-coin/biya-indexer-deploy.git
cd biya-indexer-deploy

# 2. 初始化环境（可选，会自动创建 .env 文件）
make init

# 3. 配置环境变量（编辑 .env 文件，设置区块链节点地址等）
vim .env

# 4. 一键部署（构建镜像 + 启动服务）
make deploy
```

**一键部署流程**：
1. 自动初始化 Git 子模块（如果未初始化）
2. 从源码编译构建三个索引服务镜像
3. 启动所有服务（中间件 + 索引服务）

> 💡 **提示**: 运行 `make help` 可以查看所有可用的命令。

### 方式二：分步部署

如果需要分步执行，可以使用以下命令：

```bash
# 1. 克隆项目
git clone --recursive https://github.com/biya-coin/biya-indexer-deploy.git
cd biya-indexer-deploy

# 2. 初始化环境
make init

# 3. 配置环境变量
vim .env

# 4. 构建索引服务镜像（从源码编译）
make build-images

# 5. 启动所有服务
make start
```

### 配置环境变量

编辑 `.env` 文件，配置必要的环境变量：

```bash
# 复制环境变量模板
cp env.example .env

# 编辑配置文件
vim .env
```

**重要配置项**：
- `INDEXER_CHAIN_GRPC_STREAM`: 区块链 gRPC Stream 地址（必需）
- `INDEXER_CHAIN_GRPC_QUERY`: 区块链 gRPC Query 地址（必需）
- `INDEXER_CHAIN_RPC`: 区块链 Tendermint RPC 地址（必需）

**代理配置（可选）**：如果需要在构建时使用代理，在 `.env` 文件中添加：

```bash
HTTP_PROXY=http://proxy.example.com:8080
HTTPS_PROXY=http://proxy.example.com:8080
NO_PROXY=localhost,127.0.0.1,.local
```

构建脚本会自动读取并使用这些代理配置。

### 验证部署

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

# 验证 indexer-client 日志
docker logs indexer-client --tail=50

# 验证 indexer-consumer 日志
docker logs indexer-consumer --tail=50

# 验证 indexer-grpc-server 日志
docker logs indexer-grpc-server --tail=50

# 或使用 Makefile 命令（推荐）
make status          # 查看服务状态
make health          # 执行健康检查
```

> 💡 **提示**: 所有服务启动后，建议等待 1-2 分钟让服务完全初始化，然后再执行健康检查。

> 💡 **提示**: 所有服务启动后，建议等待 1-2 分钟让服务完全初始化，然后再执行健康检查。

## 构建镜像

### 使用 Makefile 命令（推荐）

最简单的方式是使用 Makefile 命令：

```bash
# 构建所有索引服务镜像
make build-images
```

这个命令会：
1. 自动检查并初始化 Git 子模块
2. 从 `.env` 文件读取代理配置（如果配置了）
3. 依次构建三个镜像：
   - `indexer-client:latest` - 从 `Dockerfile.grpc.client` 构建
   - `indexer-consumer:latest` - 从 `Dockerfile.consumer` 构建
   - `indexer-server:latest` - 从 `Dockerfile.grpc.server` 构建

### 手动构建

如果需要手动构建单个镜像：

```bash
# 构建 indexer-client 镜像
docker build -f biya-indexer-rs/Dockerfile.grpc.client \
  -t indexer-client:latest \
  biya-indexer-rs/

# 构建 indexer-consumer 镜像
docker build -f biya-indexer-rs/Dockerfile.consumer \
  -t indexer-consumer:latest \
  biya-indexer-rs/

# 构建 indexer-server 镜像
docker build -f biya-indexer-rs/Dockerfile.grpc.server \
  -t indexer-server:latest \
  biya-indexer-rs/
```

### 使用代理构建

如果配置了代理，构建脚本会自动使用。也可以手动传递代理参数：

```bash
docker build \
  --build-arg HTTP_PROXY=http://proxy.example.com:8080 \
  --build-arg HTTPS_PROXY=http://proxy.example.com:8080 \
  --build-arg NO_PROXY=localhost,127.0.0.1,.local \
  -f biya-indexer-rs/Dockerfile.grpc.server \
  -t indexer-server:latest \
  biya-indexer-rs/
```

### 构建时间

首次构建可能需要较长时间（10-30 分钟），因为需要：
- 下载 Rust 工具链
- 编译 Rust 依赖项
- 构建项目二进制文件

后续构建会利用 Docker 缓存，速度会快很多。

## 组件说明

### Indexer 服务

#### indexer-client

从区块链节点获取数据并写入 Kafka 的服务。

**功能**:
- 连接区块链节点的 gRPC Stream 和 Query 接口
- 获取区块和交易数据
- 将数据序列化后写入 Kafka

**环境变量**:
- `GRPC_STREAM_ENDPOINT`: 区块链 gRPC Stream 地址
- `GRPC_QUERY_ENDPOINT`: 区块链 gRPC Query 地址
- `KAFKA_BROKERS`: Kafka Broker 地址
- `KAFKA_TOPIC`: Kafka Topic 名称
- `KAFKA_CLIENT_ID`: Kafka Client ID

#### indexer-consumer

从 Kafka 消费数据并写入存储层的服务。

**功能**:
- 从 Kafka 消费事件数据
- 处理数据并写入 ScyllaDB（持久化存储）
- 写入 Dragonfly（缓存层）

**依赖关系**:
- 等待 `kafka` 服务健康
- 等待 `dragonfly` 服务健康
- 等待 `scylla-init` 服务完成（确保 ScyllaDB 完全就绪）

**环境变量**:
- `KAFKA_BROKERS`: Kafka Broker 地址
- `KAFKA_TOPIC`: Kafka Topic 名称
- `KAFKA_CONSUMER_GROUP`: Consumer Group 名称
- `REDIS_URL`: Dragonfly/Redis 连接地址
- `SCYLLADB_NODES`: ScyllaDB 节点地址

#### indexer-grpc-server

对外提供 gRPC 查询服务的服务。

**功能**:
- 提供 gRPC 和 gRPC-Web 接口
- 从 ScyllaDB 和 Dragonfly 查询数据
- 支持区块链数据查询

**环境变量**:
- `GRPC_LISTEN_ADDR`: gRPC 监听地址
- `GRPC_WEB_LISTEN_ADDR`: gRPC-Web 监听地址
- `REDIS_URL`: Dragonfly/Redis 连接地址
- `SCYLLA_NODES`: ScyllaDB 节点地址
- `CHAIN_GRPC_ENDPOINT`: 区块链 gRPC 端点（用于链上查询）
- `TENDERMINT_RPC_ENDPOINT`: Tendermint RPC 端点

**服务端点**:
- gRPC: `localhost:50052`
- gRPC-Web: `localhost:50053`

> 💡 **注意**: 服务启动时会自动重试连接 ScyllaDB（最多 10 次），如果 `scylla-init` 正常完成，通常第一次或前几次就能成功连接。

### ScyllaDB

ScyllaDB 是高性能的 NoSQL 数据库，兼容 Apache Cassandra。

**配置文件位置**: `deploy/scylladb/`

```bash
# 检查 ScyllaDB 状态
docker exec scylla nodetool status
# 期望看到 UN (Up Normal) 状态

# 连接到 CQL Shell
docker exec -it scylla cqlsh

# 查看 Keyspaces
docker exec scylla cqlsh -e "DESCRIBE KEYSPACES"

# 查看初始化服务日志
docker logs scylla-init
```

**初始化流程**:
1. ScyllaDB 容器启动并等待健康检查通过
2. `scylla-init` 服务等待 ScyllaDB 健康后执行初始化脚本
3. 初始化脚本确保 CQL 端口（9042）可用
4. `indexer-consumer` 和 `indexer-grpc-server` 等待 `scylla-init` 完成后启动

> 💡 **注意**: 如果遇到数据文件版本不兼容问题，需要清理数据目录：`sudo rm -rf ./data/scylla/data/*`

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
SCYLLA_VERSION=5.2                 # ScyllaDB 版本（固定为 5.2，与 biya-indexer-rs 保持一致）
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

# ===== Indexer 服务配置 =====
INDEXER_VERSION=latest                    # Indexer 服务镜像版本
KAFKA_TOPIC=biya-events                   # Kafka Topic 名称
KAFKA_CLIENT_ID=biya-indexer-client       # Kafka Client ID
KAFKA_CONSUMER_GROUP=biya-consumers       # Kafka Consumer Group
INDEXER_GRPC_PORT=50052                   # gRPC 服务端口
INDEXER_GRPC_WEB_PORT=50053               # gRPC-Web 服务端口
FEE_PAYER_ADDRESS=                        # 费用支付地址（可选）
FEE_PAYER_PRIVATE_KEY=                    # 费用支付私钥（可选）

# ===== 区块链节点连接 =====
INDEXER_CHAIN_RPC=http://localhost:26657          # 区块链 RPC 地址（Tendermint）
INDEXER_CHAIN_GRPC=http://localhost:9900          # 区块链 gRPC Query 地址
INDEXER_CHAIN_GRPC_STREAM=http://localhost:9999   # 区块链 gRPC Stream 地址
INDEXER_CHAIN_GRPC_QUERY=http://localhost:9900    # 区块链 gRPC Query 地址
HOST_LAN_IP=host.docker.internal          # 主机 IP（用于访问宿主机上的区块链节点）

# ===== 数据库连接 =====
SCYLLA_HOSTS=scylla:9042           # ScyllaDB 连接地址
KAFKA_BROKERS=kafka:29092          # Kafka Broker 地址
REDIS_URL=dragonfly:6379           # Redis/Dragonfly 连接地址

# ===== 代理配置（可选）=====
# 如果需要在容器构建时使用代理（如 Cargo 更新 crates.io 索引）
# 配置后，构建脚本会自动读取并使用这些代理配置
# HTTP_PROXY=http://proxy.example.com:8080
# HTTPS_PROXY=http://proxy.example.com:8080
# NO_PROXY=localhost,127.0.0.1,.local
```

### 目录结构

```
biya-indexer-deploy/
├── README.md                          # 本文档
├── Makefile                           # Makefile 命令定义
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
├── biya-indexer-rs/                   # 核心索引服务项目（Git 子模块）
│   ├── Dockerfile.grpc.client         # indexer-client 构建文件
│   ├── Dockerfile.consumer            # indexer-consumer 构建文件
│   ├── Dockerfile.grpc.server         # indexer-grpc-server 构建文件
│   ├── indexer-grpc-server/           # gRPC 服务器源码
│   ├── injective-consumer/            # Consumer 源码
│   └── grpc/                          # gRPC Client 源码
└── scripts/                           # 运维脚本
    ├── build-images.sh                # 构建镜像脚本
    ├── start.sh                       # 启动脚本
    └── health-check.sh                # 健康检查脚本
```

## 运维操作

### 使用 Makefile 命令（推荐）

项目提供了便捷的 Makefile 命令，简化日常运维操作：

```bash
# 查看所有可用命令
make help

# ===== 初始化 =====
make init                    # 初始化环境（创建目录和配置文件）

# ===== 构建和部署 =====
make build-images            # 构建所有索引服务镜像（从源码编译）
make deploy                  # 一键部署（构建镜像 + 启动服务）

# ===== 服务管理 =====
make start                   # 启动所有服务
make start-ui                # 启动所有服务（包含 Kafka UI）
make stop                    # 停止所有服务
make restart                 # 重启所有服务
make down                    # 停止并删除容器
make destroy                 # 停止并删除容器和数据（危险！）

# ===== 中间件单独管理 =====
make start-dragonfly         # 启动 Dragonfly
make start-kafka             # 启动 Kafka + Zookeeper
make start-scylla            # 启动 ScyllaDB

# ===== 监控和日志 =====
make status                  # 查看服务状态
make logs                    # 查看所有日志
make logs-dragonfly          # 查看 Dragonfly 日志
make logs-kafka              # 查看 Kafka 日志
make logs-scylla             # 查看 ScyllaDB 日志
make health                  # 执行健康检查

# ===== 数据管理 =====
make backup                  # 备份数据
make clean-logs              # 清理日志文件
```

### 使用 Docker Compose 命令

也可以直接使用 Docker Compose 命令：

```bash
# ===== 启动服务 =====
# 启动所有服务
docker-compose -f docker-compose.all-in-one.yaml up -d

# 启动单个服务
docker-compose -f docker-compose.all-in-one.yaml up -d scylla

# 启动包含 Kafka UI 的服务
docker-compose -f docker-compose.all-in-one.yaml --profile ui up -d

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
docker-compose -f docker-compose.all-in-one.yaml logs -f indexer-client
docker-compose -f docker-compose.all-in-one.yaml logs -f indexer-consumer
docker-compose -f docker-compose.all-in-one.yaml logs -f indexer-grpc-server
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
# 期望看到 UN (Up Normal) 状态

# 检查 ScyllaDB 健康状态
docker compose -f docker-compose.all-in-one.yaml ps scylla
# 应该显示 (healthy)

# 检查初始化服务状态
docker compose -f docker-compose.all-in-one.yaml ps scylla-init
# 应该显示 Exited (0) 表示成功完成

# 检查网络连通性
docker exec scylla cqlsh -e "DESCRIBE KEYSPACES"

# 查看 ScyllaDB 日志
docker logs scylla --tail=100

# 查看初始化服务日志
docker logs scylla-init

# 如果遇到数据文件版本不兼容错误，清理数据目录
docker compose -f docker-compose.all-in-one.yaml stop scylla scylla-init
sudo rm -rf ./data/scylla/data/*
docker compose -f docker-compose.all-in-one.yaml up -d scylla
```

**常见问题**:
- **数据文件版本不兼容**: 如果 ScyllaDB 启动失败并提示 "invalid version for file"，需要清理数据目录
- **初始化服务未完成**: 确保 `scylla-init` 服务成功完成（Exit 0）后再启动索引服务
- **连接被拒绝**: 检查 ScyllaDB 是否健康，以及 `scylla-init` 是否已完成

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

#### 5. Indexer 服务问题

```bash
# 检查 indexer-client 状态
docker logs indexer-client --tail=100

# 检查 indexer-consumer 状态
docker logs indexer-consumer --tail=100
# 如果看到 "Connection refused" 错误，检查 ScyllaDB 和 scylla-init 状态

# 检查 indexer-grpc-server 状态
docker logs indexer-grpc-server --tail=100
# 如果看到 "Failed to connect to Scylla" 错误，检查：
# 1. ScyllaDB 是否健康: docker compose ps scylla
# 2. scylla-init 是否完成: docker compose ps scylla-init
# 3. 服务会自动重试连接（最多 10 次），等待一段时间后查看是否成功

# 测试 gRPC 服务（需要 grpcurl 工具）
grpcurl -plaintext localhost:50052 list

# 检查 Kafka Topic 中的数据
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic biya-events \
  --from-beginning \
  --max-messages 10
```

**常见问题**:
- **indexer-consumer 连接 ScyllaDB 失败**: 确保 `scylla-init` 服务已完成，ScyllaDB 健康
- **indexer-grpc-server 连接 ScyllaDB 失败**: 服务会自动重试，如果持续失败，检查 ScyllaDB 状态和初始化服务
- **服务启动顺序问题**: 使用 `docker compose ps` 检查所有服务的依赖关系是否正确

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

使用 Makefile 命令执行健康检查：

```bash
make health
```

健康检查脚本会自动检查以下服务：
- Dragonfly (Redis 缓存)
- ScyllaDB (数据库)
- Kafka (消息队列)
- Zookeeper (协调服务)

**服务依赖检查**:
- 确保 `scylla-init` 服务已完成（Exit 0）
- 确保所有索引服务正常连接各自的依赖服务

也可以手动执行健康检查脚本：

```bash
./scripts/health-check.sh
```

### 推荐监控方案

1. **Prometheus + Grafana**: 收集和可视化指标
2. **AlertManager**: 告警管理
3. **Loki**: 日志聚合

## 升级指南

### 升级流程（使用源码构建）

如果使用源码构建的镜像，升级流程如下：

1. **备份数据**
   ```bash
   make backup
   ```

2. **更新代码**
   ```bash
   # 更新主项目
   git pull
   
   # 更新子模块
   git submodule update --remote
   ```

3. **停止服务**
   ```bash
   make stop
   ```

4. **重新构建镜像**
   ```bash
   make build-images
   ```

5. **启动服务**
   ```bash
   make start
   ```

6. **验证升级**
   ```bash
   make health
   ```

### 升级流程（使用预构建镜像）

如果使用预构建的镜像（从镜像仓库拉取）：

1. **备份数据**
   ```bash
   make backup
   ```

2. **拉取新版本镜像**
   ```bash
   make pull
   # 或
   docker-compose -f docker-compose.all-in-one.yaml pull
   ```

3. **更新环境变量**
   ```bash
   # 更新 .env 中的版本号
   vim .env
   ```

4. **停止服务**
   ```bash
   make stop
   ```

5. **启动服务**
   ```bash
   make start
   ```

6. **验证升级**
   ```bash
   make health
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
