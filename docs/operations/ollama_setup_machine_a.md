# Ollama Server Setup - Machine A

**Purpose:** Run Ollama 24×7, CPU-only, stable, never hangs.

**Hardware:** i7 7th gen (8 threads), 16 GB RAM, NVIDIA 940MX (ignored), Wi-Fi laptop

---

## A1. Ollama Docker Container (FINAL)

> ⚠️ **Do not change these values unless hardware changes.**

```bash
docker rm -f ollama

docker run -d \
  --name ollama \
  --restart unless-stopped \
  -p 11434:11434 \
  --cpus="4.0" \
  --memory="11g" \
  --memory-swap="11g" \
  -e OLLAMA_HOST=0.0.0.0:11434 \
  -e OLLAMA_NUM_GPU=0 \
  -e OLLAMA_NUM_THREADS=4 \
  -e OLLAMA_NUM_PARALLEL=1 \
  -e OLLAMA_MAX_LOADED_MODELS=1 \
  -e OLLAMA_KEEP_ALIVE=24h \
  -v ollama:/root/.ollama \
  ollama/ollama:latest
```

### Why This Works

| Setting | Reason |
|---------|--------|
| `--cpus=4` | Prevent kernel/network starvation |
| `NUM_THREADS=4` | Avoid CPU lockups |
| `NUM_PARALLEL=1` | No concurrent inference |
| `MAX_LOADED_MODELS=1` | Prevent RAM thrash |
| `memory=11g` | No swap storms |
| `KEEP_ALIVE=24h` | No reload pauses |

---

## A2. Allowed Models (STRICT)

### Chat Models (pick ONE at a time)

- `phi3:mini` ✅ **default**
- `qwen2.5:1.5b-instruct`

### Embedding Models (run separately, not concurrently)

- `nomic-embed-text`
- `all-minilm`

> ⚠️ **Never run chat + embeddings concurrently on this machine.**

---

## A3. Health Check (Server)

Run locally on the Ollama machine:

```bash
curl --max-time 2 http://localhost:11434/api/version
```

If this fails → Ollama is stuck.

### Optional Watchdog (Recommended)

Add to crontab (`crontab -e`):

```
*/5 * * * * curl --max-time 2 http://localhost:11434/api/version || docker restart ollama
```

This automatically restarts the container if it becomes unresponsive.

---

## A4. What This Machine Must NOT Do

❌ No Rails  
❌ No trading logic  
❌ No parallel requests  
❌ No embeddings + chat together  

**This machine is ONLY inference.**

---

## A5. Network Configuration

### Local Network (Default)

Server listens on `0.0.0.0:11434` (all interfaces).

Client connects via: `http://192.168.0.200:11434` (replace with actual IP)

### Tailscale (Optional but Recommended)

For stable IP addresses without DHCP issues:

**On server:**

```bash
sudo tailscale up
```

Then client uses: `http://100.x.y.z:11434` (Tailscale IP)

No LAN issues. No DHCP pain.

---

## A6. Troubleshooting

### Container Won't Start

```bash
docker logs ollama
```

Check for:
- Port conflicts (another service on 11434)
- Insufficient memory
- Docker daemon issues

### Container Hangs

```bash
docker restart ollama
```

If hangs persist:
1. Check system load: `htop`
2. Check memory: `free -h`
3. Reduce `--cpus` or `--memory` if needed

### High CPU Usage

Expected during inference. If idle CPU is high:
- Check `NUM_PARALLEL=1` is set
- Verify only one model is loaded
- Check for stuck requests from clients

---

## A7. Model Management

### Pull Models

```bash
docker exec ollama ollama pull phi3:mini
docker exec ollama ollama pull nomic-embed-text
```

### List Models

```bash
docker exec ollama ollama list
```

### Remove Models

```bash
docker exec ollama ollama rm <model-name>
```

---

## A8. Monitoring

### Check Container Status

```bash
docker ps | grep ollama
```

### View Resource Usage

```bash
docker stats ollama
```

### Check Logs

```bash
docker logs -f ollama
```

---

## Summary

**Server Configuration:**

- CPU: 4 cores
- RAM: 11GB
- 1 model at a time
- No parallelism
- Auto-restart on failure
- Health check every 5 minutes
