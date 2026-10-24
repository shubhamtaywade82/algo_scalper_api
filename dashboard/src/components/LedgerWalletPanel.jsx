import { createSignal, onMount, onCleanup, Show, For } from 'solid-js'
import AnimatedNumber from './AnimatedNumber'
import { dashboardApiHeaders } from '../lib/dashboardApi'

const POLL_MS = 30_000

export default function LedgerWalletPanel() {
  const [data, setData] = createSignal(null)
  const [error, setError] = createSignal(null)
  const [loading, setLoading] = createSignal(true)

  let timer = null

  async function fetchLedger() {
    try {
      const res = await fetch('/api/ledger/balance', { headers: dashboardApiHeaders() })
      if (!res.ok) {
        setError(`HTTP ${res.status}`)
        return
      }
      const body = await res.json()
      if (!body.success) {
        setError(body.error || 'ledger_unavailable')
        return
      }
      setError(null)
      setData(body)
    } catch (e) {
      setError(e.message || 'fetch_failed')
    } finally {
      setLoading(false)
    }
  }

  onMount(() => {
    fetchLedger()
    timer = setInterval(fetchLedger, POLL_MS)
  })

  onCleanup(() => clearInterval(timer))

  const wallet = () => data()?.wallet || {}
  const config = () => data()?.config || {}
  const reconciliation = () => data()?.reconciliation || {}
  const accounts = () => data()?.accounts || []

  const driftOk = () => {
    const r = reconciliation()
    const cash = Math.abs(Number(r.cash_drift || 0))
    const equity = Math.abs(Number(r.equity_drift || 0))
    return cash <= 1 && equity <= 1
  }

  return (
    <div class="glass glass-hover p-6 rounded-2xl border border-violet-500/20 shadow-[0_4px_24px_rgba(139,92,246,0.08)]">
      <div class="flex flex-wrap items-center justify-end gap-2 mb-5">
          <Show when={config().paper_enabled}>
            <span class="text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded border text-violet-300 border-violet-500/30 bg-violet-500/10">
              WALLET SOURCE
            </span>
          </Show>
          <Show when={config().shadow_mode} fallback={
            <span class="text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded border text-gray-400 border-gray-600/30 bg-white/5">
              SHADOW OFF
            </span>
          }>
            <span class="text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded border text-amber-300 border-amber-500/30 bg-amber-500/10">
              SHADOW MODE
            </span>
          </Show>
      </div>

      <Show when={loading()} fallback={
        <Show when={!error()} fallback={
          <p class="text-sm text-rose-400">Ledger unavailable: {error()}</p>
        }>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
            <div>
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Ledger Cash</span>
              <div class="text-xl font-black text-white mt-1">
                <AnimatedNumber value={wallet().cash} currency decimals={2} />
              </div>
            </div>
            <div>
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Equity</span>
              <div class="text-xl font-black text-violet-300 mt-1">
                <AnimatedNumber value={wallet().equity} currency decimals={2} />
              </div>
            </div>
            <div>
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Deployed</span>
              <div class="text-xl font-black text-indigo-300 mt-1">
                <AnimatedNumber value={wallet().utilized} currency decimals={2} />
              </div>
            </div>
            <div>
              <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Realized PnL</span>
              <div class="text-xl font-black mt-1">
                <AnimatedNumber value={wallet().realized_pnl} currency decimals={2} pnlColor zeroPositive />
              </div>
            </div>
          </div>

          <Show when={config().shadow_mode}>
            <div class={`rounded-xl border px-4 py-3 mb-5 ${driftOk() ? 'border-emerald-500/20 bg-emerald-500/5' : 'border-amber-500/30 bg-amber-500/10'}`}>
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-[10px] font-black uppercase tracking-widest text-gray-400">Reconciliation vs legacy wallet</span>
                <span class={`text-[9px] font-black uppercase tracking-widest ${driftOk() ? 'text-emerald-400' : 'text-amber-400'}`}>
                  {driftOk() ? 'ALIGNED' : 'DRIFT'}
                </span>
              </div>
              <div class="grid grid-cols-2 gap-3 mt-2 text-[11px] text-gray-400">
                <span>Cash drift: ₹{Number(reconciliation().cash_drift || 0).toFixed(2)}</span>
                <span>Equity drift: ₹{Number(reconciliation().equity_drift || 0).toFixed(2)}</span>
              </div>
            </div>
          </Show>

          <div class="overflow-x-auto">
            <table class="w-full text-left text-xs">
              <thead>
                <tr class="text-[10px] font-black uppercase tracking-widest text-gray-500 border-b border-white/5">
                  <th class="py-2 pr-4">Account</th>
                  <th class="py-2 pr-4">Type</th>
                  <th class="py-2 text-right">Balance</th>
                </tr>
              </thead>
              <tbody>
                <For each={accounts()}>
                  {(account) => (
                    <tr class="border-b border-white/5 text-gray-300">
                      <td class="py-2 pr-4 font-mono text-[11px]">{account.code}</td>
                      <td class="py-2 pr-4 text-gray-500">{account.account_type}</td>
                      <td class="py-2 text-right font-semibold">
                        <AnimatedNumber value={account.balance} currency decimals={2} />
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </Show>
      }>
        <p class="text-sm text-gray-500">Loading ledger…</p>
      </Show>
    </div>
  )
}
