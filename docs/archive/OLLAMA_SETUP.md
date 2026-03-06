# Ollama Integration Guide

This guide explains how to connect to Ollama running on another machine (e.g., Omarchy OS laptop) on your local network. Supports both native Ollama installation and Docker-based deployment.

## Quick Decision Guide

**Choose your setup based on your hardware:**

- **GPU with 4GB+ VRAM** → Use GPU mode (faster, can run larger models)
- **GPU with < 4GB VRAM or crashes** → Use CPU-only mode (stable, slower)
- **No GPU or limited GPU** → Use CPU-only mode (requires 16GB+ RAM)

## Quick Start (Working Example)

If you have Ollama accessible at `http://192.168.1.11:11434` with model `phi3:mini`:

```bash
# Add to .env
export OLLAMA_BASE_URL="http://192.168.1.11:11434"
export OLLAMA_MODEL="phi3:mini"

# Enable in config/algo.yml
# ai:
#   enabled: true

# Test
bundle exec rake ai:test
```

## Overview

Ollama is an OpenAI-compatible API server that allows you to run LLMs locally. The AI integration module automatically detects and uses Ollama when `OLLAMA_BASE_URL` is configured.

## Prerequisites

1. **Ollama installed and running** on the remote machine (Omarchy OS laptop)
   - Native installation, OR
   - Docker container
2. **Network connectivity** between machines
3. **Ollama accessible** from the trading system machine

## Installation Options

### Option 1: Docker (Recommended)

#### Running Ollama in Docker

**Choose based on your hardware:**

##### GPU Mode (4GB+ VRAM, Compatible GPU)

```bash
# With GPU support (requires nvidia-docker2)
docker run -d \
  --name ollama \
  --gpus all \
  -p 11434:11434 \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -v ollama:/root/.ollama \
  ollama/ollama:latest
```

##### CPU-Only Mode (Limited GPU/VRAM, 16GB+ RAM)

**Use this if:**
- GPU has < 4GB VRAM (e.g., NVIDIA 940MX 2GB)
- Models crash with "exit status 2" on GPU
- You have 16GB+ system RAM

```bash
# Remove existing container if present
docker rm -f ollama

# Run in CPU-only mode
docker run -d \
  --name ollama \
  -p 11434:11434 \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -e OLLAMA_NUM_GPU=0 \
  -v ollama:/root/.ollama \
  ollama/ollama:latest
```

**Key settings:**
- `OLLAMA_NUM_GPU=0` → Forces pure CPU execution (no GPU offload)
- Models run entirely in system RAM
- Stable but slower (2-5 tokens/s typical on CPU)
- No GPU crashes or memory errors

**Verify CPU-only mode:**
```bash
docker logs ollama | grep -i "gpu"
# Should NOT show "CUDA" or "GPU layers loaded"
```

2. **Pull a model:**
   ```bash
   docker exec -it ollama ollama pull llama3
   ```

3. **Verify it's running:**
   ```bash
   curl http://localhost:11434/api/tags
   ```

#### Docker Compose (Alternative)

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  ollama:
    image: ollama/ollama
    container_name: ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama
    # Uncomment for GPU support
    # deploy:
    #   resources:
    #     reservations:
    #       devices:
    #         - driver: nvidia
    #           count: 1
    #           capabilities: [gpu]
    restart: unless-stopped

volumes:
  ollama:
```

Run with:
```bash
docker-compose up -d
docker exec -it ollama ollama pull llama3
```

### Option 2: Native Installation

Install Ollama natively on Omarchy OS:

```bash
# Download and install
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama service
ollama serve

# Pull a model
ollama pull llama3
```

## Finding Your Ollama Server IP Address

### On Omarchy OS (Ollama Server)

1. Find your machine's IP address:
   ```bash
   # Option 1: Using ip command
   ip addr show | grep "inet " | grep -v 127.0.0.1

   # Option 2: Using hostname
   hostname -I

   # Option 3: Using ifconfig
   ifconfig | grep "inet " | grep -v 127.0.0.1
   ```

2. Note the IP address (e.g., `192.168.1.100`)

3. Verify Ollama is accessible:
   ```bash
   # For native installation
   curl http://localhost:11434/api/tags

   # For Docker
   curl http://localhost:11434/api/tags
   # Or from outside the container
   docker exec ollama curl http://localhost:11434/api/tags
   ```

### On Trading System Machine

Test connectivity to Ollama server:
```bash
# Replace 192.168.1.11 with your Ollama server IP
curl http://192.168.1.11:11434/api/tags
```

**Example working connection:**
```bash
# Test with a simple prompt
curl -s http://192.168.1.11:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"phi3:mini","prompt":"Hello!"}'
```

If this works, you can proceed with configuration.

## Configuration

### 1. Environment Variables

Add these to your `.env` file or export them:

```bash
# Ollama Configuration
# Replace 192.168.1.11 with your actual Ollama server IP
export OLLAMA_BASE_URL="http://192.168.1.11:11434"
export OLLAMA_API_KEY="ollama"  # Optional, default is 'ollama'

