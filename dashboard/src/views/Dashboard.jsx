import { createSignal, createMemo, createEffect } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import StatsBar from '../components/StatsBar'
import OpenPositions from '../components/OpenPositions'
import ClosedTrades from '../components/ClosedTrades'

const RUNNING_PEAK_KEY = 'algo_dashboard_daily_pnl_hwm'

function calendarDayKey() {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function loadRunningPeak() {
  try {
    const raw = sessionStorage.getItem(RUNNING_PEAK_KEY)
    if (!raw) return 0
    const { date, value } = JSON.parse(raw)
    if (date !== calendarDayKey()) return 0
    return Number(value) || 0
  } catch {
    return 0
  }
}

function saveRunningPeak(n) {
  try {
    sessionStorage.setItem(RUNNING_PEAK_KEY, JSON.stringify({ date: calendarDayKey(), value: n }))
  } catch { /* ignore */ }
}

export default function Dashboard() {
  const {
    balance, stats, open, circuitBreaker, positionsConnected, positionsStale,
    closeOpenPosition, closingPositionId
  } = useDashboardContext()

  const [runningPeakPnl, setRunningPeakPnl] = createSignal(loadRunningPeak())

  createEffect(() => {
    const currentOpen = open() || []
    const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
    const realized = Number(stats()?.realized_pnl_rupees || 0)
    const total = realized + unrealized
    const serverPeak = Number(stats()?.peak_pnl || 0)
    const next = Math.max(loadRunningPeak(), runningPeakPnl(), total, serverPeak)
    if (next !== runningPeakPnl()) {
      setRunningPeakPnl(next)
      saveRunningPeak(next)
    }
  })

  const liveStats = createMemo(() => {
    const currentOpen = open() || []
    const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
    const realized = Number(stats()?.realized_pnl_rupees || 0)
    const total = realized + unrealized
    return {
      ...stats(),
      unrealized_pnl_rupees: unrealized,
      total_pnl_rupees: total,
      peak_pnl: runningPeakPnl()
    }
  })

  return (
    <div class="space-y-8">
      <StatsBar balance={balance()} stats={liveStats()} />
      <div class="grid grid-cols-1 gap-8">
        <OpenPositions
          positions={open()}
          circuitBreaker={circuitBreaker()}
          wsConnected={positionsConnected()}
          wsStale={positionsStale()}
          onClosePosition={closeOpenPosition}
          closingPositionId={closingPositionId}
        />
        <ClosedTrades />
      </div>
    </div>
  )
}
