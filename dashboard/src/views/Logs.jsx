// DEPENDENCY: backend — requires /api/logs endpoint (not yet implemented)
import { createSignal, onMount } from 'solid-js'
import { Show } from 'solid-js'

export default function Logs() {
  const [logs, setLogs] = createSignal([])
  const [loading, setLoading] = createSignal(true)
  const [error, setError] = createSignal(null)

  async function fetchLogs() {
    setLoading(true)
    setError(null)
    try {
      // TODO: backend — implement GET /api/logs returning application logs
      // Expected: { logs: [{ timestamp, level, source, message }] }
      const res = await fetch('/api/logs')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setLogs(data.logs || [])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  onMount(fetchLogs)

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-black text-white uppercase tracking-widest">System Logs</h1>
        <button
          onClick={fetchLogs}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
        >
          {loading() ? '↻' : '↻'} Refresh
        </button>
      </div>

      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: GET /api/logs not yet implemented
        </p>
        <p class="text-[9px] text-gray-500 mt-2">
          Planned: GET /api/logs (paginated, filterable by level/source), GET /api/logs/export
        </p>
      </div>

      <Show when={error()}>
        <div class="text-rose-400 text-xs px-2">{error()}</div>
      </Show>

      <Show when={!loading() && !error() && logs().length === 0}>
        <div class="glass rounded-2xl p-12 text-center">
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No logs available</p>
        </div>
      </Show>

      <Show when={logs().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto max-h-[600px] overflow-y-auto">
            <table class="w-full border-collapse text-xs font-mono">
              <thead class="sticky top-0 bg-gray-900">
                <tr class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5">
                  <th class="text-left px-4 py-3 font-black">Time</th>
                  <th class="text-left px-4 py-3 font-black">Level</th>
                  <th class="text-left px-4 py-3 font-black">Source</th>
                  <th class="text-left px-4 py-3 font-black">Message</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/5">
                <For each={logs()}>
                  {(log) => (
                    <tr class="hover:bg-white/[0.02]">
                      <td class="px-4 py-2 text-gray-500">{log.timestamp}</td>
                      <td class="px-4 py-2">
                        <span class={`text-[9px] font-black uppercase ${
                          log.level === 'error' ? 'text-rose-400' :
                          log.level === 'warn' ? 'text-amber-400' :
                          'text-gray-400'
                        }`}>{log.level}</span>
                      </td>
                      <td class="px-4 py-2 text-gray-400">{log.source}</td>
                      <td class="px-4 py-2 text-gray-300">{log.message}</td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </div>
      </Show>
    </div>
  )
}
