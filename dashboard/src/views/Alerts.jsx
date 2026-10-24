import { Show, For } from 'solid-js'
import { useAlerts } from '../stores/useAlerts'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../components/ui/Table'

const severityVariant = {
  critical: 'danger',
  error: 'danger',
  warning: 'warning',
  info: 'info',
}

export default function Alerts() {
  const { alerts, loading, error, fetchAlerts, deleteAlert, markRead } = useAlerts()

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-end">
        <Button
          variant="ghost"
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider"
          onClick={fetchAlerts}
          loading={loading()}
          leftIcon={<span>↻</span>}
        >
          {loading() ? 'Loading...' : 'Refresh'}
        </Button>
      </div>

      <Show when={error()}>
        <div class="glass rounded-2xl p-6 border border-rose-500/20">
          <p class="text-xs text-rose-400">{error()}</p>
        </div>
      </Show>

      <Show when={alerts().length === 0 && !loading() && !error()}>
        <div class="glass rounded-2xl p-12 text-center">
          <div class="text-3xl mb-3">🔔</div>
          <p class="text-xs font-bold text-gray-600 uppercase tracking-widest">No alerts configured</p>
          <p class="text-[10px] text-gray-600 mt-2">Set up price, P&L, or technical alerts</p>
        </div>
      </Show>

      <Show when={alerts().length > 0}>
        <div class="glass rounded-2xl overflow-hidden">
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="text-[10px] text-gray-400 uppercase tracking-widest border-b border-white/5 bg-white/[0.02]">
                  <TableHead class="text-left px-6 py-4 font-black">Type</TableHead>
                  <TableHead class="text-left px-4 py-4 font-black">Severity</TableHead>
                  <TableHead class="text-left px-4 py-4 font-black">Message</TableHead>
                  <TableHead class="text-right px-4 py-4 font-black">Created</TableHead>
                  <TableHead class="text-center px-4 py-4 font-black w-32">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={alerts()}>
                  {(alert) => (
                    <TableRow class={`hover:bg-white/[0.02] transition-colors ${!alert.read ? 'bg-primary-500/[0.02]' : ''}`}>
                      <TableCell class="px-6 py-4 font-bold text-white">{alert.type}</TableCell>
                      <TableCell class="px-4 py-4">
                        <Badge variant={severityVariant[alert.severity] || 'outline'} class="text-[9px] font-black uppercase">
                          {alert.severity}
                        </Badge>
                      </TableCell>
                      <TableCell class="px-4 py-4 text-gray-300">{alert.message}</TableCell>
                      <TableCell class="px-4 py-4 text-right text-gray-500 text-[11px]">{alert.created_at}</TableCell>
                      <TableCell class="px-4 py-4 text-center">
                        <div class="flex items-center justify-center gap-2">
                          <Show when={!alert.read}>
                            <Button variant="ghost" class="text-[9px] !h-auto !py-1" onClick={() => markRead(alert.id)}>Read</Button>
                          </Show>
                          <Button variant="ghost" class="text-[9px] !h-auto !py-1 text-rose-400" onClick={() => deleteAlert(alert.id)}>Delete</Button>
                        </div>
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
