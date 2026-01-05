# Dragonfly 部署指南

本目录包含了 Dragonfly 的单节点和集群部署配置文件。

## 文件说明

- `docker-compose.dragonfly.yaml` - 单节点 Docker Compose 部署配置
- `docker-compose.dragonfly.cluster.yaml` - 集群 Docker Swarm 部署配置（主从复制模式）

## 单节点部署

### 使用 Docker Compose

```bash
# 启动服务
docker-compose -f docker-compose.dragonfly.yaml up -d

# 查看日志
docker-compose -f docker-compose.dragonfly.yaml logs -f

# 停止服务
docker-compose -f docker-compose.dragonfly.yaml down

# 停止服务并删除数据卷
docker-compose -f docker-compose.dragonfly.yaml down -v
```

### 配置说明

- **端口**: 6379 (Redis 协议), 6380 (管理端口)
- **内存限制**: 2GB (可通过 `--maxmemory` 参数调整)
- **数据持久化**: 
  - 已启用 RDB 快照持久化
  - 数据存储在 `./data/dragonfly` 目录
  - RDB 文件名: `dump.rdb`
  - 自动保存策略:
    - 900 秒内至少 1 个键变化时保存
    - 300 秒内至少 10 个键变化时保存
    - 60 秒内至少 10000 个键变化时保存
- **日志**: 日志存储在 `./dragonfly-logs` 目录

### 环境变量

可以通过环境变量 `DRAGONFLY_DATA_PATH` 自定义数据存储路径：

```bash
export DRAGONFLY_DATA_PATH=/path/to/data
docker-compose -f docker-compose.dragonfly.yaml up -d
```

### 验证部署

```bash
# 使用 redis-cli 连接测试
redis-cli -h localhost -p 6379 ping
# 应该返回: PONG

# 查看服务状态
docker-compose -f docker-compose.dragonfly.yaml ps

# 查看健康检查状态
docker-compose -f docker-compose.dragonfly.yaml ps --format "table {{.Name}}\t{{.Status}}"
```

## 集群部署（Docker Swarm）

### 前置条件

1. 初始化 Docker Swarm（如果尚未初始化）：
```bash
docker swarm init
```

2. 为节点添加标签（用于服务放置约束）：
```bash
# 在 manager 节点上执行
# 为 3 个主机节点添加标签
docker node update --label-add dragonfly.host=1 <node-id-1>
docker node update --label-add dragonfly.host=2 <node-id-2>
docker node update --label-add dragonfly.host=3 <node-id-3>
```

查看节点 ID：
```bash
docker node ls
```

### 使用 Docker Stack 部署

```bash
# 部署服务栈
docker stack deploy -c docker-compose.dragonfly.cluster.yaml dragonfly

# 查看服务状态
docker stack services dragonfly

# 查看服务日志
docker service logs dragonfly_dragonfly-host1-master
docker service logs dragonfly_dragonfly-host1-replica
docker service logs dragonfly_dragonfly-host2-master
docker service logs dragonfly_dragonfly-host2-replica
docker service logs dragonfly_dragonfly-host3-master
docker service logs dragonfly_dragonfly-host3-replica

# 扩展服务（如果需要）
docker service scale dragonfly_dragonfly-node1=1

# 移除服务栈
docker stack rm dragonfly
```

### 集群配置说明

集群采用**一主一从模式**，共 3 个主机，每个主机上部署一个主节点和一个从节点：

**架构拓扑:**
```
Host 1: Master (6379) + Replica (6381)
Host 2: Master (6379) + Replica (6381)
Host 3: Master (6379) + Replica (6381)
```

**节点配置:**

- **Host 1**:
  - Master: `dragonfly-host1-master` - 端口: 6379 (Redis), 6380 (管理), 16379 (集群总线)
  - Replica: `dragonfly-host1-replica` - 端口: 6381 (Redis), 6382 (管理), 16381 (集群总线)
  - 数据存储: `./data/dragonfly-host1-master`, `./data/dragonfly-host1-replica`

- **Host 2**:
  - Master: `dragonfly-host2-master` - 端口: 6379 (Redis), 6380 (管理), 16379 (集群总线)
  - Replica: `dragonfly-host2-replica` - 端口: 6381 (Redis), 6382 (管理), 16381 (集群总线)
  - 数据存储: `./data/dragonfly-host2-master`, `./data/dragonfly-host2-replica`

