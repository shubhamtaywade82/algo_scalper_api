import { Show, For } from 'solid-js'
import { useScheduler } from '../stores/useScheduler'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import Badge from '../components/ui/Badge'
import Button from '../components/ui/Button'

const statusVariant = {
  running: 'success',
  active: 'success',
  pending: 'warning',
  idle: 'outline',
  error: 'danger',
  failed: 'danger',
}

export default function Scheduler() {
  const { tasks, loading, error, fetchTasks, executeTask } = useScheduler()

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={fetchTasks}
          loading={loading()}
          leftIcon={<span>↻</span>}
        >
          {loading() ? 'Loading...' : 'Refresh'}
        </Button>
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
            <Table>
              <TableHeader>
                <TableRow class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 bg-white/[0.02]">
                  <TableHead class="text-left px-6 py-4 font-black">Name</TableHead>
                  <TableHead class="text-left px-4 py-4 font-black">Schedule</TableHead>
                  <TableHead class="text-center px-4 py-4 font-black">Status</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">Last Run</TableHead>
                  <TableHead class="text-center px-4 py-4 font-black w-24">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={tasks()}>
                  {(task) => (
                    <TableRow class="hover:bg-white/[0.02] transition-colors">
                      <TableCell class="px-6 py-4 font-bold text-white">{task.name}</TableCell>
                      <TableCell class="px-4 py-4 text-gray-400 font-mono text-[11px]">{task.cron || task.schedule}</TableCell>
                      <TableCell class="px-4 py-4 text-center">
                        <Badge variant={statusVariant[task.status] || 'outline'} class="text-[9px] font-black uppercase tracking-widest">
                          {task.status}
                        </Badge>
                      </TableCell>
                      <TableCell class="px-4 py-4 text-right text-gray-500 text-[11px]">{task.last_run_at || '—'}</TableCell>
                      <TableCell class="px-4 py-4 text-center">
                        <Button
                          variant="outline"
                          class="text-[9px] font-black uppercase tracking-widest rounded-lg"
                          onClick={() => executeTask(task.id)}
                        >
                          Run
                        </Button>
                      </TableCell>
                    </TableRow>
                  )}
                </For>
              </TableBody>
            </Table>
          </div>
        </div>
      </Show>
    </div>
  )
}
