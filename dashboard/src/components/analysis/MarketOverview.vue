<script setup>
import { computed } from 'vue'

const props = defineProps({ data: Object })

const regime = computed(() => props.data?.market_regime)
const metrics = computed(() => regime.value?.metrics)

function regimeColor(r) {
  const map = {
    'TRENDING_UP': 'bg-emerald-500/15 text-emerald-400 border-emerald-500/20',
    'TRENDING_DOWN': 'bg-rose-500/15 text-rose-400 border-rose-500/20',
    'RANGING': 'bg-blue-500/15 text-blue-400 border-blue-500/20',
    'CHOPPY': 'bg-amber-500/15 text-amber-400 border-amber-500/20'
  }
  return map[r] || 'bg-white/5 text-gray-400 border-white/10'
}

function inr(val) {
  if (val == null) return '—'
  return Number(val).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

function validityLabel(v) {
  if (!v) return null
  if (v.cached && v.age_seconds != null) {
    const age = v.age_seconds
    if (age < 60) return `${age}s ago`
    return `${Math.round(age / 60)}m ago`
  }
  return 'just now'
}

function validityDot(v) {
  if (!v) return 'bg-gray-600'
  return v.fresh ? 'bg-emerald-400' : 'bg-amber-400'
}

const validities = computed(() => {
  if (!props.data) return []
  return [
    { label: 'SMC', v: props.data.smc_validity },
    { label: 'Regime', v: props.data.regime_validity },
    { label: 'AI', v: props.data.ai_validity }
  ].filter(x => x.v)
})
</script>

<template>
  <div class="glass rounded-2xl p-6 glass-hover">
    <div class="flex items-center justify-between mb-4">
      <div class="flex items-center gap-3">
        <span class="text-[10px] font-black text-gray-500 tracking-[0.2em] uppercase">📊 Market Overview</span>
        <span class="text-xs font-bold text-primary-400">{{ data?.index_key }}</span>
      </div>
      <!-- Validity badges -->
      <div v-if="validities.length" class="flex items-center gap-3">
        <div v-for="item in validities" :key="item.label" class="flex items-center gap-1.5" :title="`${item.label}: cached ${validityLabel(item.v)}, TTL ${item.v.ttl_seconds}s`">
          <span :class="['w-1.5 h-1.5 rounded-full', validityDot(item.v)]"></span>
          <span class="text-[8px] font-bold text-gray-600 tracking-wider">{{ item.label }}: {{ validityLabel(item.v) }}</span>
        </div>
      </div>
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <!-- LTP -->
      <div class="bg-white/[0.03] rounded-xl p-4 border border-white/5 text-center">
        <div class="text-2xl font-black text-data text-cyan-400">{{ inr(data?.ltp) }}</div>
        <div class="text-[9px] font-black text-gray-600 tracking-widest uppercase mt-1">LTP</div>
      </div>

      <!-- Regime -->
      <div class="bg-white/[0.03] rounded-xl p-4 border border-white/5 text-center">
        <div>
          <span :class="['inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[10px] font-black tracking-wider border', regimeColor(regime?.regime)]">
            {{ regime?.regime || 'NO DATA' }}
          </span>
        </div>
        <div class="text-[9px] font-black text-gray-600 tracking-widest uppercase mt-2">Regime</div>
      </div>

      <!-- Session -->
      <div class="bg-white/[0.03] rounded-xl p-4 border border-white/5 text-center">
        <div>
          <span class="inline-flex items-center px-3 py-1.5 rounded-lg text-[10px] font-black tracking-wider bg-purple-500/15 text-purple-400 border border-purple-500/20">
            {{ data?.time_regime || '—' }}
          </span>
        </div>
        <div class="text-[9px] font-black text-gray-600 tracking-widest uppercase mt-2">Time Session</div>
      </div>

      <!-- Positions -->
      <div class="bg-white/[0.03] rounded-xl p-4 border border-white/5 text-center">
        <div class="text-2xl font-black text-data text-primary-400">{{ data?.active_positions ?? 0 }}</div>
        <div class="text-[9px] font-black text-gray-600 tracking-widest uppercase mt-1">Active Positions</div>
      </div>
    </div>

    <!-- Regime Metrics Row -->
    <div v-if="metrics" class="grid grid-cols-3 gap-3 mt-4">
      <div class="bg-white/[0.02] rounded-lg p-3 border border-white/5 text-center">
        <div class="text-sm font-black text-data text-white">{{ metrics.adx_value?.toFixed(1) }}</div>
        <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase">ADX</div>
      </div>
      <div class="bg-white/[0.02] rounded-lg p-3 border border-white/5 text-center">
        <div class="text-sm font-black text-data text-white">{{ (metrics.atr_percent * 100)?.toFixed(2) }}%</div>
        <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase">ATR %</div>
      </div>
      <div class="bg-white/[0.02] rounded-lg p-3 border border-white/5 text-center">
        <div class="text-sm font-black text-data text-white">{{ metrics.volatility_regime || '—' }}</div>
        <div class="text-[8px] font-black text-gray-600 tracking-widest uppercase">Vol Regime</div>
      </div>
    </div>
  </div>
</template>
