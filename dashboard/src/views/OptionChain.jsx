import { createSignal, createMemo, For, Show } from 'solid-js'
import { useOptionChain } from '../stores/useOptionChain'
import AnimatedNumber from '../components/AnimatedNumber'

export default function OptionChain() {
  const [selectedAsset, setSelectedAsset] = createSignal('NIFTY')
  const [viewMode, setViewMode] = createSignal('Greeks')

  // Wire Option Chain store with active asset key
  const { chain, isStale, connected } = useOptionChain(selectedAsset)

  // Dynamic spot & change calculations
  const spotPrice = () => chain()?.spot || 22015.60
  const spotChange = () => {
    const spot = spotPrice()
    return spot * 0.0062 // Mocking dynamic change matching 0.62%
  }
  const spotChangePct = () => 0.62
  const atmStrike = () => chain()?.atm_strike || 22000
  const currentExpiry = () => chain()?.expiry || '06 JUN 2024'

  // Map legs from backend stream to table rows
  const derivedChainRows = createMemo(() => {
    const data = chain()
    if (!data || !data.legs || data.legs.length === 0) {
      // Fallback fallback data so the view isn't empty on boot
      return [
        { strike: 21600, c_oi: 193350, c_choi: 12890, c_vol: 305210, c_ltp: 441.15, c_chg: 4.10, c_iv: 15.3, c_delta: 0.79, c_theta: -3.61, c_vega: 10.62, p_ltp: 64.85, p_chg: -3.49, p_iv: 15.7, p_delta: -0.21, p_theta: -0.85, p_vega: 1.90, p_vol: 158920, p_choi: 7215, p_oi: 163200 },
        { strike: 21700, c_oi: 218900, c_choi: 15320, c_vol: 382450, c_ltp: 356.80, c_chg: 3.75, c_iv: 15.1, c_delta: 0.72, c_theta: -3.05, c_vega: 8.85, p_ltp: 77.30, p_chg: -3.21, p_iv: 15.5, p_delta: -0.28, p_theta: -1.02, p_vega: 2.25, p_vol: 182330, p_choi: 8320, p_oi: 190650 },
        { strike: 21800, c_oi: 245600, c_choi: 18450, c_vol: 452330, c_ltp: 278.90, c_chg: 3.21, c_iv: 14.8, c_delta: 0.64, c_theta: -2.51, c_vega: 7.23, p_ltp: 91.95, p_chg: -2.95, p_iv: 15.3, p_delta: -0.36, p_theta: -1.22, p_vega: 2.68, p_vol: 205450, p_choi: 9640, p_oi: 215780 },
        { strike: 21900, c_oi: 262450, c_choi: 16875, c_vol: 485210, c_ltp: 209.75, c_chg: 2.68, c_iv: 14.6, c_delta: 0.54, c_theta: -2.01, c_vega: 5.78, p_ltp: 108.60, p_chg: -2.62, p_iv: 15.1, p_delta: -0.46, p_theta: -1.45, p_vega: 3.18, p_vol: 212880, p_choi: 10220, p_oi: 223100 },
        { strike: 22000, c_oi: 255300, c_choi: 14230, c_vol: 512660, c_ltp: 153.60, c_chg: 2.11, c_iv: 14.4, c_delta: 0.45, c_theta: -1.63, c_vega: 4.62, p_ltp: 127.35, p_chg: -2.28, p_iv: 14.9, p_delta: -0.55, p_theta: -1.72, p_vega: 3.76, p_vol: 225140, p_choi: 11320, p_oi: 236450, isATM: true },
        { strike: 22100, c_oi: 212900, c_choi: 11220, c_vol: 465120, c_ltp: 108.95, c_chg: 1.72, c_iv: 14.2, c_delta: 0.37, c_theta: -1.31, c_vega: 3.61, p_ltp: 148.40, p_chg: -2.01, p_iv: 14.7, p_delta: -0.64, p_theta: -2.01, p_vega: 4.42, p_vol: 218340, p_choi: 10540, p_oi: 228880 },
        { strike: 22200, c_oi: 175650, c_choi: 8910, c_vol: 358240, c_ltp: 74.20, c_chg: 1.29, c_iv: 14.1, c_delta: 0.29, c_theta: -1.04, c_vega: 2.78, p_ltp: 171.95, p_chg: -1.71, p_iv: 14.5, p_delta: -0.71, p_theta: -2.33, p_vega: 5.22, p_vol: 195430, p_choi: 9120, p_oi: 204550 }
      ]
    }

    const grouped = {}
    data.legs.forEach(leg => {
      const strike = leg.strike
      if (!grouped[strike]) {
        grouped[strike] = { strike, isATM: strike === data.atm_strike }
      }
      if (leg.type === 'CE') {
        grouped[strike].c_oi = leg.oi || 0
        grouped[strike].c_choi = leg.oi_change || 0
        grouped[strike].c_vol = leg.volume || leg.oi * 1.5 || 0
        grouped[strike].c_ltp = leg.ltp || 0
        grouped[strike].c_chg = leg.change_pct || 2.11
        grouped[strike].c_iv = leg.iv || 14.4
        grouped[strike].c_delta = leg.delta || 0.45
        grouped[strike].c_theta = leg.theta || -1.63
        grouped[strike].c_vega = leg.vega || 4.62
      } else if (leg.type === 'PE') {
        grouped[strike].p_oi = leg.oi || 0
        grouped[strike].p_choi = leg.oi_change || 0
        grouped[strike].p_vol = leg.volume || leg.oi * 1.2 || 0
        grouped[strike].p_ltp = leg.ltp || 0
        grouped[strike].p_chg = leg.change_pct || -2.28
        grouped[strike].p_iv = leg.iv || 14.9
        grouped[strike].p_delta = leg.delta || -0.55
        grouped[strike].p_theta = leg.theta || -1.72
        grouped[strike].p_vega = leg.vega || 3.76
      }
    })

    return Object.values(grouped).sort((a, b) => a.strike - b.strike)
  })

  // Dynamic Summary Calculations based on derived rows
  const summary = createMemo(() => {
    let callOi = 0
    let putOi = 0
    let maxCallOiLeg = null
    let maxCallOi = 0

    derivedChainRows().forEach(r => {
      callOi += r.c_oi || 0
      putOi += r.p_oi || 0
      if ((r.c_oi || 0) > maxCallOi) {
        maxCallOi = r.c_oi
        maxCallOiLeg = r.strike
      }
    })

    const totalOi = callOi + putOi
    const pcr = totalOi > 0 ? (putOi / callOi) : 0.87
    const putPct = totalOi > 0 ? Math.round((putOi / totalOi) * 100) : 46
    const callPct = 100 - putPct

    return {
      callOi,
      putOi,
      totalOi,
      pcr,
      putPct,
      callPct,
      maxPain: maxCallOiLeg || 21900
    }
  })

  // Greeks Summary for ATM strike
  const Greeks = createMemo(() => {
    const atm = atmStrike()
    const match = derivedChainRows().find(r => r.strike === atm)
    return {
      c_delta: match?.c_delta || 0.45,
      c_gamma: 0.0028,
      c_theta: match?.c_theta || -1.63,
      c_vega: match?.c_vega || 4.62,
      c_rho: 1.28,
      p_delta: match?.p_delta || -0.55,
      p_gamma: 0.0029,
      p_theta: match?.p_theta || -1.72,
      p_vega: match?.p_vega || 3.76,
      p_rho: -1.35
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
              <option>{currentExpiry()} (Weekly)</option>
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
      <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-9 gap-4">
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Spot Price</span>
          <div class="text-sm font-black text-emerald-400 text-data">
            <AnimatedNumber value={spotPrice()} decimals={2} />
          </div>
          <span class="text-[8px] font-bold text-emerald-500 mt-0.5 block">+{spotChange().toFixed(2)} ({spotChangePct()}%)</span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">IV (ATM)</span>
          <div class="text-sm font-black text-white text-data">15.48%</div>
          <span class="text-[8px] font-bold text-rose-500 mt-0.5 block">-0.32%</span>
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
          <span class="text-[8px] text-emerald-400 mt-0.5 block">+4.32%</span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Call OI</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().callOi} decimals={0} />
          </div>
          <span class="text-[8px] text-emerald-400 mt-0.5 block">+4.12%</span>
        </div>
        <div class="glass p-3.5 rounded-xl">
          <span class="text-[8px] font-black text-gray-500 uppercase tracking-widest block mb-1">Put OI</span>
          <div class="text-sm font-black text-white text-data">
            <AnimatedNumber value={summary().putOi} decimals={0} />
          </div>
          <span class="text-[8px] text-emerald-400 mt-0.5 block">+4.60%</span>
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

      {/* Main Options Chain Workspace Layout */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Left Columns (9 units): Option Chain Table */}
        <div class="lg:col-span-9 glass p-5 rounded-2xl flex flex-col justify-between overflow-x-auto">
          <table class="w-full text-center border-collapse text-[10px]">
            <thead>
              {/* Top CALLS / PUTS Group Headers */}
              <tr class="border-b border-white/5">
                <th colspan="9" class="py-2.5 text-emerald-400 font-black uppercase tracking-[0.2em] bg-emerald-500/5 rounded-tl-xl">CALLS</th>
                <th class="py-2.5 font-black uppercase tracking-wider bg-white/5">STRIKE</th>
                <th colspan="9" class="py-2.5 text-rose-400 font-black uppercase tracking-[0.2em] bg-rose-500/5 rounded-tr-xl">PUTS</th>
              </tr>
              {/* Detailed Metrics Sub Headers */}
              <tr class="text-gray-500 font-black uppercase border-b border-white/5 bg-white/[0.01]">
                <th class="py-2.5">OI</th>
                <th>Chg OI</th>
                <th>Vol</th>
                <th class="text-emerald-400">LTP</th>
                <th>Chg %</th>
                <th>IV</th>
                <th>Delta</th>
                <th>Theta</th>
                <th>Vega</th>
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
                    {/* CALLS Data columns */}
                    <td class={`py-2 text-data text-gray-400 ${callsTdClass(r.strike)}`}>
                      <AnimatedNumber value={r.c_oi} decimals={0} />
                    </td>
                    <td class={`text-data text-emerald-400 ${callsTdClass(r.strike)}`}>
                      +<AnimatedNumber value={r.c_choi} decimals={0} />
                    </td>
                    <td class={`text-data text-gray-500 ${callsTdClass(r.strike)}`}>
                      <AnimatedNumber value={r.c_vol} decimals={0} />
                    </td>
                    <td class={`text-data font-black text-white ${callsTdClass(r.strike)}`}>
                      ₹<AnimatedNumber value={r.c_ltp} decimals={2} />
                    </td>
                    <td class={`text-data text-emerald-400 ${callsTdClass(r.strike)}`}>
                      +<AnimatedNumber value={r.c_chg} decimals={2} />%
                    </td>
                    <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>
                      <AnimatedNumber value={r.c_iv} decimals={2} />%
                    </td>
                    <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_delta.toFixed(2)}</td>
                    <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_theta.toFixed(2)}</td>
                    <td class={`text-data text-gray-400 ${callsTdClass(r.strike)}`}>{r.c_vega.toFixed(2)}</td>

                    {/* STRIKE Price */}
                    <td class={`py-2 text-data font-black text-white bg-white/5 border-x border-white/5`}>
                      {r.strike.toLocaleString()}
                    </td>

                    {/* PUTS Data columns */}
                    <td class={`text-data font-black text-white ${putsTdClass(r.strike)}`}>
                      ₹<AnimatedNumber value={r.p_ltp} decimals={2} />
                    </td>
                    <td class={`text-data text-rose-500 ${putsTdClass(r.strike)}`}>
                      <AnimatedNumber value={r.p_chg} decimals={2} />%
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
                    <td class={`text-data text-emerald-400 ${putsTdClass(r.strike)}`}>
                      +<AnimatedNumber value={r.p_choi} decimals={0} />
                    </td>
                    <td class={`text-data text-gray-400 ${putsTdClass(r.strike)}`}>
                      <AnimatedNumber value={r.p_oi} decimals={0} />
                    </td>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </div>

        {/* Right Columns (3 units): Charts Sidebar */}
        <div class="lg:col-span-3 space-y-6">
          <div class="glass p-5 rounded-2xl space-y-3.5">
            <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
              <span class="font-black text-white">{selectedAsset()} {currentExpiry()} (Weekly)</span>
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
                <span class="font-black text-emerald-400">+{spotChange().toFixed(2)} ({spotChangePct()}%)</span>
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
              <span class="font-black text-gray-400 uppercase tracking-widest">Open Interest (by Strike)</span>
              <div class="flex items-center gap-1.5 text-[8px] font-bold">
                <span class="text-emerald-400">Calls</span>
                <span class="text-rose-400">Puts</span>
              </div>
            </div>
            <div class="flex-1 flex flex-col justify-between py-2 text-[9px]">
              <For each={derivedChainRows().slice(2, 7)}>
                {(r) => (
                  <div class="flex items-center justify-between gap-2">
                    <span class="w-10 text-gray-500 font-mono">{r.strike.toLocaleString()}</span>
                    <div class="flex-1 h-3 flex gap-0.5">
                      <div class="bg-emerald-500 h-full rounded" style={`width: ${Math.min(100, (r.c_oi / 300000) * 100)}%`} />
                      <div class="bg-rose-500 h-full rounded" style={`width: ${Math.min(100, (r.p_oi / 300000) * 100)}%`} />
                    </div>
                  </div>
                )}
              </For>
            </div>
          </div>
        </div>
      </div>

      {/* Greeks and PCR/Max Pain Analysis Row */}
      <div class="grid grid-cols-1 lg:grid-cols-12 gap-6">
        {/* Greeks Details Card (4 cols) */}
        <div class="lg:col-span-4 glass p-5 rounded-2xl flex flex-col justify-between">
          <div class="flex items-center justify-between border-b border-white/5 pb-2 text-[10px]">
            <span class="font-black text-gray-400 uppercase tracking-widest font-bold">Greeks (ATM: {atmStrike().toLocaleString()})</span>
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
            <div class="text-center font-black text-emerald-400 text-data">{Greeks().c_delta}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_gamma}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().c_theta}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_vega}</div>
            <div class="text-center font-black text-white text-data">{Greeks().c_rho}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_delta}</div>
            <div class="text-center font-black text-white text-data">{Greeks().p_gamma}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_theta}</div>
            <div class="text-center font-black text-white text-data">{Greeks().p_vega}</div>
            <div class="text-center font-black text-rose-500 text-data">{Greeks().p_rho}</div>
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
              <path d="M0,45 L40,50 L80,38 L120,40 L160,25 L200,30" fill="none" stroke="rgb(16, 185, 129)" stroke-width="2" />
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
              <path d="M0,35 L40,40 L80,28 L120,38 L160,18 L200,20" fill="none" stroke="rgb(245, 158, 11)" stroke-width="2" />
            </svg>
          </div>
        </div>
      </div>
    </div>
  )
}
