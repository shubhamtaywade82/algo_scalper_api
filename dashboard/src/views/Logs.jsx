import { Show, For } from 'solid-js'
import { useLogs } from '../stores/useLogs'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'
import Badge from '../components/ui/Badge'
import Button from '../components/ui/Button'

const levelVariant = {
  error: 'danger',
  warn: 'warning',
  info: 'info',
  debug: 'outline',
}

export default function Logs() {
  const { logs, meta, loading, error, fetchLogs } = useLogs()

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={() => fetchLogs({ page: meta().page, per_page: meta().per_page })}
          loading={loading()}
          leftIcon={<span>↻</span>}
        >
          {loading() ? 'Loading...' : 'Refresh'}
        </Button>
      </div>

      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: GET /api/logs not yet implemented
        </p>
      </div>

      <Show when={error()}>
        <div class="text-rose-400 text-xs">{error()}</div>
      </Show>

      <Show when={!loading() && !error() && logs().length === 0}>
        <div class="glass rounded-2xl p-12 text-center">
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No logs available</p>
        </div>
      </Show>

      <Show when={logs().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto max-h-[600px] overflow-y-auto">
            <Table>
              <TableHeader>
                <TableRow class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 sticky top-0 bg-gray-900">
                  <TableHead class="text-left px-4 py-3 font-black">Time</TableHead>
                  <TableHead class="text-left px-4 py-3 font-black">Level</TableHead>
                  <TableHead class="text-left px-4 py-3 font-black">Source</TableHead>
                  <TableHead class="text-left px-4 py-3 font-black">Message</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={logs()}>
                  {(log) => (
                    <TableRow class="hover:bg-white/[0.02]">
                      <TableCell class="px-4 py-2 text-gray-500 font-mono text-[11px]">{log.timestamp}</TableCell>
                      <TableCell class="px-4 py-2">
                        <Badge variant={levelVariant[log.level] || 'outline'} class="text-[9px] font-black uppercase">
                          {log.level}
                        </Badge>
                      </TableCell>
                      <TableCell class="px-4 py-2 text-gray-400 font-mono text-[11px]">{log.source}</TableCell>
                      <TableCell class="px-4 py-2 text-gray-300 text-[11px]">{log.message}</TableCell>
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
