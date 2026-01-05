#!/bin/bash

# ScyllaDB 数据迁移脚本
# 支持节点间数据迁移、集群迁移、备份恢复等场景
# 使用方法: ./migrate-data.sh <operation> [options]

set -e

OPERATION=${1:-help}

case "$OPERATION" in
    backup)
        # 备份操作
        NODE_NAME=${2:-scylla-node1}
        BACKUP_PATH=${3:-./backups/$(date +%Y%m%d_%H%M%S)}
        
        echo "=========================================="
        echo "ScyllaDB 数据备份"
        echo "节点: $NODE_NAME"
        echo "备份路径: $BACKUP_PATH"
        echo "=========================================="
        
        mkdir -p "$BACKUP_PATH"
        
        # 创建快照
        echo "创建快照..."
        docker exec "$NODE_NAME" nodetool snapshot -t "backup_$(date +%Y%m%d_%H%M%S)"
        
        # 导出 schema
        echo "导出 schema..."
        docker exec "$NODE_NAME" cqlsh -e "DESC KEYSPACE system" > "$BACKUP_PATH/schema.cql" 2>/dev/null || true
        
        # 使用 sstableloader 或直接复制数据文件
        echo "复制数据文件..."
        docker cp "${NODE_NAME}:/var/lib/scylla/data" "$BACKUP_PATH/data"
        docker cp "${NODE_NAME}:/var/lib/scylla/commitlog" "$BACKUP_PATH/commitlog" 2>/dev/null || true
        
        echo "备份完成: $BACKUP_PATH"
        ;;
        
    restore)
        # 恢复操作
        NODE_NAME=${2:-scylla-node1}
        BACKUP_PATH=${3:-./backups/latest}
        
        echo "=========================================="
        echo "ScyllaDB 数据恢复"
        echo "节点: $NODE_NAME"
        echo "备份路径: $BACKUP_PATH"
        echo "=========================================="
        
        if [ ! -d "$BACKUP_PATH" ]; then
            echo "错误: 备份路径不存在: $BACKUP_PATH"
            exit 1
        fi
        
        # 停止节点
        echo "停止节点..."
        docker stop "$NODE_NAME"
        
        # 恢复数据文件
        echo "恢复数据文件..."
        docker cp "$BACKUP_PATH/data" "${NODE_NAME}:/var/lib/scylla/"
        
        # 恢复 schema
        if [ -f "$BACKUP_PATH/schema.cql" ]; then
            echo "恢复 schema..."
            docker exec -i "$NODE_NAME" cqlsh < "$BACKUP_PATH/schema.cql" || echo "警告: schema 恢复失败"
        fi
        
        # 启动节点
        echo "启动节点..."
        docker start "$NODE_NAME"
        
        # 刷新数据
        sleep 30
        echo "刷新数据..."
        docker exec "$NODE_NAME" nodetool refresh -- || echo "注意: 节点可能还在启动中"
        
        echo "恢复完成"
        ;;
        
    node-to-node)
        # 节点间数据迁移
        SOURCE_NODE=${2:-scylla-node1}
        TARGET_NODE=${3:-scylla-node2}
        KEYSPACE=${4:-""}
        
        echo "=========================================="
        echo "ScyllaDB 节点间数据迁移"
        echo "源节点: $SOURCE_NODE"
        echo "目标节点: $TARGET_NODE"
        echo "Keyspace: ${KEYSPACE:-all}"
        echo "=========================================="
        
        # 方法1: 使用 nodetool rebuild（推荐用于添加新节点）
        echo "方法1: 使用 nodetool rebuild..."
        echo "这适用于新节点加入集群时自动同步数据"
        echo "在新节点上运行: nodetool rebuild"
        
        # 方法2: 使用 sstableloader
        if [ -n "$KEYSPACE" ]; then
            echo "方法2: 使用 sstableloader 迁移特定 keyspace..."
            echo "导出 sstables..."
            SNAPSHOT_NAME="migration_$(date +%Y%m%d_%H%M%S)"
            docker exec "$SOURCE_NODE" nodetool snapshot -t "$SNAPSHOT_NAME" -kt "$KEYSPACE"
            
            echo "使用 sstableloader 导入到目标节点..."
            # 获取目标节点 IP
            TARGET_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TARGET_NODE")
            
            # 复制 sstables 并加载
            echo "请手动执行以下步骤:"
            echo "1. 从源节点复制 sstables:"
            echo "   docker cp ${SOURCE_NODE}:/var/lib/scylla/data/.../snapshots/$SNAPSHOT_NAME ./sstables"
            echo "2. 使用 sstableloader 加载:"
            echo "   docker exec $TARGET_NODE sstableloader -d $TARGET_IP ./sstables"
        fi
        
        echo "迁移完成"
        ;;
        
    cluster-migration)
        # 集群迁移
        SOURCE_CLUSTER=${2:-"scylla-node1,scylla-node2,scylla-node3"}
        TARGET_CLUSTER=${3:-"new-scylla-node1,new-scylla-node2,new-scylla-node3"}
        
        echo "=========================================="
        echo "ScyllaDB 集群迁移"
        echo "源集群: $SOURCE_CLUSTER"
        echo "目标集群: $TARGET_CLUSTER"
        echo "=========================================="
        
        echo "集群迁移步骤:"
        echo "1. 在新集群中创建相同的 schema"
        echo "2. 使用 sstableloader 或 nodetool rebuild 迁移数据"
        echo "3. 更新应用连接配置"
        echo "4. 验证数据一致性"
        echo "5. 切换流量到新集群"
        echo "6. 下线旧集群"
        
        # 导出 schema
        FIRST_SOURCE_NODE=$(echo "$SOURCE_CLUSTER" | cut -d',' -f1)
        echo "导出 schema..."
        docker exec "$FIRST_SOURCE_NODE" cqlsh -e "DESC SCHEMA" > ./migration_schema.cql
        
        echo "Schema 已导出到: ./migration_schema.cql"
        echo "请在新集群中执行此 schema，然后使用 sstableloader 迁移数据"
        ;;
        
    streaming)
        # 流式数据迁移（使用 ScyllaDB 的 streaming 功能）
        SOURCE_NODE=${2:-scylla-node1}
        TARGET_NODE=${3:-scylla-node2}
        
        echo "=========================================="
        echo "ScyllaDB 流式数据迁移"
        echo "源节点: $SOURCE_NODE"
        echo "目标节点: $TARGET_NODE"
        echo "=========================================="
        
        # 获取节点 IP
        SOURCE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$SOURCE_NODE")
        TARGET_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TARGET_NODE")
        
        echo "源节点 IP: $SOURCE_IP"
        echo "目标节点 IP: $TARGET_IP"
        
        # 使用 nodetool rebuild（适用于新节点）
        echo "在目标节点上执行 rebuild（从源节点同步数据）..."
        docker exec "$TARGET_NODE" nodetool rebuild -- $SOURCE_IP
        
        echo "流式迁移完成"
        ;;
        
    help|*)
        echo "ScyllaDB 数据迁移脚本"
        echo ""
        echo "用法: $0 <operation> [options]"
        echo ""
        echo "操作:"
        echo "  backup <node> <backup_path>          - 备份节点数据"
        echo "  restore <node> <backup_path>        - 恢复节点数据"
        echo "  node-to-node <src> <dst> [keyspace] - 节点间数据迁移"
        echo "  cluster-migration <src> <dst>       - 集群迁移"
        echo "  streaming <src> <dst>               - 流式数据迁移"
        echo ""
        echo "示例:"
        echo "  $0 backup scylla-node1 ./backups/backup1"
        echo "  $0 restore scylla-node2 ./backups/backup1"
        echo "  $0 node-to-node scylla-node1 scylla-node2 mykeyspace"
        echo "  $0 streaming scylla-node1 scylla-node2"
        ;;
esac