// DEPENDENCY: backend endpoints GET /api/scheduler/tasks, POST /api/scheduler/tasks/:id/execute
// Expected shape: [{ id, name, cron, status, last_run_at, next_run_at, description }]
// TODO: Wire to ActionCable SchedulerChannel when available

import { createSignal, onMount, onCleanup } from 'solid-js'
import { apiClient } from '../lib/api'
import toast from 'solid-toast'

const POLL_MS = 10000

export function useScheduler() {
  const [tasks, setTasks] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)

  async function fetchTasks() {
    setLoading(true)
    try {
      const res = await apiClient.get('/scheduler/tasks')
      setTasks(res.data || [])
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function executeTask(taskId) {
    try {
      const res = await apiClient.post(`/scheduler/tasks/${taskId}/execute`)
      toast.success(`Task ${res.data?.name || taskId} triggered`)
      await fetchTasks()
      return { ok: true }
    } catch (e) {
      toast.error(`Failed to execute task: ${e.message}`)
      return { ok: false }
    }
  }

  onMount(() => {
    fetchTasks()
    const timer = setInterval(fetchTasks, POLL_MS)
    onCleanup(() => clearInterval(timer))
  })

  return { tasks, loading, error, fetchTasks, executeTask }
}
