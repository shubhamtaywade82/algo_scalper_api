import { createSignal, onMount, createMemo, Show, createEffect } from 'solid-js'
import { useParams, useNavigate } from '@solidjs/router'
import { useStrategies } from '../stores/useStrategies'
import CodeEditor from '../components/strategies/CodeEditor'
import ParametersTable from '../components/strategies/ParametersTable'
import StrategyFlowChart from '../components/strategies/StrategyFlowChart'
import BacktestPreview from '../components/strategies/BacktestPreview'
import RecentLogs from '../components/strategies/RecentLogs'

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

function scanReportToErrors(scanReport) {
  if (!scanReport) return []
  const blocked = (scanReport.blocked || []).map(f => ({ line: f.line || 1, message: f.message, severity: 'error' }))
  const warnings = (scanReport.warnings || []).map(f => ({ line: f.line || 1, message: f.message, severity: 'warning' }))
  return [...blocked, ...warnings]
}

export default function StrategyCreator() {
  const params = useParams()
  const navigate = useNavigate()
  const { currentStrategy, fetchOne, create, update, validateStrategy, loading } = useStrategies()

  // State signals
  const [name, setName] = createSignal('New Strategy')
  const [version, setVersion] = createSignal('1.0.0')
  const [status, setStatus] = createSignal('draft')
  const [code, setCode] = createSignal('')
  const [description, setDescription] = createSignal('')
  const [author, setAuthor] = createSignal('System')
  const [runtime, setRuntime] = createSignal('Ruby')
  const [timeframe, setTimeframe] = createSignal('1m')
  const [tradeDirection, setTradeDirection] = createSignal('both')
  const [parameters, setParameters] = createSignal([])
  const [instruments, setInstruments] = createSignal(['NIFTY'])
  const [tags, setTags] = createSignal(['Intraday'])
  const [checks, setChecks] = createSignal({ syntax: 'not_run', logic: 'not_run', risk: 'not_run', backtest: 'not_run' })
  const [backtestResults, setBacktestResults] = createSignal({})
  const [codeErrors, setCodeErrors] = createSignal(null)

  const [activeTab, setActiveTab] = createSignal('Code')
  const [newInstrument, setNewInstrument] = createSignal('')
  const [newTag, setNewTag] = createSignal('')
  const [isSaved, setIsSaved] = createSignal(true)

  // Load strategy if ID is present
  onMount(async () => {
    if (params.id) {
      const data = await fetchOne(params.id)
      if (data) {
        setName(data.name || '')
        setVersion(data.version || '1.0.0')
        setStatus(data.status || 'draft')
        setCode(data.code || '')
        setDescription(data.description || '')
        setAuthor(data.author || 'System')
        setRuntime(data.runtime || 'Ruby')
        setTimeframe(data.timeframe || '1m')
        setTradeDirection(data.trade_direction || 'both')
        setParameters(data.parameters || [])
        setInstruments(data.instruments || [])
        setTags(data.tags || [])
        setChecks(data.checks || { syntax: 'not_run', logic: 'not_run', risk: 'not_run', backtest: 'not_run' })
        setBacktestResults(data.backtest_results || {})
        setIsSaved(true)
      }
    }
  })

  // Mark form as dirty when changes occur
  createEffect(() => {
    // track changes to trigger unsaved indicator
    name()
    version()
    code()
    description()
    timeframe()
    tradeDirection()
    parameters()
    instruments()
    tags()
    setIsSaved(false)
  })

  const saveStrategy = async () => {
    const payload = {
      name: name(),
      version: version(),
      status: status(),
      code: code(),
      description: description(),
      author: author(),
      runtime: runtime(),
      timeframe: timeframe(),
      trade_direction: tradeDirection(),
      parameters: parameters(),
      instruments: instruments(),
      tags: tags(),
      checks: checks(),
      backtest_results: backtestResults()
    }

    if (params.id) {
      await update(params.id, payload)
    } else {
      const res = await create(payload)
      if (res && res.id) {
        navigate(`/strategies/${res.id}`, { replace: true })
      }
    }
    setIsSaved(true)
  }

  const runValidation = async () => {
    if (!params.id) return
    const res = await validateStrategy(params.id)
    if (res && res.checks) {
      setChecks(res.checks)
      if (res.backtest_results) setBacktestResults(res.backtest_results)
      
      if (res.scan_report) {
        setCodeErrors(scanReportToErrors(res.scan_report))
      } else {
        const errs = []
        if (res.checks.syntax === 'failed') {
          errs.push({ line: 1, message: 'Ruby syntax validation failed', severity: 'error' })
        }
        if (res.checks.risk === 'failed') {
          errs.push({ line: 1, message: 'Security scanner blocked unsafe calls', severity: 'error' })
        }
        setCodeErrors(errs)
      }
    }
  }

  const addInstrument = () => {
    if (newInstrument() && !instruments().includes(newInstrument().toUpperCase())) {
      setInstruments([...instruments(), newInstrument().toUpperCase()])
      setNewInstrument('')
    }
  }

  const removeInstrument = (inst) => {
    setInstruments(instruments().filter(i => i !== inst))
  }

  const addTag = () => {
    if (newTag() && !tags().includes(newTag())) {
      setTags([...tags(), newTag()])
      setNewTag('')
    }
  }

  const removeTag = (t) => {
    setTags(tags().filter(item => item !== t))
  }

  return (
    <div class="space-y-6">
      {/* Top action bar */}
      <div class="flex items-center justify-between bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex items-center gap-3">
          <button
            onClick={() => navigate('/strategies')}
            class="px-3.5 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all"
          >
            ← Back
          </button>
          <div class="flex flex-col">
            <div class="flex items-center gap-2">
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">
                Strategies / My Strategies
              </span>
              <Show when={!isSaved()}>
                <span class="text-[8px] font-black uppercase text-amber-400 bg-amber-500/10 px-1.5 py-0.5 rounded border border-amber-500/20">
                  Unsaved Changes
                </span>
              </Show>
            </div>
            <div class="flex items-center gap-2.5">
              <span class="text-sm font-black text-white uppercase tracking-wide">{name()}</span>
              <span class="text-[9px] font-mono text-gray-500">v{version()}</span>
              <span class="text-[9px] font-mono text-primary-400">({status()})</span>
            </div>
          </div>
        </div>

        <div class="flex items-center gap-2.5">
          <button
            onClick={saveStrategy}
            class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all"
          >
            Save Draft
          </button>
          <button
            onClick={runValidation}
            disabled={!params.id}
            class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all disabled:opacity-40"
          >
            Test Strategy
          </button>
          <button class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all">
            Deploy
          </button>
        </div>
      </div>

      {/* Main 3-column workspace */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        {/* Left Column: Side Info & Anchors (2 cols) */}
        <div class="lg:col-span-2 space-y-6">
          {/* Section Navigation */}
          <div class="glass p-4 rounded-2xl space-y-4">
            <input
              type="text"
              value={name()}
              onInput={(e) => setName(e.target.value)}
              class="w-full bg-white/5 border border-white/5 rounded-lg px-3 py-1.5 text-xs text-white outline-none font-bold"
              placeholder="Strategy Name"
            />

            <div class="space-y-1 text-[10px] font-black uppercase tracking-wider text-gray-500">
              <button class="w-full text-left px-2 py-1.5 rounded-lg text-primary-400 bg-primary-500/5 font-bold">Strategy Builder</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Entry Rules</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Exit Rules</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Risk Management</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Filters</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Parameters</button>
              <button class="w-full text-left px-2 py-1.5 rounded-lg hover:text-white hover:bg-white/5">Schedule</button>
            </div>
          </div>

          {/* Strategy Status checks */}
          <div class="glass p-4 rounded-2xl">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-3">Strategy Status</span>
            <div class="space-y-2.5 text-[10px] font-bold text-gray-400">
              <div class="flex items-center justify-between">
                <span>Syntax Check</span>
                <span class={checks().syntax === 'passed' ? 'text-emerald-400 font-black' : 'text-gray-600'}>
                  {checks().syntax === 'passed' ? 'Passed' : 'Not Run'}
                </span>
              </div>
              <div class="flex items-center justify-between">
                <span>Logic Check</span>
                <span class={checks().logic === 'passed' ? 'text-emerald-400 font-black' : 'text-gray-600'}>
                  {checks().logic === 'passed' ? 'Passed' : 'Not Run'}
                </span>
              </div>
              <div class="flex items-center justify-between">
                <span>Risk Check</span>
                <span class={checks().risk === 'passed' ? 'text-emerald-400 font-black' : 'text-gray-600'}>
                  {checks().risk === 'passed' ? 'Passed' : 'Not Run'}
                </span>
              </div>
              <div class="flex items-center justify-between">
                <span>Backtest</span>
                <span class={checks().backtest === 'passed' ? 'text-emerald-400 font-black' : 'text-gray-600'}>
                  {checks().backtest === 'passed' ? 'Passed' : 'Not Run'}
                </span>
              </div>
            </div>
          </div>

          {/* Strategy Info metadata */}
          <div class="glass p-4 rounded-2xl space-y-2.5 text-[9px] font-bold text-gray-400">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Strategy Info</span>
            <div class="flex justify-between">
              <span class="text-gray-500">Author</span>
              <span class="text-white font-black">{author()}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-500">Runtime</span>
              <span class="text-white font-black font-mono">{runtime()}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-500">Timeframe</span>
              <span class="text-white font-black font-mono">{timeframe()}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-gray-500">Version</span>
              <span class="text-white font-black font-mono">{version()}</span>
            </div>
          </div>
        </div>

        {/* Center Column: Editor & Tab Panel (7 cols) */}
        <div class="lg:col-span-7 space-y-6">
          {/* Main workspace Tabs */}
          <div class="glass p-4 rounded-2xl flex flex-col min-h-[500px]">
            {/* Tab buttons */}
            <div class="flex items-center border-b border-white/5 pb-2.5 gap-2">
              {['Builder', 'Code', 'Backtest', 'Logs'].map(tab => (
                <button
                  onClick={() => setActiveTab(tab)}
                  class={`px-4 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all ${
                    activeTab() === tab ? 'bg-primary-600/15 text-primary-400 border border-primary-500/30' : 'text-gray-400 hover:text-white border border-transparent'
                  }`}
                >
                  {tab === 'Builder' ? 'Builder (Visual)' : tab === 'Code' ? 'Code (Ruby)' : tab === 'Backtest' ? 'Backtest' : 'Live Logs'}
                </button>
              ))}
            </div>

            {/* Tab content view */}
            <div class="flex-1 mt-4 flex flex-col min-h-0">
              <Show when={activeTab() === 'Builder'}>
                <StrategyFlowChart strategyName={name()} />
              </Show>

              <Show when={activeTab() === 'Code'}>
                <CodeEditor code={code} onChange={setCode} language="ruby" errors={codeErrors} />
              </Show>

              <Show when={activeTab() === 'Backtest'}>
                <BacktestPreview results={backtestResults} />
              </Show>

              <Show when={activeTab() === 'Logs'}>
                <RecentLogs logs={sampleLogs} strategyName={name()} />
              </Show>
            </div>
          </div>

          {/* Bottom split panels (Flowchart + Backtest compact preview) */}
          <Show when={activeTab() === 'Code'}>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6 h-[250px]">
              <StrategyFlowChart strategyName={name()} />
              <BacktestPreview results={backtestResults} />
            </div>
          </Show>
        </div>

        {/* Right Column: Properties & Input Table (3 cols) */}
        <div class="lg:col-span-3 space-y-6">
          {/* Parameters table */}
          <div class="glass p-5 rounded-2xl">
            <ParametersTable parameters={parameters} onChange={setParameters} />
          </div>

          {/* Instruments */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest font-bold">Instruments</span>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <For each={instruments()}>
                {inst => (
                  <span class="flex items-center gap-1 text-[9px] font-black uppercase tracking-wider bg-primary-600/10 text-primary-400 border border-primary-500/10 px-2 py-0.5 rounded-lg">
                    {inst}
                    <button onClick={() => removeInstrument(inst)} class="hover:text-white">×</button>
                  </span>
                )}
              </For>
            </div>
            <div class="flex gap-2">
              <input
                type="text"
                value={newInstrument()}
                onInput={(e) => setNewInstrument(e.target.value)}
                placeholder="e.g. SENSEX"
                class="flex-1 bg-white/5 border border-white/5 rounded-lg px-2.5 py-1 text-[9px] text-white outline-none font-mono"
              />
              <button
                onClick={addInstrument}
                class="px-3 py-1 bg-primary-600 hover:bg-primary-500 text-[9px] text-white font-bold uppercase rounded-lg"
              >
                + Add
              </button>
            </div>
          </div>

          {/* Timeframe */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block">Timeframe</span>
            <div class="grid grid-cols-6 gap-1.5 bg-white/5 rounded-lg p-0.5 border border-white/5">
              {['1m', '3m', '5m', '15m', '1h', '1D'].map(tf => (
                <button
                  onClick={() => setTimeframe(tf)}
                  class={`py-1 text-[9px] font-black uppercase tracking-wider rounded-md ${timeframe() === tf ? 'bg-primary-600 text-white' : 'text-gray-400 hover:text-white'}`}
                >
                  {tf}
                </button>
              ))}
            </div>
          </div>

          {/* Trade Direction */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block">Trade Direction</span>
            <div class="grid grid-cols-3 gap-1.5 bg-white/5 rounded-lg p-0.5 border border-white/5">
              {['long', 'short', 'both'].map(dir => (
                <button
                  onClick={() => setTradeDirection(dir)}
                  class={`py-1.5 text-[9px] font-black uppercase tracking-wider rounded-md ${tradeDirection() === dir ? 'bg-primary-600 text-white' : 'text-gray-400 hover:text-white'}`}
                >
                  {dir}
                </button>
              ))}
            </div>
          </div>

          {/* Strategy Tags */}
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block">Strategy Tags</span>
            <div class="flex flex-wrap gap-1.5">
              <For each={tags()}>
                {t => (
                  <span class="flex items-center gap-1 text-[9px] font-black uppercase tracking-wider bg-white/5 text-gray-300 border border-white/5 px-2 py-0.5 rounded-lg">
                    {t}
                    <button onClick={() => removeTag(t)} class="hover:text-white">×</button>
                  </span>
                )}
              </For>
            </div>
            <div class="flex gap-2">
              <input
                type="text"
                value={newTag()}
                onInput={(e) => setNewTag(e.target.value)}
                placeholder="e.g. Trend"
                class="flex-1 bg-white/5 border border-white/5 rounded-lg px-2.5 py-1 text-[9px] text-white outline-none"
              />
              <button
                onClick={addTag}
                class="px-3 py-1 bg-primary-600 hover:bg-primary-500 text-[9px] text-white font-bold uppercase rounded-lg"
              >
                + Add
              </button>
            </div>
          </div>

          {/* Description */}
          <div class="glass p-5 rounded-2xl space-y-2.5">
            <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block">Description</span>
            <textarea
              value={description()}
              onInput={(e) => setDescription(e.target.value)}
              maxLength={500}
              class="w-full bg-white/5 border border-white/5 rounded-lg p-2.5 text-[10px] text-gray-300 outline-none resize-none h-24"
              placeholder="Describe the strategy rules and setup..."
            />
            <span class="text-[8px] text-gray-500 block text-right">
              {description().length} / 500
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}
