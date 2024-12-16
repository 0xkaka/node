#!/bin/bash

# 更新系统并安装必要工具
echo "Updating system and installing required tools..."
sudo apt-get update
sudo apt-get install --reinstall -y sudo
sudo apt-get install -y curl screen jq bc

# 克隆代码仓库
echo "Cloning miner-release repository..."
git clone https://github.com/heurist-network/miner-release.git
cd miner-release

# 下载并安装 Miniconda
echo "Installing Miniconda..."
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
export PATH="$HOME/miniconda/bin:$PATH"
source ~/.bashrc

# 创建并激活 Conda 虚拟环境
echo "Creating and activating Conda environment..."
conda create --name heurist-miner python=3.11 -y
conda activate heurist-miner

# 安装依赖
echo "Installing dependencies..."
pip install -r requirements.txt

# 检测 GPU 数量
echo "Detecting GPU devices..."
GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
echo "Detected $GPU_COUNT GPUs."

# 配置环境变量文件
echo "Configuring .env file..."
echo "MINER_ID_0=0x876de2b615c813e33a2e36f2b44e98b10fe25480-" > .env
for ((i=1; i<$GPU_COUNT; i++)); do
  echo "MINER_ID_$i=0x876de2b615c813e33a2e36f2b44e98b10fe25480-$i" >> .env
done

# 创建 .heurist-keys 文件夹及密钥文件
echo "Creating .heurist-keys folder and key file..."
mkdir -p /root/.heurist-keys
cat <<EOL > /root/.heurist-keys/0x876de2b615c813e33a2e36f2b44e98b10fe25480.txt
Seed Phrase: inform theme lunar wine pause hand time account zoo month smile bottom
Identity Wallet Address: 0x25b3f493fd0861a7defb9b492ef6d434b9da0972
EOL

# 用户选择启动 GPU 数量
echo "Setup completed. Available GPUs: $GPU_COUNT"
read -p "Enter the number of GPUs to use (1-$GPU_COUNT): " SELECTED_GPU_COUNT

if [[ $SELECTED_GPU_COUNT -lt 1 || $SELECTED_GPU_COUNT -gt $GPU_COUNT ]]; then
  echo "Invalid GPU count. Exiting."
  exit 1
fi

# 启动 GPU 守护进程
echo "Starting mining processes..."
for ((i=0; i<$SELECTED_GPU_COUNT; i++)); do
  SCREEN_NAME="llm$((i+1))"
  echo "Launching screen session $SCREEN_NAME for GPU $i..."
  screen -dmS $SCREEN_NAME bash -c "
    source ~/.bashrc
    conda activate heurist-miner
    ./llm-miner-starter.sh dolphin-2.9-llama3-8b --miner-id-index $i --port $((8000 + i)) --gpu-ids $i
  "
done

echo "All selected mining processes have been started in screen sessions."
echo "Use 'screen -ls' to list active sessions and 'screen -r <session_name>' to attach to a session."
