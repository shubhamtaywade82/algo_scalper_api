import { createSignal, createMemo, createEffect, For, Show, onMount } from 'solid-js'
import { useNavigate, useParams } from '@solidjs/router'
import { useStrategies } from '../stores/useStrategies'
import CodeEditor from '../components/strategies/CodeEditor'
import ParametersTable from '../components/strategies/ParametersTable'
import StrategyFlowChart from '../components/strategies/StrategyFlowChart'
import BacktestPreview from '../components/strategies/BacktestPreview'
import RecentLogs from '../components/strategies/RecentLogs'

const sampleResults = {
  net_profit: 124500,
  total_trades: 248,
  win_rate: 62.5,
  profit_factor: 1.84,
  max_drawdown: -8.2,
}

const sampleLogs = [
  { time: '09:24:12', message: '[ORB Breakout] Candle closed 09:23, O:24180.5 H:24195.2 L:24170.8 C:24190.3', level: 'info' },
  { time: '09:24:12', message: '[ORB Breakout] Opening Range High: 24195.2 · Low: 24140.7', level: 'info' },
  { time: '09:24:12', message: '[ORB Breakout] Breakout UP detected @ 24195.2', level: 'success' },
  { time: '09:24:12', message: '[ORB Breakout] Signal: Buy Call', level: 'success' },
  { time: '09:24:12', message: '[Risk Engine] Position size: 75 lots (Risk: 1.00%)', level: 'warn' },
  { time: '09:24:13', message: '[Option Selector] Selected: NIFTY 06 JUN 24160 CE', level: 'info' },
  { time: '09:24:13', message: '[Order Manager] Order placed Successfully', level: 'success' },
  { time: '09:24:13', message: '[Execution] Order ID: 230518001238843', level: 'info' },
]

const defaultCode = `# Strategy Entry Logic
# Define your entry conditions here

class OrbBreakout < BaseStrategy
  def on_candle(candle)
    if candle.close > opening_range_high
      signal(:buy_call, candle)
    elsif candle.close < opening_range_low
      signal(:buy_put, candle)
    end
  end
end`

