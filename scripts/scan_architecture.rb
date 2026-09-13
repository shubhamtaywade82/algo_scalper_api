#!/usr/bin/env ruby
# frozen_string_literal: true

# Standalone architecture scanner — no Rails, no gems required.
# Scans the codebase and regenerates architecture-dashboard/src/lib/architecture-data.ts
# in the exact schema expected by ArchDashboard.tsx / Sections.tsx.
#
# Usage:
#   ruby scripts/scan_architecture.rb                                    # stdout
#   ruby scripts/scan_architecture.rb > architecture-dashboard/src/lib/architecture-data.ts
#   ruby scripts/scan_architecture.rb architecture-dashboard/src/lib/architecture-data.ts  # write to file

REPO_ROOT = File.expand_path('..', __dir__)

# ─── Helpers ─────────────────────────────────────────────────────

def humanize(s)
  s.to_s.tr('_', ' ').gsub(/\b\w/, &:upcase)
end

# ─── Scanners ────────────────────────────────────────────────────

def first_comment(content)
  comment = content.lines.reject { |l| l.include?('frozen_string_literal') }
                   .find { |l| l.match?(/^\s*#/) }&.sub(/^\s*#\s*/, '')&.strip
  comment && comment.length > 80 ? "#{comment[0, 80]}..." : comment
end

def scan_services
  svcs = []
  bootstrap = File.join(REPO_ROOT, 'lib', 'trading_system', 'bootstrap.rb')
  if File.exist?(bootstrap)
    File.read(bootstrap).scan(/register\(\s*:(\w+)\s*,\s*([\w:]+)(?:,\s*[^)]*cadence:\s*['"]([^'"]*)['"])?/).each do |m|
      key, cls, cadence = m
      svcs << { key:, name: humanize(key), cls:, cadence: cadence || 'on_tick', category: guess_cat(key), status: 'active' }
    end
  end
  Dir.glob(File.join(REPO_ROOT, 'strategies', '*/manifest.yml')).each do |mf|
    key = File.basename(File.dirname(mf))
    svcs << { key:, name: humanize(key), cls: "strategies/#{key}", cadence: 'plugin', category: 'strategy', status: 'active' }
  end
  svcs.uniq { |s| s[:key] }
end

def scan_guards
  guards = []
  gd = File.join(REPO_ROOT, 'app', 'services', 'entries', 'guards')
  if Dir.exist?(gd)
    Dir.glob(File.join(gd, '*.rb')).each do |f|
      name = File.basename(f, '.rb').tr('_', ' ')
      desc = first_comment(File.read(f)) || name
      guards << { name: name, category: guess_guard_cat(name).capitalize, description: desc.tr("\n", ' '), isNew: false }
    end
  end
  vg = File.join(REPO_ROOT, 'app', 'services', 'signal', 'validation_gates.rb')
  if File.exist?(vg)
    File.read(vg).scan(/def\s+(check_\w+)/).flatten.each do |m|
      name = m.sub('check_', '').tr('_', ' ')
      guards << { name: name, category: 'Signal', description: "Signal validation: #{name}", isNew: false }
    end
  end
  guards
end

def scan_risk_rules
  rd = File.join(REPO_ROOT, 'app', 'services', 'risk', 'rules')
  return [] unless Dir.exist?(rd)
  Dir.glob(File.join(rd, '*_rule.rb')).map { |f| File.basename(f, '.rb') }
end

def scan_options_strategies
  sd = File.join(REPO_ROOT, 'app', 'services', 'options_buying', 'strategies')
  return [] unless Dir.exist?(sd)
  Dir.glob(File.join(sd, '*.rb')).map { |f| File.basename(f, '.rb') }
end

def scan_tables
  sf = File.join(REPO_ROOT, 'db', 'schema.rb')
  return [] unless File.exist?(sf)
  File.read(sf).scan(/create_table\s+"(\w+)"/).flatten.map do |t|
    { table: t, category: guess_table_cat(t).capitalize, isNew: false }
  end
end

def scan_endpoints
  rf = File.join(REPO_ROOT, 'config', 'routes.rb')
  return [] unless File.exist?(rf)
  eps = []
  content = File.read(rf)
  content.scan(/(get|post|put|patch|delete|match)\s+['"]([^'"]+)['"]/).each do |m|
    next if m[1].include?('/cable') || m[1].include?('rails/')
    eps << { method: m[0].upcase, path: m[1], isNew: false }
  end
  content.scan(/resources\s+:(\w+)/).flatten.each do |r|
    eps << { method: 'REST', path: "/#{r}", isNew: false }
    eps << { method: 'REST', path: "/#{r}/:id", isNew: false }
  end
  eps.uniq { |e| "#{e[:method]} #{e[:path]}" }
end

def scan_jobs
  yf = File.join(REPO_ROOT, 'config', 'recurring.yml')
  return [] unless File.exist?(yf)
  require 'yaml'
  yaml = YAML.safe_load_file(yf)
  jobs = yaml['production'] || yaml
  (jobs || {}).map do |key, cfg|
    cls = cfg['class'].to_s
    name = cls.empty? ? humanize(key) : cls.split('::').last
    {
      name:,
      schedule: humanize_schedule(cfg['schedule'].to_s),
      phase: guess_phase(cfg['schedule'].to_s)
    }
  end
end

def humanize_schedule(s)
  s = s.to_s
  s = s.delete_prefix('at ')
  s = s.sub('every Sunday at ', 'Sunday ')
  s = s.sub('Asia/Kolkata', 'IST')
  s = s.sub(/every weekday\z/, 'weekdays')
  s = s.sub(/ every weekday\z/, ' weekdays')
  s = s.sub(/\bevery day\z/, 'weekdays')
  s = s.sub('minutes', 'min')
  s = s.sub(/every hour at minute \d+/, 'every hour')
  s = s.sub(/between ([0-9:]+)(am|pm) and ([0-9:]+)(am|pm)/, '(\1\2-\3\4)')
  s = s.sub(' on weekdays', '')
  s.strip
end

def scan_ai
  dirs = [
    { p: 'app/services/ai/trading_bot', n: 'Trading Bot', d: 'Semi-autonomous scan-analyze-trade loop (Ollama-backed polling)', s: 'active' },
    { p: 'app/services/ai/trading_agent', n: 'Trading Agent', d: 'LLM tool-calling agent with REPL and audit trace', s: 'active' },
    { p: 'app/services/ai/calibration', n: 'AI Calibration', d: 'Weekly automated indicator calibration via LLM', s: 'active' },
    { p: 'app/services/ai/autonomous', n: 'Autonomous', d: 'LLM experiment runner with Observe-Think-Act loop', s: 'experimental' },
    { p: 'app/services/auto_exp', n: 'AutoExp', d: 'LLM-driven automated config experiments: plan - backtest - evaluate - apply', s: 'new' },
    { p: 'app/services/agents', n: 'Trading Orchestrator', d: 'LLM-chained MarketAnalyst - Strategy - Risk - OptionSelector pipeline', s: 'overlapping' }
  ]
  dirs.filter_map do |dir|
    fp = File.join(REPO_ROOT, dir[:p])
    next unless Dir.exist?(fp)
    components = Dir.glob(File.join(fp, '*.rb')).map { |f| File.basename(f, '.rb') }.sort
    next if components.empty?
    { name: dir[:n], path: dir[:p], components:, description: dir[:d], status: dir[:s] }
  end
end

def scan_env
  vars = {}
  env_file = File.join(REPO_ROOT, '.env')
  if File.exist?(env_file)
    File.read(env_file).scan(/^([A-Z_][A-Z0-9_]*)=/).flatten.each { |v| vars[v] = 'Yes' }
  end
  example_file = File.join(REPO_ROOT, '.env.example')
  if File.exist?(example_file)
    File.read(example_file).scan(/^([A-Z_][A-Z0-9_]*)=/).flatten.each { |v| vars[v] ||= 'Recommended' }
  end
  vars.map { |variable, required| { variable:, required:, purpose: '' } }
end

def guess_cat(k)
  n = k.to_s.downcase
  return 'market' if n.include?('feed') || n.include?('tick') || n.include?('market') || n.include?('option_chain')
  return 'signal' if n.include?('signal') || n.include?('scheduler') || n.include?('entry')
  return 'risk' if n.include?('risk') || n.include?('circuit') || n.include?('limit') || n.include?('guard')
  return 'position' if n.include?('position') || n.include?('trailing') || n.include?('pnl') || n.include?('heartbeat')
  return 'order' if n.include?('order') || n.include?('executor') || n.include?('bracket')
  return 'exit' if n.include?('exit') || n.include?('stop') || n.include?('profit')
  return 'cache' if n.include?('cache') || n.include?('warm') || n.include?('sync')
  return 'smc' if n.include?('smc') || n.include?('ict') || n.include?('structure')
  return 'strategy' if n.include?('strategy') || n.include?('deploy')
  return 'paper' if n.include?('paper') || n.include?('wallet')
  return 'candle' if n.include?('candle') || n.include?('ohlc')
  'stats'
end

def guess_guard_cat(n)
  n = n.downcase
  return 'timing' if n.include?('time') || n.include?('session') || n.include?('market_open')
  return 'trend' if n.include?('trend') || n.include?('direction') || n.include?('momentum')
  return 'volatility' if n.include?('volatility') || n.include?('atr') || n.include?('vix')
  return 'capital' if n.include?('capital') || n.include?('lot') || n.include?('size') || n.include?('quantity')
  return 'risk' if n.include?('risk') || n.include?('drawdown') || n.include?('loss') || n.include?('circuit')
  return 'signal' if n.include?('signal') || n.include?('confluence') || n.include?('quality')
  return 'market' if n.include?('market') || n.include?('regime') || n.include?('permission')
  return 'expiry' if n.include?('expiry') || n.include?('dte')
  'general'
end

def guess_table_cat(t)
  t = t.downcase
  return 'trading' if t.include?('position') || t.include?('signal') || t.include?('order') || t.include?('trade')
  return 'auth' if t.include?('token') || t.include?('session')
  return 'research' if t.include?('research') || t.include?('experiment') || t.include?('backtest')
  return 'system' if t.include?('setting') || t.include?('log') || t.include?('audit')
  return 'market' if t.include?('instrument') || t.include?('derivative') || t.include?('candle') || t.include?('holiday')
  return 'strategy' if t.include?('strategy') || t.include?('calibration') || t.include?('alpha')
  return 'ledger' if t.include?('ledger') || t.include?('journal') || t.include?('wallet')
  'other'
end

def guess_phase(s)
  s = s.downcase
  return 'weekly' if s.include?('sunday')
  return 'intraday' if s.include?('minute') || s.include?('min ')
  return 'post-close' if s.include?('pm')
  return 'pre-market' if s.include?('am')
  'intraday'
end

# ─── TypeScript Generator ─────────────────────────────────────────

def ts_esc(s) = s.to_s.gsub("'", "\\'").tr("\n", ' ')

def ts_arr(items, &)
  return '[]' unless items&.any?
  "[\n" + items.map { |i| "  #{yield(i)}" }.join(",\n") + "\n]"
end

def ts_str_arr(items)
  return '[]' unless items&.any?
  "[\n" + items.map { |i| "  '#{ts_esc(i)}'" }.join(",\n") + "\n]"
end

def generate_ts
  svcs = scan_services
  guards = scan_guards
  rules = scan_risk_rules
  opts = scan_options_strategies
  tables = scan_tables
  endpoints = scan_endpoints
  jobs = scan_jobs
  ai = scan_ai
  env = scan_env
  ts = Time.now.strftime('%Y-%m-%d %H:%M')

  deltas = [
    ['Registered Services', '19', svcs.size],
    ['Entry Guards', '33', guards.size],
    ['AI Subsystems', '4', ai.size],
    ['API Endpoints', '68', endpoints.size],
    ['Recurring Jobs', '31', jobs.size],
    ['DB Tables', '58', tables.size],
    ['Signal Paths', '2', '3 (all active)'],
    ['Risk Rules', '~8', rules.size]
  ].map do |metric, review, actual|
    direction = if actual.is_a?(Numeric)
if actual > review.to_i
'up'
else
actual < review.to_i ? 'down' : 'same'
end
                else
'up'
                end
    { metric:, review:, actual: actual.to_s, direction: }
  end

  <<~TYPESCRIPT
       // AUTO-GENERATED by scripts/scan_architecture.rb at #{ts}
       // DO NOT EDIT MANUALLY — regenerate with: ruby scripts/scan_architecture.rb > architecture-dashboard/src/lib/architecture-data.ts

       export interface Delta { metric: string; review: string; actual: string; direction: 'up' | 'down' | 'same'; }

       export const deltas: Delta[] = #{ts_arr(deltas) { |d| "{\n      metric: '#{ts_esc(d[:metric])}',\n      review: '#{ts_esc(d[:review])}',\n      actual: '#{ts_esc(d[:actual])}',\n      direction: '#{d[:direction]}'\n    }" }};

       export interface Service { key: string; name: string; cls: string; cadence: string; category: string; status: string; }
       export const services: Service[] = #{ts_arr(svcs) { |s| "{\n      key: '#{ts_esc(s[:key])}',\n      name: '#{ts_esc(s[:name])}',\n      cls: '#{ts_esc(s[:cls])}',\n      cadence: '#{ts_esc(s[:cadence])}',\n      category: '#{s[:category]}',\n      status: '#{s[:status]}'\n    }" }};

       export interface Guard { name: string; category: string; description: string; isNew: boolean; }
       export const entryGuards: Guard[] = #{ts_arr(guards) { |g| "{\n      name: '#{ts_esc(g[:name])}',\n      category: '#{ts_esc(g[:category])}',\n      description: '#{ts_esc(g[:description])}',\n      isNew: #{g[:isNew]}\n    }" }};

       export const riskRules: string[] = #{ts_str_arr(rules)};

       export const optionsBuyingStrategies: string[] = #{ts_str_arr(opts)};

       export interface DbTable { table: string; category: string; isNew: boolean; }
       export const dbTables: DbTable[] = #{ts_arr(tables) { |t| "{\n      table: '#{ts_esc(t[:table])}',\n      category: '#{ts_esc(t[:category])}',\n      isNew: #{t[:isNew]}\n    }" }};

       export interface ApiEndpoint { method: string; path: string; isNew: boolean; }
       export const apiEndpoints: ApiEndpoint[] = #{ts_arr(endpoints) { |e| "{\n      method: '#{ts_esc(e[:method])}',\n      path: '#{ts_esc(e[:path])}',\n      isNew: #{e[:isNew]}\n    }" }};

       export interface RecurringJob { name: string; schedule: string; phase: string; }
       export const recurringJobs: RecurringJob[] = #{ts_arr(jobs) { |j| "{\n      name: '#{ts_esc(j[:name])}',\n      schedule: '#{ts_esc(j[:schedule])}',\n      phase: '#{j[:phase]}'\n    }" }};

       export interface AiSubsystem { name: string; path: string; components: string[]; description: string; status: string; }
       export const aiSubsystems: AiSubsystem[] = #{ts_arr(ai) do |a| # {' '}
                                                      comps = a[:components].map { |c| "'#{ts_esc(c)}'" }.join(', ')
    "{\n      name: '#{ts_esc(a[:name])}',\n      path: '#{ts_esc(a[:path])}',\n      components: [#{comps}],\n      description: '#{ts_esc(a[:description])}',\n      status: '#{a[:status]}'\n    }"
                                                  end};

       // ─── Static Data (manually curated from repo audit, update as needed) ─────────

       export interface TechLayer { layer: string; technology: string; }
       export const techStack: TechLayer[] = #{ts_arr([
                                                        { layer: 'Language/Framework', technology: 'Ruby 3.3.4, Rails 8.1.3 (API-only)' },
                                                        { layer: 'Job Backend', technology: 'Solid Queue' },
                                                        { layer: 'WebSocket', technology: 'Solid Cable' },
                                                        { layer: 'Cache', technology: 'Solid Cache' },
                                                        { layer: 'Database', technology: 'PostgreSQL 15' },
                                                        { layer: 'Queue Store', technology: 'Redis 7' },
                                                        { layer: 'Broker API', technology: 'DhanHQ v2' },
                                                        { layer: 'LLM Runtime', technology: 'Ollama (local)' },
                                                        { layer: 'AI Framework', technology: 'ruby_llm-agents' },
                                                        { layer: 'Frontend', technology: 'Vite + SolidJS/Vue (main), Next.js (arch)' },
                                                        { layer: 'Deployment', technology: 'Docker Compose (6 processes)' }
                                                      ]) { |t| "{\n      layer: '#{ts_esc(t[:layer])}',\n      technology: '#{ts_esc(t[:technology])}'\n    }" }};

       export interface ProcessModel { process: string; command: string; role: string; }
       export const processModel: ProcessModel[] = #{ts_arr([
                                                              { process: 'web', command: 'bin/rails server (Puma)', role: 'Rails API — REST endpoints, WebSocket cable, static assets' },
                                                              { process: 'jobs', command: 'bin/jobs (Solid Queue)', role: 'Background jobs — scheduled tasks, research pipeline' },
                                                              { process: 'dashboard', command: 'Vite / nginx :3000', role: 'Main trading dashboard — positions, signals, option chain' },
                                                              { process: 'arch-dashboard', command: 'Next.js standalone :3003', role: 'Architecture dashboard — live codebase visualization' }
                                                            ]) { |p| "{\n      process: '#{ts_esc(p[:process])}',\n      command: '#{ts_esc(p[:command])}',\n      role: '#{ts_esc(p[:role])}'\n    }" }};

       export const indexParams = #{ts_arr([
                                             { index: 'NIFTY', capital: '30%', premium: '30-160', risk: '1%', maxTrades: 3 },
                                             { index: 'BANKNIFTY', capital: '30%', premium: '60-650', risk: '2%', maxTrades: 3 },
                                             { index: 'SENSEX', capital: '30%', premium: '40-320', risk: '2%', maxTrades: 3 }
                                           ]) { |i| "{\n      index: '#{ts_esc(i[:index])}',\n      capital: '#{ts_esc(i[:capital])}',\n      premium: '#{ts_esc(i[:premium])}',\n      risk: '#{ts_esc(i[:risk])}',\n      maxTrades: #{i[:maxTrades]}\n    }" }};

       export const smcDetectors: string[] = #{ts_str_arr(%w[
                                                            fvg order_blocks liquidity structure
                                                            swing_structure internal_structure premium_discount
                                                          ])};

       export const lockedPaths: string[] = #{ts_str_arr([
                                                           'DhanHQ gateways/adapters',
                                                           'WebSocket/market-data/caching (market_feed_hub, order_update_hub, redis_tick_cache)',
                                                           'Position lifecycle (active_cache, serializer, positions/states/*)',
                                                           'Order execution plumbing (orders/commands/*, executor, entry_manager, FSM, bracket placer)',
                                                           'Exit engine (exit_engine, trailing_engine, mfe_exit_engine, gamma_trailing_engine)',
                                                           'Risk-manager plumbing',
                                                           'Process wiring (lib/trading_system/, jobs, controllers/routes)',
                                                           'Instrument/chain plumbing (instrument.rb, chain_analyzer.rb, strike_selector.rb)'
                                                         ])};

       export const alphaPaths: string[] = #{ts_str_arr([
                                                          'signal/*',
                                                          'indicators/*',
                                                          'market_state/*', 'market_context/*',
                                                          'smc/*',
                                                          'trading/trend_scorer.rb',
                                                          'trading/permission_resolver.rb',
                                                          'entries/entry_guard.rb, entry_filter_engine, entry_guard_pipeline',
                                                          'All entries/guards/*',
                                                          'orders/analyzer.rb, adjuster.rb, adaptive_trailing.rb, gamma_detector.rb',
                                                          'All risk/*, all policies/*',
                                                          'capital/allocator.rb',
                                                          'options/flow_analyzer.rb, strike_qualification/*',
                                                          'options/historical_calibration_engine.rb',
                                                          'auto_exp/* (new experiment framework)',
                                                          'backtest/* (new backtest subsystem)',
                                                          'event_store/* (new decision audit trail)'
                                                        ])};

       export const tokenFallback: string[] = #{ts_str_arr([
                                                             'Authority server HTTP GET ($TRADER_API_BASE_URL/auth/dhan/token, 60s cache)',
                                                             'TOTP auto-refresh (DHAN_PIN + DHAN_TOTP_SECRET via rotp gem)',
                                                             'Static ENV["DHAN_ACCESS_TOKEN"] fallback'
                                                           ])};

       export const bootSequence: string[] = #{ts_str_arr([
                                                            'Rails initializers wire DhanHQ config, gateway (paper/live), token bootstrap',
                                                            'Live::PositionSyncService.instance.force_sync! - reconcile DB vs broker',
                                                            'Market::VixGate.evaluate! at boot (VIX entry gating)',
                                                            'supervisor.start_all - launches all daemon services'
                                                          ])};

       export const docDebt: string[] = #{ts_str_arr([
                                                       'README.md describes 11-service supervisor; actual registry has 16 entries',
                                                       'Signal::Scheduler IS still registered - coexists with Strategies::Manager',
                                                       'Entry guard count documented as 20; actual directory has #{guards.size} guard files',
                                                       'docs/ has ~200+ files, many under docs/archive/ (superseded)',
                                                       '~200 backtest artifact files committed to lib/ (should be in .gitignore)'
                                                     ])};

       export const criticalInvariants: string[] = #{ts_str_arr([
                                                                  'DhanHQ only - no other broker integration exists or should be added',
                                                                  'exit_engine.rb is the single source of truth for exit placement',
                                                                  'TickQuery returns nil (not zero) on cache miss',
                                                                  'Position sizing must go through capital/',
                                                                  'Solid Queue only, never Sidekiq',
                                                                  'Redis tick cache is write-through; must degrade gracefully if Redis is down',
                                                                  'Never write to DB from inside a WebSocket tick handler',
                                                                  'Live::Gateway is deprecated - use Orders::GatewayLive directly',
                                                                  'Gateway (paper/live) is chosen once at boot - changing LIVE_TRADING requires restart',
                                                                  'Strategies::Loader uses load (eval) for strategy code - security scanning is mandatory'
                                                                ])};

       export interface EnvVar { variable: string; required: string; purpose: string; }
       export const envVars: EnvVar[] = #{ts_arr(env) { |e| "{\n      variable: '#{ts_esc(e[:variable])}',\n      required: '#{ts_esc(e[:required])}',\n      purpose: '#{ts_esc(e[:purpose])}'\n    }" }};

       export interface NewSubsystem { name: string; path: string; fileCount: number; description: string; }
       export const newSubsystems: NewSubsystem[] = #{ts_arr([
                                                               { name: 'Strategies Plugin System', path: 'app/services/strategies/', fileCount: 11, description: 'Hot-loadable, versioned, DB-backed strategy plugins with SHA-256 checksum verification, security scanning, deploy pipeline, and lifecycle management' },
                                                               { name: 'AutoExp', path: 'app/services/auto_exp/', fileCount: 6, description: 'LLM-driven automated config experiments: plan - backtest - evaluate - apply. Full experiment lifecycle.' },
                                                               { name: 'EventStore', path: 'app/services/event_store/', fileCount: 3, description: 'Publisher, DecisionTrace, ReplayEngine for full decision audit trail' },
                                                               { name: 'Policies', path: 'app/services/policies/', fileCount: 4, description: 'Explicit BasePolicy, EntryPolicy, ExitPolicy, RiskPolicy classes' },
                                                               { name: 'Market Context', path: 'app/services/market_context/', fileCount: 5, description: 'ParticipationAnalyzer, RegimeComposer, RegimeSnapshot, StructureAnalyzer, VolatilityAnalyzer' },
                                                               { name: 'Market State', path: 'app/services/market_state/', fileCount: 4, description: 'VolatilityDetector, MarketStateEngine, FeatureStore, TrendDetector' },
                                                               { name: 'Core EventBus', path: 'app/services/core/event_bus.rb', fileCount: 1, description: 'Singleton pub/sub for candle_closed and strategy_status_change events' },
                                                               { name: 'Backtest Engine', path: 'app/services/backtest/', fileCount: 14, description: 'Full backtest subsystem: engine, market replayer, option trade simulator, strategy adapter, SMC replay, metrics, report' },
                                                               { name: 'Data Quality', path: 'app/services/data_quality/', fileCount: 2, description: 'TickStalenessSampler + DailyCheck for monitoring feed/data health' }
                                                             ]) { |s| "{\n      name: '#{ts_esc(s[:name])}',\n      path: '#{ts_esc(s[:path])}',\n      fileCount: #{s[:fileCount]},\n      description: '#{ts_esc(s[:description])}'\n    }" }};

       export interface Concern { severity: string; title: string; description: string; }
       export const concerns: Concern[] = #{ts_arr([
                                                     { severity: 'critical', title: 'Triple Signal Path Coexistence', description: 'Signal::Scheduler (30s polling) AND Strategies::Manager (2s EventBus) AND Signal::Engine all registered and running simultaneously. Manager says it "replaces" Scheduler but both start. Risk of duplicate/conflicting signals.' },
                                                     { severity: 'high', title: 'Duplicate recurring job in dev', description: 'dhan_auto_ip_sync appears twice in recurring.yml development section. SolidQueue may silently deduplicate.' },
                                                     { severity: 'high', title: '200+ backtest artifacts in git', description: 'lib/trading_system/algo_trading_system/backtest_results/ contains ~200 generated files (JSON, CSV, HTML) committed to repo.' },
                                                     { severity: 'medium', title: 'Strategy eval security', description: 'Strategies::Loader uses load (eval) for strategy code. Security scanning exists but risk surface is significant.' },
                                                     { severity: 'medium', title: 'Ruby 3.4+ CSV gem', description: 'Gemfile adds csv gem with require: false for Ruby 3.4+ compatibility. May fail if code does require csv directly.' },
                                                     { severity: 'low', title: 'Recent token re-encryption', description: 'Migration reencrypt_existing_dhan_access_tokens implies a security fix was applied to stored tokens.' }
                                                   ]) { |c| "{\n      severity: '#{ts_esc(c[:severity])}',\n      title: '#{ts_esc(c[:title])}',\n      description: '#{ts_esc(c[:description])}'\n    }" }};
  TYPESCRIPT
end

# ─── Main ─────────────────────────────────────────────────────────

output = generate_ts

if ARGV[0]
  File.write(ARGV[0], output)
  puts "[scan] Wrote #{ARGV[0]} (#{output.lines.count} lines)"
else
  print output
end