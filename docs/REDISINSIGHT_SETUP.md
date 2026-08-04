# RedisInsight Setup Guide

This guide explains how to use RedisInsight with your `algo_scalper_api` Rails application.

## Overview

RedisInsight is a GUI tool for managing and monitoring Redis databases. Your Rails app uses Redis for:
- **PnL Cache** (`pnl:tracker:*` keys)
- **Tick Cache** (`tick:*:*` keys)
- **Sidekiq** job queues
- **ActiveCache** peak values
- **Daily Limits** tracking

## Current Redis Configuration

Your app connects to Redis using:
- **Default URL**: `redis://127.0.0.1:6379/0` (local Redis)
- **Environment Variable**: `REDIS_URL` (can override default)

## Setup Instructions

### 1. Start RedisInsight

```bash
# Start RedisInsight container
docker-compose -f docker-compose.redis-ui.yml up -d redisinsight

# Check if it's running
docker ps | grep redisinsight
```

### 2. Access RedisInsight

Open your browser and navigate to:
```
http://localhost:8001
```

### 3. Connect to Your Redis Instance

#### Option A: Connect to Local Redis (Recommended)

Since your Rails app uses local Redis (`127.0.0.1:6379`), you need to connect RedisInsight to it:

1. **On Mac/Windows (Docker Desktop)**:
   - Host: `host.docker.internal`
   - Port: `6379`
   - Database Alias: `algo_scalper_api_local`

2. **On Linux**:
   - Host: `172.17.0.1` (Docker bridge gateway) or your host IP
   - Port: `6379`
   - Database Alias: `algo_scalper_api_local`

   **Alternative for Linux**: Use host network mode:
   ```bash
   docker run -d \
     --name redisinsight \
     --network host \
     -v redisinsight-data:/db \
     redislabs/redisinsight:latest
   ```

#### Option B: Use Docker Redis (Optional)

If you want to use Docker Redis instead of local Redis:

1. Uncomment the `redis` service in `docker-compose.redis-ui.yml`
2. Update your `REDIS_URL` environment variable:
   ```bash
   export REDIS_URL=redis://localhost:6379/0
   ```
3. Start both services:
   ```bash
   docker-compose -f docker-compose.redis-ui.yml up -d
   ```

### 4. Connection Details

When adding a database in RedisInsight:

- **Host**: `host.docker.internal` (Mac/Windows) or `172.17.0.1` (Linux)
- **Port**: `6379`
- **Database Alias**: `algo_scalper_api_local`
- **Username**: (leave empty if not using Redis ACL)
- **Password**: (leave empty if not using Redis password)
- **Database Index**: `0` (default)

## Using RedisInsight

### Key Patterns to Explore

1. **PnL Keys**: `pnl:tracker:*`
   - View real-time PnL for active positions
   - Check `hwm_pnl` and `hwm_pnl_pct` values

2. **Tick Keys**: `tick:*:*`
   - View latest tick data for subscribed instruments
   - Format: `tick:{segment}:{security_id}`

3. **Sidekiq Keys**: `queue:*`, `stat:*`
   - Monitor background job queues
   - Check job statistics

4. **Peak Profit Keys**: `peak_profit:tracker:*`
   - View peak profit values cached by ActiveCache

### Useful Features

1. **Browser**: Browse keys by pattern
2. **CLI**: Execute Redis commands directly
3. **Profiler**: Monitor Redis commands in real-time
4. **Slow Log**: View slow commands
5. **Memory Analysis**: Analyze memory usage

## Troubleshooting

### Cannot Connect to Redis

**Problem**: RedisInsight can't connect to `127.0.0.1:6379`

**Solution**:
- **Mac/Windows**: Use `host.docker.internal` as host
- **Linux**: Use `172.17.0.1` or run RedisInsight with `--network host`
- **WSL2**: Use your Windows host IP (check with `ipconfig` on Windows)

### Find Your Host IP (Linux/WSL2)

```bash
# Get Docker bridge gateway IP
docker network inspect bridge | grep Gateway

# Or get your host IP
ip route show default | awk '/default/ {print $3}'
```

### Redis Not Running

```bash
# Check if Redis is running locally
redis-cli ping

# If not running, start it:
# Ubuntu/Debian:
sudo systemctl start redis-server

# macOS (Homebrew):
brew services start redis

# Or use Docker Redis (see Option B above)
```

## Integration with Your Rails App

Your Rails app already has a custom Redis UI at `/redis_ui` (development only). RedisInsight provides additional features:

- **Better visualization** of key structures
- **Performance monitoring** and profiling
- **Memory analysis** tools
- **Command execution** interface
- **Multi-database support**

Both tools complement each other:
- **RedisInsight**: Full-featured Redis management
- **Custom Redis UI**: Quick access from your Rails app

## Stopping RedisInsight

```bash
# Stop RedisInsight
docker-compose -f docker-compose.redis-ui.yml stop redisinsight

# Stop and remove container
docker-compose -f docker-compose.redis-ui.yml down

# Remove volumes (clears RedisInsight data)
docker-compose -f docker-compose.redis-ui.yml down -v
```

## Environment Variables

You can customize Redis connection via environment variables:

```bash
# In your .env or shell
export REDIS_URL=redis://localhost:6379/0

# Or for password-protected Redis
export REDIS_URL=redis://:password@localhost:6379/0
```

## Next Steps

1. Start RedisInsight: `docker-compose -f docker-compose.redis-ui.yml up -d redisinsight`
2. Open browser: `http://localhost:8001`
3. Add database connection using the details above
4. Explore your Redis keys and monitor your trading system!