# OLLAMA_MODEL is optional - system auto-detects and selects best model
# Only set if you want to force a specific model:
# export OLLAMA_MODEL="phi3:mini"

# Optional: Force Ollama provider (otherwise auto-detected)
export OPENAI_PROVIDER="ollama"
```

**Important**:
- Replace `192.168.1.11` with your actual Ollama server IP address
- **OLLAMA_MODEL is optional**: The system automatically fetches available models and selects the best one
- To see available models: `bundle exec rake ai:list_models`
- To force a specific model: Set `OLLAMA_MODEL` environment variable

### 2. Enable AI in Config

Edit `config/algo.yml`:

```yaml
ai:
  enabled: true
```

### 3. Verify Configuration

Test the connection:

```bash
bundle exec rake ai:test
```

Expected output:
```
Testing AI Client...

✅ AI client enabled
   Provider: ollama
   Available models: phi3:mini, llama3, mistral
   Selected model: llama3

Testing chat completion (model: llama3)...
✅ Chat completion successful:
   Response: AI integration working
```

**List available models:**
```bash
bundle exec rake ai:list_models
```

This will:
1. Fetch all available models from your Ollama server
2. Show which model is auto-selected as "best"
3. Display all available models with the selected one marked

## Available Ollama Models

### Automatic Model Selection

The system **automatically fetches and selects the best model** from your Ollama server. You don't need to set `OLLAMA_MODEL` unless you want to force a specific model.

**Model Selection Priority:**
1. Explicitly set model (`OLLAMA_MODEL` env var) - if available
2. Auto-selected "best" model based on priority:
   - **8B models** (best balance: capable + fast enough)
     - `llama3.1:8b`, `llama3.1:8b-instruct`, `llama3:8b`, `llama3:8b-instruct`
   - **7B models** (good for CPU-only with 16GB RAM)
     - `mistral:7b`, `mistral`, `mistral:instruct`
   - **3B models** (excellent for CPU-only, good balance)
     - `llama3.2:3b`, `llama3.2:3b-instruct`, `llama3:3b`
   - **Small models** (fastest for CPU-only)
     - `phi3:mini`, `phi3`, `phi3:medium`
     - `qwen2.5:1.5b-instruct`, `gemma:2b`, `gemma`
   - **Large models** (require GPU or lots of RAM)
     - `llama3:70b`, `llama3:70b-instruct`
     - `llama3`, `llama3:instruct`
   - **Code models** (not ideal for trading)
     - `codellama`, `codellama:instruct`
3. First available model (if no priority match)

**Note for CPU-Only Mode:**
- System prioritizes 3B models (`llama3.2:3b`) over 8B models for CPU-only setups
- Smaller models (`phi3:mini`, `qwen2.5:1.5b-instruct`) are preferred for speed

### List Available Models

```bash
# From trading system (recommended)
bundle exec rake ai:list_models

# On Ollama server
ollama list

# Or via API
curl http://192.168.1.11:11434/api/tags
```

**Example output:**
```
Found 3 model(s):
  1. phi3:mini
  2. llama3 ⭐ (selected)
  3. mistral

