import { createSignal, onMount, onCleanup, Show, For } from 'solid-js'

const POLL_MS = 30_000

function formatTime(iso) {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  } catch {
    return iso
  }
}

export default function LedgerJournalPanel() {
  const [entries, setEntries] = createSignal([])
  const [error, setError] = createSignal(null)
  const [loading, setLoading] = createSignal(true)

  let timer = null

  async function fetchJournal() {
    try {
      const res = await fetch('/api/ledger/journal?per_page=25')
      if (!res.ok) {
        setError(`HTTP ${res.status}`)
        return
      }
      const body = await res.json()
      if (!body.success) {
        setError(body.error || 'journal_unavailable')
        return
      }
      setError(null)
      setEntries(body.entries || [])
    } catch (e) {
      setError(e.message || 'fetch_failed')
    } finally {
      setLoading(false)
    }
  }

  onMount(() => {
    fetchJournal()
    timer = setInterval(fetchJournal, POLL_MS)
  })

  onCleanup(() => clearInterval(timer))

  return (
    <div class="glass glass-hover p-6 rounded-2xl border border-white/5">
      <h2 class="text-sm font-black text-white uppercase tracking-widest mb-4">Recent Journal</h2>

      <Show when={loading()} fallback={
        <Show when={!error()} fallback={
          <p class="text-sm text-rose-400">Journal unavailable: {error()}</p>
        }>
          <Show when={entries().length > 0} fallback={
            <p class="text-sm text-gray-500">No journal entries yet.</p>
          }>
            <div class="overflow-x-auto">
              <table class="w-full text-left text-xs border-collapse">
                <thead>
                  <tr class="text-[10px] font-black uppercase tracking-widest text-gray-500 border-b border-white/5">
                    <th class="py-2 pr-4">Time</th>
                    <th class="py-2 pr-4">Event</th>
                    <th class="py-2 pr-4">Position</th>
                    <th class="py-2 pr-4">Postings</th>
                  </tr>
                </thead>
                <tbody>
                  <For each={entries()}>
                    {(entry) => (
                      <tr class="border-b border-white/5 text-gray-300 align-top">
                        <td class="py-3 pr-4 whitespace-nowrap text-gray-500">{formatTime(entry.created_at)}</td>
                        <td class="py-3 pr-4">
                          <div class="font-mono text-[11px] text-violet-300">{entry.event_type}</div>
                          <div class="text-[10px] text-gray-600 mt-0.5">{entry.idempotency_key}</div>
                        </td>
                        <td class="py-3 pr-4 text-[11px]">
                          {entry.position_tracker_id ? `#${entry.position_tracker_id}` : '—'}
                        </td>
                        <td class="py-3 pr-4">
                          <div class="space-y-1">
                            <For each={entry.postings || []}>
                              {(posting) => (
                                <div class="text-[10px] font-mono text-gray-400">
                                  {posting.account_code}
                                  {Number(posting.debit) > 0 && (
                                    <span class="text-rose-300"> DR {Number(posting.debit).toFixed(2)}</span>
                                  )}
                                  {Number(posting.credit) > 0 && (
                                    <span class="text-emerald-300"> CR {Number(posting.credit).toFixed(2)}</span>
                                  )}
                                </div>
                              )}
                            </For>
                          </div>
                        </td>
                      </tr>
                    )}
                  </For>
                </tbody>
              </table>
            </div>
          </Show>
        </Show>
      }>
        <p class="text-sm text-gray-500">Loading journal…</p>
      </Show>
    </div>
  )
}
