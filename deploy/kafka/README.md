# Kafka Deployment Guide

This directory contains Docker-based deployment configurations for Kafka, supporting both single-node and cluster deployments using Docker Swarm.

## Directory Structure

```
deploy/kafka/
├── docker-compose.kafka.yaml          # Single-node deployment
├── docker-compose.kafka-cluster.yaml  # Cluster deployment (Docker Swarm)
├── env.example                        # Environment variables template
└── README.md                          # This file
```

## Prerequisites

- **Docker Engine** 20.10+ 
- **Docker Compose** 2.0+ (for single-node deployment)
- **Docker Swarm** initialized (for cluster deployment only)
- **System Resources**:
  - Single-node: At least 2GB RAM available
  - Cluster: 8GB+ RAM recommended

## Deployment Options

### Option 1: Single-Node Deployment

Best for development, testing, or small-scale production environments.

**Quick Start:**

```bash
# Optional: Copy and customize environment variables
cp env.example .env
# Edit .env if needed

# Start services
docker-compose -f docker-compose.kafka.yaml up -d

# Start with Kafka UI (optional)
docker-compose -f docker-compose.kafka.yaml --profile ui up -d
```

**Common Commands:**

```bash
# View logs
docker-compose -f docker-compose.kafka.yaml logs -f

# View logs for specific service
docker-compose -f docker-compose.kafka.yaml logs -f kafka

# Stop services
docker-compose -f docker-compose.kafka.yaml down

# Stop and remove volumes (⚠️ deletes all data)
docker-compose -f docker-compose.kafka.yaml down -v

# Restart services
docker-compose -f docker-compose.kafka.yaml restart

# View service status
docker-compose -f docker-compose.kafka.yaml ps
```

**Service Endpoints:**
- **Kafka Broker**: `localhost:9092` (external), `kafka:29092` (internal)
- **Zookeeper**: `localhost:2181`
- **Kafka UI** (optional): `http://localhost:8080`

### Option 2: Cluster Deployment (Docker Swarm)

Best for production environments requiring high availability and scalability.

**Initial Setup:**

1. Initialize Docker Swarm (if not already done):
```bash
docker swarm init
```

2. Copy and configure environment file:
```bash
cp env.example .env
# Edit .env with your cluster configuration
```

3. Deploy cluster:
```bash
# Load environment variables
export $(cat .env | grep -v '^#' | xargs)

# Deploy stack
docker stack deploy -c docker-compose.kafka-cluster.yaml kafka
```

**Configuration:**

Edit `.env` file to customize cluster settings:
- `KAFKA_REPLICAS`: Number of Kafka brokers (default: 3, recommended: 3+)
- `ZOOKEEPER_REPLICAS`: Number of Zookeeper nodes (default: 3, recommended: 3 or 5)
- `KAFKA_REPLICATION_FACTOR`: Topic replication factor (should be ≤ KAFKA_REPLICAS)
- `KAFKA_MIN_ISR`: Minimum in-sync replicas (should be < replication factor)
- Resource limits: `KAFKA_CPU_LIMIT`, `KAFKA_MEMORY_LIMIT`, etc.

**Important Notes:**
- Broker IDs are automatically assigned in Swarm mode
- Ensure `KAFKA_REPLICATION_FACTOR` ≤ `KAFKA_REPLICAS`
- Set `KAFKA_MIN_ISR` < `KAFKA_REPLICATION_FACTOR` for availability

## Scaling Kafka Cluster

### Scale Manually

```bash
# Scale Kafka service to 5 brokers
docker service scale kafka_kafka=5

# Check scaling status
docker service ps kafka_kafka

# View service logs
docker service logs -f kafka_kafka

# View all services in stack
docker stack services kafka
```

### Important Scaling Considerations

1. **Broker ID Assignment**: In Swarm mode, broker IDs are automatically managed. For manual assignment, set `KAFKA_BROKER_ID` in `.env` (not recommended for dynamic scaling).

2. **Zookeeper Configuration**: Ensure Zookeeper has enough nodes (typically 3-5 for production)