Best model: llama3
```

### Model Recommendations by Setup

#### For GPU Mode (4GB+ VRAM)
- **llama3.1:8b** - Best balance of capability and speed (recommended)
- **mistral:7b** - Good alternative 7B model
- **llama3.2:3b** - Faster, good for quick queries

#### For CPU-Only Mode (16GB RAM, Limited/No GPU)

**Best Models (in priority order):**

1. **llama3.2:3b** ⭐ (Recommended)
   - RAM: ~7GB
   - Speed: Good (3-5 tokens/s on CPU)
   - Capability: Excellent for trading analysis
   - Best balance for CPU-only setups

2. **phi3:mini**
   - RAM: ~5GB
   - Speed: Very fast (5-8 tokens/s on CPU)
   - Capability: Good for quick queries and coding
   - Fastest option for CPU-only

3. **qwen2.5:1.5b-instruct**
   - RAM: ~4GB
   - Speed: Very fast (8-12 tokens/s on CPU)
   - Capability: Good for simple queries
   - Lightest option, multiple models can run simultaneously

4. **mistral:7b** (If you have 16GB+ RAM)
   - RAM: ~10GB
   - Speed: Slower (2-3 tokens/s on CPU)
   - Capability: Excellent for complex analysis
   - Use only if you have sufficient RAM

**Models to Avoid on CPU-Only:**
- ❌ **llama3.1:8b** - May cause OOM on 16GB RAM systems
- ❌ **llama3:70b** - Requires GPU or 64GB+ RAM
- ❌ Any model > 7B parameters on CPU-only

**Quick Test:**
```bash
# Test a lightweight model
docker exec -it ollama ollama run phi3:mini <<< "Hello!"

# If successful, try larger models
docker exec -it ollama ollama run llama3.2:3b <<< "Analyze NIFTY"
```

## Usage

### Basic Usage

```ruby
client = Services::AI::OpenAIClient.instance

# Model is auto-selected (best available), or specify explicitly
response = client.chat(
  messages: [
    { role: 'user', content: 'Analyze today\'s trading performance' }
  ],
  # model: 'phi3:mini',  # Optional: override auto-selection
  temperature: 0.7
)

# Check which model was used
puts "Using model: #{client.selected_model}"
puts "Available models: #{client.available_models.join(', ')}"
```

### Trading Analysis

```ruby
# Analyze trading day using Ollama
analysis = Services::Ai::TradingAnalyzer.analyze_trading_day(date: Date.today)
```

### Streaming

```ruby
# Model auto-selected, or specify explicitly
client.chat_stream(
  messages: [
    { role: 'user', content: 'Explain trading strategy' }
  ]
  # model: 'llama3'  # Optional: override auto-selection
) do |chunk|
  print chunk
end
```

## Network Configuration

### Firewall Settings

If connection fails, check firewall on Ollama server:

```bash
# On Omarchy OS (Ollama server)
# Allow incoming connections on port 11434

# Using ufw (if installed)
sudo ufw allow 11434/tcp

# Using firewalld (if installed)
sudo firewall-cmd --add-port=11434/tcp --permanent
sudo firewall-cmd --reload

# Using iptables
sudo iptables -A INPUT -p tcp --dport 11434 -j ACCEPT
```

### Ollama Server Configuration

#### For Docker

Docker automatically exposes the port when using `-p 11434:11434`. To allow network access:

1. **Default Docker setup** (already exposes port):
   ```bash
   # Port is already exposed with -p 11434:11434
   # Accessible from network at http://<server-ip>:11434
   ```

2. **Bind to specific interface** (if needed):
   ```bash
   # Restart container binding to specific interface
   docker stop ollama
   docker rm ollama
   docker run -d \
     --name ollama \
     -p 0.0.0.0:11434:11434 \
     -v ollama:/root/.ollama \
     ollama/ollama
   ```

3. **Use reverse proxy** (Recommended for production):
   - Set up nginx/caddy reverse proxy
   - Add authentication
   - Expose only through proxy

4. **SSH Tunnel** (Most secure):
   ```bash
   # On trading system machine
   ssh -L 11434:localhost:11434 user@192.168.1.100

   # Then use localhost in config
   export OLLAMA_BASE_URL="http://localhost:11434"
   ```

#### For Native Installation

By default, Ollama only listens on `localhost`. To allow network access:

1. **Option 1: Bind to network interface** (Less secure)
   ```bash
   # Start Ollama with host binding
   OLLAMA_HOST=0.0.0.0:11434 ollama serve
   ```

2. **Option 2: Use reverse proxy** (Recommended for security)
   - Set up nginx/caddy reverse proxy
   - Add authentication
   - Expose only through proxy

3. **Option 3: SSH Tunnel** (Most secure)
   ```bash
   # On trading system machine
   ssh -L 11434:localhost:11434 user@192.168.1.100

   # Then use localhost in config
   export OLLAMA_BASE_URL="http://localhost:11434"
   ```

## Troubleshooting

### Connection Refused

**Problem**: Cannot connect to Ollama server

**Solutions**:
1. Verify Ollama is running: `curl http://192.168.1.100:11434/api/tags`
2. Check firewall settings
3. Verify IP address is correct
4. Check network connectivity: `ping 192.168.1.100`

