# Repository Guidelines

## 🎯 Project Overview

The Algo Scalper API is a **production-ready autonomous trading system** for Indian index options trading. This document outlines the development guidelines, coding standards, and operational procedures for maintaining and extending the system.

---

## 📁 Project Structure & Module Organization

### **Core Architecture**
- **`app/`** - Rails API surface: controllers orchestrate requests, models encapsulate domain logic, jobs run async work via Solid Queue
- **`config/`** - Environment wiring: update `config/routes.rb` for new endpoints, add initializers under `config/initializers/`
- **`db/`** - Persistence layer: `*_schema.rb`, seeds, migrations under `db/migrate/`
- **`bin/`** - Project scripts: `bin/setup`, `bin/dev`, linters; favor these wrappers over direct `bundle exec` calls
- **`lib/`** - Shared abstractions and rake tasks; keep reusable utilities here instead of bloating controllers
- **`app/services/`** - Business logic services organized by domain:
  - `signal/` - Signal generation and analysis
  - `options/` - Option chain analysis
  - `capital/` - Capital allocation and management
  - `entries/` - Entry management and guards
  - `orders/` - Order placement and management
  - `live/` - Real-time services (WebSocket, risk management)
  - `risk/` - Risk management and circuit breakers

### **Key Services**
- **`Signal::Engine`** - Core signal generation with Supertrend + ADX analysis
- **`Options::ChainAnalyzer`** - Advanced option chain analysis with ATM focus
- **`Capital::Allocator`** - Dynamic position sizing with risk-based allocation
- **`Live::RiskManagerService`** - Comprehensive PnL tracking and trailing stops
- **`Live::MarketFeedHub`** - WebSocket market data management
- **`TickCache`** - High-performance tick storage singleton

---

## 🛠️ Build, Test, and Development Commands

### **Setup & Development**
```bash
# Complete setup (gems, database, server)
bin/setup

# Development server with live trading
bin/dev

# Database management
bin/rails db:prepare
bin/rails db:migrate
bin/rails db:seed
```

### **Code Quality**
```bash
# Format and lint
bin/rubocop

# Security scan
bin/brakeman --no-pager

# Run tests
bin/rails test
```

### **Trading System Management**
```bash
# Instrument management
bin/rails instruments:import
bin/rails instruments:status
bin/rails instruments:reimport

# Health check
curl http://localhost:3000/api/health
```

---

## 🎨 Coding Style & Naming Conventions

### **Ruby Standards**
- **Target**: Ruby 3.3.4 with omakase RuboCop rules in `.rubocop.yml`
- **Indentation**: Two-space indentation
- **Naming**: `snake_case` filenames, descriptive `CamelCase` classes/modules
- **Services**: PORO services under `app/services/` when logic grows beyond controllers/models

### **Class Naming Examples**
- `OrderBookUpdater` - Clear, descriptive class names
- `SyncPricesJob` - Job classes with action-oriented names
- `Signal::Engine` - Namespaced services for domain organization
- `Options::ChainAnalyzer` - Domain-specific service organization

### **File Organization**
- **Services**: `app/services/domain/service_name.rb`
- **Models**: `app/models/model_name.rb` with concerns in `app/models/concerns/`
- **Controllers**: `app/controllers/api/controller_name.rb`
- **Jobs**: `app/jobs/job_name.rb`

---

## 🧪 Testing Guidelines

### **Test Structure**
- **Framework**: Rails Minitest (default)
- **Location**: Tests under `test/` mirroring `app/` paths
- **Examples**: `test/controllers/orders_controller_test.rb`, `test/models/ticker_test.rb`

### **Test Execution**
```bash
# Full test suite
bin/rails test

# Targeted testing
bin/rails test test/models/ticker_test.rb
bin/rails test test/services/signal/engine_test.rb
```

### **Testing Best Practices**
- **Jobs**: Use `ActiveJob::TestHelper` for job testing
- **Edge Cases**: Cover Solid Cache/Queue interactions
- **API Responses**: Keep assertions against API responses explicit
- **Mocking**: Mock external API calls (DhanHQ) for reliable testing

---

## 📝 Commit & Pull Request Guidelines

### **Commit Messages**
- **Format**: Imperative summaries (e.g., `Add throttle guard to quotes API`)
- **Length**: First line ≤ 72 characters
- **Style**: Move from CamelCase (`InitialCommit`) to imperative summaries

### **Pull Request Requirements**
Each PR should include:
- **Intent**: Clear description of changes and purpose
- **Issues**: Link to tracking issues if applicable
- **Verification**: Manual verification steps:
  - `bin/rubocop` - Code style compliance
  - `bin/brakeman` - Security scan
  - `bin/rails test` - Test suite
- **Impact**: Mention schema or config impacts
- **Samples**: Include request/response samples for API changes

