import { createSignal, For } from 'solid-js'

export default function RecentLogs(props) {
  const [filter, setFilter] = createSignal('All')

  const filteredLogs = () => {
    const raw = props.logs || []
    if (filter() === 'All') return raw
    return raw.filter(log => log.message.toUpperCase().includes(filter().toUpperCase()))
  }

  const logColor = (level) => {
    switch (level) {
      case 'success': return 'text-emerald-400 font-bold'
      case 'warn': return 'text-amber-500 font-bold'
      case 'error': return 'text-rose-400 font-bold'
      default: return 'text-gray-300'
    }
  }

  return (
    <div class="glass border border-white/5 rounded-2xl overflow-hidden flex flex-col h-full bg-[#0d1117]/20">
      {/* Header */}
      <div class="flex items-center justify-between px-4 py-2 border-b border-white/5 bg-white/[0.01]">
        <h4 class="text-[9px] font-black text-gray-400 uppercase tracking-widest flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-cyan-400" />
          Recent Logs
        </h4>
        <select
          value={filter()}
          onChange={(e) => setFilter(e.target.value)}
          class="glass-select text-[9px] px-2 py-0.5 rounded-md border border-white/5 bg-[#0d1117] text-gray-400 font-bold cursor-pointer"
        >
          <option value="All">All Categories</option>
          <option value="Breakout">Entry/Exit</option>
          <option value="Risk">Risk Engine</option>
          <option value="Order">Order Manager</option>
        </select>
      </div>

      {/* Logs Window */}
      <div class="flex-1 p-4 font-mono text-[10px] leading-5 overflow-y-auto space-y-1 max-h-[160px] min-h-[100px] select-text">
        <For each={filteredLogs()}>
          {(log) => (
            <div class="flex items-start gap-3 hover:bg-white/[0.01] px-1 rounded transition-colors">
              <span class="text-gray-600 select-none font-semibold">{log.time}</span>
              <span class={logColor(log.level)}>{log.message}</span>
            </div>
          )}
        </For>
        {filteredLogs().length === 0 && (
          <div class="text-center py-6 text-gray-600 uppercase tracking-widest text-[9px]">
            No matching log entries
          </div>
        )}
      </div>
    </div>
  )
}