### Model Not Found

**Problem**: Model specified doesn't exist on Ollama server

**Solutions**:
1. List available models: `bundle exec rake ai:list_models`
2. Pull the model: `ollama pull llama3` (on Ollama server) or `docker exec ollama ollama pull llama3`
3. Remove `OLLAMA_MODEL` env var to let system auto-select
4. Or update `OLLAMA_MODEL` to match an available model

### Slow Responses

**Problem**: Ollama responses are slow

**Solutions**:
1. Use smaller models (e.g., `llama3:8b` instead of `llama3:70b`)
2. Ensure Ollama server has sufficient RAM
3. Check network latency
4. Consider using GPU acceleration on Ollama server

### Provider Not Detected

**Problem**: System not using Ollama even though configured

**Solutions**:
1. Verify `OLLAMA_BASE_URL` is set: `echo $OLLAMA_BASE_URL`
2. Explicitly set provider: `export OPENAI_PROVIDER="ollama"`
3. Check logs for initialization errors

## Security Considerations

1. **Network Access**: Exposing Ollama to network can be a security risk
   - Use SSH tunnel for production
   - Add authentication if possible
   - Restrict access via firewall rules

2. **API Keys**: Ollama doesn't require authentication by default
   - Consider adding authentication layer
   - Use reverse proxy with auth

3. **Model Access**: Control which models are available
   - Only pull necessary models
   - Monitor resource usage

## Docker-Specific Commands

### Managing Ollama Docker Container

```bash
# Start container
docker start ollama

# Stop container
docker stop ollama

# View logs
docker logs ollama

# Pull a model
docker exec -it ollama ollama pull llama3

# List available models
docker exec -it ollama ollama list

# Remove container (keeps data in volume)
docker stop ollama
docker rm ollama

# Remove everything (including models)
docker stop ollama
docker rm ollama
docker volume rm ollama
```

### Docker with Persistent Storage

Models are stored in the Docker volume `ollama`. To backup:

```bash
# Backup models
docker run --rm -v ollama:/data -v $(pwd):/backup alpine tar czf /backup/ollama-backup.tar.gz /data

# Restore models
docker run --rm -v ollama:/data -v $(pwd):/backup alpine tar xzf /backup/ollama-backup.tar.gz -C /
```

### Docker Network Configuration

If running on same machine as trading system:

```bash
# Use Docker network
docker network create ollama-net

docker run -d \
  --name ollama \
  --network ollama-net \
  -p 11434:11434 \
  -v ollama:/root/.ollama \
  ollama/ollama

# Then use container name in config
export OLLAMA_BASE_URL="http://ollama:11434"
```

## Example .env Configuration

### For Docker on Remote Machine (Working Example)

```bash
# Ollama Configuration (for Omarchy OS laptop with Docker)
# Based on working connection at 192.168.1.11
OLLAMA_BASE_URL=http://192.168.1.11:11434
OLLAMA_MODEL=phi3:mini
OLLAMA_API_KEY=ollama

# Optional: Force Ollama provider
OPENAI_PROVIDER=ollama

# AI Integration
# (ai.enabled set in config/algo.yml)
```

**Note**: Your Ollama server is accessible at `192.168.1.11:11434` with model `phi3:mini` available.

### For Docker on Same Machine

```bash
# Ollama Configuration (Docker on same machine)
OLLAMA_BASE_URL=http://localhost:11434
# Or use Docker network
# OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODEL=llama3
OLLAMA_API_KEY=ollama
```

## Testing

### Quick Test

```bash
# Test connection (replace IP with your Ollama server IP)
curl http://192.168.1.11:11434/api/tags

# Test chat completion (OpenAI-compatible endpoint)
curl http://192.168.1.11:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3:mini",
    "messages": [{"role": "user", "content": "Say hello"}],
    "stream": false
  }'

# Test using Ollama's native API (working example)
curl -s http://192.168.1.11:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"phi3:mini","prompt":"Hello from Windows!"}'
```

