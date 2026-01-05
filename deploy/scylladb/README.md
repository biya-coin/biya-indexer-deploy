# ScyllaDB 部署指南

本目录包含 ScyllaDB 的 Docker Compose 部署配置，支持单节点和集群两种部署模式。

## 📁 目录结构

```
deploy/scylladb/
├── docker-compose.scylladb.yaml      # 3节点集群配置
├── docker-compose.scylladb.single.yaml  # 单节点配置
├── expand-disk.sh                    # 磁盘扩容脚本
├── migrate-data.sh                   # 数据迁移脚本
└── README.md                          # 本文档
```

## 🚀 快速开始

### 单节点部署（开发/测试环境）

单节点部署适合开发、测试或小规模应用场景。

```bash
# 启动单节点 ScyllaDB
docker-compose -f docker-compose.scylladb.single.yaml up -d

# 查看日志
docker-compose -f docker-compose.scylladb.single.yaml logs -f

# 停止服务
docker-compose -f docker-compose.scylladb.single.yaml down
```

**单节点配置特点：**
- 使用 `developer-mode` 模式，适合开发测试
- 标准端口映射：9042 (CQL), 10000 (REST API), 9180 (Metrics)
- 数据目录：`./data/single`
- 简化配置，无需集群协调

### 集群部署（生产环境）

3节点集群部署适合生产环境，提供高可用性和数据冗余。

```bash
# 启动 3节点集群
docker-compose -f docker-compose.scylladb.yaml up -d

# 查看所有节点状态
docker-compose -f docker-compose.scylladb.yaml ps

# 查看特定节点日志
docker-compose -f docker-compose.scylladb.yaml logs -f scylla-node1

# 停止集群
docker-compose -f docker-compose.scylladb.yaml down
```

**集群配置特点：**
- 3节点集群，提供高可用性
- 节点端口映射：
  - node1: 9042, 10000, 9180
  - node2: 9043, 10001, 9181
  - node3: 9044, 10002, 9182
- 数据目录：`./data/node1`, `./data/node2`, `./data/node3`
- 使用 overlay 网络，支持跨主机部署
- 配置了健康检查和自动重启策略

## ⚙️ 配置说明

### 环境变量

可以通过环境变量自定义数据存储路径：

```bash
export SCYLLA_DATA_PATH=/path/to/data
docker-compose -f docker-compose.scylladb.yaml up -d
```

默认数据路径为 `./data/`。

### 资源配置

**单节点配置：**
- CPU: 2 cores (`--smp 2`)
- 内存: 2GB (`--memory 2G`)
- 共享内存: 1GB

**集群节点配置：**
- 每个节点: 2 cores, 2GB 内存
- 共享内存: 1GB per node
- 文件描述符限制: 200000

### 网络配置

- **单节点**: 使用 bridge 网络，子网 `172.29.0.0/16`
- **集群**: 使用 overlay 网络，子网 `172.28.0.0/16`，支持跨主机通信

### 端口说明

| 端口 | 用途 | 说明 |
|------|------|------|
| 9042 | CQL Native Protocol | Cassandra Query Language 协议端口 |
| 10000 | REST API | ScyllaDB REST API 端口 |
| 9180 | Prometheus Metrics | 监控指标导出端口 |

## 🔧 常用操作

### 检查集群状态

```bash
# 单节点
docker exec scylla nodetool status

# 集群
docker exec scylla-node1 nodetool status
```

### 连接到 CQL Shell

```bash
# 单节点
docker exec -it scylla cqlsh

# 集群（连接到 node1）
docker exec -it scylla-node1 cqlsh
```

### 查看节点信息

```bash
# 查看节点详细信息
docker exec scylla-node1 nodetool info

# 查看表空间使用情况
docker exec scylla-node1 nodetool tablestats
```

## 💾 数据管理

### 磁盘扩容

使用 `expand-disk.sh` 脚本扩展节点磁盘容量：

```bash
# 扩展单节点磁盘
./expand-disk.sh scylla 200 ./data/single

# 扩展集群节点磁盘
./expand-disk.sh scylla-node1 500 ./data/node1
```

**注意事项：**
- 脚本会指导你完成底层存储扩展
- 扩展后需要重启节点
- 建议在低峰期执行扩容操作

### 数据迁移

使用 `migrate-data.sh` 脚本进行数据迁移：

```bash
# 查看帮助
./migrate-data.sh help

# 备份数据
./migrate-data.sh backup scylla-node1 ./backups/backup1

# 恢复数据
./migrate-data.sh restore scylla-node2 ./backups/backup1

# 节点间数据迁移
./migrate-data.sh node-to-node scylla-node1 scylla-node2 mykeyspace

# 流式数据迁移（适用于新节点加入）
./migrate-data.sh streaming scylla-node1 scylla-node2
```

**迁移场景：**
- `backup`: 备份节点数据到本地目录
- `restore`: 从备份恢复数据
- `node-to-node`: 节点间数据迁移
- `cluster-migration`: 集群迁移
- `streaming`: 流式数据迁移（新节点加入集群）

## 📊 监控

### Prometheus 指标

ScyllaDB 在 `9180` 端口暴露 Prometheus 格式的指标：

```bash
# 查看指标
curl http://localhost:9180/metrics
```

### 健康检查

Docker Compose 配置了自动健康检查：

```bash
# 查看健康状态
docker ps --format "table {{.Names}}\t{{.Status}}"
```

## 🔒 安全建议

1. **生产环境配置：**
   - 禁用 `developer-mode`（集群模式已禁用）
   - 配置认证和授权
   - 使用 TLS 加密连接
   - 限制网络访问

2. **数据持久化：**
   - 确保数据目录有足够的磁盘空间
   - 定期备份重要数据
   - 监控磁盘使用情况

3. **资源限制：**
   - 根据实际负载调整 CPU 和内存配置
   - 监控系统资源使用情况
   - 设置适当的 ulimits

## 🐛 故障排查

### 节点无法启动

```bash
# 查看详细日志
docker-compose logs scylla-node1

# 检查数据目录权限
ls -la ./data/node1

# 检查端口占用
netstat -tuln | grep 9042
```

### 集群节点无法加入

```bash
# 检查网络连通性
docker exec scylla-node1 ping scylla-node2

# 检查种子节点配置
docker exec scylla-node1 cat /etc/scylla/scylla.yaml | grep seeds

# 查看集群状态
docker exec scylla-node1 nodetool status
```

### 性能问题

```bash
# 查看节点统计信息
docker exec scylla-node1 nodetool info

# 查看表统计信息
docker exec scylla-node1 nodetool tablestats

# 查看压缩统计
docker exec scylla-node1 nodetool compactionstats
```

## 📚 相关资源

- [ScyllaDB 官方文档](https://docs.scylladb.com/)
- [ScyllaDB Docker Hub](https://hub.docker.com/r/scylladb/scylla)
- [CQL 参考文档](https://docs.scylladb.com/stable/cql/)

## 📝 注意事项

1. **数据目录：** 确保数据目录有足够的磁盘空间和正确的权限
2. **网络配置：** 集群模式需要 overlay 网络支持（Docker Swarm）
3. **资源配置：** 根据实际负载调整 CPU、内存和存储配置
4. **备份策略：** 定期备份数据，特别是在生产环境
5. **监控告警：** 配置监控和告警，及时发现和解决问题

## 🔄 版本信息

- ScyllaDB 镜像: `scylladb/scylla:latest`
- Docker Compose 版本: 3.8

---

**提示：** 在生产环境部署前，请仔细阅读 ScyllaDB 官方文档，并根据实际需求调整配置参数。