### **PR Best Practices**
- **Size**: Prefer small, reviewable changes
- **Scope**: Focus on single feature or bug fix
- **Documentation**: Update relevant documentation
- **Testing**: Include tests for new functionality

---

## 🔒 Security & Configuration Tips

### **Secrets Management**
- **Credentials**: Keep secrets in `config/credentials.yml.enc`
- **Master Key**: Never commit `config/master.key`
- **Environment**: Supply `RAILS_MASTER_KEY` for Docker/Kamal deploys
- **API Keys**: Use environment variables for DhanHQ credentials

### **Configuration Management**
- **Environment Variables**: Use `.env` for development
- **Production**: Use proper secret management in production
- **Database**: Ensure migrations are idempotent and reversible
- **Docker**: `bin/docker-entrypoint` auto-runs `db:prepare`

### **Security Best Practices**
- **API Keys**: Never commit API credentials
- **Database**: Use strong passwords and proper access controls
- **Logging**: Avoid logging sensitive information
- **Validation**: Validate all external inputs

---

## 🚀 Trading System Guidelines

### **Signal Generation**
- **Indicators**: Use established technical indicators (Supertrend, ADX)
- **Validation**: Implement comprehensive validation layers
- **Configuration**: Make parameters configurable via `config/algo.yml`
- **Logging**: Provide detailed signal analysis logs

### **Risk Management**
- **Position Limits**: Enforce maximum position limits
- **Capital Allocation**: Implement risk-based position sizing
- **Circuit Breakers**: Use circuit breakers for system protection
- **Monitoring**: Continuous PnL tracking and alerting

### **Order Management**
- **Idempotency**: Ensure order placement is idempotent
- **Validation**: Validate all order parameters
- **Error Handling**: Robust error handling for order failures
- **Logging**: Comprehensive order logging and tracking

---

## 🔧 Development Workflow

### **Feature Development**
1. **Planning**: Define requirements and acceptance criteria
2. **Implementation**: Follow coding standards and patterns
3. **Testing**: Write comprehensive tests
4. **Documentation**: Update relevant documentation
5. **Review**: Submit PR with proper description
6. **Deployment**: Follow deployment procedures

### **Bug Fixes**
1. **Reproduction**: Reproduce the issue consistently
2. **Root Cause**: Identify the root cause
3. **Fix**: Implement minimal fix
4. **Testing**: Ensure fix doesn't break existing functionality
5. **Documentation**: Update documentation if needed

### **Code Review Process**
1. **Automated Checks**: Ensure RuboCop and tests pass
2. **Manual Review**: Review code for logic, style, and security
3. **Testing**: Verify functionality works as expected
4. **Documentation**: Ensure documentation is updated
5. **Approval**: Approve and merge when ready

---

## 📊 Monitoring & Operations

### **Health Monitoring**
- **Health Endpoint**: Use `/api/health` for system status
- **Logging**: Monitor application logs for errors
- **Metrics**: Track key performance indicators
- **Alerts**: Set up alerts for critical issues

### **Production Operations**
- **Deployment**: Use proper deployment procedures
- **Rollback**: Have rollback procedures ready
- **Backup**: Regular database and configuration backups
- **Monitoring**: Continuous system monitoring

---

## 🎯 Best Practices Summary

### **Code Quality**
- ✅ Follow RuboCop guidelines
- ✅ Write comprehensive tests
- ✅ Use descriptive naming
- ✅ Keep functions focused and small
- ✅ Document complex logic

### **Trading System**
- ✅ Implement proper risk management
- ✅ Use comprehensive validation
- ✅ Log all trading decisions
- ✅ Monitor system health
- ✅ Handle errors gracefully

### **Operations**
- ✅ Use environment variables for configuration
- ✅ Implement proper logging
- ✅ Monitor system performance
- ✅ Have rollback procedures
- ✅ Regular backups

---

## 📚 Additional Resources

- **README.md**: Complete setup and usage guide
- **docs/dhanhq-client.md**: DhanHQ integration reference
- **docs/review.md**: Current implementation status
- **docs/requirements_gap_analysis.md**: Requirements analysis
- **config/algo.yml**: Trading configuration reference

---

## 🤝 Contributing

1. **Follow Guidelines**: Adhere to all guidelines in this document
2. **Code Quality**: Ensure RuboCop compliance and test coverage
3. **Documentation**: Update documentation for new features
4. **Testing**: Include tests for new functionality
5. **Review**: Submit PRs with proper descriptions and verification steps

---

## ⚠️ Important Notes

- **Trading Risk**: This system involves real money trading - use appropriate risk management
- **Testing**: Thoroughly test all changes before production deployment
- **Monitoring**: Continuously monitor system health and performance
- **Backup**: Regular backups of database and configuration
- **Security**: Never commit sensitive information like API keys or passwords