3. **Topic Replication**: Update topic replication factors after scaling:
   ```bash
   # Example: Increase replication factor for a topic
   docker exec -it $(docker ps -q -f name=kafka_kafka) \
     kafka-topics --alter --topic your-topic \
     --bootstrap-server localhost:9092 \
     --partitions 6 \
     --replication-factor 3
   ```

4. **Resource Allocation**: Monitor CPU and memory usage when scaling:
   ```bash
   docker stats
   ```

5. **Network Bandwidth**: Consider network constraints for inter-broker communication

6. **Update Configuration**: After scaling, update `.env` file to reflect new replica counts

## Configuration Guide

### Environment Variables

All configuration is done through environment variables. Copy `env.example` to `.env` and customize as needed.

#### Key Configuration Variables

**Cluster Settings:**
| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_REPLICAS` | 3 | Number of Kafka broker replicas (cluster only) |
| `ZOOKEEPER_REPLICAS` | 3 | Number of Zookeeper nodes (cluster only) |
| `KAFKA_BROKER_ID` | 1 (single) / auto (cluster) | Broker ID (leave empty for auto-assignment in cluster) |

**Topic Configuration:**
| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_REPLICATION_FACTOR` | 3 | Default replication factor for topics |
| `KAFKA_MIN_ISR` | 2 | Minimum in-sync replicas |
| `KAFKA_NUM_PARTITIONS` | 3 | Default number of partitions for new topics |
| `KAFKA_AUTO_CREATE_TOPICS_ENABLE` | false | Auto-create topics on first write |

**Log Retention:**
| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_LOG_RETENTION_HOURS` | 168 | Log retention time (7 days) |
| `KAFKA_LOG_SEGMENT_BYTES` | 1073741824 | Maximum segment size (1GB) |
| `KAFKA_LOG_CLEANUP_POLICY` | delete | Cleanup policy (delete or compact) |

**Performance Tuning:**
| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_NUM_NETWORK_THREADS` | 8 | Network thread pool size |
| `KAFKA_NUM_IO_THREADS` | 8 | I/O thread pool size |
| `KAFKA_COMPRESSION_TYPE` | producer | Compression type (none, gzip, snappy, lz4, zstd) |

**Resource Limits (Cluster Only):**
| Variable | Default | Description |
|----------|---------|-------------|
| `KAFKA_CPU_LIMIT` | 2 | CPU limit per broker |
| `KAFKA_MEMORY_LIMIT` | 4G | Memory limit per broker |
| `KAFKA_CPU_RESERVATION` | 1 | CPU reservation per broker |
| `KAFKA_MEMORY_RESERVATION` | 2G | Memory reservation per broker |

## Monitoring and Management

### View Service Status

```bash
# Single-node
docker-compose -f docker-compose.kafka.yaml ps

# Cluster
docker stack services kafka
docker stack ps kafka
```

### View Logs

```bash
# Single-node
docker-compose -f docker-compose.kafka.yaml logs -f kafka

# Cluster
docker service logs -f kafka_kafka
docker service logs -f kafka_zookeeper
```

### Kafka UI

Access Kafka UI at `http://localhost:8080` (when enabled with `--profile ui`)

**Features:**
- View topics and partitions
- Browse messages
- Consumer group monitoring
- Broker metrics
- Topic management

**Enable Kafka UI:**
```bash
# Single-node
docker-compose -f docker-compose.kafka.yaml --profile ui up -d

# Cluster (already enabled by default)
# Access at http://localhost:8080
```

## Troubleshooting

### Services Not Starting

1. **Check Docker logs:**
   ```bash
   # Single-node
   docker-compose -f docker-compose.kafka.yaml logs
   
   # Cluster
   docker service logs kafka_kafka
   docker service logs kafka_zookeeper
   ```

2. **Verify ports are not in use:**
   ```bash
   # Linux
   netstat -tuln | grep -E '2181|9092|8080'
   # or
   ss -tuln | grep -E '2181|9092|8080'
   
   # macOS
   lsof -i :2181 -i :9092 -i :8080
   ```

