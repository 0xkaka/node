#!/usr/bin/env bash

# 验证十六进制私钥格式
validate_hex() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "私钥格式错误，退出..."
    exit 1
  fi
}

# 验证端口号是否有效
validate_port() {
  if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -le 1024 ] || [ "$1" -ge 65535 ]; then
    echo "端口号无效，必须介于 1024 和 65535 之间。"
    exit 1
  fi
}

# 验证输入是否为有效的 IPv4 地址或 FQDN
validate_ip_or_fqdn() {
  local input=$1
  if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || [[ "$input" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    return 0
  else
    echo "输入无效，必须是有效的 IPv4 地址或 FQDN。"
    return 1
  fi
}

# 从私钥生成地址
generate_address_from_private_key() {
  local private_key=$1
  private_key=${private_key#0x}  # 去掉 '0x' 前缀
  echo -n "$private_key" > /tmp/private_key_file

  docker_output=$(docker run --rm -v /tmp/private_key_file:/tmp/private_key_file ethereum/client-go:latest account import --password /dev/null /tmp/private_key_file 2>&1)

  rm /tmp/private_key_file

  address=$(echo "$docker_output" | grep -oP '(?<=Address: \{)[a-fA-F0-9]+(?=\})')

  if [ -z "$address" ]; then
    echo "无法从私钥生成地址。"
    return 1
  fi

  echo "$address"
}

# 获取公网 IP 地址
get_public_ip() {
  curl -s https://api.ipify.org
}

# 安装节点
install_nodes() {
  read -p "输入节点的起始索引: " START_INDEX
  read -p "输入节点的结束索引: " END_INDEX
  # 直接指定基础目录为 /root/ocean
  BASE_DIR="/root/ocean"

  # 创建目录，如果不存在
  if ! mkdir -p "$BASE_DIR"; then
    echo "无法创建基础目录: $BASE_DIR"
    exit 1
  fi

  P2P_ANNOUNCE_ADDRESS=$(get_public_ip)
  echo "检测到的公网 IP 地址: $P2P_ANNOUNCE_ADDRESS"
  read -p "使用此 IP 作为 P2P_ANNOUNCE_ADDRESS? (y/n): " use_detected_ip
  if [[ $use_detected_ip != "y" ]]; then
    read -p "提供节点可访问的公网 IPv4 地址或 FQDN: " P2P_ANNOUNCE_ADDRESS
  fi
  validate_ip_or_fqdn "$P2P_ANNOUNCE_ADDRESS"

  # 通过安装批次自动调整 BASE_HTTP_PORT
  BASE_HTTP_PORT=$((10000 + (START_INDEX - 1) * 4))
  PORT_INCREMENT=4

  install_single_node() {
  local i=$1
  local NODE_DIR="${BASE_DIR}/node${i}"
  mkdir -p "$NODE_DIR"
  echo "在 $NODE_DIR 中设置节点 $i"

  # 检查私钥文件是否存在
  if [ ! -f "$NODE_DIR/private_key" ]; then
    # 私钥文件不存在，生成新的私钥
    PRIVATE_KEY=$(openssl rand -hex 32)
    PRIVATE_KEY="0x$PRIVATE_KEY"
    echo "$PRIVATE_KEY" > "${NODE_DIR}/private_key"
    echo "为节点 $i 生成的私钥: $PRIVATE_KEY"
  else
    # 私钥文件存在，读取现有私钥
    PRIVATE_KEY=$(cat "$NODE_DIR/private_key")
    echo "为节点 $i 读取现有私钥: $PRIVATE_KEY"
  fi

  validate_hex "$PRIVATE_KEY"

  ADMIN_ADDRESS=$(generate_address_from_private_key "$PRIVATE_KEY")
  echo "为节点 $i 生成的管理员地址: 0x$ADMIN_ADDRESS"

    validate_hex "$PRIVATE_KEY"

  HTTP_PORT=$((10000 + i * 10))    
  P2P_TCP_PORT=$((10000 + i))       
  P2P_WS_PORT=$((10010 + i))         
  TYPESENSE_PORT=$((10000 + i * 100))


  validate_port "$HTTP_PORT"
  validate_port "$P2P_TCP_PORT"
  validate_port "$P2P_WS_PORT"
  validate_port "$TYPESENSE_PORT"


    if [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      P2P_ANNOUNCE_ADDRESSES='["/ip4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_TCP_PORT'", "/ip4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_WS_PORT'"]'
    elif [[ "$P2P_ANNOUNCE_ADDRESS" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      P2P_ANNOUNCE_ADDRESSES='["/dns4/'$P2P_ANNOUNCE_ADDRESS'/tcp/'$P2P_TCP_PORT'", "/dns4/'$P2P_ANNOUNCE_ADDRESS'/ws/tcp/'$P2P_WS_PORT'"]'
    else
      P2P_ANNOUNCE_ADDRESSES=''
      echo "未提供输入，其他节点可能无法访问 Ocean 节点。"
    fi
    # 生成 docker-compose.yml
#...(docker-compose.yml 文件内容，太长省略)



    if [ ! -f "${NODE_DIR}/docker-compose.yml" ]; then
      echo "无法为节点 $i 生成 docker-compose.yml"
      return 1
    fi

    echo "节点 $i 的 Docker Compose 文件已生成，位于 ${NODE_DIR}/docker-compose.yml"

    # 启动 Docker 容器
    echo "正在启动节点 $i..."
    (cd "$NODE_DIR" && docker-compose up -d)

    if [ $? -eq 0 ]; then
      echo "节点 $i 启动成功。"
    else
      echo "无法启动节点 $i。"
      return 1
    fi
  }

  # 顺序安装节点
  for ((i=START_INDEX; i<=END_INDEX; i++)); do
    install_single_node $i
  done
}

# 卸载节点
uninstall_nodes() {
  read -p "输入节点的起始索引: " START_INDEX
  read -p "输入节点的结束索引: " END_INDEX
  # 卸载时也直接指定基础目录
  BASE_DIR="/root/ocean"

  uninstall_single_node() {
    local i=$1
    local NODE_DIR="${BASE_DIR}/node${i}"
    if [ -d "$NODE_DIR" ]; then
      echo "正在停止并移除节点 $i 的容器..."
      (cd "$NODE_DIR" && docker-compose down -v)
      echo "正在移除节点目录..."
      rm -rf "$NODE_DIR"
      echo "节点 $i 已卸载。"
    else
      echo "未找到节点 $i 的目录。跳过..."
    fi
  }

  for ((i=START_INDEX; i<=END_INDEX; i++)); do
    uninstall_single_node $i
  done

  echo "卸载完成。"
}

# 读取所有生成的私钥
read_all_private_keys() {
  BASE_DIR="/root/ocean"
  START_INDEX=1 # 或者根据你的需求修改起始索引
  END_INDEX=$(ls -l "$BASE_DIR"/node* | wc -l) # 动态获取节点数量
  echo "读取所有节点私钥："

  for ((i=START_INDEX; i<=END_INDEX; i++)); do
    NODE_DIR="${BASE_DIR}/node${i}"
    if [ -f "$NODE_DIR/private_key" ]; then
      PRIVATE_KEY=$(cat "$NODE_DIR/private_key")
      echo "节点 ${i}: $PRIVATE_KEY"
    else
      echo "警告: 未找到节点 ${i} 的私钥文件。"
    fi
  done
}
# 单独重启节点容器
restart_single_node() {
  local node_index=$1
  local NODE_DIR="/root/ocean/node${node_index}"

  if [ -d "$NODE_DIR" ]; then
    if [ -f "$NODE_DIR/docker-compose.yml" ]; then
      echo "正在重启节点 ${node_index}..."
      (cd "$NODE_DIR" && docker-compose restart)
      if [ $? -eq 0 ]; then
        echo "节点 ${node_index} 重启成功。"
      else
        echo "节点 ${node_index} 重启失败。"
      fi
    else
      echo "错误：未找到节点 ${node_index} 的 docker-compose.yml 文件。"
    fi
  else
    echo "错误：未找到节点 ${node_index} 的目录。"
  fi
}


# 主脚本
echo "Ocean 节点管理脚本"
echo "1. 安装 Ocean 节点"
echo "2. 卸载 Ocean 节点"
echo "3. 读取所有私钥"
echo "4. 重启节点 (支持多选)"  # 修改菜单选项
read -p "输入你的选择 (1, 2, 3 或 4): " choice

case $choice in
  1)
    install_nodes
    read_all_private_keys
    ;;
  2)
    uninstall_nodes
    ;;
  3)
    read_all_private_keys
    ;;
  4)
    read -p "输入要重启的节点索引 (用空格分隔，例如 1 2 3): " node_indices
    IFS=' ' read -r -a indices <<< "$node_indices" # 将输入分割成数组

    for node_index in "${indices[@]}"; do
      restart_single_node "$node_index"
    done
    ;;
  *)
    echo "无效的选择。退出。"
    exit 1
    ;;
esac