- **Host 3**:
  - Master: `dragonfly-host3-master` - 端口: 6379 (Redis), 6380 (管理), 16379 (集群总线)
  - Replica: `dragonfly-host3-replica` - 端口: 6381 (Redis), 6382 (管理), 16381 (集群总线)
  - 数据存储: `./data/dragonfly-host3-master`, `./data/dragonfly-host3-replica`

**端口说明:**
- 所有主节点使用相同的端口映射：6379, 6380, 16379（因为部署在不同主机，不会冲突）
- 所有从节点使用相同的端口映射：6381, 6382, 16381（因为部署在不同主机，不会冲突）
- 每个主机上的主从节点使用不同端口，避免同一主机上的端口冲突

**集群配置:**
- 集群配置文件: `dragonfly-cluster.conf`（挂载到所有节点）
- 主节点启用集群模式: `--cluster-enabled yes`
- 从节点配置主从复制: `--replicaof <master-host> 6379`
- 集群总线端口: 16379（主节点），16381（从节点）

**优势:**
- 高可用性：每个主机都有主从备份
- 负载均衡：可以分散读写请求
- 故障隔离：单个主机故障不影响其他主机

### 环境变量

可以通过环境变量自定义配置：

```bash
# 数据存储路径
export DRAGONFLY_DATA_PATH=/path/to/data

# Dragonfly 镜像版本
export DRAGONFLY_VERSION=latest

# 集群主机 IP 地址（如果使用固定 IP 而不是服务名）
export DRAGONFLY_HOST1_IP=192.168.1.10
export DRAGONFLY_HOST2_IP=192.168.1.11
export DRAGONFLY_HOST3_IP=192.168.1.12

# 主节点服务名（可选，默认使用服务名）
export DRAGONFLY_HOST1_MASTER=dragonfly-host1-master
export DRAGONFLY_HOST2_MASTER=dragonfly-host2-master
export DRAGONFLY_HOST3_MASTER=dragonfly-host3-master

# 部署集群
docker stack deploy -c docker-compose.dragonfly.cluster.yaml dragonfly
```

**环境变量说明:**
- `DRAGONFLY_DATA_PATH`: 数据存储路径（默认: `./data`）
- `DRAGONFLY_VERSION`: Dragonfly 镜像版本（默认: `latest`）
- `DRAGONFLY_HOST1_IP`: Host 1 的集群通告IP（默认: `dragonfly-host1-master`）
- `DRAGONFLY_HOST2_IP`: Host 2 的集群通告IP（默认: `dragonfly-host2-master`）
- `DRAGONFLY_HOST3_IP`: Host 3 的集群通告IP（默认: `dragonfly-host3-master`）
- `DRAGONFLY_HOST*_MASTER`: 主节点服务名（用于从节点连接）

**注意**: 如果节点部署在不同的主机上，需要设置实际的 IP 地址而不是服务名。

### 集群配置文件

集群使用统一的配置文件 `dragonfly-cluster.conf`，包含以下配置：
- 集群拓扑信息
- 节点网络配置
- 持久化配置
- 性能参数

配置文件会自动挂载到所有节点，确保配置一致性。

### 初始化集群

部署后，主节点会自动启用集群模式。如果需要手动初始化集群拓扑：

```bash
# 方法 1: 使用 redis-cli 创建集群（仅主节点）
redis-cli --cluster create \
  dragonfly-host1-master:6379 \
  dragonfly-host2-master:6379 \
  dragonfly-host3-master:6379 \
  --cluster-replicas 0

# 方法 2: 如果节点在不同的主机上，使用 IP 地址
redis-cli --cluster create \
  <host1-ip>:6379 \
  <host2-ip>:6379 \
  <host3-ip>:6379 \
  --cluster-replicas 0

# 方法 3: 手动添加主节点到集群
redis-cli -h dragonfly-host1-master -p 6379 CLUSTER MEET dragonfly-host2-master 6379
redis-cli -h dragonfly-host1-master -p 6379 CLUSTER MEET dragonfly-host3-master 6379
```

