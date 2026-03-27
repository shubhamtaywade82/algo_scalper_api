import { createMemo } from 'solid-js'
import { For, Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'

function formatTime(timestamp) {
  if (!timestamp) return '—'
  try {
    const d = new Date(timestamp)
    if (isNaN(d.getTime())) return '—'
    return d.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  } catch {
    return '—'
  }
}

function getSignalClass(direction) {
  const dir = String(direction || '').toLowerCase()
  if (dir.includes('bullish') || dir.includes('buy')) return 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20'
  if (dir.includes('bearish') || dir.includes('sell')) return 'text-rose-400 bg-rose-500/10 border-rose-500/20'
  return 'text-gray-400 bg-gray-500/10 border-gray-500/20'
}

function getConfidenceClass(level) {
  const l = String(level || '').toLowerCase()
  if (l.includes('very_high')) return 'bg-emerald-500'
  if (l.includes('high')) return 'bg-emerald-400'
  if (l.includes('medium')) return 'bg-amber-400'
  if (l.includes('low')) return 'bg-rose-400'
  return 'bg-gray-500'
}

function getEntryOutcomeStyle(outcome) {
  switch (outcome) {
    case 'entered': return { cls: 'text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 rounded-full', label: '● ENTERED' }
    case 'blocked': return { cls: 'text-amber-400 bg-amber-500/10 border border-amber-500/20 rounded-full', label: '✗ BLOCKED' }
    case 'skipped': return { cls: 'text-gray-500 bg-gray-500/10 border border-gray-500/20 rounded-full', label: '◌ SKIPPED' }
    default: return { cls: 'text-gray-600', label: '— —' }
  }
}

export default function Signals() {
  const { recentSignals } = useDashboardContext()

  const processedSignals = createMemo(() => {
    const data = recentSignals()
    if (!Array.isArray(data)) return []
    return data.map(sig => {
      const outcome = sig.metadata?.entry_outcome || 'pending'
      const style = getEntryOutcomeStyle(outcome)
      return {
        ...sig,
        displayTime: formatTime(sig.signal_timestamp),
        displayStrategy: String(sig.metadata?.strategy || 'Supertrend').replace(/_/g, ' '),
        displayAdx: Number(sig.adx_value || 0).toFixed(1),
        displaySt: Number(sig.supertrend_value || 0).toFixed(0),
        displayConfidence: String(sig.confidence_level || '').replace(/_/g, ' '),
        signalClass: getSignalClass(sig.direction),
        confidenceBars: Math.round((Number(sig.confidence_score) || 0) * 5),
        confidenceClass: getConfidenceClass(sig.confidence_level),
        entryOutcome: outcome,
        entryBlockedReason: sig.metadata?.entry_blocked_reason || null,
        entryOutcomeCls: style.cls,
        entryOutcomeLabel: style.label
      }
    })
  })

  return (
    <div class="flex flex-col gap-6">
      <div class="flex items-center justify-between px-2">
        <h2 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-amber-500"></span>
          Signal Intelligence
        </h2>
        <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter">Real-time Feed</span>
      </div>

      <div class="glass rounded-3xl overflow-hidden border border-white/5 shadow-2xl">
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="bg-white/[0.02]">
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Time</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Instrument</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Signal</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Strategy</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Entry</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5">Analysis</th>
                <th class="p-6 text-[10px] font-black text-gray-500 uppercase tracking-widest border-b border-white/5 text-right">Confidence</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <For each={processedSignals()}>
                {(sig) => (
                  <tr class="hover:bg-white/[0.03] transition-colors group">
                    <td class="p-6">
                      <span class="text-xs font-bold text-gray-400 text-data">{sig.displayTime}</span>
                    </td>
                    <td class="p-6">
                      <div class="flex flex-col">
                        <span class="text-sm font-black text-white">{sig.index_key}</span>
                        <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter mt-0.5">{sig.timeframe}</span>
                      </div>
                    </td>
                    <td class="p-6">
                      <div class={`px-3 py-1 rounded-full border text-[10px] font-black uppercase inline-block tracking-widest ${sig.signalClass}`}>
                        {sig.direction}
                      </div>
                    </td>
                    <td class="p-6">
                      <span class="text-[10px] font-black text-gray-300 uppercase tracking-wide bg-white/5 px-2 py-1 rounded">{sig.displayStrategy}</span>
                    </td>
                    <td class="p-6">
                      <span class={`px-3 py-1 text-[9px] font-black uppercase tracking-widest inline-block ${sig.entryOutcomeCls}`} title={sig.entryBlockedReason || ''}>
                        {sig.entryOutcomeLabel}
                      </span>
                    </td>
                    <td class="p-6">
                      <div class="flex items-center gap-3">
                        <div class="flex flex-col">
                          <span class="text-[9px] font-black text-gray-600 uppercase tracking-widest">ADX</span>
                          <span class="text-xs font-bold text-white text-data">{sig.displayAdx}</span>
                        </div>
                        <div class="w-[1px] h-6 bg-white/10"></div>
                        <div class="flex flex-col">
                          <span class="text-[9px] font-black text-gray-600 uppercase tracking-widest">ST</span>
                          <span class="text-xs font-bold text-white text-data">{sig.displaySt}</span>
                        </div>
                      </div>
                    </td>
                    <td class="p-6 text-right">
                      <div class="flex items-center justify-end gap-3">
                        <span class="text-[10px] font-black text-gray-500 uppercase tracking-tighter">{sig.displayConfidence}</span>
                        <div class="flex gap-1">
                          <For each={[1, 2, 3, 4, 5]}>
                            {(i) => (
                              <div class={`w-1.5 h-4 rounded-full ${i <= sig.confidenceBars ? sig.confidenceClass : 'bg-white/5'}`}></div>
                            )}
                          </For>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
              </For>
              <Show when={processedSignals().length === 0}>
                <tr>
                  <td colspan="7" class="p-20 text-center">
                    <div class="flex flex-col items-center gap-4">
                      <div class="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center">
                        <span class="text-gray-600">📭</span>
                      </div>
                      <span class="text-sm font-bold text-gray-600 uppercase tracking-[0.2em]">Silence on the wire</span>
                    </div>
                  </td>
                </tr>
              </Show>
            </tbody>
          </table>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mt-4">
        <For each={[{label: 'Success Rate', val: '64%'}, {label: 'Avg Confidence', val: '0.82'}, {label: 'Peak Period', val: '10:15 IST'}]}>
          {(item) => (
            <div class="glass p-6 rounded-2xl flex flex-col gap-1 border border-white/5">
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">{item.label}</span>
              <span class="text-xl font-black text-white tracking-tight">{item.val}</span>
            </div>
          )}
        </For>
      </div>
    </div>
  )
}
