import { createSignal, createMemo, For, Show, onMount } from 'solid-js'

export default function RecentLogs(props) {
  const [filter, setFilter] = createSignal('All')
  let scrollRef

  const filters = ['All', 'Entry', 'Exit', 'Risk', 'System']

  const filteredLogs = createMemo(() => {
    const logs = props.logs()
    if (!logs || logs.length === 0) return []
    const f = filter()
    if (f === 'All') return logs
    return logs.filter(log => {
      const msg = log.message.toLowerCase()
      switch (f) {
        case 'Entry': return msg.includes('entry') || msg.includes('breakout') || msg.includes('signal') || msg.includes('buy')
        case 'Exit': return msg.includes('exit') || msg.includes('close') || msg.includes('sell')
        case 'Risk': return msg.includes('risk') || msg.includes('position size') || msg.includes('drawdown')
        case 'System': return msg.includes('execution') || msg.includes('order') || msg.includes('system')
        default: return true
      }
    })
  })

  const levelColor = (level) => {
    switch (level) {
      case 'success': return 'text-emerald-500'
      case 'warn': return 'text-amber-500'
      case 'error': return 'text-rose-500'
      default: return 'text-gray-300'
    }
  }

  const levelIcon = (level) => {
    switch (level) {
      case 'success': return '✓'
      case 'warn': return '⚠'
      case 'error': return '✕'
      default: return '›'
    }
  }

  onMount(() => {
    if (scrollRef) {
      scrollRef.scrollTop = scrollRef.scrollHeight
    }
  })

  return (
    <div class="flex flex-col h-full">
      {/* Header */}
      <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5 flex-shrink-0">
        <div class="flex items-center gap-2">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Recent Logs</span>
          <Show when={props.strategyName}>
            <span class="text-[10px] text-gray-700 font-bold">• {props.strategyName}</span>
          </Show>
        </div>
        <select
          value={filter()}
          onChange={(e) => setFilter(e.target.value)}
          class="glass-select rounded-lg px-2.5 py-1 text-[10px] font-bold cursor-pointer"
        >
          <For each={filters}>
            {(f) => <option value={f}>{f}</option>}
          </For>
        </select>
      </div>

      {/* Log entries */}
      <div
        ref={scrollRef}
        class="flex-1 overflow-y-auto px-4 py-2 space-y-0.5"
        style="max-height: 400px"
      >
        <Show
          when={filteredLogs().length > 0}
          fallback={
            <div class="flex items-center justify-center h-full py-8">
              <span class="text-[11px] text-gray-700 font-bold">No log entries</span>
            </div>
          }
        >
          <For each={filteredLogs()}>
            {(log) => (
              <div class="flex items-start gap-2.5 py-1 hover:bg-white/[0.02] rounded px-1.5 transition-colors group">
                <span class="text-data text-[11px] text-gray-600 flex-shrink-0 pt-px font-medium">
                  {log.time}
                </span>
                <span class={`text-[11px] flex-shrink-0 pt-px w-3 text-center ${levelColor(log.level)}`}>
                  {levelIcon(log.level)}
                </span>
                <span class={`text-data text-[11px] leading-relaxed ${levelColor(log.level)}`}>
                  {log.message}
                </span>
              </div>
            )}
          </For>
        </Show>
      </div>
    </div>
  )
}
