'use client';

import React, { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import {
  services,
  entryGuards,
  aiSubsystems,
  recurringJobs,
  dbTables,
  apiEndpoints,
  envVars,
  criticalInvariants,
  indexParams,
  optionsBuyingStrategies,
  smcDetectors,
  riskRules,
  lockedPaths,
  alphaPaths,
  tokenFallback,
  docDebt,
  type Service,
} from '@/lib/architecture-data';
import {
  Zap,
  Shield,
  Layers,
  BarChart3,
  Database,
  FileCode,
  Brain,
  Eye,
  Settings,
  Globe,
  Clock,
  GitBranch,
  ShieldCheck,
  Lock,
  Unlock,
  AlertTriangle,
  Workflow,
  ChevronRight,
} from 'lucide-react';

// ─── Color Maps (re-exported from main or inline) ──────────────────
const categoryColors: Record<string, string> = {
  market: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30',
  signal: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
  risk: 'bg-red-500/20 text-red-400 border-red-500/30',
  position: 'bg-sky-500/20 text-sky-400 border-sky-500/30',
  order: 'bg-violet-500/20 text-violet-400 border-violet-500/30',
  paper: 'bg-gray-500/20 text-gray-400 border-gray-500/30',
  exit: 'bg-rose-500/20 text-rose-400 border-rose-500/30',
  cache: 'bg-cyan-500/20 text-cyan-400 border-cyan-500/30',
  recon: 'bg-teal-500/20 text-teal-400 border-teal-500/30',
  stats: 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30',
  smc: 'bg-purple-500/20 text-purple-400 border-purple-500/30',
  strategy: 'bg-orange-500/20 text-orange-400 border-orange-500/30',
  pnl: 'bg-lime-500/20 text-lime-400 border-lime-500/30',
  candle: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
  chain: 'bg-fuchsia-500/20 text-fuchsia-400 border-fuchsia-500/30',
};

const guardCategoryColors: Record<string, string> = {
  Core: 'bg-zinc-500/20 text-zinc-300 border-zinc-500/30',
  Risk: 'bg-red-500/20 text-red-400 border-red-500/30',
  Policy: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
  Quality: 'bg-violet-500/20 text-violet-400 border-violet-500/30',
  Validation: 'bg-sky-500/20 text-sky-400 border-sky-500/30',
  Data: 'bg-cyan-500/20 text-cyan-400 border-cyan-500/30',
  Timing: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
  Structure: 'bg-purple-500/20 text-purple-400 border-purple-500/30',
  Market: 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30',
  Capital: 'bg-lime-500/20 text-lime-400 border-lime-500/30',
  Volatility: 'bg-rose-500/20 text-rose-400 border-rose-500/30',
  Volume: 'bg-teal-500/20 text-teal-400 border-teal-500/30',
  Pricing: 'bg-orange-500/20 text-orange-400 border-orange-500/30',
  Research: 'bg-indigo-500/20 text-indigo-400 border-indigo-500/30',
};

const phaseColors: Record<string, string> = {
  'pre-market': 'bg-sky-500/20 text-sky-400',
  intraday: 'bg-emerald-500/20 text-emerald-400',
  'post-close': 'bg-amber-500/20 text-amber-400',
  weekly: 'bg-violet-500/20 text-violet-400',
};

const methodColors: Record<string, string> = {
  GET: 'bg-emerald-500/20 text-emerald-400',
  POST: 'bg-amber-500/20 text-amber-400',
  PUT: 'bg-sky-500/20 text-sky-400',
  PATCH: 'bg-violet-500/20 text-violet-400',
  DELETE: 'bg-red-500/20 text-red-400',
  WS: 'bg-cyan-500/20 text-cyan-400',
  MOUNT: 'bg-purple-500/20 text-purple-400',
};

// ─── Signal Generation Section ─────────────────────────────────────
export function SignalSection() {
  return (
    <div className="space-y-4">
      {/* CRITICAL WARNING */}
      <Card className="bg-red-500/5 border-red-500/20">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-zinc-400">
              <p className="text-red-400 font-semibold mb-1">Triple Signal Path Coexistence</p>
              <p>All three signal paths are <span className="text-red-400 font-semibold">simultaneously registered and running</span> in the daemon supervisor. Strategies::Manager comment says it &quot;replaces&quot; Signal::Scheduler, but both are started. Risk of duplicate or conflicting signals.</p>
            </div>
          </div>
        </CardContent>
      </Card>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Path A */}
        <Card className="bg-zinc-900/50 border-amber-500/30">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-amber-400 text-sm uppercase tracking-wider">Path A: Legacy Engine</CardTitle>
              <Badge variant="outline" className="bg-amber-500/10 text-amber-400 border-amber-500/30 text-[10px]">938 lines</Badge>
            </div>
            <CardDescription className="text-zinc-400 font-mono text-xs">Signal::Engine</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-zinc-400">
            <p>Supertrend options-buying pipeline</p>
            <p>1m flip, chop gate, ATM strike, EntryGuard</p>
            <p className="text-amber-400/80 italic">Still present, still generates signals</p>
          </CardContent>
        </Card>
        {/* Path B */}
        <Card className="bg-zinc-900/50 border-amber-500/30">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-amber-400 text-sm uppercase tracking-wider">Path B: Scheduler</CardTitle>
              <Badge variant="outline" className="bg-amber-500/10 text-amber-400 border-amber-500/30 text-[10px]">Registered</Badge>
            </div>
            <CardDescription className="text-zinc-400 font-mono text-xs">Signal::Scheduler</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-zinc-400">
            <p>30s period, 5s inter-index delay</p>
            <p><code className="text-xs font-mono text-amber-400/80">:signal_scheduler</code> IS registered in bootstrap.rb</p>
            <p className="text-red-400/80 italic">Qwen review wrongly said it was not registered</p>
          </CardContent>
        </Card>
        {/* Path C */}
        <Card className="bg-zinc-900/50 border-emerald-500/30">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-emerald-400 text-sm uppercase tracking-wider">Path C: Strategy Mgr</CardTitle>
              <Badge variant="outline" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/30 text-[10px]">Primary</Badge>
            </div>
            <CardDescription className="text-zinc-400 font-mono text-xs">Strategies::Manager</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-zinc-400">
            <p>2s control loop + per-strategy runners</p>
            <p>EventBus-driven, 10s heartbeat</p>
            <p className="text-emerald-400/80">SHA-256 verified, security scanning</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

// ─── Service Registry Section ──────────────────────────────────────
export function ServiceRegistrySection() {
  const [filter, setFilter] = useState<string>('all');
  const categories = ['all', ...new Set(services.map(s => s.category))];
  const filtered = filter === 'all' ? services : services.filter(s => s.category === filter);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {categories.map(cat => (
          <button
            key={cat}
            onClick={() => setFilter(cat)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-all ${
              filter === cat
                ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                : 'bg-zinc-800/50 text-zinc-500 border-zinc-700 hover:border-zinc-600'
            }`}
          >
            {cat === 'all' ? `All (${services.length})` : `${cat} (${services.filter(s => s.category === cat).length})`}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {filtered.map(svc => (
          <Card key={svc.key} className="bg-zinc-900/50 border-zinc-800 hover:border-zinc-600 transition-all group">
            <CardContent className="p-4">
              <div className="flex items-start justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span className={`w-2 h-2 rounded-full ${svc.status === 'active' ? 'bg-emerald-400 animate-pulse' : svc.status === 'legacy' ? 'bg-amber-400' : 'bg-zinc-600'}`} />
                  <span className="text-sm font-semibold text-zinc-200 group-hover:text-white transition-colors">{svc.name}</span>
                </div>
                <Badge variant="outline" className={`text-[10px] border ${categoryColors[svc.category] || 'bg-zinc-800 text-zinc-400 border-zinc-700'}`}>
                  {svc.category}
                </Badge>
              </div>
              <p className="text-xs text-zinc-500 font-mono mb-1">{svc.cls}</p>
              <p className="text-xs text-zinc-400">{svc.cadence}</p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}


// ─── Entry Guards Section ──────────────────────────────────────────
export function EntryGuardsSection() {
  const [filter, setFilter] = useState<string>('all');
  const categories = ['all', ...new Set(entryGuards.map(g => g.category))];
  const filtered = filter === 'all' ? entryGuards : entryGuards.filter(g => g.category === filter);

  // Count guards per category for the mini bar chart
  const catCounts = entryGuards.reduce<Record<string, number>>((acc, g) => {
    acc[g.category] = (acc[g.category] || 0) + 1;
    return acc;
  }, {});
  const maxCount = Math.max(...Object.values(catCounts));

  return (
    <div className="space-y-4">
      {/* Category distribution bar */}
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-xs text-zinc-400 uppercase tracking-wider">Guard Distribution by Category</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col gap-1.5">
            {Object.entries(catCounts)
              .sort((a, b) => b[1] - a[1])
              .map(([cat, count]) => (
                <div key={cat} className="flex items-center gap-3">
                  <span className="text-xs text-zinc-500 w-20 text-right flex-shrink-0">{cat}</span>
                  <div className="flex-1 bg-zinc-800 rounded-full h-4 overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all duration-500 ${
                        guardCategoryColors[cat]?.split(' ')[0] || 'bg-zinc-600'
                      }`}
                      style={{ width: `${(count / maxCount) * 100}%` }}
                    />
                  </div>
                  <span className="text-xs text-zinc-400 font-mono w-4">{count}</span>
                </div>
              ))}
          </div>
        </CardContent>
      </Card>

      <div className="flex flex-wrap gap-2">
        {categories.map(cat => (
          <button
            key={cat}
            onClick={() => setFilter(cat)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-all ${
              filter === cat
                ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                : 'bg-zinc-800/50 text-zinc-500 border-zinc-700 hover:border-zinc-600'
            }`}
          >
            {cat === 'all' ? `All (${entryGuards.length})` : `${cat} (${entryGuards.filter(g => g.category === cat).length})`}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {filtered.map((guard, i) => (
          <Card key={i} className="bg-zinc-900/50 border-zinc-800 hover:border-zinc-600 transition-all">
            <CardContent className="p-3">
              <div className="flex items-center justify-between mb-1.5">
                <span className="text-sm font-mono text-zinc-200">{guard.name}</span>
                <Badge variant="outline" className={`text-[10px] border ${guardCategoryColors[guard.category] || 'bg-zinc-800 text-zinc-400 border-zinc-700'}`}>
                  {guard.category}
                </Badge>
              </div>
              <p className="text-xs text-zinc-400 leading-relaxed">{guard.description}</p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── Options Framework Section ─────────────────────────────────────
export function OptionsSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Enabled Strategies</CardTitle>
          <CardDescription className="text-zinc-500 text-xs font-mono">app/services/options_buying/strategies/</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {optionsBuyingStrategies.map(s => (
              <Badge key={s} variant="outline" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/30 font-mono text-xs">
                {s}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {[
          { name: 'chain_radar.rb', desc: 'Periodic option chain scan (delta 0.45–0.55, min volume, 30min refresh)' },
          { name: 'breakout_watcher.rb', desc: '1m breakout detection with volume multiplier + OI unwind confirmation' },
          { name: 'breakout_evaluator.rb', desc: 'Evaluates breakout quality and triggers entry signals' },
          { name: 'atr_compression/', desc: 'Compression setup detector (ATR period 14, arms before 11:15)' },
          { name: 'gamma_wall_detector.rb', desc: 'OI-based gamma wall detection with buffer zone' },
          { name: 'vix_filter.rb', desc: 'Blocks buying outside VIX 12–30 band or on fast VIX drops' },
          { name: 'carry_policy.rb', desc: 'Positional mode: hold overnight if min ROI 30%+, capped at 3 carries / ₹150k' },
          { name: 'eod_carry_manager.rb', desc: 'EOD carry management and position rollover logic' },
          { name: 'stream_consumer.rb', desc: 'Redis Streams pipeline consumer' },
          { name: 'stream_writer.rb', desc: 'Redis Streams pipeline writer' },
        ].map(comp => (
          <Card key={comp.name} className="bg-zinc-900/50 border-zinc-800">
            <CardContent className="p-3">
              <p className="text-xs font-mono text-emerald-400/80 mb-1">{comp.name}</p>
              <p className="text-xs text-zinc-400">{comp.desc}</p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── Capital & Exits Section ───────────────────────────────────────
export function CapitalExitsSection() {
  return (
    <div className="space-y-4">
      {/* Index Parameters */}
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Index Parameters (Live Config)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-800">
                  <th className="text-left text-zinc-500 text-xs uppercase py-2 pr-4">Index</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-2 pr-4">Capital %</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-2 pr-4">Premium Band</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-2 pr-4">Base Risk</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-2">Max Trades/Day</th>
                </tr>
              </thead>
              <tbody>
                {indexParams.map(idx => (
                  <tr key={idx.index} className="border-b border-zinc-800/50 hover:bg-zinc-800/30 transition-colors">
                    <td className="py-2.5 pr-4 font-mono text-emerald-400 font-semibold">{idx.index}</td>
                    <td className="py-2.5 pr-4 text-zinc-300">{idx.capital}</td>
                    <td className="py-2.5 pr-4 text-zinc-300 font-mono">{idx.premium}</td>
                    <td className="py-2.5 pr-4 text-zinc-300">{idx.risk}</td>
                    <td className="py-2.5 text-zinc-300">{idx.maxTrades}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {/* Capital Allocation */}
        <Card className="bg-zinc-900/50 border-zinc-800">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Capital Allocation</CardTitle>
          </CardHeader>
          <CardContent className="text-xs text-zinc-400 space-y-1.5 font-mono">
            <p>Capital::Allocator — rupee/percentage sizing</p>
            <p className="text-amber-400/80">{'post_peak_size_cut: halves size once peak ≥ ₹2k and giveback > 50%'}</p>
          </CardContent>
        </Card>

        {/* Order Execution */}
        <Card className="bg-zinc-900/50 border-zinc-800">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Order Execution</CardTitle>
          </CardHeader>
          <CardContent className="text-xs text-zinc-400 space-y-1.5 font-mono">
            <p>Orders::GatewayFactory — picks paper/live at boot</p>
            <p>Orders::Placer — idempotency + dry-run gate</p>
            <p className="text-red-400/80">Live orders require BOTH algo.yml + ENV PLACE_ORDER=true</p>
          </CardContent>
        </Card>

        {/* Exit Engine */}
        <Card className="bg-zinc-900/50 border-rose-500/20">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-rose-400 uppercase tracking-wider">Exit Engine (SSOT)</CardTitle>
          </CardHeader>
          <CardContent className="text-xs text-zinc-400 space-y-1.5 font-mono">
            <p>Live::ExitEngine — ONLY component that places exits</p>
            <p>RiskManager + TrailingEngine only detect conditions</p>
            <p className="text-rose-400/80">Per-tick: UnifiedExitChecker (250ms debounce)</p>
            <p className="text-rose-400/80">5s loop: R-stop, trailing, profit floor, time stop</p>
          </CardContent>
        </Card>
      </div>

      {/* Risk Rules */}
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Risk Rules <span className="text-zinc-500 font-normal">(app/services/risk/rules/)</span></CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {riskRules.map(rule => (
              <Badge key={rule} variant="outline" className="bg-red-500/10 text-red-400 border-red-500/30 font-mono text-xs">
                {rule}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Ledger Section ────────────────────────────────────────────────
export function LedgerSection() {
  return (
    <Card className="bg-zinc-900/50 border-zinc-800">
      <CardContent className="p-6 space-y-4">
        <div className="flex items-center gap-3 mb-2">
          <div className="p-2 rounded-lg bg-emerald-500/10">
            <Database className="w-5 h-5 text-emerald-400" />
          </div>
          <div>
            <h3 className="text-base font-semibold text-zinc-200">Double-Entry Paper Accounting</h3>
            <p className="text-xs text-zinc-500">Paper wallet + sizing reads ledger cash balance</p>
          </div>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
          {['ledger_accounts', 'ledger_journal_entries', 'ledger_postings', 'paper_daily_wallets'].map(t => (
            <div key={t} className="p-3 rounded-lg bg-zinc-800/50 border border-zinc-700/50">
              <p className="text-xs font-mono text-emerald-400/80">{t}</p>
            </div>
          ))}
        </div>
        <div className="text-xs text-zinc-400 space-y-1">
          <p><span className="text-amber-400">ledger.enabled:</span> true — paper wallet + sizing reads ledger cash balance</p>
          <p><span className="text-amber-400">ledger.shadow_mode:</span> true — journals post, ReconciliationJob just compares</p>
          <p><span className="text-amber-400">ledger.block_negative_cash:</span> true</p>
          <p className="mt-2"><span className="text-sky-400">Recurring:</span> Ledger::ReconciliationJob (30 min) + Ledger::DailyCloseJob (3:35pm)</p>
        </div>
      </CardContent>
    </Card>
  );
}

// ─── Research Section ──────────────────────────────────────────────
export function ResearchSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardContent className="p-6">
          <p className="text-sm text-zinc-400 mb-4">
            Offline research pipeline that <span className="text-amber-400 font-semibold">never touches live trading</span>. Runs signal analysis, premium lifecycle tracking, and expectancy reports.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
            <div className="p-3 rounded-lg bg-zinc-800/50 border border-zinc-700/50">
              <p className="text-xs text-zinc-500 uppercase mb-1">Pipeline</p>
              <p className="text-xs font-mono text-emerald-400/80">Research::Pipeline.run</p>
              <p className="text-xs text-zinc-400 mt-1">Single signal → ranked ATM±N candidates</p>
            </div>
            <div className="p-3 rounded-lg bg-zinc-800/50 border border-zinc-700/50">
              <p className="text-xs text-zinc-500 uppercase mb-1">Lifecycle</p>
              <p className="text-xs font-mono text-emerald-400/80">Research::LifecycleRunner.run</p>
              <p className="text-xs text-zinc-400 mt-1">Full board → ranked premium lifecycles</p>
            </div>
            <div className="p-3 rounded-lg bg-zinc-800/50 border border-zinc-700/50">
              <p className="text-xs text-zinc-500 uppercase mb-1">Expectancy</p>
              <p className="text-xs font-mono text-emerald-400/80">Research::ExpectancyReport.call</p>
              <p className="text-xs text-zinc-400 mt-1">Groups by regime → win rate / avg drawdown</p>
            </div>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {['research_signals', 'research_option_candidates', 'research_option_bars', 'research_premium_lifecycles', 'research_raw_fetches', 'research_hypotheses', 'research_events', 'research_edge_registry'].map(t => (
              <Badge key={t} variant="outline" className="bg-indigo-500/10 text-indigo-400 border-indigo-500/30 font-mono text-[10px]">
                {t}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── AI Agents Section ─────────────────────────────────────────────
export function AiSection() {
  const statusColors = {
    active: 'border-emerald-500/30 bg-emerald-500/5',
    experimental: 'border-amber-500/30 bg-amber-500/5',
    overlapping: 'border-red-500/30 bg-red-500/5',
    new: 'border-sky-500/30 bg-sky-500/5',
  };
  const statusBadge = {
    active: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
    experimental: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
    overlapping: 'bg-red-500/10 text-red-400 border-red-500/30',
    new: 'bg-sky-500/10 text-sky-400 border-sky-500/30',
  };

  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-amber-500/20">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-zinc-400">
              <p className="text-amber-400 font-semibold mb-1">Overlap Risk</p>
              <p>6+ AI decision surfaces coexist (Qwen said 4) with no doc reconciling which is authoritative. AutoExp and TradingOrchestrator are new additions not in the review.</p>
            </div>
          </div>
        </CardContent>
      </Card>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {aiSubsystems.map(sub => (
          <Card key={sub.name} className={`bg-zinc-900/50 border ${statusColors[sub.status]}`}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="text-zinc-200 text-sm">{sub.name}</CardTitle>
                <Badge variant="outline" className={`text-[10px] border ${statusBadge[sub.status]}`}>{sub.status}</Badge>
              </div>
              <CardDescription className="text-zinc-500 text-xs font-mono">{sub.path}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <p className="text-xs text-zinc-400">{sub.description}</p>
              <div className="flex flex-wrap gap-1.5">
                {sub.components.map(c => (
                  <Badge key={c} variant="outline" className="bg-zinc-800 text-zinc-400 border-zinc-700 text-[10px] font-mono">{c}</Badge>
                ))}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── SMC Section ───────────────────────────────────────────────────
export function SmcSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardContent className="p-6 space-y-4">
          <div>
            <p className="text-xs text-zinc-500 uppercase mb-2">7 Pure Detectors</p>
            <div className="flex flex-wrap gap-2">
              {smcDetectors.map(d => (
                <Badge key={d} variant="outline" className="bg-purple-500/10 text-purple-400 border-purple-500/30 font-mono text-xs">
                  {d}
                </Badge>
              ))}
            </div>
          </div>
          <Separator className="bg-zinc-800" />
          <div>
            <p className="text-xs text-zinc-500 uppercase mb-2">Multi-Timeframe Confluence</p>
            <div className="flex flex-wrap gap-2">
              {['engine', 'mtf_digest', 'ltf_snapshot', 'bar_result', 'state'].map(c => (
                <Badge key={c} variant="outline" className="bg-violet-500/10 text-violet-400 border-violet-500/30 font-mono text-xs">
                  {c}
                </Badge>
              ))}
            </div>
          </div>
          <Separator className="bg-zinc-800" />
          <div>
            <p className="text-xs text-zinc-500 uppercase mb-2">Per-Tick SMC+AI Fusion</p>
            <div className="flex flex-wrap gap-2">
              {['analysis_service', 'edge_detector', 'gate', 'snapshot_store'].map(c => (
                <Badge key={c} variant="outline" className="bg-cyan-500/10 text-cyan-400 border-cyan-500/30 font-mono text-xs">
                  tick_ai/{c}
                </Badge>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Configuration Section ─────────────────────────────────────────
export function ConfigSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Config Merge Order</CardTitle>
          <CardDescription className="text-zinc-500 text-xs font-mono">AlgoConfig.fetch with 30s in-process cache</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {[
            { src: 'config/algo.yml', desc: 'Base configuration' },
            { src: 'settings table → algo_config_overrides', desc: 'Deep-merged JSON overrides' },
            { src: 'config/signal_tier_presets.yml', desc: 'Tier: exploratory / standard / selective / LIVE_TRADING' },
            { src: 'ENV vars', desc: 'LIVE_TRADING env forces paper/live mode' },
          ].map((item, i) => (
            <div key={i} className="flex items-start gap-3">
              <span className="flex-shrink-0 w-6 h-6 rounded-full bg-amber-500/20 text-amber-400 text-xs font-mono flex items-center justify-center mt-0.5">
                {i + 1}
              </span>
              <div>
                <p className="text-xs font-mono text-emerald-400/80">{item.src}</p>
                <p className="text-xs text-zinc-500">{item.desc}</p>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-zinc-300 uppercase tracking-wider">Token Management</CardTitle>
          <CardDescription className="text-zinc-500 text-xs font-mono">Dhan::TokenManager — 3-tier fallback</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {tokenFallback.map((step, i) => (
            <div key={i} className="flex items-start gap-3">
              <span className="flex-shrink-0 w-6 h-6 rounded-full bg-sky-500/20 text-sky-400 text-xs font-mono flex items-center justify-center mt-0.5">
                {i + 1}
              </span>
              <p className="text-xs text-zinc-400 font-mono leading-relaxed">{step}</p>
            </div>
          ))}
          <p className="text-xs text-zinc-500 mt-2">Dhan::AutoIpUpdaterJob (every 30 min) auto-syncs local public IP with Dhan whitelist.</p>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Database Schema Section ───────────────────────────────────────
export function DatabaseSection() {
  const [filter, setFilter] = useState<string>('all');
  const categories = ['all', ...new Set(dbTables.map(t => t.category))];
  const filtered = filter === 'all' ? dbTables : dbTables.filter(t => t.category === filter);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {categories.map(cat => (
          <button
            key={cat}
            onClick={() => setFilter(cat)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-all ${
              filter === cat
                ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                : 'bg-zinc-800/50 text-zinc-500 border-zinc-700 hover:border-zinc-600'
            }`}
          >
            {cat === 'all' ? `All (${dbTables.length})` : `${cat} (${dbTables.filter(t => t.category === cat).length})`}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-2">
        {filtered.map((t, i) => (
          <TooltipProvider key={i}>
            <Tooltip>
              <TooltipTrigger asChild>
                <div className="p-2 rounded-lg bg-zinc-900/50 border border-zinc-800 hover:border-zinc-600 transition-colors cursor-default">
                  <p className="text-[11px] font-mono text-zinc-300 truncate">{t.table}</p>
                  <p className="text-[9px] text-zinc-600 mt-0.5">{t.category}</p>
                </div>
              </TooltipTrigger>
              <TooltipContent side="top" className="bg-zinc-800 border-zinc-700 text-xs">
                <p className="font-mono text-zinc-200">{t.table}</p>
                <p className="text-zinc-400">Category: {t.category}</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        ))}
      </div>
    </div>
  );
}

// ─── API Surface Section ───────────────────────────────────────────
export function ApiSection() {
  const [search, setSearch] = useState('');
  const filtered = search
    ? apiEndpoints.filter(e => e.path.toLowerCase().includes(search.toLowerCase()))
    : apiEndpoints;

  return (
    <div className="space-y-4">
      <input
        type="text"
        placeholder="Filter endpoints..."
        value={search}
        onChange={e => setSearch(e.target.value)}
        className="w-full max-w-sm bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-zinc-300 placeholder-zinc-600 focus:outline-none focus:border-emerald-500/30"
      />
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardContent className="p-0">
          <div className="max-h-[500px] overflow-y-auto">
            {filtered.map((ep, i) => {
              const methods = ep.method.split('/');
              return (
                <div key={i} className="flex items-center gap-3 px-4 py-2 border-b border-zinc-800/50 hover:bg-zinc-800/30 transition-colors">
                  <div className="flex gap-1 flex-shrink-0">
                    {methods.map(m => (
                      <Badge key={m} variant="outline" className={`text-[10px] border font-mono ${methodColors[m] || 'bg-zinc-800 text-zinc-400'}`}>
                        {m}
                      </Badge>
                    ))}
                  </div>
                  <code className="text-xs font-mono text-zinc-400 truncate">{ep.path}</code>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Recurring Jobs Section ────────────────────────────────────────
export function JobsSection() {
  const [filter, setFilter] = useState<string>('all');
  const phases = ['all', 'pre-market', 'intraday', 'post-close', 'weekly'];
  const filtered = filter === 'all' ? recurringJobs : recurringJobs.filter(j => j.phase === filter);

  const phaseGroups = ['pre-market', 'intraday', 'post-close', 'weekly'];
  const phaseIcons: Record<string, string> = {
    'pre-market': '🌅',
    intraday: '📈',
    'post-close': '🌆',
    weekly: '📅',
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {phases.map(p => (
          <button
            key={p}
            onClick={() => setFilter(p)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition-all ${
              filter === p
                ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30'
                : 'bg-zinc-800/50 text-zinc-500 border-zinc-700 hover:border-zinc-600'
            }`}
          >
            {p === 'all' ? `All (${recurringJobs.length})` : `${phaseIcons[p]} ${p} (${recurringJobs.filter(j => j.phase === p).length})`}
          </button>
        ))}
      </div>

      <div className="space-y-6">
        {phaseGroups.filter(p => filter === 'all' || filter === p).map(phase => {
          const jobs = recurringJobs.filter(j => j.phase === phase);
          return (
            <div key={phase}>
              <div className="flex items-center gap-2 mb-3">
                <Badge variant="outline" className={`text-xs border ${phaseColors[phase]}`}>{phaseIcons[phase]} {phase}</Badge>
                <Separator className="flex-1 bg-zinc-800" />
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                {jobs.map(job => (
                  <Card key={job.name} className="bg-zinc-900/50 border-zinc-800 hover:border-zinc-600 transition-colors">
                    <CardContent className="p-3 flex items-center justify-between">
                      <div>
                        <p className="text-xs font-mono text-zinc-300">{job.name}</p>
                        <p className="text-[10px] text-zinc-500 mt-0.5">{job.schedule}</p>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Locked vs Alpha Section ───────────────────────────────────────
export function LayersSection() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <Card className="bg-zinc-900/50 border-red-500/20">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <Lock className="w-4 h-4 text-red-400" />
            <CardTitle className="text-red-400 text-sm uppercase tracking-wider">LOCKED (Infrastructure)</CardTitle>
          </div>
          <CardDescription className="text-zinc-500 text-xs">Touch only for critical scenarios</CardDescription>
        </CardHeader>
        <CardContent className="space-y-1.5">
          {lockedPaths.map((p, i) => (
            <div key={i} className="flex items-start gap-2">
              <span className="text-red-500/50 mt-0.5">●</span>
              <p className="text-xs font-mono text-zinc-400 leading-relaxed">{p}</p>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card className="bg-zinc-900/50 border-emerald-500/20">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <Unlock className="w-4 h-4 text-emerald-400" />
            <CardTitle className="text-emerald-400 text-sm uppercase tracking-wider">ALPHA (Safe to Iterate)</CardTitle>
          </div>
          <CardDescription className="text-zinc-500 text-xs">Strategy experimentation layer</CardDescription>
        </CardHeader>
        <CardContent className="space-y-1.5">
          {alphaPaths.map((p, i) => (
            <div key={i} className="flex items-start gap-2">
              <span className="text-emerald-500/50 mt-0.5">●</span>
              <p className="text-xs font-mono text-zinc-400 leading-relaxed">{p}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Critical Invariants Section ───────────────────────────────────
export function InvariantsSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-zinc-900/50 border-rose-500/20">
        <CardContent className="p-6">
          <div className="flex items-start gap-3 mb-4">
            <ShieldCheck className="w-5 h-5 text-rose-400 flex-shrink-0 mt-0.5" />
            <p className="text-sm text-zinc-400">These invariants <span className="text-rose-400 font-semibold">must never be violated</span>. They represent critical system constraints.</p>
          </div>
          <div className="space-y-2">
            {criticalInvariants.map((inv, i) => (
              <div key={i} className="flex items-start gap-3 p-2 rounded-lg bg-zinc-800/30 border border-zinc-800">
                <span className="flex-shrink-0 w-6 h-6 rounded-full bg-rose-500/20 text-rose-400 text-xs font-mono flex items-center justify-center mt-0.5">
                  {i + 1}
                </span>
                <p className="text-xs text-zinc-400 font-mono leading-relaxed">{inv}</p>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card className="bg-zinc-900/50 border-amber-500/20">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 text-amber-400" />
            <CardTitle className="text-amber-400 text-sm uppercase tracking-wider">Known Documentation Debt</CardTitle>
          </div>
        </CardHeader>
        <CardContent className="space-y-1.5">
          {docDebt.map((d, i) => (
            <div key={i} className="flex items-start gap-2">
              <span className="text-amber-500/50 mt-0.5">●</span>
              <p className="text-xs text-zinc-400 leading-relaxed">{d}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Environment Section ───────────────────────────────────────────
export function EnvSection() {
  return (
    <Card className="bg-zinc-900/50 border-zinc-800">
      <CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-zinc-800">
                <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Variable</th>
                <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Required</th>
                <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Purpose</th>
              </tr>
            </thead>
            <tbody>
              {envVars.map((v, i) => (
                <tr key={i} className="border-b border-zinc-800/50 hover:bg-zinc-800/30 transition-colors">
                  <td className="py-2.5 px-4 font-mono text-emerald-400/80 text-xs">{v.variable}</td>
                  <td className="py-2.5 px-4">
                    <Badge
                      variant="outline"
                      className={`text-[10px] border ${
                        v.required === 'Yes'
                          ? 'bg-red-500/10 text-red-400 border-red-500/30'
                          : v.required === 'Recommended'
                          ? 'bg-amber-500/10 text-amber-400 border-amber-500/30'
                          : 'bg-zinc-800 text-zinc-500 border-zinc-700'
                      }`}
                    >
                      {v.required}
                    </Badge>
                  </td>
                  <td className="py-2.5 px-4 text-zinc-400 text-xs">{v.purpose}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  );
}
