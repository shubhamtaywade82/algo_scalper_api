'use client';

import React, { useState, useEffect, useRef } from 'react';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import {
  Activity, Server, Cpu, Shield, Database, Globe, Brain,
  Lock, AlertTriangle, Clock, Zap, Layers, GitBranch,
  Settings, FileCode, BarChart3, Radio, Eye,
  ShieldCheck, Menu, X, ChevronRight,
} from 'lucide-react';
import {
  techStack, processModel, services, entryGuards, deltas, newSubsystems, concerns, dbTables, apiEndpoints, recurringJobs, riskRules, bootSequence,
} from '@/lib/architecture-data';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import {
  SignalSection,
  ServiceRegistrySection,
  EntryGuardsSection,
  OptionsSection,
  CapitalExitsSection,
  LedgerSection,
  ResearchSection,
  AiSection,
  SmcSection,
  ConfigSection,
  DatabaseSection,
  ApiSection,
  JobsSection,
  LayersSection,
  InvariantsSection,
  EnvSection,
} from './Sections';
import { TrendingUp, TrendingDown, Minus, AlertOctagon, Sparkles, FileWarning } from 'lucide-react';

// ─── Section Definitions ─────────────────────────────────────────────
const sections = [
  { id: 'overview', label: 'Overview', icon: Activity },
  { id: 'techstack', label: 'Tech Stack', icon: Server },
  { id: 'processes', label: 'Process Model', icon: Cpu },
  { id: 'services', label: 'Service Registry', icon: Radio },
  { id: 'signals', label: 'Signal Generation', icon: Zap },
  { id: 'guards', label: 'Entry Guards', icon: Shield },
  { id: 'options', label: 'Options Framework', icon: Layers },
  { id: 'orders', label: 'Capital & Exits', icon: BarChart3 },
  { id: 'ledger', label: 'Ledger System', icon: Database },
  { id: 'research', label: 'Research Pipeline', icon: FileCode },
  { id: 'ai', label: 'AI / Agents', icon: Brain },
  { id: 'smc', label: 'SMC Module', icon: Eye },
  { id: 'config', label: 'Configuration', icon: Settings },
  { id: 'database', label: 'Database Schema', icon: Database },
  { id: 'api', label: 'API Surface', icon: Globe },
  { id: 'jobs', label: 'Recurring Jobs', icon: Clock },
  { id: 'layers', label: 'Locked vs Alpha', icon: GitBranch },
  { id: 'invariants', label: 'Invariants', icon: ShieldCheck },
  { id: 'env', label: 'Environment', icon: Settings },
  { id: 'deltas', label: 'Review Deltas', icon: TrendingUp },
  { id: 'newsubsystems', label: 'New Subsystems', icon: Sparkles },
  { id: 'concerns', label: 'Concerns', icon: AlertOctagon },
];

