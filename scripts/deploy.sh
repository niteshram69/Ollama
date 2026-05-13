#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# Jarvis Inference Stack — Full Deployment Script
# Model: Qwen2.5 8B Instruct Q4_K_M
# Target: Azure Standard_B8ms (8 vCPU / 32 GB / CPU-only)
# =============================================================

SERVER_IP="${1:?Usage: deploy.sh <SERVER_IP>}"
SSH_KEY="${2:-$HOME/Downloads/Ram_key.pem}"
SSH="ssh -o StrictHostKeyChecking=accept-new -i $SSH_KEY niteshram@$SERVER_IP"

echo "=== [1/9] Installing system packages ==="
$SSH "sudo apt-get update -qq && sudo apt-get install -y -qq \
  build-essential cmake git pkg-config libcurl4-openssl-dev libomp-dev ccache \
  python3 python3-pip python3-venv tmux htop jq fail2ban ufw curl \
  redis-server nginx > /dev/null 2>&1 && echo 'packages done'"

echo "=== [2/9] Creating directory structure ==="
$SSH "sudo mkdir -p /opt/jarvis/{models,runtime,cache,logs,bin} && \
  sudo chown -R niteshram:niteshram /opt/jarvis"

echo "=== [3/9] Building llama.cpp ==="
$SSH "cd /opt/jarvis/runtime && \
  ([ -d llama.cpp ] && cd llama.cpp && git pull || git clone --depth 1 https://github.com/ggml-org/llama.cpp.git && cd llama.cpp) && \
  cd llama.cpp && mkdir -p build && cd build && \
  cmake .. -DCMAKE_BUILD_TYPE=Release -DGGML_OPENMP=ON -DLLAMA_CURL=ON \
    -DCMAKE_C_FLAGS='-march=skylake -mtune=skylake -O3' \
    -DCMAKE_CXX_FLAGS='-march=skylake -mtune=skylake -O3' 2>&1 | tail -5 && \
  cmake --build . --config Release -j8 2>&1 | tail -5 && \
  echo 'build done' && ls -lh bin/llama-server"

echo "=== [4/9] Downloading Qwen2.5 8B Q4_K_M GGUF ==="
$SSH "cd /opt/jarvis/models && \
  [ -f qwen2.5-8b-instruct-q4_k_m.gguf ] && echo 'model exists' || \
  (curl -L -o qwen2.5-8b-instruct-q4_k_m.gguf \
    'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf' \
    --progress-bar && echo 'download done') && \
  ls -lh qwen2.5-8b-instruct-q4_k_m.gguf"

echo "=== [5/9] Installing LiteLLM ==="
$SSH "[ -d /opt/litellm/venv ] || (sudo mkdir -p /opt/litellm && \
  sudo python3 -m venv /opt/litellm/venv && \
  sudo /opt/litellm/venv/bin/pip install --upgrade pip && \
  sudo /opt/litellm/venv/bin/pip install 'litellm[proxy]' pyyaml) && \
  echo 'litellm ready'"

echo "=== [6/9] Deploying config files ==="
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
scp -i "$SSH_KEY" "$SCRIPT_DIR/litellm/config.yaml" "niteshram@$SERVER_IP:/tmp/litellm-config.yaml"
scp -i "$SSH_KEY" "$SCRIPT_DIR/litellm/litellm.env" "niteshram@$SERVER_IP:/tmp/litellm.env"
scp -i "$SSH_KEY" "$SCRIPT_DIR/systemd/llama-server.service" "niteshram@$SERVER_IP:/tmp/llama-server.service"
scp -i "$SSH_KEY" "$SCRIPT_DIR/systemd/litellm.service" "niteshram@$SERVER_IP:/tmp/litellm.service"
scp -i "$SSH_KEY" "$SCRIPT_DIR/nginx/litellm" "niteshram@$SERVER_IP:/tmp/nginx-litellm"
scp -i "$SSH_KEY" "$SCRIPT_DIR/tuning/99-jarvis-inference.conf" "niteshram@$SERVER_IP:/tmp/99-jarvis-inference.conf"
scp -i "$SSH_KEY" "$SCRIPT_DIR/tuning/99-jarvis.conf" "niteshram@$SERVER_IP:/tmp/99-jarvis.conf"
scp -i "$SSH_KEY" "$SCRIPT_DIR/scripts/validate_jarvis.py" "niteshram@$SERVER_IP:/opt/jarvis/runtime/validate_jarvis.py"

$SSH "sudo mkdir -p /etc/litellm && \
  sudo cp /tmp/litellm-config.yaml /etc/litellm/config.yaml && \
  sudo cp /tmp/litellm.env /etc/litellm/litellm.env && \
  sudo chown -R root:niteshram /etc/litellm && sudo chmod 750 /etc/litellm && \
  sudo chmod 640 /etc/litellm/config.yaml /etc/litellm/litellm.env && \
  sudo cp /tmp/llama-server.service /etc/systemd/system/ && \
  sudo cp /tmp/litellm.service /etc/systemd/system/ && \
  sudo cp /tmp/nginx-litellm /etc/nginx/sites-available/litellm && \
  sudo ln -sf /etc/nginx/sites-available/litellm /etc/nginx/sites-enabled/litellm && \
  sudo rm -f /etc/nginx/sites-enabled/default && \
  sudo cp /tmp/99-jarvis-inference.conf /etc/sysctl.d/ && \
  sudo cp /tmp/99-jarvis.conf /etc/security/limits.d/ && \
  echo 'configs deployed'"

echo "=== [7/9] Applying kernel tuning ==="
$SSH "sudo sysctl --system > /dev/null 2>&1 && echo 'sysctl applied'"

echo "=== [8/9] Starting services ==="
$SSH "sudo systemctl daemon-reload && \
  sudo nginx -t && \
  sudo systemctl enable --now redis-server nginx && \
  sudo systemctl enable --now llama-server && \
  sleep 20 && \
  sudo systemctl enable --now litellm && \
  sleep 8 && \
  echo 'SERVICES:' && systemctl is-active llama-server litellm redis-server nginx"

echo "=== [9/9] Configuring firewall ==="
$SSH "sudo ufw --force reset > /dev/null 2>&1 && \
  sudo ufw default deny incoming && sudo ufw default allow outgoing && \
  sudo ufw allow OpenSSH && sudo ufw allow 4000/tcp && \
  sudo ufw --force enable && sudo ufw status"

echo ""
echo "=== DEPLOYMENT COMPLETE ==="
echo "Endpoint: http://$SERVER_IP:4000/v1"
echo "API Key:  sk-q38YjUhFGiyAw5MuK6WaPfTaEK225aL8mNanHftySFEkRUec"
echo ""
echo "Run validation: ssh -i $SSH_KEY niteshram@$SERVER_IP python3 /opt/jarvis/runtime/validate_jarvis.py"
