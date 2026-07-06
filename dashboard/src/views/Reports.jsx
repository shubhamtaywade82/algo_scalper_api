// DEPENDENCY: backend — requires /api/reports endpoints (not yet implemented)
import { createSignal, onMount } from 'solid-js'
import { Show } from 'solid-js'

export default function Reports() {
  const [loading, setLoading] = createSignal(false)

  async function fetchReports() {
    setLoading(true)
    try {
      // TODO: backend — implement GET /api/reports/pnl, /api/reports/trades, /api/reports/performance
      await fetch('/api/reports/pnl')
    } catch {
      /* expected — endpoint not implemented */
    } finally {
      setLoading(false)
    }
  }

  onMount(fetchReports)

  return (
    <div class="space-y-6">


      <div class="glass rounded-2xl p-6 border border-amber-500/20 bg-amber-500/5">
        <p class="text-[10px] font-bold text-amber-400 uppercase tracking-widest">
          ⚠ Backend Dependency: /api/reports/* endpoints not yet implemented
        </p>
        <div class="mt-4 space-y-2 text-[10px] text-gray-500 font-mono">
          <p>Planned endpoints:</p>
          <p class="ml-4">· GET /api/reports/pnl — P&L summary by period</p>
          <p class="ml-4">· GET /api/reports/trades — Detailed trade log export</p>
          <p class="ml-4">· GET /api/reports/performance — Performance metrics</p>
          <p class="ml-4">· GET /api/reports/export — CSV/PDF export</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="glass glass-hover p-5 rounded-2xl opacity-40">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">P&L Summary</span>
          <div class="text-2xl font-black text-white mt-1">—</div>
        </div>
        <div class="glass glass-hover p-5 rounded-2xl opacity-40">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Trade Log</span>
          <div class="text-2xl font-black text-white mt-1">—</div>
        </div>
        <div class="glass glass-hover p-5 rounded-2xl opacity-40">
          <span class="text-[10px] font-black text-gray-500 uppercase tracking-widest">Win Rate</span>
          <div class="text-2xl font-black text-white mt-1">—</div>
        </div>
      </div>
    </div>
  )
}