export default function StrategyCreator() {
  const navigate = useNavigate()
  const params = useParams()
  const { currentStrategy, loading, error, fetchOne, create, update } = useStrategies()

  // ── State ──
  const [name, setName] = createSignal('Untitled Strategy')
  const [status, setStatus] = createSignal('draft')
  const [version, setVersion] = createSignal('0.1')
  const [code, setCode] = createSignal(defaultCode)
  const [parameters, setParameters] = createSignal([
    { name: 'lookback_period', type: 'Integer', default_value: '14', description: 'Number of candles to look back' },
    { name: 'risk_percent', type: 'Float', default_value: '1.0', description: 'Max risk per trade as percentage' },
    { name: 'enable_trailing', type: 'Boolean', default_value: 'true', description: 'Enable trailing stop loss' },
  ])
  const [instruments, setInstruments] = createSignal(['NIFTY', 'BANKNIFTY'])
  const [timeframe, setTimeframe] = createSignal('5m')
  const [direction, setDirection] = createSignal('Both')
  const [tags, setTags] = createSignal(['scalper', 'breakout'])
  const [description, setDescription] = createSignal('')
  const [activeTab, setActiveTab] = createSignal('code')
  const [activeNavItem, setActiveNavItem] = createSignal('entry')
  const [isDirty, setIsDirty] = createSignal(false)
  const [newTagInput, setNewTagInput] = createSignal('')
  const [newInstrumentInput, setNewInstrumentInput] = createSignal('')

  const [validationStatus] = createSignal({
    syntax: 'passed',
    logic: 'not_run',
    risk: 'passed',
    backtest: 'not_run',
  })

  const isEditing = createMemo(() => !!params.id)

  const tabs = [
    { key: 'builder', label: 'Builder', sublabel: 'Visual' },
    { key: 'code', label: 'Code', sublabel: 'Ruby' },
    { key: 'backtest', label: 'Backtest', sublabel: '' },
    { key: 'logs', label: 'Live Logs', sublabel: '' },
  ]

  const navItems = [
    { key: 'entry', label: 'Entry Rules', icon: '→' },
    { key: 'exit', label: 'Exit Rules', icon: '←' },
    { key: 'risk', label: 'Risk Management', icon: '⛨' },
    { key: 'filters', label: 'Filters', icon: '⊙' },
    { key: 'parameters', label: 'Parameters', icon: '⚙' },
    { key: 'variables', label: 'Variables', icon: '𝑥' },
    { key: 'schedule', label: 'Schedule', icon: '⏱' },
    { key: 'notes', label: 'Notes', icon: '✎' },
  ]

  const timeframes = ['1m', '3m', '5m', '15m', '1h', '1D']
  const directions = ['Long', 'Short', 'Both']

  // ── On Mount: Load strategy if editing ──
  onMount(async () => {
    if (params.id) {
      const data = await fetchOne(params.id)
      if (data) {
        setName(data.name || 'Untitled Strategy')
        setStatus(data.status || 'draft')
        setVersion(data.version || '0.1')
        setCode(data.code || defaultCode)
        if (data.parameters) setParameters(data.parameters)
        if (data.instruments) setInstruments(data.instruments)
        if (data.timeframe) setTimeframe(data.timeframe)
        if (data.direction) setDirection(data.direction)
        if (data.tags) setTags(data.tags)
        if (data.description) setDescription(data.description)
      }
    }
  })

  // ── Handlers ──
  async function handleSave() {
    const payload = {
      name: name(), status: status(), version: version(), code: code(),
      parameters: parameters(), instruments: instruments(),
      timeframe: timeframe(), direction: direction(),
      tags: tags(), description: description(),
    }
    if (params.id) {
      await update(params.id, payload)
    } else {
      const result = await create(payload)
      if (result?.id) navigate(`/strategies/${result.id}`)
    }
    setIsDirty(false)
  }

  function addTag() {
    const val = newTagInput().trim()
    if (val && !tags().includes(val)) {
      setTags(prev => [...prev, val])
      setNewTagInput('')
      setIsDirty(true)
    }
  }

  function removeTag(tag) {
    setTags(prev => prev.filter(t => t !== tag))
    setIsDirty(true)
  }

  function addInstrument() {
    const val = newInstrumentInput().trim().toUpperCase()
    if (val && !instruments().includes(val)) {
      setInstruments(prev => [...prev, val])
      setNewInstrumentInput('')
      setIsDirty(true)
    }
  }

  function removeInstrument(inst) {
    setInstruments(prev => prev.filter(i => i !== inst))
    setIsDirty(true)
  }

  function statusDot(s) {
    switch (s) {
      case 'passed': return 'bg-emerald-500'
      case 'failed': return 'bg-rose-500'
      default: return 'bg-gray-600'
    }
  }

  function statusText(s) {
    switch (s) {
      case 'passed': return 'text-emerald-500'
      case 'failed': return 'text-rose-500'
      default: return 'text-gray-600'
    }
  }

  function statusLabel(s) {
    switch (s) {
      case 'passed': return 'Passed'
      case 'failed': return 'Failed'
      default: return 'Not Run'
    }
  }

  function statusBadgeClass(s) {
    switch (s) {
      case 'active': return 'bg-emerald-500/15 text-emerald-500 border-emerald-500/20'
      case 'draft': return 'bg-amber-500/15 text-amber-500 border-amber-500/20'
      case 'archived': return 'bg-gray-500/15 text-gray-500 border-gray-500/20'
      default: return 'bg-white/10 text-gray-400 border-white/10'
    }
  }

  return (
    <div class="flex flex-col gap-4" style="height: calc(100vh - 80px)">
      {/* ═══ Top Action Bar ═══ */}
      <div class="flex items-center justify-between flex-shrink-0">
        {/* Breadcrumb */}
        <div class="flex items-center gap-1.5 text-xs">
          <button onClick={() => navigate('/strategies')} class="text-gray-600 hover:text-gray-400 transition font-bold">
            Strategies
          </button>
          <span class="text-gray-700">›</span>
          <span class="text-gray-500 font-bold">My Strategies</span>
          <span class="text-gray-700">›</span>
          <span class="text-white font-bold truncate max-w-[180px]">{name()}</span>
          <span class="text-gray-700">›</span>
          <span class="text-gray-500 font-medium">v{version()}</span>
          <span class={`text-[10px] font-black uppercase tracking-tight px-2 py-0.5 rounded-md border ml-1 ${statusBadgeClass(status())}`}>
            {status()}
          </span>
        </div>

        {/* Action Buttons */}
        <div class="flex items-center gap-2">
          <button
            onClick={() => navigate('/strategies')}
            class="border border-white/10 text-gray-400 hover:text-white hover:border-white/20 px-4 py-2 rounded-xl text-xs font-bold transition"
          >
            Back
          </button>
          <button
            onClick={handleSave}
            disabled={loading()}
            class={`border px-4 py-2 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
              isDirty()
                ? 'border-primary-500/30 text-primary-400 hover:bg-primary-500/10'
                : 'border-white/10 text-gray-500'
            }`}
          >
            <Show when={isDirty()}>
              <span class="w-1.5 h-1.5 rounded-full bg-amber-500" />
            </Show>
            Save Draft
          </button>
          <button class="border border-white/10 text-gray-400 hover:text-white hover:border-white/20 px-4 py-2 rounded-xl text-xs font-bold transition">
            Test Strategy
          </button>
          <button class="bg-gradient-to-r from-primary-500 to-primary-600 text-white px-5 py-2 rounded-xl text-xs font-bold hover:opacity-90 transition shadow-lg shadow-primary-500/20">
            Deploy
          </button>
        </div>
      </div>

      {/* ═══ Main 3-Column Layout ═══ */}
      <div class="flex gap-4 flex-1 overflow-hidden min-h-0">
        {/* ─── LEFT PANEL ─── */}
        <div class="w-56 flex-shrink-0 flex flex-col gap-3 overflow-y-auto">
          {/* Strategy Name */}
          <div class="glass rounded-xl p-4">
            <input
              value={name()}
              onInput={(e) => { setName(e.target.value); setIsDirty(true) }}
              class="bg-transparent text-base font-black text-white w-full outline-none border-b border-white/10 pb-2 placeholder-gray-700"
              placeholder="Strategy Name"
            />
            <div class="flex items-center gap-2 mt-2.5">
              <span class={`text-[10px] font-black uppercase tracking-tight px-2 py-0.5 rounded-md border ${statusBadgeClass(status())}`}>
                {status()}
              </span>
              <span class="text-[10px] text-gray-600 font-bold">v{version()}</span>
            </div>
          </div>

          {/* Navigation */}
          <div class="glass rounded-xl p-3">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-2 px-1">Strategy Builder</div>
            <div class="flex flex-col gap-0.5">
              <For each={navItems}>
                {(item) => (
                  <button
                    onClick={() => setActiveNavItem(item.key)}
                    class={`flex items-center gap-2.5 px-3 py-2 rounded-lg text-xs font-bold transition w-full text-left ${
                      activeNavItem() === item.key
                        ? 'bg-primary-500/10 text-primary-400'
                        : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
                    }`}
                  >
                    <span class="w-4 text-center text-[11px] opacity-60">{item.icon}</span>
                    {item.label}
                  </button>
                )}
              </For>
            </div>
          </div>

          {/* Validation Status */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Validation Status</div>
            <div class="flex flex-col gap-2.5">
              {[
                { key: 'syntax', label: 'Syntax Check' },
                { key: 'logic', label: 'Logic Check' },
                { key: 'risk', label: 'Risk Check' },
                { key: 'backtest', label: 'Backtest' },
              ].map(item => (
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <span class={`w-2 h-2 rounded-full ${statusDot(validationStatus()[item.key])}`} />
                    <span class="text-[11px] font-bold text-gray-400">{item.label}</span>
                  </div>
                  <span class={`text-[10px] font-black uppercase tracking-tight ${statusText(validationStatus()[item.key])}`}>
                    {statusLabel(validationStatus()[item.key])}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Strategy Info */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Strategy Info</div>
            <div class="flex flex-col gap-2">
              {[
                { label: 'Created', value: '05 Jul 2026' },
                { label: 'Updated', value: 'Just now' },
                { label: 'Author', value: 'System' },
                { label: 'Runtime', value: 'Ruby 3.2' },
              ].map(row => (
                <div class="flex items-center justify-between">
                  <span class="text-[11px] text-gray-600 font-medium">{row.label}</span>
                  <span class="text-[11px] text-gray-300 font-bold">{row.value}</span>
                </div>
              ))}
              <div class="flex items-center justify-between mt-1">
                <span class="text-[11px] text-gray-600 font-medium">Timeframe</span>
                <span class="text-[11px] text-primary-400 font-bold">{timeframe()}</span>
              </div>
              <div class="mt-1.5">
                <span class="text-[11px] text-gray-600 font-medium block mb-1.5">Instruments</span>
                <div class="flex flex-wrap gap-1">
                  <For each={instruments()}>
                    {(inst) => (
                      <span class="bg-white/5 border border-white/10 text-[9px] font-bold text-gray-400 px-2 py-0.5 rounded-full">
                        {inst}
                      </span>
                    )}
                  </For>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* ─── CENTER PANEL ─── */}
        <div class="flex-1 flex flex-col gap-3 overflow-hidden min-w-0">
          {/* Tab Bar */}
          <div class="flex items-center gap-1 bg-white/5 rounded-xl p-1 flex-shrink-0">
            <For each={tabs}>
              {(tab) => (
                <button
                  onClick={() => setActiveTab(tab.key)}
                  class={`px-4 py-2 rounded-lg text-xs font-bold transition flex items-center gap-1.5 ${
                    activeTab() === tab.key
                      ? 'bg-white/10 text-white'
                      : 'text-gray-500 hover:text-gray-300'
                  }`}
                >
                  {tab.label}
                  <Show when={tab.sublabel}>
                    <span class="text-[10px] opacity-50">({tab.sublabel})</span>
                  </Show>
                </button>
              )}
            </For>
          </div>

          {/* Tab Content */}
          <div class="flex-1 overflow-hidden min-h-0">
            {/* Builder Tab */}
            <Show when={activeTab() === 'builder'}>
              <div class="h-full glass rounded-xl overflow-hidden">
                <StrategyFlowChart strategyName={name()} />
              </div>
            </Show>

            {/* Code Tab */}
            <Show when={activeTab() === 'code'}>
              <div class="flex flex-col h-full gap-3">
                <div class="flex-1 min-h-0">
                  <CodeEditor
                    code={code}
                    onChange={(v) => { setCode(v); setIsDirty(true) }}
                    language="ruby"
                    readOnly={false}
                  />
                </div>
                {/* Split bottom panels */}
                <div class="flex gap-3 flex-shrink-0" style="height: 230px">
                  <div class="flex-1 glass rounded-xl overflow-hidden p-3 flex flex-col">
                    <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-2 flex-shrink-0">Flow Preview</div>
                    <div class="flex-1 min-h-0">
                      <StrategyFlowChart strategyName={name()} />
                    </div>
                  </div>
                  <div class="flex-1 glass rounded-xl overflow-hidden p-3 flex flex-col">
                    <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-2 flex-shrink-0">Backtest Preview</div>
                    <div class="flex-1 min-h-0">
                      <BacktestPreview results={() => sampleResults} dateRange="Jan 2026 – Jul 2026" />
                    </div>
                  </div>
                </div>
              </div>
            </Show>

            {/* Backtest Tab */}
            <Show when={activeTab() === 'backtest'}>
              <div class="h-full glass rounded-xl p-4 overflow-auto">
                <BacktestPreview results={() => sampleResults} dateRange="Jan 2026 – Jul 2026" />
              </div>
            </Show>

            {/* Logs Tab */}
            <Show when={activeTab() === 'logs'}>
              <div class="h-full glass rounded-xl overflow-hidden">
                <RecentLogs logs={() => sampleLogs} strategyName={name()} />
              </div>
            </Show>
          </div>
        </div>

        {/* ─── RIGHT PANEL ─── */}
        <div class="w-[300px] flex-shrink-0 flex flex-col gap-3 overflow-y-auto">
          {/* Parameters */}
          <div class="glass rounded-xl p-4">
            <ParametersTable
              parameters={parameters}
              onChange={(p) => { setParameters(p); setIsDirty(true) }}
            />
          </div>

          {/* Instruments */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Instruments</div>
            <div class="flex flex-wrap gap-1.5 mb-3">
              <For each={instruments()}>
                {(inst) => (
                  <span class="bg-white/5 border border-white/10 text-[10px] font-bold text-gray-300 pl-2.5 pr-1 py-1 rounded-full flex items-center gap-1.5 group">
                    {inst}
                    <button
                      onClick={() => removeInstrument(inst)}
                      class="w-4 h-4 rounded-full flex items-center justify-center text-gray-600 hover:text-rose-400 hover:bg-rose-500/10 transition"
                    >
                      ×
                    </button>
                  </span>
                )}
              </For>
            </div>
            <div class="flex gap-1.5">
              <input
                value={newInstrumentInput()}
                onInput={(e) => setNewInstrumentInput(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && addInstrument()}
                placeholder="Add instrument..."
                class="flex-1 bg-white/5 border border-white/10 rounded-lg px-2.5 py-1.5 text-[11px] text-gray-300 focus:border-primary-500/50 outline-none transition placeholder-gray-700"
              />
              <button
                onClick={addInstrument}
                class="text-[10px] font-bold text-primary-400 hover:text-primary-300 px-2 transition"
              >
                +Add
              </button>
            </div>
          </div>

          {/* Timeframe */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Timeframe</div>
            <div class="flex flex-wrap gap-1.5">
              <For each={timeframes}>
                {(tf) => (
                  <button
                    onClick={() => { setTimeframe(tf); setIsDirty(true) }}
                    class={`px-3 py-1.5 rounded-lg text-xs font-bold transition ${
                      timeframe() === tf
                        ? 'bg-primary-500/20 text-primary-400 border border-primary-500/30'
                        : 'bg-white/5 text-gray-500 border border-white/5 hover:text-gray-300 hover:bg-white/10'
                    }`}
                  >
                    {tf}
                  </button>
                )}
              </For>
            </div>
          </div>

          {/* Trade Direction */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Trade Direction</div>
            <div class="flex gap-1.5">
              <For each={directions}>
                {(dir) => (
                  <button
                    onClick={() => { setDirection(dir); setIsDirty(true) }}
                    class={`flex-1 px-3 py-2 rounded-lg text-xs font-bold transition ${
                      direction() === dir
                        ? 'bg-primary-500/20 text-primary-400 border border-primary-500/30'
                        : 'bg-white/5 text-gray-500 border border-white/5 hover:text-gray-300 hover:bg-white/10'
                    }`}
                  >
                    {dir}
                  </button>
                )}
              </For>
            </div>
          </div>

          {/* Tags */}
          <div class="glass rounded-xl p-4">
            <div class="text-[10px] font-black text-gray-600 uppercase tracking-widest mb-3">Tags</div>
            <div class="flex flex-wrap gap-1.5 mb-3">
              <For each={tags()}>
                {(tag) => (
                  <span class="bg-violet-500/10 border border-violet-500/20 text-[10px] font-bold text-violet-400 pl-2.5 pr-1 py-1 rounded-full flex items-center gap-1.5">
                    {tag}
                    <button
                      onClick={() => removeTag(tag)}
                      class="w-4 h-4 rounded-full flex items-center justify-center text-violet-600 hover:text-rose-400 hover:bg-rose-500/10 transition"
                    >
                      ×
                    </button>
                  </span>
                )}
              </For>
            </div>
            <div class="flex gap-1.5">
              <input
                value={newTagInput()}
                onInput={(e) => setNewTagInput(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && addTag()}
                placeholder="Add tag..."
                class="flex-1 bg-white/5 border border-white/10 rounded-lg px-2.5 py-1.5 text-[11px] text-gray-300 focus:border-primary-500/50 outline-none transition placeholder-gray-700"
              />
              <button
                onClick={addTag}
                class="text-[10px] font-bold text-primary-400 hover:text-primary-300 px-2 transition"
              >
                +Add
              </button>
            </div>
          </div>

          {/* Description */}
          <div class="glass rounded-xl p-4">
            <div class="flex items-center justify-between mb-3">
              <span class="text-[10px] font-black text-gray-600 uppercase tracking-widest">Description</span>
              <span class="text-[10px] text-gray-700 font-bold">{description().length} / 500</span>
            </div>
            <textarea
              value={description()}
              onInput={(e) => { setDescription(e.target.value); setIsDirty(true) }}
              maxLength={500}
              rows={4}
              placeholder="Describe your strategy's logic and purpose..."
              class="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-[11px] text-gray-300 focus:border-primary-500/50 outline-none transition resize-none placeholder-gray-700 leading-relaxed"
            />
          </div>
        </div>
      </div>

      {/* ═══ Bottom: Recent Logs ═══ */}
      <div class="glass rounded-xl flex-shrink-0 overflow-hidden" style="height: 180px">
        <RecentLogs logs={() => sampleLogs} strategyName={name()} />
      </div>
    </div>
  )
}
