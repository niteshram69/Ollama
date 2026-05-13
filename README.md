# Jarvis Inference Stack

Production-grade CPU-only LLM inference platform using **Qwen2.5 8B Instruct Q4_K_M** on Azure Standard_B8ms.

## Architecture

```
Client → :4000 NGINX (buffering=off) → :4001 LiteLLM (auth+routing+cache) → :8080 llama-server (Qwen2.5 8B Q4_K_M)
                                                          ↕
                                                    :6379 Redis (response cache)
```

## Quick Deploy

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh 20.237.150.26
```

## Access

- **Endpoint:** `http://<SERVER_IP>:4000/v1`
- **API Key:** `sk-q38YjUhFGiyAw5MuK6WaPfTaEK225aL8mNanHftySFEkRUec`
- **Models:** `qwen2.5-8b`, `planner`, `chat`, `classifier`

## Directory Structure

```
jarvis-inference/
├── litellm/
│   ├── config.yaml          # LiteLLM routing, caching, fallbacks
│   └── litellm.env          # API key + environment variables
├── systemd/
│   ├── llama-server.service  # llama.cpp inference server
│   ├── litellm.service       # LiteLLM proxy gateway
│   └── ollama-override.conf  # Ollama tuning (if using Ollama)
├── nginx/
│   └── litellm               # Streaming reverse proxy config
├── tuning/
│   ├── 99-jarvis-inference.conf  # Kernel/network sysctl tuning
│   └── 99-jarvis.conf           # ulimits for inference user
├── scripts/
│   ├── deploy.sh             # One-command full deployment
│   └── validate_jarvis.py    # End-to-end validation suite
└── README.md
```

## Server File Locations

| Local File | Server Path |
|------------|-------------|
| `litellm/config.yaml` | `/etc/litellm/config.yaml` |
| `litellm/litellm.env` | `/etc/litellm/litellm.env` |
| `systemd/llama-server.service` | `/etc/systemd/system/llama-server.service` |
| `systemd/litellm.service` | `/etc/systemd/system/litellm.service` |
| `nginx/litellm` | `/etc/nginx/sites-available/litellm` |
| `tuning/99-jarvis-inference.conf` | `/etc/sysctl.d/99-jarvis-inference.conf` |
| `tuning/99-jarvis.conf` | `/etc/security/limits.d/99-jarvis.conf` |
| `scripts/validate_jarvis.py` | `/opt/jarvis/runtime/validate_jarvis.py` |

## llama-server Parameters

| Flag | Value | Rationale |
|------|-------|-----------|
| `--threads 6` | 6 of 8 cores | Reserve 2 for NGINX/LiteLLM/Redis/OS |
| `--parallel 4` | 4 slots | Concurrent request capacity |
| `--ctx-size 8192` | 8K per slot | 32K total KV across 4 slots |
| `--batch-size 2048` | Prompt batch | Fast prompt processing |
| `--ubatch-size 512` | Token micro-batch | Generation efficiency |
| `--flash-attn auto` | Auto | Use if backend supports it |
| `--mlock` | Enabled | Pin model in RAM, zero page faults |
| `--cont-batching` | Enabled | Continuous batching for concurrency |
| `--cache-type-k q8_0` | Quantized KV | Saves ~1 GB RAM |
| `--cache-type-v q8_0` | Quantized KV | Saves ~1 GB RAM |

## Service Management

```bash
# Status
sudo systemctl status llama-server litellm redis-server nginx

# Restart
sudo systemctl restart llama-server litellm

# Logs
sudo journalctl -u llama-server -f
sudo journalctl -u litellm -f

# Validate
python3 /opt/jarvis/runtime/validate_jarvis.py
```

## Example Usage

```bash
export KEY="sk-q38YjUhFGiyAw5MuK6WaPfTaEK225aL8mNanHftySFEkRUec"
export URL="http://20.237.150.26:4000/v1"

# Chat
curl -s -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  "$URL/chat/completions" \
  -d '{"model":"chat","messages":[{"role":"user","content":"Hello Jarvis"}],"max_tokens":128}' | jq

# Streaming
curl -N -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  "$URL/chat/completions" \
  -d '{"model":"chat","messages":[{"role":"user","content":"Explain quantum computing"}],"stream":true,"max_tokens":256}'
```

## Python Integration

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-q38YjUhFGiyAw5MuK6WaPfTaEK225aL8mNanHftySFEkRUec",
    base_url="http://20.237.150.26:4000/v1",
)

stream = client.chat.completions.create(
    model="chat",
    messages=[{"role": "user", "content": "Hello Jarvis"}],
    stream=True,
    max_tokens=256,
)
for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```