**Expected output** (streaming JSON responses):
```json
{"model":"phi3:mini","created_at":"...","response":"G","done":false}
{"model":"phi3:mini","created_at":"...","response":"uten","done":false}
{"model":"phi3:mini","created_at":"...","response":" Tag","done":false}
...
{"model":"phi3:mini","created_at":"...","response":"","done":true}
```

### Docker-Specific Testing

```bash
# Test from inside container
docker exec ollama curl http://localhost:11434/api/tags

# Test from host
curl http://localhost:11434/api/tags

# Test from network (from trading system machine)
curl http://192.168.1.100:11434/api/tags
```

### Rails Console Test

```ruby
# In Rails console
client = Services::AI::OpenAIClient.instance
puts "Provider: #{client.provider}"  # Should show "ollama"
puts "Enabled: #{client.enabled?}"   # Should show true

# Test with your available model
response = client.chat(
  messages: [{ role: 'user', content: 'Hello!' }],
  model: ENV['OLLAMA_MODEL'] || 'phi3:mini'
)
puts response
```

**Working example configuration:**
```ruby
# With OLLAMA_BASE_URL=http://192.168.1.11:11434
# (OLLAMA_MODEL is optional - system auto-selects best model)

client = Services::AI::OpenAIClient.instance
# => Provider: ollama, Enabled: true

# Check available and selected models
puts "Available: #{client.available_models.join(', ')}"
puts "Selected: #{client.selected_model}"

# Use auto-selected model (or specify explicitly)
response = client.chat(
  messages: [{ role: 'user', content: 'Analyze trading performance' }]
  # model: 'phi3:mini'  # Optional: override auto-selection
)
```

## Performance Tips

### CPU-Only Mode

1. **Enable swap** - Keep 1-2GB swap enabled for stability
   ```bash
   sudo swapon -s  # Check swap status
   # Enable swap if needed (varies by distro)
   ```

2. **Use smaller context windows** - Reduce RAM usage
   - Default: 2048-4096 tokens
   - CPU-only: 1024-2048 tokens recommended

3. **Run multiple small models** - Can parallelize lightweight models
   - `phi3:mini` + `qwen2.5:1.5b-instruct` can run simultaneously
   - Each uses ~4-5GB RAM

4. **Monitor RAM usage:**
   ```bash
   docker stats ollama  # Watch container memory usage
   free -h  # Check system RAM
   ```

5. **Recommended models for CPU-only:**
   - `llama3.2:3b` (~7GB RAM) - Best balance
   - `phi3:mini` (~5GB RAM) - Fastest
   - `qwen2.5:1.5b-instruct` (~4GB RAM) - Lightest

### GPU Mode

1. **Model Selection**: Match model to GPU VRAM
   - 4GB VRAM: `llama3.2:3b`, `phi3:mini`
   - 8GB+ VRAM: `llama3.1:8b`, `mistral:7b`
   - 16GB+ VRAM: `llama3:70b`

2. **Monitor VRAM usage:**
   ```bash
   nvidia-smi  # Check GPU memory usage
   ```

3. **GPU Acceleration** (Docker):
   ```bash
   # Requires nvidia-docker2
   docker run -d \
     --name ollama \
     --gpus all \
     -p 11434:11434 \
     -v ollama:/root/.ollama \
     ollama/ollama
   ```

### General Tips

1. **Docker Resource Limits**: Set appropriate limits
   ```bash
   docker run -d \
     --name ollama \
     --memory="8g" \
     --cpus="4" \
     -p 11434:11434 \
     -v ollama:/root/.ollama \
     ollama/ollama
   ```

2. **Caching**: Models stay loaded in memory after first use

3. **Streaming**: Use `STREAM=true` for better UX (reduces perceived latency)

4. **Network Optimization**: Ensure low latency between machines

5. **Docker Volume Performance**: Use local SSD for better I/O
   ```bash
   # Use specific mount point for better performance
   docker run -d \
     --name ollama \
     -p 11434:11434 \
     -v /fast-ssd/ollama:/root/.ollama \
     ollama/ollama
   ```

## Next Steps

Once Ollama is configured:
1. Test with `rake ai:test`
2. Try trading analysis: `rake ai:analyze_day`
3. Integrate into your trading workflows
4. Monitor performance and adjust models as needed