3. **Check Docker resources:**
   ```bash
   docker system df
   docker stats
   ```

4. **Verify environment variables:**
   ```bash
   # Check if .env file exists and is properly formatted
   cat .env | grep -v '^#' | grep -v '^$'
   ```

### Scaling Issues

1. **Check node availability:**
   ```bash
   docker node ls
   ```

2. **Verify resource constraints:**
   ```bash
   docker service inspect kafka_kafka
   ```

3. **Check service events and status:**
   ```bash
   docker service ps kafka_kafka --no-trunc
   docker service logs kafka_kafka --tail 100
   ```

4. **Verify Swarm is initialized:**
   ```bash
   docker info | grep Swarm
   ```

### Performance Issues

1. **Monitor resource usage:**
   ```bash
   docker stats
   # For cluster
   docker service ps kafka_kafka
   ```

2. **Adjust resource limits in `.env` file:**
   - Increase `KAFKA_CPU_LIMIT` and `KAFKA_MEMORY_LIMIT`
   - Adjust `KAFKA_CPU_RESERVATION` and `KAFKA_MEMORY_RESERVATION`

3. **Tune thread pools:**
   - Increase `KAFKA_NUM_IO_THREADS` and `KAFKA_NUM_NETWORK_THREADS`
   - Monitor CPU usage to find optimal values

4. **Review topic configuration:**
   - Increase partition counts for better parallelism
   - Adjust replication factors based on cluster size

5. **Check disk I/O:**
   ```bash
   docker exec -it $(docker ps -q -f name=kafka) df -h
   ```

## Production Recommendations

### High Availability
- ✅ Use cluster deployment with at least **3 brokers**
- ✅ Set `KAFKA_REPLICATION_FACTOR=3` and `KAFKA_MIN_ISR=2`
- ✅ Deploy Zookeeper with **3-5 nodes** (odd number recommended)
- ✅ Distribute brokers across different nodes using placement constraints

### Performance
- ✅ Allocate adequate CPU and memory resources (see resource limits in `.env`)
- ✅ Use **SSD storage** for Kafka data directories
- ✅ Tune JVM heap size (configured via environment variables)
- ✅ Monitor and adjust thread pool sizes based on workload

### Security
- ⚠️ **Enable SSL/TLS** for production (not configured in these files)
- ⚠️ Configure **SASL authentication** for client access
- ⚠️ Use **network policies** to restrict access
- ⚠️ Implement **ACLs** for topic-level access control

### Monitoring
- ✅ Enable Kafka UI for basic monitoring
- ✅ Consider **Prometheus/JMX exporters** for advanced metrics
- ✅ Monitor broker metrics, consumer lag, and disk usage
- ✅ Set up alerts for critical metrics (disk space, consumer lag, etc.)

### Backup and Disaster Recovery
- ✅ Regular backups of **Zookeeper data**
- ✅ Consider **Kafka MirrorMaker** for cross-datacenter replication
- ✅ Document recovery procedures
- ✅ Test backup restoration regularly

## Quick Reference

### Single-Node Commands
```bash
# Start
docker-compose -f docker-compose.kafka.yaml up -d

# Start with UI
docker-compose -f docker-compose.kafka.yaml --profile ui up -d

# Stop
docker-compose -f docker-compose.kafka.yaml down

# Logs
docker-compose -f docker-compose.kafka.yaml logs -f
```

### Cluster Commands
```bash
# Deploy
export $(cat .env | grep -v '^#' | xargs)
docker stack deploy -c docker-compose.kafka-cluster.yaml kafka

# Scale
docker service scale kafka_kafka=5

# Remove
docker stack rm kafka

# Logs
docker service logs -f kafka_kafka
```

## Additional Resources

- [Kafka Documentation](https://kafka.apache.org/documentation/)
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Confluent Platform Docs](https://docs.confluent.io/)
- [Kafka UI Documentation](https://docs.kafka-ui.provectus.io/)

## License

This deployment configuration is part of the injective-indexer-rs project.