// ─── Metric Card ─────────────────────────────────────────────────────
function MetricCard({ title, value, sub, icon: Icon }: { title: string; value: string; sub?: string; icon: React.ElementType }) {
  return (
    <Card className="bg-zinc-900/50 border-zinc-800 hover:border-zinc-700 transition-colors">
      <CardContent className="p-4">
        <div className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-emerald-500/10">
            <Icon className="w-4 h-4 text-emerald-400" />
          </div>
          <div>
            <p className="text-[10px] text-zinc-500 uppercase tracking-wider">{title}</p>
            <p className="text-2xl font-bold text-zinc-100 font-mono">{value}</p>
            {sub && <p className="text-[10px] text-zinc-500">{sub}</p>}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

// ─── Section Title ──────────────────────────────────────────────────
function SectionTitle({ id, title, icon: Icon }: { id: string; title: string; icon: React.ElementType }) {
  return (
    <div id={id} className="flex items-center gap-3 mb-6 pt-8 first:pt-0 scroll-mt-4">
      <div className="p-2 rounded-lg bg-emerald-500/10">
        <Icon className="w-5 h-5 text-emerald-400" />
      </div>
      <h2 className="text-xl font-bold text-zinc-100">{title}</h2>
      <Separator className="flex-1 bg-zinc-800" />
    </div>
  );
}

// ─── Overview Section ───────────────────────────────────────────────
function OverviewSection() {
  const activeServices = services.filter(s => s.status === 'active' || s.status === 'coexisting').length;
  const guardCategories = [...new Set(entryGuards.map(g => g.category))].length;
  const newGuards = entryGuards.filter(g => g.isNew).length;
  const newEndpoints = apiEndpoints.filter(e => e.isNew).length;
  const newTables = dbTables.filter(t => t.isNew).length;

  return (
    <div className="space-y-6">
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-3">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-3 h-3 rounded-full bg-emerald-400 animate-pulse" />
            <CardTitle className="text-zinc-100 text-lg">Algo-Scalper API</CardTitle>
            <Badge variant="outline" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/30 text-[10px]">v8.1.3</Badge>
            <Badge variant="outline" className="bg-amber-500/10 text-amber-400 border-amber-500/30 text-[10px]">Verified Aug 2026</Badge>
          </div>
          <CardDescription className="text-zinc-400 leading-relaxed">
            Fully autonomous intraday options scalping on Indian index derivatives (NIFTY, BANKNIFTY, SENSEX).
            Generates signals, qualifies option strikes, sizes capital, places orders via DhanHQ, and manages exits with zero human intervention.
          </CardDescription>
        </CardHeader>
      </Card>
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <MetricCard title="Services" value={String(services.length)} sub={`${activeServices} active, 1 coexisting`} icon={Radio} />
        <MetricCard title="Entry Guards" value={String(entryGuards.length)} sub={`${newGuards} new since review`} icon={Shield} />
        <MetricCard title="API Endpoints" value={String(apiEndpoints.length)} sub={`${newEndpoints} new, REST+WS`} icon={Globe} />
        <MetricCard title="DB Tables" value={String(dbTables.length)} sub={`${newTables} new tables`} icon={Database} />
        <MetricCard title="Recurring Jobs" value={String(recurringJobs.length)} sub={`${recurringJobs.filter(j => j.phase === 'intraday').length} intraday`} icon={Clock} />
        <MetricCard title="Risk Rules" value={String(riskRules.length)} sub={`28 rules total`} icon={ShieldCheck} />
      </div>
      {/* Delta Summary */}
      <Card className="bg-amber-500/5 border-amber-500/20">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <FileWarning className="w-4 h-4 text-amber-400" />
            <CardTitle className="text-amber-400 text-xs uppercase tracking-wider">Qwen Review vs Actual Code — Key Deltas</CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            {deltas.map((d, i) => {
              const Arrow = d.direction === 'up' ? TrendingUp : d.direction === 'down' ? TrendingDown : Minus;
              const color = d.direction === 'up' ? 'text-sky-400' : d.direction === 'down' ? 'text-amber-400' : 'text-zinc-500';
              return (
                <div key={i} className="flex items-center gap-2 p-2 rounded-lg bg-zinc-900/50">
                  <Arrow className={`w-3.5 h-3.5 ${color} flex-shrink-0`} />
                  <div>
                    <p className="text-[10px] text-zinc-500">{d.metric}</p>
                    <p className="text-xs font-mono"><span className="text-zinc-500 line-through">{d.review}</span> <span className={`${color}`}>{d.actual}</span></p>
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardHeader className="pb-3">
          <CardTitle className="text-xs text-zinc-400 uppercase tracking-wider">Boot Sequence</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {bootSequence.map((step, i) => (
            <div key={i} className="flex items-start gap-3">
              <span className="flex-shrink-0 w-6 h-6 rounded-full bg-emerald-500/20 text-emerald-400 text-xs font-mono flex items-center justify-center mt-0.5">
                {i + 1}
              </span>
              <p className="text-xs text-zinc-400 font-mono leading-relaxed">{step}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}

// ─── Tech Stack Section ─────────────────────────────────────────────
function TechStackSection() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
      {techStack.map((item, i) => (
        <Card key={i} className="bg-zinc-900/50 border-zinc-800 hover:border-emerald-500/30 transition-colors">
          <CardContent className="p-4">
            <p className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1">{item.layer}</p>
            <p className="text-sm text-zinc-200 font-mono">{item.technology}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

// ─── Process Model Section ──────────────────────────────────────────
function ProcessModelSection() {
  const colors = ['bg-emerald-500/10 border-emerald-500/30', 'bg-amber-500/10 border-amber-500/30', 'bg-sky-500/10 border-sky-500/30', 'bg-violet-500/10 border-violet-500/30'];
  const icons = [Server, Brain, Clock, Globe];
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {processModel.map((proc, i) => {
        const Icon = icons[i];
        return (
          <Card key={i} className={`${colors[i]} border`}>
            <CardHeader className="pb-2">
              <div className="flex items-center gap-3">
                <Icon className="w-5 h-5 text-zinc-300" />
                <div>
                  <CardTitle className="text-zinc-100 text-base">{proc.process}</CardTitle>
                  <CardDescription className="text-zinc-400 text-xs font-mono">{proc.command}</CardDescription>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-zinc-300">{proc.role}</p>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

// ─── Section Router ─────────────────────────────────────────────────
function SectionRenderer({ id }: { id: string }) {
  switch (id) {
    case 'overview': return <OverviewSection />;
    case 'techstack': return <TechStackSection />;
    case 'processes': return <ProcessModelSection />;
    case 'services': return <ServiceRegistrySection />;
    case 'signals': return <SignalSection />;
    case 'guards': return <EntryGuardsSection />;
    case 'options': return <OptionsSection />;
    case 'orders': return <CapitalExitsSection />;
    case 'ledger': return <LedgerSection />;
    case 'research': return <ResearchSection />;
    case 'ai': return <AiSection />;
    case 'smc': return <SmcSection />;
    case 'config': return <ConfigSection />;
    case 'database': return <DatabaseSection />;
    case 'api': return <ApiSection />;
    case 'jobs': return <JobsSection />;
    case 'layers': return <LayersSection />;
    case 'invariants': return <InvariantsSection />;
    case 'env': return <EnvSection />;
    case 'deltas': return <DeltasSection />;
    case 'newsubsystems': return <NewSubsystemsSection />;
    case 'concerns': return <ConcernsSection />;
    default: return null;
  }
}

// ─── Deltas Section ──────────────────────────────────────────────
function DeltasSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-amber-500/5 border-amber-500/20">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <FileWarning className="w-5 h-5 text-amber-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-zinc-400">
              <p className="text-amber-400 font-semibold mb-1">Qwen Coder Review Inaccuracies</p>
              <p>The Qwen architecture review had several significant inaccuracies when compared against the actual codebase. Below are the corrected metrics with source-of-truth references.</p>
            </div>
          </div>
        </CardContent>
      </Card>
      <Card className="bg-zinc-900/50 border-zinc-800">
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-zinc-800">
                  <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Metric</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Qwen Said</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Actual</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Delta</th>
                  <th className="text-left text-zinc-500 text-xs uppercase py-3 px-4">Source of Truth</th>
                </tr>
              </thead>
              <tbody>
                {deltas.map((d, i) => {
                  const sources: Record<string, string> = {
                    'Registered Services': 'lib/trading_system/bootstrap.rb',
                    'Entry Guards': 'app/services/entries/guards/*.rb',
                    'AI Subsystems': 'app/services/ai/ + app/services/auto_exp/',
                    'API Endpoints': 'config/routes.rb',
                    'Recurring Jobs': 'config/recurring.yml (production)',
                    'DB Tables': 'db/schema.rb (2026_08_07)',
                    'Signal Paths': 'bootstrap.rb + signal/engine.rb + strategies/manager.rb',
                    'Risk Rules': 'app/services/risk/rules/*.rb',
                  };
                  const Arrow = d.direction === 'up' ? TrendingUp : d.direction === 'down' ? TrendingDown : Minus;
                  const color = d.direction === 'up' ? 'text-sky-400' : d.direction === 'down' ? 'text-amber-400' : 'text-zinc-500';
                  return (
                    <tr key={i} className="border-b border-zinc-800/50 hover:bg-zinc-800/30 transition-colors">
                      <td className="py-2.5 px-4 text-zinc-300 font-medium text-xs">{d.metric}</td>
                      <td className="py-2.5 px-4 text-zinc-500 font-mono line-through text-xs">{d.review}</td>
                      <td className="py-2.5 px-4 text-emerald-400 font-mono font-semibold text-xs">{d.actual}</td>
                      <td className="py-2.5 px-4"><Arrow className={`w-4 h-4 ${color}`} /></td>
                      <td className="py-2.5 px-4 text-zinc-500 font-mono text-[10px]">{sources[d.metric]}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

// ─── New Subsystems Section ─────────────────────────────────────────
function NewSubsystemsSection() {
  return (
    <div className="space-y-4">
      <Card className="bg-sky-500/5 border-sky-500/20">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <Sparkles className="w-5 h-5 text-sky-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-zinc-400">
              <p className="text-sky-400 font-semibold mb-1">New Subsystems Not in Qwen Review</p>
              <p>These 9 subsystems were built after the Qwen architecture review and represent significant new capability.</p>
            </div>
          </div>
        </CardContent>
      </Card>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {newSubsystems.map((sub, i) => (
          <Card key={i} className="bg-zinc-900/50 border-zinc-800 hover:border-sky-500/30 transition-colors">
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="text-zinc-200 text-sm">{sub.name}</CardTitle>
                <Badge variant="outline" className="bg-sky-500/10 text-sky-400 border-sky-500/30 text-[10px]">{sub.fileCount} files</Badge>
              </div>
              <CardDescription className="text-zinc-600 text-[10px] font-mono">{sub.path}</CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-zinc-400 leading-relaxed">{sub.description}</p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── Concerns Section ──────────────────────────────────────────────
function ConcernsSection() {
  const severityColors: Record<string, string> = {
    critical: 'bg-red-500/20 text-red-400 border-red-500/30',
    high: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
    medium: 'bg-sky-500/20 text-sky-400 border-sky-500/30',
    low: 'bg-zinc-500/20 text-zinc-400 border-zinc-500/30',
  };
  return (
    <div className="space-y-4">
      <Card className="bg-red-500/5 border-red-500/20">
        <CardContent className="p-4">
          <div className="flex items-start gap-3">
            <AlertOctagon className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-zinc-400">
              <p className="text-red-400 font-semibold mb-1">Issues Found During Code Audit</p>
              <p>These concerns were identified by analyzing the actual repository code. Severity levels: critical requires immediate action, high should be addressed soon.</p>
            </div>
          </div>
        </CardContent>
      </Card>
      <div className="space-y-3">
        {concerns.map((c, i) => (
          <Card key={i} className="bg-zinc-900/50 border-zinc-800">
            <CardContent className="p-4">
              <div className="flex items-start gap-3">
                <Badge variant="outline" className={`text-[10px] border flex-shrink-0 mt-0.5 ${severityColors[c.severity]}`}>
                  {c.severity}
                </Badge>
                <div>
                  <p className="text-sm font-semibold text-zinc-200 mb-1">{c.title}</p>
                  <p className="text-xs text-zinc-400 leading-relaxed">{c.description}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── Main Dashboard ─────────────────────────────────────────────────
export default function ArchDashboard() {
  const [activeSection, setActiveSection] = useState('overview');
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const contentRef = useRef<HTMLDivElement>(null);

  const filteredSections = searchQuery
    ? sections.filter(s => s.label.toLowerCase().includes(searchQuery.toLowerCase()))
    : sections;

  // Scroll to section when sidebar item is clicked
  const handleNavClick = (id: string) => {
    setActiveSection(id);
    setSidebarOpen(false);
    // Small delay to ensure section renders
    setTimeout(() => {
      const el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, 100);
  };

  // Track scroll position to highlight active section
  useEffect(() => {
    const handleScroll = () => {
      if (!contentRef.current) return;
      const scrollTop = contentRef.current.scrollTop;
      const sectionElements = sections.map(s => ({
        id: s.id,
        el: document.getElementById(s.id),
      })).filter(s => s.el);

      for (let i = sectionElements.length - 1; i >= 0; i--) {
        const el = sectionElements[i].el;
        if (el && el.offsetTop - 100 <= scrollTop) {
          setActiveSection(sectionElements[i].id);
          break;
        }
      }
    };

    const ref = contentRef.current;
    if (ref) ref.addEventListener('scroll', handleScroll);
    return () => { if (ref) ref.removeEventListener('scroll', handleScroll); };
  }, []);

  return (
    <div className="flex h-screen bg-[#09090b] text-zinc-100 overflow-hidden">
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/60 z-40 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={
        `fixed lg:static inset-y-0 left-0 z-50 w-64 bg-zinc-950 border-r border-zinc-800 flex flex-col transition-transform duration-300 lg:translate-x-0 ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        }`
      }>
        {/* Sidebar Header */}
        <div className="p-4 border-b border-zinc-800">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                <Activity className="w-4 h-4 text-emerald-400" />
              </div>
              <div>
                <h1 className="text-sm font-bold text-zinc-100">algo_scalper_api</h1>
                <p className="text-[10px] text-zinc-500">Architecture Dashboard</p>
              </div>
            </div>
            <button
              onClick={() => setSidebarOpen(false)}
              className="lg:hidden p-1 rounded hover:bg-zinc-800"
            >
              <X className="w-4 h-4 text-zinc-400" />
            </button>
          </div>
        </div>

        {/* Search */}
        <div className="p-3">
          <input
            type="text"
            placeholder="Search sections..."
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-1.5 text-xs text-zinc-300 placeholder-zinc-600 focus:outline-none focus:border-emerald-500/30"
          />
        </div>

        {/* Nav Items */}
        <ScrollArea className="flex-1 px-3 pb-4">
          <nav className="space-y-0.5">
            {filteredSections.map(section => {
              const Icon = section.icon;
              const isActive = activeSection === section.id;
              return (
                <button
                  key={section.id}
                  onClick={() => handleNavClick(section.id)}
                  className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-xs font-medium transition-all ${
                    isActive
                      ? 'bg-emerald-500/10 text-emerald-400'
                      : 'text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/50'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5 flex-shrink-0" />
                  <span className="truncate">{section.label}</span>
                  {isActive && <ChevronRight className="w-3 h-3 ml-auto flex-shrink-0" />}
                </button>
              );
            })}
          </nav>
        </ScrollArea>

        {/* Sidebar Footer */}
        <div className="p-3 border-t border-zinc-800">
          <div className="flex items-center gap-2 px-3 py-1.5">
            <Badge variant="outline" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/30 text-[10px]">
              develop
            </Badge>
            <span className="text-[10px] text-zinc-600 font-mono">Ruby 3.3.4 · Rails 8.1.3</span>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0">
        {/* Top Bar */}
        <header className="flex items-center gap-3 px-4 py-3 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur-sm flex-shrink-0">
          <button
            onClick={() => setSidebarOpen(true)}
            className="lg:hidden p-2 rounded-lg hover:bg-zinc-800"
          >
            <Menu className="w-5 h-5 text-zinc-400" />
          </button>
          <div className="flex items-center gap-2">
            {(() => {
              const sec = sections.find(s => s.id === activeSection);
              if (!sec) return null;
              const Icon = sec.icon;
              return <Icon className="w-4 h-4 text-emerald-400" />;
            })()}
            <h2 className="text-sm font-semibold text-zinc-200">
              {sections.find(s => s.id === activeSection)?.label}
            </h2>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <div className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            <span className="text-[10px] text-zinc-500 font-mono">Verified Aug 2026</span>
          </div>
        </header>

        {/* Scrollable Content — render ALL sections for scroll tracking */}
        <div ref={contentRef} className="flex-1 overflow-y-auto">
          <div className="max-w-6xl mx-auto px-4 md:px-6 lg:px-8 py-6 space-y-2">
            {sections.map(section => {
              const Icon = section.icon;
              return (
                <section key={section.id}>
                  <SectionTitle id={section.id} title={section.label} icon={Icon} />
                  <SectionRenderer id={section.id} />
                </section>
              );
            })}
          </div>
          {/* Bottom padding for footer space */}
          <div className="h-16" />
        </div>
      </main>
    </div>
  );
}
