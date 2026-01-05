#!/bin/bash

# ScyllaDB 磁盘扩容脚本
# 用于扩展 ScyllaDB 节点的数据磁盘容量
# 使用方法: ./expand-disk.sh <node_name> <new_size_gb> [data_path]

set -e

NODE_NAME=${1:-scylla-node1}
NEW_SIZE_GB=${2:-100}
DATA_PATH=${3:-./data/${NODE_NAME#scylla-node}}

if [ -z "$NODE_NAME" ] || [ -z "$NEW_SIZE_GB" ]; then
    echo "用法: $0 <node_name> <new_size_gb> [data_path]"
    echo "示例: $0 scylla-node1 200 ./data/node1"
    exit 1
fi

echo "=========================================="
echo "ScyllaDB 磁盘扩容脚本"
echo "节点: $NODE_NAME"
echo "目标大小: ${NEW_SIZE_GB}GB"
echo "数据路径: $DATA_PATH"
echo "=========================================="

# 检查节点是否运行
if ! docker ps | grep -q "$NODE_NAME"; then
    echo "错误: 节点 $NODE_NAME 未运行"
    exit 1
fi


# 方法3: 如果数据目录在主机上
if [ -d "$DATA_PATH" ]; then
    echo "数据目录位于主机: $DATA_PATH"
    echo "请手动扩展底层存储设备，然后执行以下操作:"
    echo ""
    echo "1. 如果使用 LVM:"
    echo "   sudo lvextend -L +${NEW_SIZE_GB}G <LV_PATH>"
    echo "   sudo resize2fs <LV_PATH>  # 对于 ext4"
    echo "   sudo xfs_growfs $DATA_PATH  # 对于 xfs"
    echo ""
    echo "2. 如果使用直接挂载:"
    echo "   扩展底层块设备后，使用 resize2fs 或 xfs_growfs"
    echo ""
    echo "3. 扩展完成后，重启节点以应用更改:"
    echo "   docker restart $NODE_NAME"
fi

# 验证扩展结果
echo ""
echo "等待节点重启后验证磁盘空间..."
echo "运行以下命令检查:"
echo "  docker exec $NODE_NAME df -h /var/lib/scylla"

# 触发 ScyllaDB 重新扫描数据目录
echo ""
echo "触发 ScyllaDB 重新扫描数据目录..."
docker exec "$NODE_NAME" nodetool refresh -- || echo "注意: 如果节点未完全启动，请稍后手动运行 nodetool refresh"

echo ""
echo "=========================================="
echo "磁盘扩容流程完成"
echo "=========================================="
echo ""
echo "后续步骤:"
echo "1. 验证磁盘空间已扩展"
echo "2. 检查 ScyllaDB 日志确认无错误"
echo "3. 运行 nodetool status 确认节点状态正常"
echo "4. 监控集群性能指标"