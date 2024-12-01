#!/bin/bash

set -e  # 如果脚本出错，立即退出

# 变量
DOCKER_COMPOSE_VERSION="2.20.2"
REPO_URL="https://github.com/Uniswap/unichain-node"
ETH_RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
BEACON_API_URL="https://ethereum-sepolia-beacon-api.publicnode.com"

# 更新系统
echo "正在更新系统..."
sudo apt update -y && sudo apt upgrade -y

# 安装 Git
echo "正在安装 Git..."
sudo apt install -y git curl

# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
  echo "未找到 Docker，正在安装 Docker..."
  sudo apt install -y docker.io
else
  echo "Docker 已安装。"
fi

# 检查并安装或更新 Docker Compose
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CURRENT_VERSION=$(docker-compose --version | awk '{print $3}' | sed 's/,//g')
  
  if [[ "$DOCKER_COMPOSE_CURRENT_VERSION" =~ ^1 ]]; then
    echo "检测到 Docker Compose 版本为 1，正在更新到版本 2..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  else
    echo "Docker Compose 已是 2 或更高版本。"
  fi
else
  echo "未找到 Docker Compose，正在安装 Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

# 克隆 Unichain 仓库
echo "正在克隆 Unichain 仓库..."
git clone $REPO_URL

# 切换到 unichain-node 目录
cd unichain-node || { echo "无法进入 unichain-node 目录"; exit 1; }

# 编辑 .env.sepolia 文件
echo "正在编辑 .env.sepolia 文件..."
sed -i "s|OP_NODE_L1_ETH_RPC=.*|OP_NODE_L1_ETH_RPC=$ETH_RPC_URL|" .env.sepolia
sed -i "s|OP_NODE_L1_BEACON=.*|OP_NODE_L1_BEACON=$BEACON_API_URL|" .env.sepolia

# 启动 Unichain 节点
echo "正在启动 Unichain 节点..."
docker-compose up -d

echo "脚本执行完毕。"

# 测试节点
echo "正在测试节点:"
curl -d '{"id":1,"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false]}' \
  -H "Content-Type: application/json" http://localhost:8545 || { echo "节点测试失败"; exit 1; }

# 私钥提示
echo "接下来将显示私钥。请务必将其保存到安全的地方。"
echo "如果要添加到加密钱包，请记得在私钥前添加 '0x'，因为它是十六进制格式。"
read -p "按 Enter 键继续并查看私钥..."

# 显示私钥
echo "请复制私钥并妥善保存..."
cat geth-data/geth/nodekey || { echo "无法访问私钥"; exit 1; }
echo "安装完成，任意键显示私钥"