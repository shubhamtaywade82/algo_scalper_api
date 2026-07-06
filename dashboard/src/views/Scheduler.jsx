// Scheduler page — backend /api/scheduler/tasks already exists
import { createSignal, onMount } from 'solid-js'
import { Show, For } from 'solid-js'

export default function Scheduler() {
  const [tasks, setTasks] = createSignal([])
  const [loading, setLoading] = createSignal(true)
  const [error, setError] = createSignal(null)

  async function fetchTasks() {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch('/api/scheduler/tasks')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setTasks(data.tasks || [])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function executeTask(taskId) {
    try {
      const res = await fetch(`/api/scheduler/tasks/${taskId}/execute`, { method: 'POST' })
      if (res.ok) {
        fetchTasks()
      }
    } catch (e) {
      console.error('Failed to execute task:', e)
    }
  }

  onMount(fetchTasks)

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-lg font-black text-white uppercase tracking-widest">Scheduler</h1>
        <button
          onClick={fetchTasks}
          disabled={loading()}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40"
        >
          {loading() ? '↻ Loading...' : '↻ Refresh'}
        </button>
      </div>

      <Show when={error()}>
        <div class="glass rounded-2xl p-6 border border-rose-500/20">
          <p class="text-xs text-rose-400">Error: {error()}</p>
        </div>
      </Show>

      <Show when={tasks().length === 0 && !loading() && !error()}>
        <div class="glass rounded-2xl p-12 text-center">
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No scheduled tasks</p>
        </div>
      </Show>

      <Show when={tasks().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full border-collapse text-sm">
              <thead>
                <tr class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 bg-white/[0.02]">
                  <th class="text-left px-6 py-4 font-black">Name</th>
                  <th class="text-left px-4 py-4 font-black">Schedule</th>
                  <th class="text-center px-4 py-4 font-black">Status</th>
                  <th class="text-right px-4 py-4 font-black">Last Run</th>
                  <th class="text-center px-4 py-4 font-black w-24">Action</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/5">
                <For each={tasks()}>
                  {(task) => (
                    <tr class="hover:bg-white/[0.02] transition-colors">
                      <td class="px-6 py-4 font-bold text-white">{task.name}</td>
                      <td class="px-4 py-4 text-gray-400 font-mono text-[11px]">{task.cron || task.schedule}</td>
                      <td class="px-4 py-4 text-center">
                        <span class={`text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded-full ${
                          task.status === 'running' ? 'bg-emerald-500/10 text-emerald-400' :
                          task.status === 'pending' ? 'bg-amber-500/10 text-amber-400' :
                          'bg-gray-500/10 text-gray-400'
                        }`}>
                          {task.status}
                        </span>
                      </td>
                      <td class="px-4 py-4 text-right text-gray-500 text-[11px]">{task.last_run_at || '—'}</td>
                      <td class="px-4 py-4 text-center">
                        <button
                          onClick={() => executeTask(task.id)}
                          class="px-3 py-1 text-[9px] font-black uppercase tracking-widest bg-primary-500/10 text-primary-400 border border-primary-500/20 rounded-lg hover:bg-primary-500/20 transition-colors"
                        >
                          Run
                        </button>
                      </td>
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