**注意**: 从节点通过 `--replicaof` 参数自动配置，无需手动加入集群。

### 验证集群部署

```bash
# 测试主节点连接
redis-cli -h localhost -p 6379 ping  # Host 1 Master
redis-cli -h localhost -p 6379 ping  # Host 2 Master (如果访问该主机)
redis-cli -h localhost -p 6379 ping  # Host 3 Master (如果访问该主机)

# 测试从节点连接
redis-cli -h localhost -p 6381 ping  # Host 1 Replica
redis-cli -h localhost -p 6381 ping  # Host 2 Replica (如果访问该主机)
redis-cli -h localhost -p 6381 ping  # Host 3 Replica (如果访问该主机)

# 查看集群信息（在主节点）
redis-cli -h dragonfly-host1-master -p 6379 CLUSTER INFO
redis-cli -h dragonfly-host1-master -p 6379 CLUSTER NODES

# 查看复制状态（在主节点）
redis-cli -h dragonfly-host1-master -p 6379 INFO replication

# 查看从节点复制状态
redis-cli -h dragonfly-host1-replica -p 6381 INFO replication

# 查看所有服务状态
docker stack ps dragonfly
```

### 数据持久化

所有节点的数据都会持久化到本地文件系统，使用 RDB 格式保存。

**持久化配置:**
- **数据目录**: `/data` (挂载到本地 `./data/dragonfly-host*-*`)
- **RDB 文件名**: `dump.rdb`
- **自动保存策略**:
  - 900 秒内至少 1 个键变化时保存
  - 300 秒内至少 10 个键变化时保存
  - 60 秒内至少 10000 个键变化时保存

**确保数据目录存在并具有适当的权限:**

```bash
# 创建所有主从节点的数据目录
mkdir -p ./data/dragonfly-host1-master
mkdir -p ./data/dragonfly-host1-replica
mkdir -p ./data/dragonfly-host2-master
mkdir -p ./data/dragonfly-host2-replica
mkdir -p ./data/dragonfly-host3-master
mkdir -p ./data/dragonfly-host3-replica
chmod 755 ./data/dragonfly-*
```

**持久化参数说明:**
- `--dir /data`: 指定 RDB 文件保存目录
- `--dbfilename dump.rdb`: 指定 RDB 文件名
- `--save <seconds> <changes>`: 配置自动保存策略（满足条件时自动触发 RDB 快照）

## 性能调优

### 单节点

根据服务器资源调整以下参数：

- `--proactor_threads`: 工作线程数（建议设置为 CPU 核心数）
- `--maxmemory`: 最大内存使用量
- `--cache_mode`: 启用缓存模式以提高性能

### 集群

在集群模式下，建议：

- 每个节点至少 2GB 内存
- 使用 SSD 存储以提高 I/O 性能
- 根据负载调整 `--proactor_threads` 参数

## 故障排查

### 查看日志

```bash
# Docker Compose
docker-compose -f docker-compose.dragonfly.yaml logs -f dragonfly

# Docker Swarm
docker service logs -f dragonfly_dragonfly-node1
```

### 检查健康状态

```bash
# 使用 redis-cli 检查
redis-cli -h localhost -p 6379 INFO server

# 查看容器状态
docker ps | grep dragonfly
```

### 常见问题

1. **端口冲突**: 如果端口已被占用，修改 `ports` 配置中的 `published` 端口
2. **内存不足**: 调整 `--maxmemory` 参数或增加服务器内存
3. **数据目录权限**: 确保数据目录具有适当的读写权限
4. **网络问题**: 检查 Docker 网络配置，确保节点之间可以通信

## 备份与恢复

### 备份

Dragonfly 支持 RDB 快照。数据文件位于各节点的数据目录中：

```bash
# 备份主节点数据
cp -r ./data/dragonfly-node1 ./backup/dragonfly-node1-$(date +%Y%m%d)
```

### 恢复

停止服务后，将备份数据恢复到数据目录，然后重启服务。

## 安全建议

在生产环境中，建议：

1. 启用密码认证（添加 `--requirepass` 参数）
2. 限制网络访问（使用防火墙规则）
3. 启用 TLS/SSL 加密（如果 Dragonfly 支持）
4. 定期备份数据
5. 监控资源使用情况

