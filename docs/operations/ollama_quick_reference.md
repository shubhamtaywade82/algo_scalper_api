# Ollama Setup - Quick Reference

**Two-machine architecture for reliable Ollama inference.**

---

## 🖥️ Machine A - Server (Omarchy / Arch Laptop)

**Purpose:** Run Ollama 24×7, CPU-only, stable, never hangs.

### Docker Command (Copy-Paste Ready)

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

### Health Check

```bash
curl --max-time 2 http://localhost:11434/api/version
```

### Auto-Restart Watchdog (Crontab)

```
*/5 * * * * curl --max-time 2 http://localhost:11434/api/version || docker restart ollama
```

### Allowed Models

**Chat (pick ONE):**
- `phi3:mini` ✅ default
- `qwen2.5:1.5b-instruct`

**Embeddings (separate):**
- `nomic-embed-text`
- `all-minilm`

> ⚠️ **Never run chat + embeddings concurrently.**

---

## 💻 Machine B - Client (Windows / WSL / Dev Laptop)

**Purpose:** Send requests to Ollama server. Never blocks. Never hangs.

### Environment Setup

**Linux / WSL:**
```bash
export OLLAMA_HOST=http://192.168.0.200:11434
```

**Windows PowerShell:**
```powershell
$env:OLLAMA_HOST="http://192.168.0.200:11434"
```

**Rails (.env):**
```
OLLAMA_HOST=http://192.168.0.200:11434
```

> Replace `192.168.0.200` with your server IP (or Tailscale IP: `100.x.y.z`)

### Basic Usage

```ruby
require 'providers/ollama_client'

# Generate text
result = Providers::OllamaClient.generate("What is the trend?", model: "phi3:mini")

# Generate embeddings
embedding = Providers::OllamaClient.embed("Some text", model: "nomic-embed-text")

# Health check
healthy = Providers::OllamaClient.health_check
```

### With Lock Protection

```ruby
require 'providers/ollama_busy'

# Check if busy
return if Providers::OllamaBusy.locked?

# Use lock
result = Providers::OllamaBusy.with_lock do
  Providers::OllamaClient.generate(prompt)
end
```

### Simplest Approach (Recommended)

```ruby
sleep 0.5  # Small delay between calls
result = Providers::OllamaClient.generate(prompt)
```

---

## ✅ DO's and DON'Ts

### ✅ DO

- Serialize requests (one at a time)
- Add delays between calls (`sleep 0.5`)
- Use timeouts (built-in)
- Handle timeout errors gracefully
- Check `OllamaBusy.locked?` before calling

### ❌ DON'T

- Fire parallel LLM calls
- Mix embeddings + chat concurrently
- Retry blindly without delays
- Ignore timeout errors
- Call from multiple threads simultaneously

---

## 🔧 Troubleshooting

### Server Issues

**Container won't start:**
```bash
docker logs ollama
```

**Container hangs:**
```bash
docker restart ollama
```

**High CPU:**
- Verify `NUM_PARALLEL=1`
- Check only one model loaded
- Check for stuck client requests

### Client Issues

**Connection refused:**
- Verify `OLLAMA_HOST` is set
- Check server IP hasn't changed
- Use Tailscale for stable IP

**Timeout errors:**
- Check server not overloaded
- Verify no parallel requests
- Check server logs: `docker logs ollama`

**Lock never releases:**
- Auto-releases after 30s
- Manually release: `Providers::OllamaBusy.release_lock`
- Check Redis accessible

---

## 📚 Full Documentation

- **Machine A (Server):** [`docs/operations/ollama_setup_machine_a.md`](../operations/ollama_setup_machine_a.md)
- **Machine B (Client):** [`docs/operations/ollama_setup_machine_b.md`](../operations/ollama_setup_machine_b.md)

---

## 🧠 Mental Model

| Machine | Responsibility |
|---------|---------------|
| **Omarchy Laptop** | Inference engine only |
| **Client Laptop** | All logic, orchestration, retries |

**Decoupled:**
- If Ollama hangs → restart container (Machine A)
- If client fails → retry logic (Machine B)
- They are decoupled

---

## TL;DR (PIN THIS)

**Server:**
- CPU=4
- RAM=11GB
- 1 model at a time
- No parallelism

**Client:**
- Serialized calls
- Timeouts
- No embeddings + chat together
