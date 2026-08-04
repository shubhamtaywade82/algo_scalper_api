import { createSignal, createMemo, For, Show, createEffect } from 'solid-js'
import { useOptionChain } from '../stores/useOptionChain'
import { useDashboardContext } from '../context/DashboardContext'
import AnimatedNumber from '../components/AnimatedNumber'

export default function OptionChain() {
  const [selectedAsset, setSelectedAsset] = createSignal('NIFTY')
  const [viewMode, setViewMode] = createSignal('Greeks')

  // Wire Option Chain ActionCable store
  const { chain, isStale, connected } = useOptionChain(selectedAsset)
  const { indices } = useDashboardContext()

  const spotPrice = () => indices()?.[selectedAsset().toLowerCase()] || chain()?.spot || 0

  const indexPrevClose = () => {
    return indices()?.[selectedAsset().toLowerCase() + '_prev_close'] || (spotPrice() / 1.0062)
  }

  const spotChange = () => spotPrice() - indexPrevClose()
  const spotChangePct = () => indexPrevClose() > 0 ? (spotChange() / indexPrevClose()) * 100 : 0.62

  const atmStrike = () => chain()?.atm_strike || 0
  const currentExpiry = () => chain()?.expiry || ''

  // Map legs from backend stream to table rows
  const derivedChainRows = createMemo(() => {
    const data = chain()
    if (!data || !data.legs || data.legs.length === 0) {
      return []
    }

    const grouped = {}
    data.legs.forEach(leg => {
      const strike = leg.strike
      if (!grouped[strike]) {
        grouped[strike] = { strike, isATM: strike === data.atm_strike }
      }

      const pClose = leg.prev_close || 0
      const changePct = pClose > 0 ? ((leg.ltp - pClose) / pClose) * 100 : 0

      if (leg.type === 'CE') {
        grouped[strike].c_oi = leg.oi || 0
        grouped[strike].c_choi = leg.oi_change || 0
        grouped[strike].c_vol = leg.volume || 0
        grouped[strike].c_ltp = leg.ltp || 0
        grouped[strike].c_chg = changePct
        grouped[strike].c_iv = leg.iv || 0
        grouped[strike].c_delta = leg.delta || 0
        grouped[strike].c_gamma = leg.gamma || 0
        grouped[strike].c_theta = leg.theta || 0
        grouped[strike].c_vega = leg.vega || 0
      } else if (leg.type === 'PE') {
        grouped[strike].p_oi = leg.oi || 0
        grouped[strike].p_choi = leg.oi_change || 0
        grouped[strike].p_vol = leg.volume || 0
        grouped[strike].p_ltp = leg.ltp || 0
        grouped[strike].p_chg = changePct
        grouped[strike].p_iv = leg.iv || 0
        grouped[strike].p_delta = leg.delta || 0
        grouped[strike].p_gamma = leg.gamma || 0
        grouped[strike].p_theta = leg.theta || 0
        grouped[strike].p_vega = leg.vega || 0
      }
    })

    return Object.values(grouped).sort((a, b) => a.strike - b.strike)
  })

  // Dynamic calculations based on live table rows
  const summary = createMemo(() => {
    let callOi = 0
    let putOi = 0
    let callChoi = 0
    let putChoi = 0
    let maxCallOi = -1
    let maxCallOiStrike = atmStrike()

    derivedChainRows().forEach(r => {
      callOi += r.c_oi || 0
      putOi += r.p_oi || 0
      callChoi += r.c_choi || 0
      putChoi += r.p_choi || 0
      if ((r.c_oi || 0) > maxCallOi) {
        maxCallOi = r.c_oi
        maxCallOiStrike = r.strike
      }
    })

    const totalOi = callOi + putOi
    const totalChoi = callChoi + putChoi
    const pcr = callOi > 0 ? (putOi / callOi) : 0
    const putPct = totalOi > 0 ? Math.round((putOi / totalOi) * 100) : 0
    const callPct = 100 - putPct

    // Calculate dynamic OI change percentages
    const callOiChangePct = (callOi - callChoi) > 0 ? (callChoi / (callOi - callChoi)) * 100 : 0
    const putOiChangePct = (putOi - putChoi) > 0 ? (putChoi / (putOi - putChoi)) * 100 : 0
    const totalOiChangePct = (totalOi - totalChoi) > 0 ? (totalChoi / (totalOi - totalChoi)) * 100 : 0

    // Find live ATM IV
    const atm = atmStrike()
    const atmRow = derivedChainRows().find(r => r.strike === atm)
    const atmIv = atmRow ? (atmRow.c_iv || atmRow.p_iv || 0) : 0

    return {
      callOi,
      putOi,
      totalOi,
      totalChoi,
      pcr,
      putPct,
      callPct,
      maxPain: maxCallOiStrike,
      atmIv,
      callOiChangePct,
      putOiChangePct,
      totalOiChangePct
    }
  })

  const [history, setHistory] = createSignal([])

  createEffect(() => {
    selectedAsset()
    setHistory([])
  })

  createEffect(() => {
    const pcr = summary().pcr
    const maxPain = summary().maxPain
    if (pcr > 0 || maxPain > 0) {
      setHistory(prev => {
        const next = [...prev, { pcr, maxPain, time: Date.now() }]
        return next.slice(-50)
      })
    }
  })

  const pcrPath = createMemo(() => {
    const data = history()
    if (data.length < 2) return 'M 0,30 L 200,30'
    const values = data.map(d => d.pcr)
    const min = Math.min(...values)
    const max = Math.max(...values)
    const range = max - min

    return data.map((d, i) => {
      const x = (i / (data.length - 1)) * 200
      const y = range > 0 ? 50 - ((d.pcr - min) / range) * 40 : 30
      return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)},${y.toFixed(1)}`
    }).join(' ')
  })

  const maxPainPath = createMemo(() => {
    const data = history()
    if (data.length < 2) return 'M 0,30 L 200,30'
    const values = data.map(d => d.maxPain)
    const min = Math.min(...values)
    const max = Math.max(...values)
    const range = max - min

    return data.map((d, i) => {
      const x = (i / (data.length - 1)) * 200
      const y = range > 0 ? 50 - ((d.maxPain - min) / range) * 40 : 30
      return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)},${y.toFixed(1)}`
    }).join(' ')
  })

  // Greeks Summary for ATM strike (read from live ticks)
  const Greeks = createMemo(() => {
    const atm = atmStrike()
    const match = derivedChainRows().find(r => r.strike === atm)
    return {
      c_delta: match?.c_delta || 0,
      c_gamma: match?.c_gamma || 0,
      c_theta: match?.c_theta || 0,
      c_vega: match?.c_vega || 0,
      c_rho: 0,
      p_delta: match?.p_delta || 0,
      p_gamma: match?.p_gamma || 0,
      p_theta: match?.p_theta || 0,
      p_vega: match?.p_vega || 0,
      p_rho: 0
    }
  })

  // Left & Right classes based on ITM / OTM
  const callsTdClass = (strike) => {
    return strike < atmStrike() ? 'bg-primary-500/2.5 hover:bg-primary-500/5' : 'hover:bg-white/[0.01]'
  }
  const putsTdClass = (strike) => {
    return strike > atmStrike() ? 'bg-primary-500/2.5 hover:bg-primary-500/5' : 'hover:bg-white/[0.01]'
  }

  return (
    <div class="space-y-6">
      {/* Filters & Workspace Header */}
      <div class="flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div class="flex flex-wrap items-center gap-3">
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Index / Stock</span>
            <select
              value={selectedAsset()}
              onChange={(e) => setSelectedAsset(e.target.value)}
              class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg text-white font-mono"
            >
              <option value="NIFTY">NIFTY</option>
              <option value="BANKNIFTY">BANKNIFTY</option>
              <option value="SENSEX">SENSEX</option>
            </select>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">Expiry Date</span>
            <select class="glass-select text-[10px] px-2.5 py-1.5 rounded-lg">
              <option>{currentExpiry() ? `${currentExpiry()} (Weekly)` : 'Loading...'}</option>
            </select>
          </div>
          <div class="flex flex-col">
            <span class="text-[7px] text-gray-500 font-black uppercase tracking-wider mb-1">View Columns</span>
            <div class="flex items-center bg-white/5 rounded-lg p-0.5 border border-white/5">
              <button
                onClick={() => setViewMode('LTP')}
                class={`px-2.5 py-1 rounded-md text-[9px] font-black uppercase tracking-wider ${viewMode() === 'LTP' ? 'bg-primary-600 text-white' : 'text-gray-400'}`}
              >
                LTP
              </button>
              <button
                onClick={() => setViewMode('OI')}
                class={`px-2.5 py-1 rounded-md text-[9px] font-black uppercase tracking-wider ${viewMode() === 'OI' ? 'bg-primary-600 text-white' : 'text-gray-400'}`}
              >
                OI
              </button>
              <button
                onClick={() => setViewMode('Greeks')}
                class={`px-2.5 py-1 rounded-md text-[9px] font-black uppercase tracking-wider ${viewMode() === 'Greeks' ? 'bg-primary-600 text-white' : 'text-gray-400'}`}
              >
                Greeks
              </button>
            </div>
          </div>
        </div>

        <div class="flex items-center gap-2.5">
          <div class="flex items-center gap-2 px-3 py-1.5 bg-white/[0.02] border border-white/5 rounded-xl">
            <span class={`w-1.5 h-1.5 rounded-full ${connected() ? 'bg-emerald-400' : 'bg-rose-400 animate-pulse'}`} />
            <span class="text-[9px] font-black uppercase tracking-widest text-gray-400">
              {connected() ? 'Feed Connected' : 'Feed Closed'}
            </span>
          </div>
          <button class="px-4 py-2 bg-white/[0.03] border border-white/5 rounded-xl text-xs font-bold uppercase tracking-wider text-gray-300 hover:bg-white/[0.06] hover:text-white transition-all">
            Settings
          </button>
          <button class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all">
            Strategy Builder
          </button>
        </div>
      </div>

      {/* Spot Price & OI Summary Metrics */}
      <Show when={spotPrice() > 0 || derivedChainRows().length > 0} fallback={
        <div class="flex items-center justify-center h-20 bg-white/[0.01] border border-dashed border-white/10 rounded-2xl">
          <span class="text-xs text-gray-600 font-bold uppercase tracking-wider">Waiting for market data...</span>
        </div>
      }>
      <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-9 gap-4">
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Spot Price</span>
          <div class="text-sm font-black text-emerald-400 text-data">
            <AnimatedNumber value={spotPrice()} decimals={2} />
          </div>
          <span class="text-[8px] font-bold text-emerald-500 mt-0.5 block">
            {spotChange() >= 0 ? '+' : ''}
            <AnimatedNumber value={spotChange()} decimals={2} /> ({spotChangePct().toFixed(2)}%)
          </span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">IV (ATM)</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().atmIv} decimals={2} />%
          </div>
          <span class="text-[8px] font-bold text-gray-500 mt-0.5 block">Implied Volatility</span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">PCR (OI)</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().pcr} decimals={2} />
          </div>
          <span class="text-[8px] text-gray-500 mt-0.5 block">Overall</span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Max Pain</span>
          <div class="text-sm font-black text-amber-500 text-data">
            <AnimatedNumber value={summary().maxPain} decimals={0} />
          </div>
          <span class="text-[8px] text-gray-500 mt-0.5 block">Strike</span>
        </div>
        <div class="glass p-3.5 rounded-xl col-span-2">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Total OI (Contracts)</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().totalOi} decimals={0} />
          </div>
          <span class={`text-[8px] font-bold mt-0.5 block ${summary().totalOiChangePct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
            {summary().totalOiChangePct >= 0 ? '+' : ''}{summary().totalOiChangePct.toFixed(2)}%
          </span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Call OI</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().callOi} decimals={0} />
          </div>
          <span class={`text-[8px] font-bold mt-0.5 block ${summary().callOiChangePct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
            {summary().callOiChangePct >= 0 ? '+' : ''}{summary().callOiChangePct.toFixed(2)}%
          </span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Put OI</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().putOi} decimals={0} />
          </div>
          <span class={`text-[8px] font-bold mt-0.5 block ${summary().putOiChangePct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>
            {summary().putOiChangePct >= 0 ? '+' : ''}{summary().putOiChangePct.toFixed(2)}%
          </span>
        </div>
        <div class="glass p-3.5 rounded-xl flex flex-col justify-between">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block">Put/Call Ratio</span>
          <div class="w-full bg-rose-500 h-1.5 rounded-full overflow-hidden mt-1.5 flex">
            <div class="bg-emerald-500 h-full" style={`width: ${summary().callPct}%`} />
          </div>
          <div class="flex justify-between text-[7px] font-black uppercase text-gray-500 mt-1">
            <span>P: {summary().putPct}%</span>
            <span>C: {summary().callPct}%</span>
          </div>
        </div>
      </div>
      </Show>

      {/* Main Options Chain Workspace Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Columns (9 units): Option Chain Table */}
        <div class="lg:col-span-9 glass p-5 rounded-2xl flex flex-col justify-between overflow-x-auto">
          <Show when={derivedChainRows().length > 0} fallback={
            <div class="text-center py-12 text-xs font-black text-gray-500 uppercase tracking-widest animate-pulse">
              Waiting for live option chain stream...
            </div>
          }>
            <table class="w-full text-center border-collapse text-[10px]">
              <thead>
                <tr class="border-b border-white/5">
                  <th colspan="9" class="py-2.5 text-emerald-400 font-black uppercase tracking-[0.2em] bg-emerald-500/5 rounded-tl-xl">CALLS</th>
                  <th class="py-2.5 font-black uppercase tracking-wider bg-white/5">STRIKE</th>
                  <th colspan="9" class="py-2.5 text-rose-400 font-black uppercase tracking-[0.2em] bg-rose-500/5 rounded-tr-xl">PUTS</th>
                </tr>
                <tr class="text-gray-500 font-black uppercase border-b border-white/5 bg-white/[0.01]">
                  <th class="py-2.5">OI</th>
                  <th>Chg OI</th>
                  <th>Vol</th>
                  <th>Vega</th>
                  <th>Theta</th>
                  <th>Delta</th>
                  <th>IV</th>
                  <th>Chg %</th>
                  <th class="text-emerald-400">LTP</th>
                  <th class="text-white bg-white/5">Price</th>
                  <th class="text-rose-400">LTP</th>
                  <th>Chg %</th>
                  <th>IV</th>
                  <th>Delta</th>
                  <th>Theta</th>
                  <th>Vega</th>
                  <th>Vol</th>
                  <th>Chg OI</th>
                  <th>OI</th>
                </tr>
              </thead>
              <tbody>
                <For each={derivedChainRows()}>
                  {(r) => (
                    <tr class={`border-b border-white/5 transition-colors ${r.isATM ? 'bg-violet-500/10 hover:bg-violet-500/15 font-black' : ''}`}>
                      {/* CALLS */}
                      <td class={`py-2 text-data text-gray-400 ${callsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.c_oi} decimals={0} />
                      </td>
                      <td class={`text-data ${r.c_choi >= 0 ? 'text-emerald-400' : 'text-rose-400'} ${callsTdClass(r.strike)}`}>
                        {r.c_choi >= 0 ? '+' : ''}<AnimatedNumber value={r.c_choi} decimals={0} />
                      </td>
                      <td class={`text-data text-gray-500 ${callsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.c_vol} decimals={0} />
                      </td>
                      <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_vega.toFixed(2)}</td>
                      <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_theta.toFixed(2)}</td>
                      <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_delta.toFixed(2)}</td>
                      <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.c_iv} decimals={2} />%
                      </td>
                      <td class={`text-data ${r.c_chg >= 0 ? 'text-emerald-400' : 'text-rose-500'} ${callsTdClass(r.strike)}`}>
                        {r.c_chg >= 0 ? '+' : ''}<AnimatedNumber value={r.c_chg} decimals={2} />%
                      </td>
                      <td class={`text-data font-black text-white ${callsTdClass(r.strike)}`}>
                        ₹<AnimatedNumber value={r.c_ltp} decimals={2} />
                      </td>

                      {/* STRIKE */}
                      <td class={`py-2 text-data font-black text-white bg-white/5 border-x border-white/5`}>
                        {r.strike.toLocaleString()}
                      </td>

                      {/* PUTS */}
                      <td class={`text-data font-black text-white ${putsTdClass(r.strike)}`}>
                        ₹<AnimatedNumber value={r.p_ltp} decimals={2} />
                      </td>
                      <td class={`text-data ${r.p_chg >= 0 ? 'text-emerald-400' : 'text-rose-500'} ${putsTdClass(r.strike)}`}>
                        {r.p_chg >= 0 ? '+' : ''}<AnimatedNumber value={r.p_chg} decimals={2} />%
                      </td>
                      <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.p_iv} decimals={2} />%
                      </td>
                      <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>{r.p_delta.toFixed(2)}</td>
                      <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>{r.p_theta.toFixed(2)}</td>
                      <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>{r.p_vega.toFixed(2)}</td>
                      <td class={`text-data text-gray-500 ${putsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.p_vol} decimals={0} />
                      </td>
                      <td class={`text-data ${r.p_choi >= 0 ? 'text-emerald-400' : 'text-rose-400'} ${putsTdClass(r.strike)}`}>
                        {r.p_choi >= 0 ? '+' : ''}<AnimatedNumber value={r.p_choi} decimals={0} />
                      </td>
                      <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>
                        <AnimatedNumber value={r.p_oi} decimals={0} />
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </Show>
        </div>

        {/* Right Columns (3 units): Charts Sidebar */}
        <div class="lg:col-span-3 space-y-6">
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-white">{selectedAsset()}{currentExpiry() ? ` ${currentExpiry()} (Weekly)` : ' — Loading...'}</span>
            </div>
            <div class="text-[10px] space-y-2.5">
              <div class="flex justify-between border-b border-white/5 pb-2">
                <span class="text-gray-500 font-bold uppercase">Spot Price</span>
                <span class="font-black text-emerald-400">
                  <AnimatedNumber value={spotPrice()} decimals={2} />
                </span>
              </div>
              <div class="flex justify-between border-b border-white/5 pb-2">
                <span class="text-gray-500 font-bold uppercase">Change</span>
                <span class="font-black text-emerald-400">
                  {spotChange() >= 0 ? '+' : ''}
                  <AnimatedNumber value={spotChange()} decimals={2} /> ({spotChangePct().toFixed(2)}%)
                </span>
              </div>
              <div class="flex justify-between">
                <span class="text-gray-500 font-bold uppercase">Max Pain</span>
                <span class="font-black text-amber-500">
                  <AnimatedNumber value={summary().maxPain} decimals={0} />
                </span>
              </div>
            </div>
          </div>

          {/* Open Interest Strike Chart */}
          <div class="glass p-5 rounded-2xl flex flex-col justify-between h-[220px]">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-gray-400 uppercase tracking-widest font-bold">Open Interest (by Strike)</span>
              <div class="flex items-center gap-1.5 text-[8px] font-bold">
                <span class="text-emerald-400">Calls</span>
                <span class="text-rose-400">Puts</span>
              </div>
            </div>
            <div class="flex-1 flex flex-col justify-between py-2 text-[9px]">
              <Show when={derivedChainRows().length > 0} fallback={
                <div class="text-center py-8 text-gray-600 text-[10px] uppercase font-bold">No Data</div>
              }>
                <For each={derivedChainRows().slice(Math.max(0, derivedChainRows().length / 2 - 3), Math.min(derivedChainRows().length, derivedChainRows().length / 2 + 3))}>
                  {(r) => (
                    <div class="flex items-center justify-between gap-2">
                      <span class="w-10 text-gray-500 font-mono">{r.strike.toLocaleString()}</span>
                      <div class="flex-1 h-3 flex gap-0.5">
                        <div class="bg-emerald-500 h-full rounded" style={`width: ${Math.min(100, (r.c_oi / Math.max(1, summary().totalOi * 0.1)) * 100)}%`} />
                        <div class="bg-rose-500 h-full rounded" style={`width: ${Math.min(100, (r.p_oi / Math.max(1, summary().totalOi * 0.1)) * 100)}%`} />
                      </div>
                    </div>
                  )}
                </For>
              </Show>
            </div>
          </div>
        </div>
      </div>

      {/* Greeks and PCR/Max Pain Analysis Row */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Greeks Details Card (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
            <span class="font-black text-gray-400 uppercase tracking-widest font-bold">Greeks {atmStrike() ? `(ATM: ${atmStrike().toLocaleString()})` : ''}</span>
            <div class="flex items-center gap-1.5 text-[8px] font-black uppercase">
              <span class="text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/20">Calls</span>
              <span class="text-rose-400 bg-rose-500/10 px-1.5 py-0.5 rounded border border-rose-500/20">Puts</span>
            </div>
          </div>
          <div class="grid grid-cols-5 gap-3 mt-3 text-[10px]">
            <div class="text-center font-bold text-gray-600 uppercase text-[8px]">Delta</div>
            <div class="text-center font-bold text-gray-600 uppercase text-[8px]">Gamma</div>
            <div class="text-center font-bold text-gray-600 uppercase text-[8px]">Theta</div>
            <div class="text-center font-bold text-gray-600 uppercase text-[8px]">Vega</div>
            <div class="text-center font-bold text-gray-600 uppercase text-[8px]">Rho</div>
            <div class="text-center font-black text-emerald-400 text-data">{Greeks().c_delta.toFixed(4)}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_gamma.toFixed(4)}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().c_theta.toFixed(4)}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_vega.toFixed(4)}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_rho.toFixed(4)}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_delta.toFixed(4)}</div>
            <div class="text-center font-black text-white text-data">{Greeks().p_gamma.toFixed(4)}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_theta.toFixed(4)}</div>
            <div class="text-center font-black text-white text-data">{Greeks().p_vega.toFixed(4)}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_rho.toFixed(4)}</div>
          </div>
        </div>

        {/* PCR Historical Line Chart (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between h-[180px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
            <span class="font-black text-gray-400 uppercase tracking-widest font-bold">PCR (Historical)</span>
            <span class="text-emerald-400 font-bold text-data">
              <AnimatedNumber value={summary().pcr} decimals={2} />
            </span>
          </div>
          <div class="flex-1 py-3">
            <svg viewBox="0 0 200 60" class="w-full h-full">
              <path d={pcrPath()} fill="none" stroke="rgb(16, 185, 129)" stroke-width="2" />
            </svg>
          </div>
        </div>

        {/* Max Pain Historical Line Chart (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between h-[180px]">
          <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
            <span class="font-black text-gray-400 uppercase tracking-widest font-bold">Max Pain (Historical)</span>
            <span class="text-amber-500 font-bold text-data">
              <AnimatedNumber value={summary().maxPain} decimals={0} />
            </span>
          </div>
          <div class="flex-1 py-3">
            <svg viewBox="0 0 200 60" class="w-full h-full">
              <path d={maxPainPath()} fill="none" stroke="rgb(245, 158, 11)" stroke-width="2" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  )
}
