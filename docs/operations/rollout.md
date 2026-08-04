# Rollout Procedures

Complete guide for deploying and rolling out trading system updates.

## Pre-Rollout Checklist

### 1. Code Review
- [ ] All tests passing: `bundle exec rspec`
- [ ] RuboCop clean: `bundle exec rubocop`
- [ ] Security scan: `bundle exec brakeman --no-pager`
- [ ] Code review approved

### 2. Configuration Review
- [ ] Environment variables documented
- [ ] Database migrations tested
- [ ] Configuration changes reviewed
- [ ] Algo config validated

### 3. Database Preparation
- [ ] Migrations tested in staging
- [ ] Backup strategy in place
- [ ] Rollback plan documented
- [ ] Seed data verified

### 4. Service Dependencies
- [ ] Redis connectivity verified
- [ ] PostgreSQL connectivity verified
- [ ] DhanHQ credentials valid
- [ ] WebSocket endpoints accessible

## Rollout Steps

### Phase 1: Preparation
1. **Backup Database**
   ```bash
   pg_dump algo_scalper_api > backup_$(date +%Y%m%d).sql
   ```

2. **Verify Environment**
   ```bash
   bin/rails runner "puts Rails.env"
   bin/rails runner "puts AlgoConfig.fetch[:indices].count"
   ```

3. **Check Service Status**
   ```bash
   curl http://localhost:3000/api/health
   ```

### Phase 2: Deployment
1. **Stop Services** (if needed)
   ```bash
   # Services stop automatically on deploy
   # Or manually:
   bin/rails runner "Signal::Scheduler.instance.stop! if Signal::Scheduler.instance.running?"
   ```

2. **Run Migrations**
   ```bash
   bin/rails db:migrate
   ```

3. **Restart Services**
   ```bash
   bin/dev
   # Or in production:
   systemctl restart algo_scalper_api
   ```

### Phase 3: Verification
1. **Health Check**
   ```bash
   curl http://localhost:3000/api/health
   ```

2. **Service Status**
   ```ruby
   # In Rails console
   Signal::Scheduler.instance.running?
   Live::MarketFeedHub.instance.connected?
   Live::RiskManagerService.instance.running?
   ```

3. **Feed Verification**
   ```ruby
   Live::FeedHealthService.instance.status
   Live::TickCache.instance.all.count
   ```

## Post-Rollout

### Monitoring
- [ ] Monitor logs for errors
- [ ] Check feed health status
- [ ] Verify signal generation
- [ ] Monitor position tracking

### Rollback Procedure
If issues occur:

1. **Stop Services**
   ```bash
   # Stop all trading services
   ```

2. **Rollback Database** (if needed)
   ```bash
   bin/rails db:rollback
   ```

3. **Restore Previous Version**
   ```bash
   git checkout <previous-commit>
   bundle install
   bin/rails db:migrate
   ```

4. **Restart Services**
   ```bash
   bin/dev
   ```

## Strategy Rollout

### New Strategy Deployment
1. **Configuration Update**
   - Add strategy to `config/algo.yml`
   - Set `enabled: false` initially
   - Configure parameters

2. **Testing**
   - Test in paper mode
   - Verify signal generation
   - Check entry/exit logic

3. **Gradual Rollout**
   - Enable for one index first
   - Monitor for 1-2 days
   - Enable for all indices if successful

### Strategy Updates
1. **Parameter Changes**
   - Update `config/algo.yml`
   - Restart scheduler: `Signal::Scheduler.instance.restart!`
   - Monitor signal quality

2. **Code Changes**
   - Deploy code changes
   - Restart services
   - Monitor for issues

## Related Documentation

- [Health Checks](./health_checks.md)
- [Services Startup](../architecture/services_startup.md)

