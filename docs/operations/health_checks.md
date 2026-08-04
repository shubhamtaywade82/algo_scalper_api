# 🏥 Health Check Scripts

This directory contains comprehensive health check scripts to ensure the Algo Scalper API is ready to run before starting.

## 📋 Available Scripts

### 1. `bin/pre_startup_check`
**Purpose**: Basic checks before loading Rails
**Usage**: `ruby bin/pre_startup_check`
**Checks**:
- Ruby version compatibility
- Bundler availability
- Gemfile.lock existence
- Environment configuration
- Database configuration syntax
- Redis connectivity
- Disk space
- File permissions
- Network connectivity
- Critical files presence

### 2. `bin/health_check`
**Purpose**: Full application health check (requires Rails)
**Usage**: `bundle exec ruby bin/health_check`
**Checks**:
- Database connection
- Redis connection
- DhanHQ configuration
- Instrument data availability
- Derivative data availability
- WebSocket configuration
- File permissions
- Disk space
- Memory usage
- Environment variables
- Gem dependencies
- Database schema
- Models functionality
- Services functionality

### 3. `bin/startup_check`
**Purpose**: Comprehensive startup validation
**Usage**: `./bin/startup_check`
**Process**:
1. Runs pre-startup checks
2. Validates bundle installation
3. Checks database connection and migrations
4. Runs full health check
5. Tests Rails loading capability

## 🚀 Quick Start

```bash
# Run comprehensive startup check
./bin/startup_check

# If all checks pass, start the application
bin/dev
```

## 📊 Exit Codes

- **0**: All checks passed, application is healthy
- **1**: Critical issues found, application is not ready

## ⚠️ Common Issues

### Missing Environment Variables
```bash
# Copy environment template
cp .env.example .env

# Edit with your credentials
nano .env
```

### Missing Instruments
```bash
# Import instruments
bin/rails instruments:import
```

### Database Issues
```bash
# Run migrations
bin/rails db:migrate

# Reset database (development only)
bin/rails db:reset
```

### Redis Connection Issues
```bash
# Start Redis server
redis-server

# Or check Redis status
redis-cli ping
```

## 🔧 Customization

You can modify the health check scripts to:
- Add custom checks
- Modify warning thresholds
- Include additional validations
- Change output format

## 📝 Integration

These scripts can be integrated into:
- CI/CD pipelines
- Docker startup scripts
- Monitoring systems
- Deployment processes

## 🎯 Best Practices

1. **Always run health checks before starting** the application
2. **Fix all errors** before proceeding
3. **Address warnings** when possible
4. **Monitor regularly** in production
5. **Update checks** as the application evolves
