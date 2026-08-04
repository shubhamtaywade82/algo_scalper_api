<script setup>
import { inject, computed, ref, watch } from 'vue'
import StatsBar from '../components/StatsBar.vue'
import OpenPositions from '../components/OpenPositions.vue'
import ClosedTrades from '../components/ClosedTrades.vue'

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
    sessionStorage.setItem(
      RUNNING_PEAK_KEY,
      JSON.stringify({ date: calendarDayKey(), value: n })
    )
  } catch {
    /* ignore quota / private mode */
  }
}

const { balance, stats, open, closed, publicIpv4, publicIpv6, registeredIps, circuitBreaker, positionsConnected, positionsStale, fetchPositions } =
  inject('dashboardState')

// True day HWM: ratchet max(total) on every live update. Plain max(server, total)
// collapses to today's level whenever PnL retraces from an intraday high.
const runningPeakPnl = ref(loadRunningPeak())

watch(
  () => {
    const currentOpen = open.value || []
    const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
    const realized = Number(stats.value?.realized_pnl_rupees || 0)
    const total = realized + unrealized
    const serverPeak = Number(stats.value?.peak_pnl || 0)
    return { total, serverPeak }
  },
  ({ total, serverPeak }) => {
    const next = Math.max(loadRunningPeak(), runningPeakPnl.value, total, serverPeak)
    if (next !== runningPeakPnl.value) {
      runningPeakPnl.value = next
      saveRunningPeak(next)
    }
  },
  { flush: 'sync', immediate: true }
)

// Instantly reflect portfolio changes by summing up high-frequency position updates
const liveStats = computed(() => {
  const currentOpen = open.value || []
  const unrealized = currentOpen.reduce((sum, p) => sum + Number(p.pnl || 0), 0)
  const realized = Number(stats.value?.realized_pnl_rupees || 0)
  const total = realized + unrealized

  return {
    ...stats.value,
    unrealized_pnl_rupees: unrealized,
    total_pnl_rupees: total,
    peak_pnl: runningPeakPnl.value
  }
})
</script>

<template>
  <div class="space-y-8">
    <StatsBar :balance="balance" :stats="stats" />
    <div class="grid grid-cols-1 gap-8">
      <OpenPositions :positions="open" :circuit-breaker="circuitBreaker" @position-exited="fetchPositions" />
      <ClosedTrades :positions="closed" />
    </div>
  </div>
</template>
